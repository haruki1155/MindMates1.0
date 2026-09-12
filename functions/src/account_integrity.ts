import {randomUUID} from "node:crypto";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";

if (!getApps().length) initializeApp();

const db = getFirestore();
const POPULATION_ROLES = ["student", "teaching", "nonTeaching"] as const;
type PopulationRole = typeof POPULATION_ROLES[number];
const GENDERS = ["Male", "Female", "Non-binary", "Prefer not to say"] as const;
// Source allowlist contains every ID in these five year blocks, 0001-9999.
const STUDENT_ID_PATTERN = /^(2022|2023|2024|2025|2026)[0-9]{4}$/;

function safeErrorCode(error: unknown): string {
  if (error instanceof HttpsError) return error.code;
  if (error instanceof Error) return error.name || "unknown";
  return "unknown";
}

function requireUid(request: {auth?: {uid?: string}}): string {
  const uid = request.auth?.uid?.trim();
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  return uid;
}

function objectData(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "A valid profile is required.");
  }
  return value as Record<string, unknown>;
}

function requiredText(data: Record<string, unknown>, key: string, label: string, max = 120): string {
  const value = typeof data[key] === "string" ? data[key].trim() : "";
  if (!value || value.length > max) {
    throw new HttpsError("invalid-argument", `${label} is required and must be at most ${max} characters.`);
  }
  return value;
}

function optionalText(data: Record<string, unknown>, key: string, max = 120): string {
  const value = typeof data[key] === "string" ? data[key].trim() : "";
  if (value.length > max) throw new HttpsError("invalid-argument", `${key} is too long.`);
  return value;
}

function populationRole(value: unknown): PopulationRole {
  if (!POPULATION_ROLES.includes(value as PopulationRole)) {
    throw new HttpsError("invalid-argument", "Choose a valid population role.");
  }
  return value as PopulationRole;
}

function schoolIdFromAccount(email: string | undefined, data: Record<string, unknown>): string {
  const normalized = String(email ?? "").trim().toLowerCase();
  if (!normalized.endsWith("@mindmate.local")) {
    return requiredText(data, "schoolId", "School ID", 40);
  }
  const schoolId = normalized.slice(0, -"@mindmate.local".length);
  if (!schoolId) throw new HttpsError("failed-precondition", "The School ID is unavailable.");
  return schoolId;
}

export function registrationRoleForEmail(email: string | undefined): "student" | "teaching" {
  const normalized = String(email ?? "").trim().toLowerCase();
  const parts = normalized.split("@");
  return parts.length === 2 && parts[0].length > 0 && parts[1] === "ucu.edu.ph"
    ? "teaching"
    : "student";
}

function canonicalEmployeeId(value: string): string {
  const employeeId = value.trim().toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (employeeId.length < 3) {
    throw new HttpsError("invalid-argument", "Enter a valid employee ID.");
  }
  return employeeId;
}

export function canonicalStudentId(value: string): string {
  const id = value.trim().toUpperCase();
  if (!STUDENT_ID_PATTERN.test(id)) {
    throw new HttpsError("invalid-argument", "Enter a valid student ID from the approved list.");
  }
  return id;
}

export function validatedProfileInput(raw: unknown): Record<string, string> {
  const data = objectData(raw);
  const role = populationRole(data.populationRole);
  const firstName = requiredText(data, "firstName", "First name", 80);
  const lastName = requiredText(data, "lastName", "Last name", 80);
  const middleName = optionalText(data, "middleName", 80);
  const department = optionalText(data, "department");
  const course = optionalText(data, "course");
  const yearLevel = optionalText(data, "yearLevel", 40);
  const sector = optionalText(data, "sector");
  const position = optionalText(data, "position");
  const employeeId = optionalText(data, "employeeId", 40);
  const gender = requiredText(data, "gender", "Sex / gender", 40);
  if (!GENDERS.includes(gender as typeof GENDERS[number])) {
    throw new HttpsError("invalid-argument", "Choose a valid sex / gender option.");
  }
  const dateOfBirthText = requiredText(data, "dateOfBirth", "Date of birth", 40);
  const dateOfBirth = new Date(dateOfBirthText);
  const today = new Date();
  if (Number.isNaN(dateOfBirth.getTime()) || dateOfBirth > today || dateOfBirth.getUTCFullYear() < today.getUTCFullYear() - 120) {
    throw new HttpsError("invalid-argument", "Choose a valid date of birth.");
  }

  if (role === "student" && (!department || !course || !yearLevel)) {
    throw new HttpsError("invalid-argument", "Students must provide college, course, and year level.");
  }
  if (role === "teaching" && (!employeeId || !department || !position)) {
    throw new HttpsError("invalid-argument", "Faculty must provide employee ID, department, and position.");
  }
  if (role === "nonTeaching" && (!employeeId || !sector || !position)) {
    throw new HttpsError("invalid-argument", "Staff must provide employee ID, sector, and position.");
  }
  return {firstName, middleName, lastName, populationRole: role, department, course,
    yearLevel, sector, position, employeeId, gender, dateOfBirth: dateOfBirth.toISOString()};
}

function legacyRole(role: PopulationRole): string {
  return role === "teaching" ? "faculty" : role === "nonTeaching" ? "staff" : "student";
}

function profileIsReady(profile: FirebaseFirestore.DocumentData): boolean {
  const role = profile.populationRole as PopulationRole;
  const present = (value: unknown) => typeof value === "string" && value.trim().length > 0;
  if (!present(profile.firstName) || !present(profile.lastName) || !present(profile.gender) || !POPULATION_ROLES.includes(role)) return false;
  if (role === "student") return present(profile.schoolId) && present(profile.department) && present(profile.course) && present(profile.yearLevel) && profile.dateOfBirth instanceof Timestamp;
  if (role === "teaching") return present(profile.employeeId) && present(profile.department) && present(profile.position);
  return present(profile.employeeId) && present(profile.sector) && present(profile.position);
}

async function provisionAppUserProfileHandler(request: CallableRequest) {
  const correlationId = randomUUID();
  const uid = requireUid(request);
  try {
    const authUser = await getAuth().getUser(uid);
    const input = validatedProfileInput(request.data);
    const assignedRole = registrationRoleForEmail(authUser.email);
    if (input.populationRole !== assignedRole) {
      throw new HttpsError(
        "failed-precondition",
        assignedRole === "teaching"
          ? "Official UCU email accounts must register as Teaching personnel."
          : "Teaching personnel must verify an official @ucu.edu.ph email address.",
      );
    }
    const schoolId = assignedRole === "student"
      ? schoolIdFromAccount(authUser.email, objectData(request.data))
      : "";
    if (assignedRole === "student") canonicalStudentId(schoolId);
    const profileRef = db.collection("users").doc(uid);
    const reservationRef = assignedRole === "student"
      ? db.collection("student_id_reservations").doc(canonicalStudentId(schoolId))
      : db.collection("employee_id_reservations").doc(canonicalEmployeeId(input.employeeId));
    let created = false;
    await db.runTransaction(async (transaction) => {
      const existing = await transaction.get(profileRef);
      if (existing.exists) {
        const existingRole = existing.data()?.populationRole ?? existing.data()?.declaredRole;
        if (existingRole && existingRole !== input.populationRole) {
          throw new HttpsError("already-exists", "An account profile already exists with a different role.");
        }
        return;
      }
      if (reservationRef) {
        const reservation = await transaction.get(reservationRef);
        if (reservation.exists && reservation.data()?.userId !== uid) {
          throw new HttpsError(
            "already-exists",
            assignedRole === "student"
              ? "That student ID is already registered."
              : "That employee ID is already registered.",
          );
        }
        if (!reservation.exists) {
          transaction.create(reservationRef, {
            userId: uid,
            ...(assignedRole === "student"
              ? {studentId: schoolId}
              : {employeeId: input.employeeId}),
            createdAt: FieldValue.serverTimestamp(),
          });
        }
      }
      created = true;
      transaction.create(profileRef, {
        id: uid, email: authUser.email ?? "", emailVerified: authUser.emailVerified === true, schoolId,
        ...input,
        dateOfBirth: Timestamp.fromDate(new Date(input.dateOfBirth)),
        name: [input.firstName, input.middleName, input.lastName].filter(Boolean).join(" "),
        role: legacyRole(input.populationRole as PopulationRole),
        declaredRole: input.populationRole,
        accessRole: "appUser", verificationStatus: "verified", profileVersion: 3,
        verifiedAt: FieldValue.serverTimestamp(), verifiedBy: "automatic-registration",
        dayStreak: 0, longestStreak: 0,
        lastActivityDateKey: "", activeDateKeys: [], avatarAssetName: "",
        quickAssessmentCompleted: false, quickAssessmentCompletedAt: null,
        profileSetupCompleted: false,
        lastActiveAt: FieldValue.serverTimestamp(), createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    console.info("profile_provisioned", {correlationId, created});
    return {ok: true, created, profileReady: true, correlationId};
  } catch (error) {
    console.error("profile_provision_failed", {correlationId, code: safeErrorCode(error)});
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", "Profile setup could not be completed.", {correlationId});
  }
}

export const provisionAppUserProfile = onCall({enforceAppCheck: true}, provisionAppUserProfileHandler);
export const provisionAppUserProfileDev = onCall({enforceAppCheck: false}, provisionAppUserProfileHandler);

function isVerifiedQuick(data: FirebaseFirestore.DocumentData | undefined, uid: string): boolean {
  return data?.userId === uid && data?.type === "quick" &&
    data?.calculationAuthority === "server" && data?.verificationStatus === "verified";
}

async function getAssessmentStatusHandler(request: CallableRequest) {
  const correlationId = randomUUID();
  const uid = requireUid(request);
  try {
    const profileRef = db.collection("users").doc(uid);
    const deterministicRef = db.collection("assessments").doc(`quick_${uid}`);
    const [profile, deterministic] = await Promise.all([profileRef.get(), deterministicRef.get()]);
    if (!profile.exists) {
      throw new HttpsError("failed-precondition", "Your account profile needs to be recovered.", {reason: "profile-missing", correlationId});
    }

    let assessment = isVerifiedQuick(deterministic.data(), uid) ? deterministic : null;
    if (!assessment) {
      const legacy = await db.collection("assessments")
        .where("userId", "==", uid).where("type", "==", "quick").limit(10).get();
      assessment = legacy.docs.find((doc) => isVerifiedQuick(doc.data(), uid)) ?? null;
    }
    const completed = assessment !== null;
    const completedAt = assessment?.data()?.submittedAt ?? assessment?.data()?.createdAt ?? null;
    await db.runTransaction(async (transaction) => {
      const currentProfile = await transaction.get(profileRef);
      if (!currentProfile.exists) throw new HttpsError("failed-precondition", "Your account profile needs to be recovered.");
      transaction.update(profileRef, {
        quickAssessmentCompleted: completed,
        quickAssessmentCompletedAt: completed ? completedAt ?? FieldValue.serverTimestamp() : null,
        assessmentStatusCheckedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    const data = assessment?.data() ?? {};
    return {completed, profileReady: profileIsReady(profile.data() ?? {}),
      assessmentId: assessment?.id ?? null,
      algorithmVersion: completed ? String(data.algorithmVersion ?? "legacy") : null,
      questionSetVersion: completed ? String(data.questionSetVersion ?? "legacy") : null,
      completedAt: completedAt instanceof Timestamp ? completedAt.toDate().toISOString() : null,
      correlationId};
  } catch (error) {
    console.error("assessment_status_failed", {correlationId, code: safeErrorCode(error)});
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("unavailable", "Assessment status is temporarily unavailable.", {correlationId});
  }
}

export const getAssessmentStatus = onCall({enforceAppCheck: true}, getAssessmentStatusHandler);
export const getAssessmentStatusDev = onCall({enforceAppCheck: false}, getAssessmentStatusHandler);

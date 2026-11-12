import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireAdmin, requireClinical, requireUid, roleOf} from "./access";
import {canonicalLoginId} from "./account_recovery";
import {AUDIT_CATEGORIES, actorName, writeAudit} from "./audit";
import {loadAcademicIndex} from "./student_roster";
import {
  CORRECTABLE_FIELDS, PRIVACY_POLICY_VERSION, PersonalInfo, normalizeName, normalizeYearLevel, parseDateKey,
  validatePersonalInfo,
} from "./student_roster_domain";

if (!getApps().length) initializeApp();

type Doc = FirebaseFirestore.DocumentData;
type Field = typeof CORRECTABLE_FIELDS[number];

export type OfficialFieldsView = {studentNo: string; surname: string; firstName: string; middleName: string;
  dateOfBirth: string; college: string; course: string; yearLevel: string; email: string};
export type CorrectionView = {id: string; userId: string; studentNo: string; studentName: string; field: string;
  currentValue: string; requestedValue: string; reason: string; status: string; reviewReason: string; createdAt: string};

const MAX_TEXT = 160;
const MAX_REASON = 500;
const PERSONAL_KEYS: (keyof PersonalInfo)[] = [
  "sex", "civilStatus", "spouse", "nationality", "placeOfBirth", "cityAddress", "homeAddress", "father", "fatherOccupation",
  "mother", "motherOccupation", "guardian", "guardianRelationship", "guardianAddress", "telephone", "cellphone",
];
const NAME_FIELDS: Field[] = ["surname", "firstName", "middleName"];

function database(): FirebaseFirestore.Firestore {
  return getFirestore();
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function iso(value: unknown): string {
  return value instanceof Timestamp ? value.toDate().toISOString() : "";
}

function keyOrNull(schoolId: unknown): string | null {
  try {
    return canonicalLoginId(schoolId);
  } catch {
    return null;
  }
}

function dateKeyOf(source: Doc): string {
  if (typeof source.dateOfBirthKey === "string" && source.dateOfBirthKey) return source.dateOfBirthKey;
  const dob = source.dateOfBirth;
  if (dob instanceof Timestamp) return dob.toDate().toISOString().slice(0, 10);
  if (typeof dob === "string" && dob) return dob.slice(0, 10);
  return "";
}

type Linked = {rosterRef: FirebaseFirestore.DocumentReference | null; roster: Doc | null};

/** The roster row linked to this user, or null for legacy accounts. */
async function findRoster(
  uid: string, user: Doc, read: (ref: FirebaseFirestore.DocumentReference) => Promise<FirebaseFirestore.DocumentSnapshot>,
): Promise<Linked> {
  const key = keyOrNull(user.schoolId);
  if (!key) return {rosterRef: null, roster: null};
  const ref = database().collection("student_roster").doc(key);
  const snap = await read(ref);
  if (snap.exists && snap.data()?.userId === uid) return {rosterRef: ref, roster: snap.data() as Doc};
  return {rosterRef: null, roster: null};
}

function officialView(user: Doc, roster: Doc | null): OfficialFieldsView {
  const src = roster ?? {};
  const pick = (rosterKey: string, userKey: string) => text(roster ? src[rosterKey] : user[userKey]);
  return {
    studentNo: roster ? text(src.studentNo) : text(user.schoolId),
    surname: pick("surname", "lastName"),
    firstName: pick("firstName", "firstName"),
    middleName: pick("middleName", "middleName"),
    dateOfBirth: dateKeyOf(roster ?? user),
    college: pick("college", "college"),
    course: pick("course", "course"),
    yearLevel: pick("yearLevel", "yearLevel"),
    email: text(user.email),
  };
}

function personalView(data: Doc | undefined): Record<string, unknown> | null {
  if (!data) return null;
  const out: Record<string, unknown> = {};
  for (const key of PERSONAL_KEYS) out[key] = data[key] ?? null;
  out.updatedAt = iso(data.updatedAt);
  return out;
}

function correctionView(id: string, data: Doc): CorrectionView {
  return {
    id, userId: text(data.userId), studentNo: text(data.studentNo), studentName: text(data.studentName),
    field: text(data.field), currentValue: text(data.currentValue), requestedValue: text(data.requestedLabel || data.requestedValue),
    reason: text(data.reason), status: text(data.status), reviewReason: text(data.reviewReason), createdAt: iso(data.createdAt),
  };
}

// ------------------------------------------------------------------ save

// Mirrors the client's effectivePopulationRole: populationRole, then declaredRole, then the legacy role.
function isStudentProfile(user: Record<string, unknown> | undefined): boolean {
  const effective = user?.populationRole || user?.declaredRole || user?.role;
  return effective === "student";
}

export const saveStudentPersonalInfo = onCall(async (request) => {
  const uid = requireUid(request);
  const data = (request.data ?? {}) as {info?: unknown; privacyConsent?: unknown};
  const db = database();
  const userRef = db.collection("users").doc(uid);
  const infoRef = db.collection("student_personal_info").doc(uid);

  const userPeek = await userRef.get();
  if (!userPeek.exists || !isStudentProfile(userPeek.data())) {
    throw new HttpsError("permission-denied", "Only students can save Student Information.");
  }
  if (userPeek.data()?.accountStatus === "revoked") {
    throw new HttpsError("permission-denied", "This account has been revoked.");
  }
  const validated = validatePersonalInfo(data.info);
  if (!validated.ok) {
    throw new HttpsError("invalid-argument", "Please correct the highlighted fields.", {errors: validated.errors});
  }

  await db.runTransaction(async (transaction) => {
    const [user, existing] = await Promise.all([transaction.get(userRef), transaction.get(infoRef)]);
    if (!isStudentProfile(user.data())) {
      throw new HttpsError("permission-denied", "Only students can save Student Information.");
    }
    if (user.data()?.accountStatus === "revoked") {
      throw new HttpsError("permission-denied", "This account has been revoked.");
    }
    const hasConsent = Boolean(existing.exists && existing.data()?.privacyConsent?.policyVersion);
    if (!hasConsent && data.privacyConsent !== true) {
      throw new HttpsError("failed-precondition", "You must accept the Data Privacy notice to continue.");
    }
    const now = FieldValue.serverTimestamp();
    transaction.set(infoRef, {
      ...validated.value, userId: uid,
      privacyConsent: hasConsent ? existing.data()?.privacyConsent :
        {accepted: true, policyVersion: PRIVACY_POLICY_VERSION, acceptedAt: now},
      createdAt: existing.exists ? existing.data()?.createdAt ?? now : now,
      updatedAt: now,
    });
    const patch: Record<string, unknown> = {personalInfoRequired: false, updatedAt: now};
    if (!text(user.data()?.gender)) patch.gender = validated.value.sex;
    transaction.update(userRef, patch);
  });
  return {ok: true};
});

// ------------------------------------------------------------------ reads

async function correctionsFor(uid: string): Promise<CorrectionView[]> {
  const snap = await database().collection("student_correction_requests").where("userId", "==", uid).get();
  return snap.docs
    .map((d) => ({view: correctionView(d.id, d.data()), at: d.data().createdAt instanceof Timestamp ? d.data().createdAt.toMillis() : 0}))
    .sort((a, b) => b.at - a.at)
    .map((x) => x.view);
}

export const getMyStudentInformation = onCall(async (request) => {
  const uid = requireUid(request);
  const db = database();
  const userSnap = await db.collection("users").doc(uid).get();
  if (!userSnap.exists) throw new HttpsError("not-found", "Profile not found.");
  const user = userSnap.data() as Doc;
  const {roster} = await findRoster(uid, user, (ref) => ref.get());
  const [personal, corrections] = await Promise.all([db.collection("student_personal_info").doc(uid).get(), correctionsFor(uid)]);
  return {official: officialView(user, roster), personal: personalView(personal.data()), corrections};
});

export const getStudentPersonalInfo = onCall(async (request) => {
  const actorId = requireUid(request);
  const actor = await requireClinical(actorId);
  const targetId = text((request.data as {userId?: unknown} | null)?.userId);
  if (!targetId) throw new HttpsError("invalid-argument", "A student is required.");
  const db = database();

  const result = await db.runTransaction(async (transaction) => {
    const userSnap = await transaction.get(db.collection("users").doc(targetId));
    if (!userSnap.exists) throw new HttpsError("not-found", "Student not found.");
    const user = userSnap.data() as Doc;
    const key = keyOrNull(user.schoolId);
    const [rosterSnap, personalSnap] = await Promise.all([
      key ? transaction.get(db.collection("student_roster").doc(key)) : Promise.resolve(null),
      transaction.get(db.collection("student_personal_info").doc(targetId)),
    ]);
    const roster = rosterSnap?.exists && rosterSnap.data()?.userId === targetId ? rosterSnap.data() as Doc : null;
    // The audit record commits with this transaction, before the caller sees anything.
    writeAudit(transaction, db, {
      actorId, actorNameSnapshot: actorName(actor), actorRoleSnapshot: roleOf(actor),
      action: "STUDENT_PERSONAL_INFO_VIEWED", category: AUDIT_CATEGORIES.security,
      targetType: "student", targetId, metadata: {hasPersonalInfo: personalSnap.exists},
    });
    return {official: officialView(user, roster), personal: personalView(personalSnap.data())};
  });
  return result;
});

// ------------------------------------------------------------------ corrections

function isField(value: unknown): value is Field {
  return typeof value === "string" && (CORRECTABLE_FIELDS as readonly string[]).includes(value);
}

function currentValueOf(field: Field, official: OfficialFieldsView): string {
  return official[field];
}

export const requestStudentCorrection = onCall(async (request) => {
  const uid = requireUid(request);
  const data = (request.data ?? {}) as {field?: unknown; requestedValue?: unknown; reason?: unknown};
  if (!isField(data.field)) throw new HttpsError("invalid-argument", "That field cannot be corrected here.");
  const field = data.field;
  const reason = text(data.reason);
  if (!reason) throw new HttpsError("invalid-argument", "Tell us why this needs to change.");
  if (reason.length > MAX_REASON) throw new HttpsError("invalid-argument", `Reason must be at most ${MAX_REASON} characters.`);
  const rawValue = text(data.requestedValue);
  if (!rawValue || rawValue.length > MAX_TEXT) throw new HttpsError("invalid-argument", "Enter the corrected value.");

  let requestedValue = rawValue;
  let requestedLabel = rawValue;
  if (field === "yearLevel") {
    const normalized = normalizeYearLevel(rawValue);
    if (!normalized) throw new HttpsError("invalid-argument", "Select a valid year level.");
    requestedValue = requestedLabel = normalized;
  } else if (field === "dateOfBirth") {
    const normalized = parseDateKey(rawValue);
    if (!normalized) throw new HttpsError("invalid-argument", "Enter a valid date of birth.");
    requestedValue = requestedLabel = normalized;
  } else if (field === "college" || field === "course") {
    const index = await loadAcademicIndex();
    const record = (field === "college" ? index.colleges : index.courses).find((r) => r.id === rawValue);
    if (!record) throw new HttpsError("invalid-argument", `Select a valid ${field}.`);
    requestedLabel = record.name;
  }

  const db = database();
  const userRef = db.collection("users").doc(uid);
  const requestRef = db.collection("student_correction_requests").doc();
  await db.runTransaction(async (transaction) => {
    const userSnap = await transaction.get(userRef);
    const user = userSnap.data() ?? {};
    if (!isStudentProfile(user)) throw new HttpsError("permission-denied", "Only students can request corrections.");
    const {roster} = await findRoster(uid, user, (ref) => transaction.get(ref));
    if (!roster) throw new HttpsError("failed-precondition", "Your account is not linked to the student roster.");
    const pending = await transaction.get(
      db.collection("student_correction_requests").where("userId", "==", uid).where("status", "==", "pending"),
    );
    if (pending.docs.some((d) => d.data().field === field)) {
      throw new HttpsError("already-exists", "You already have a pending request for this field.");
    }
    const official = officialView(user, roster);
    if (currentValueOf(field, official) === requestedLabel && field !== "college" && field !== "course") {
      throw new HttpsError("invalid-argument", "That is already your current value.");
    }
    transaction.create(requestRef, {
      userId: uid, studentNo: official.studentNo, studentKey: keyOrNull(official.studentNo),
      studentName: [official.firstName, official.middleName, official.surname].filter(Boolean).join(" "),
      field, currentValue: currentValueOf(field, official), requestedValue, requestedLabel, reason,
      status: "pending", reviewReason: "", reviewedBy: null, reviewedAt: null,
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return {requestId: requestRef.id};
});

export const reviewStudentCorrection = onCall(async (request) => {
  const actorId = requireUid(request);
  const actor = await requireAdmin(actorId);
  const data = (request.data ?? {}) as {requestId?: unknown; decision?: unknown; reason?: unknown};
  const requestId = text(data.requestId);
  if (!requestId) throw new HttpsError("invalid-argument", "A request is required.");
  if (data.decision !== "approve" && data.decision !== "reject") {
    throw new HttpsError("invalid-argument", "Decision must be approve or reject.");
  }
  const approve = data.decision === "approve";
  const reason = text(data.reason);
  if (!approve && !reason) throw new HttpsError("invalid-argument", "Give a reason for rejecting this request.");
  if (reason.length > MAX_REASON) throw new HttpsError("invalid-argument", `Reason must be at most ${MAX_REASON} characters.`);

  const db = database();
  const index = approve ? await loadAcademicIndex() : null;
  const requestRef = db.collection("student_correction_requests").doc(requestId);

  await db.runTransaction(async (transaction) => {
    const reqSnap = await transaction.get(requestRef);
    if (!reqSnap.exists) throw new HttpsError("not-found", "Request not found.");
    const req = reqSnap.data() as Doc;
    if (req.status !== "pending") throw new HttpsError("failed-precondition", "This request has already been reviewed.");
    const userId = text(req.userId);
    const field = req.field as Field;
    const userRef = db.collection("users").doc(userId);

    if (approve) {
      const rosterRef = db.collection("student_roster").doc(text(req.studentKey));
      const [rosterSnap, userSnap] = await Promise.all([transaction.get(rosterRef), transaction.get(userRef)]);
      const roster = rosterSnap.data();
      if (!roster || roster.userId !== userId || !userSnap.exists) {
        throw new HttpsError("failed-precondition", "The student's roster record is no longer linked to this account.");
      }
      const value = text(req.requestedValue);
      const rosterPatch: Record<string, unknown> = {};
      const userPatch: Record<string, unknown> = {};
      if (field === "surname" || field === "firstName" || field === "middleName") {
        rosterPatch[field] = value;
        if (field === "surname") rosterPatch.surnameNormalized = normalizeName(value);
      } else if (field === "yearLevel") {
        rosterPatch.yearLevel = userPatch.yearLevel = value;
      } else if (field === "dateOfBirth") {
        const stamp = Timestamp.fromDate(new Date(`${value}T00:00:00Z`));
        rosterPatch.dateOfBirth = userPatch.dateOfBirth = stamp;
        rosterPatch.dateOfBirthKey = userPatch.dateOfBirthKey = value;
      } else if (field === "college") {
        const college = index!.colleges.find((c) => c.id === value);
        const currentCourse = index!.courses.find((c) => c.id === roster.courseId);
        if (!college) throw new HttpsError("failed-precondition", "That college is no longer available.");
        if (!currentCourse || currentCourse.collegeId !== college.id) {
          throw new HttpsError("failed-precondition", "The student's current course does not belong to that college. Correct the course first.");
        }
        rosterPatch.collegeId = userPatch.collegeId = college.id;
        rosterPatch.college = userPatch.college = college.name;
      } else if (field === "course") {
        const course = index!.courses.find((c) => c.id === value);
        if (!course) throw new HttpsError("failed-precondition", "That course is no longer available.");
        if (course.collegeId !== roster.collegeId) {
          throw new HttpsError("failed-precondition", "That course does not belong to the student's college.");
        }
        for (const target of [rosterPatch, userPatch]) {
          target.courseId = course.id;
          target.course = course.name;
          target.departmentId = course.departmentId;
          target.department = course.departmentName;
        }
      } else {
        throw new HttpsError("failed-precondition", "That field cannot be corrected.");
      }
      transaction.update(rosterRef, {...rosterPatch, updatedAt: FieldValue.serverTimestamp()});
      if (Object.keys(userPatch).length) transaction.update(userRef, {...userPatch, updatedAt: FieldValue.serverTimestamp()});
    }

    transaction.update(requestRef, {
      status: approve ? "approved" : "rejected", reviewReason: reason, reviewedBy: actorId,
      reviewedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    writeAudit(transaction, db, {
      actorId, actorNameSnapshot: actorName(actor), actorRoleSnapshot: roleOf(actor),
      action: approve ? "STUDENT_CORRECTION_APPROVED" : "STUDENT_CORRECTION_REJECTED",
      category: AUDIT_CATEGORIES.userManagement, targetType: "student", targetId: userId,
      metadata: {requestId, field},
    });
  });
  return {status: approve ? "approved" : "rejected"};
});

export const listStudentCorrectionRequests = onCall(async (request) => {
  const actorId = requireUid(request);
  await requireAdmin(actorId);
  const status = (request.data as {status?: unknown} | null)?.status;
  const col = database().collection("student_correction_requests");
  const snap = status === "pending" ?
    await col.where("status", "==", "pending").get() :
    await col.orderBy("createdAt", "desc").limit(200).get();
  const requests = snap.docs
    .map((d) => ({view: correctionView(d.id, d.data()), at: d.data().createdAt instanceof Timestamp ? d.data().createdAt.toMillis() : 0}))
    .sort((a, b) => b.at - a.at)
    .map((x) => x.view);
  return {requests};
});

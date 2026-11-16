import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireStaff, requireUid, roleOf} from "./access";
import {AUDIT_CATEGORIES, actorName, writeAudit} from "./audit";
import {
  AcademicYearError,
  AcademicYearSummary,
  parseAcademicYearInput,
  parseSchoolYear,
  validateAcademicYearAgainstExisting,
  validateAcademicYearClose,
} from "./academic_year";

if (!getApps().length) initializeApp();
const db = getFirestore();

// Keep this list aligned with the registration organization catalog. Population
// settings are keyed by school year, so the next school year can be entered
// without overwriting historical totals.
export const REPORT_DEPARTMENTS = [
  "College of Accountancy and Business Administration",
  "College of Arts and Sciences / College of Arts and Languages",
  "College of Information and Technology Education / College of Computer Studies",
  "College of Criminology",
  "College of Education / College of Teacher Education",
  "College of Engineering and Architecture",
  "College of Law",
  "College of Nursing",
  "College of Pharmacy",
  "College of Science and Mathematics",
  "College of Social Work",
  "Graduate School / Institute of Graduate and Advanced Studies",
  "School of Hotel and Restaurant Services and Tourism Management",
  "School of Midwifery",
] as const;

const text = (value: unknown) => typeof value === "string" ? value.trim() : "";
const config = (schoolYear: string) => db.collection("counseling_population").doc(schoolYear);

export type AcademicYearRecord = AcademicYearSummary;

function toAcademicYearRecord(id: string, data: FirebaseFirestore.DocumentData): AcademicYearRecord {
  const schoolYear = text(data.schoolYear) || id;
  const startDate = text(data.startDate) || `${schoolYear.slice(0, 4)}-06-01`;
  const endDate = text(data.endDate) || `${Number(schoolYear.slice(5, 9))}-05-31`;
  return {
    schoolYear,
    startDate,
    endDate,
    status: data.status === "closed" ? "closed" : "current",
  };
}

export async function listAcademicYears(): Promise<AcademicYearRecord[]> {
  const snapshot = await db.collection("counseling_population").get();
  return snapshot.docs
    .map((doc) => toAcademicYearRecord(doc.id, doc.data()))
    .sort((a, b) => b.schoolYear.localeCompare(a.schoolYear));
}

async function requireActiveAdmin(uid: string): Promise<FirebaseFirestore.DocumentData> {
  const staff = await requireStaff(uid);
  if (staff.accessRole !== "admin") {
    throw new HttpsError("permission-denied", "Administrator access is required.");
  }
  return staff;
}

function rethrowAcademicYearError(error: unknown): never {
  if (error instanceof AcademicYearError) {
    throw new HttpsError(error.code, error.message);
  }
  throw error;
}

export function defaultSchoolYear(now = new Date()): string {
  const start = now.getMonth() >= 5 ? now.getFullYear() : now.getFullYear() - 1;
  return `${start}-${start + 1}`;
}

export async function readPopulationConfig(schoolYear: string) {
  const snapshot = await config(schoolYear).get();
  const raw = snapshot.data()?.populations;
  const populations: Record<string, number> = {};
  if (raw && typeof raw === "object") {
    for (const department of REPORT_DEPARTMENTS) {
      const value = (raw as Record<string, unknown>)[department];
      if (typeof value === "number" && Number.isInteger(value) && value > 0) {
        populations[department] = value;
      }
    }
  }
  return {
    schoolYear,
    startDate: text(snapshot.data()?.startDate) || `${schoolYear.slice(0, 4)}-06-01`,
    endDate: text(snapshot.data()?.endDate) || `${Number(schoolYear.slice(5, 9))}-05-31`,
    status: (snapshot.data()?.status === "closed" ? "closed" : "current") as "current" | "closed",
    departments: [...REPORT_DEPARTMENTS],
    populations,
    configured: REPORT_DEPARTMENTS.every((department) => populations[department] != null),
    totalPopulation: Object.values(populations).reduce((total, value) => total + value, 0),
  };
}

export const getCounselingPopulation = onCall(async (request) => {
  const uid = requireUid(request);
  await requireActiveAdmin(uid);
  try {
    const {schoolYear} = parseSchoolYear(request.data?.schoolYear);
    return {...await readPopulationConfig(schoolYear), years: await listAcademicYears()};
  } catch (error) {
    rethrowAcademicYearError(error);
  }
});

export const getAcademicYears = onCall(async (request) => {
  const uid = requireUid(request);
  await requireActiveAdmin(uid);
  return {years: await listAcademicYears()};
});

export const createAcademicYear = onCall(async (request) => {
  const uid = requireUid(request);
  const actor = await requireActiveAdmin(uid);
  try {
    const candidate = parseAcademicYearInput({
      schoolYear: request.data?.schoolYear,
      startDate: request.data?.startDate,
      endDate: request.data?.endDate,
    });
    const sourceYear = text(request.data?.copyFrom);
    const copyPopulation = request.data?.copyPopulation === true;
    await db.runTransaction(async (tx) => {
      const snapshot = await tx.get(db.collection("counseling_population"));
      const existing = snapshot.docs.map((doc) => toAcademicYearRecord(doc.id, doc.data()));
      validateAcademicYearAgainstExisting(candidate, existing);
      const sourceDoc = sourceYear ? snapshot.docs.find((doc) => doc.id === sourceYear)?.data() : undefined;
      tx.set(config(candidate.schoolYear), {
        schoolYear: candidate.schoolYear,
        startDate: candidate.startDate,
        endDate: candidate.endDate,
        status: "current",
        populations: copyPopulation && sourceDoc?.populations ? sourceDoc.populations : {},
        createdAt: FieldValue.serverTimestamp(),
        createdBy: uid,
      });
      writeAudit(tx, db, {
        actorId: uid,
        actorNameSnapshot: actorName(actor),
        actorRoleSnapshot: roleOf(actor),
        action: "ACADEMIC_YEAR_CREATED",
        category: AUDIT_CATEGORIES.system,
        targetType: "academic_year",
        targetId: candidate.schoolYear,
        metadata: {
          academicYearId: candidate.schoolYear,
          startDate: candidate.startDate,
          endDate: candidate.endDate,
          copiedFrom: copyPopulation && sourceDoc ? sourceYear : null,
        },
      });
    });
    return {years: await listAcademicYears()};
  } catch (error) {
    rethrowAcademicYearError(error);
  }
});

export const closeAcademicYear = onCall(async (request) => {
  const uid = requireUid(request);
  const actor = await requireActiveAdmin(uid);
  try {
    const {schoolYear} = parseSchoolYear(request.data?.schoolYear);
    const reference = config(schoolYear);
    await db.runTransaction(async (tx) => {
      const snapshot = await tx.get(reference);
      validateAcademicYearClose(snapshot.exists ? snapshot.data() ?? {} : null);
      tx.update(reference, {
        status: "closed",
        closedAt: FieldValue.serverTimestamp(),
        closedBy: uid,
      });
      writeAudit(tx, db, {
        actorId: uid,
        actorNameSnapshot: actorName(actor),
        actorRoleSnapshot: roleOf(actor),
        action: "ACADEMIC_YEAR_CLOSED",
        category: AUDIT_CATEGORIES.system,
        targetType: "academic_year",
        targetId: schoolYear,
        metadata: {academicYearId: schoolYear},
      });
    });
    return {years: await listAcademicYears()};
  } catch (error) {
    rethrowAcademicYearError(error);
  }
});

export const saveCounselingPopulation = onCall(async (request) => {
  const uid = requireUid(request);
  const actor = await requireActiveAdmin(uid);
  const raw = request.data?.populations;
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new HttpsError("invalid-argument", "Department populations are required.");
  }
  const populations: Record<string, number> = {};
  for (const department of REPORT_DEPARTMENTS) {
    const value = (raw as Record<string, unknown>)[department];
    if (!Number.isInteger(value) || (value as number) < 1 || (value as number) > 1000000) {
      throw new HttpsError("invalid-argument", `Enter a valid population for ${department}.`);
    }
    populations[department] = value as number;
  }
  try {
    const {schoolYear} = parseSchoolYear(request.data?.schoolYear);
    const ref = config(schoolYear);
    await db.runTransaction(async (tx) => {
      const existing = await tx.get(ref);
      if (!existing.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Create the academic year in Academic Year Management before saving department populations.",
        );
      }
      if (existing.data()?.status === "closed") {
        throw new HttpsError("failed-precondition", "Closed academic years are read-only.");
      }
      tx.update(ref, {
        populations,
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: uid,
      });
      writeAudit(tx, db, {
        actorId: uid,
        actorNameSnapshot: actorName(actor),
        actorRoleSnapshot: roleOf(actor),
        action: "ACADEMIC_YEAR_POPULATION_UPDATED",
        category: AUDIT_CATEGORIES.system,
        targetType: "academic_year",
        targetId: schoolYear,
        metadata: {academicYearId: schoolYear},
      });
    });
    return readPopulationConfig(schoolYear);
  } catch (error) {
    rethrowAcademicYearError(error);
  }
});

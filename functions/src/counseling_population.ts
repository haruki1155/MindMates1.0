import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

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
const yearPattern = /^\d{4}-\d{4}$/;
const config = (schoolYear: string) => db.collection("counseling_population").doc(schoolYear);

export type AcademicYearRecord = {
  schoolYear: string;
  startDate: string;
  endDate: string;
  status: "current" | "closed";
};

export async function listAcademicYears(): Promise<AcademicYearRecord[]> {
  const snapshot = await db.collection("counseling_population").get();
  return snapshot.docs.map((doc) => {
    const data = doc.data();
    const schoolYear = text(data.schoolYear) || doc.id;
    const startDate = text(data.startDate) || `${schoolYear.slice(0, 4)}-06-01`;
    const endDate = text(data.endDate) || `${Number(schoolYear.slice(5, 9))}-05-31`;
    return {
      schoolYear,
      startDate,
      endDate,
      status: (data.status === "closed" ? "closed" : "current") as "current" | "closed",
    };
  }).sort((a, b) => b.schoolYear.localeCompare(a.schoolYear));
}

async function requireAdmin(uid: string): Promise<void> {
  const data = (await db.collection("users").doc(uid).get()).data() ?? {};
  const role = text(data.accessRole) || text(data.role);
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Administrator access is required.");
  }
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
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  await requireAdmin(uid);
  const schoolYear = text(request.data?.schoolYear);
  if (!yearPattern.test(schoolYear)) {
    throw new HttpsError("invalid-argument", "Use a school year such as 2026-2027.");
  }
  return {...await readPopulationConfig(schoolYear), years: await listAcademicYears()};
});

export const getAcademicYears = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  await requireAdmin(uid);
  return {years: await listAcademicYears()};
});

export const createAcademicYear = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  await requireAdmin(uid);
  const schoolYear = text(request.data?.schoolYear);
  if (!yearPattern.test(schoolYear)) throw new HttpsError("invalid-argument", "Use a school year such as 2027-2028.");
  const startDate = text(request.data?.startDate) || `${schoolYear.slice(0, 4)}-06-01`;
  const endDate = text(request.data?.endDate) || `${schoolYear.slice(5, 9)}-05-31`;
  if (Number.isNaN(Date.parse(startDate)) || Number.isNaN(Date.parse(endDate)) || startDate >= endDate) {
    throw new HttpsError("invalid-argument", "Enter a valid start and end date.");
  }
  const reference = config(schoolYear);
  if ((await reference.get()).exists) throw new HttpsError("already-exists", "That academic year already exists.");
  const sourceYear = text(request.data?.copyFrom);
  const copyPopulation = request.data?.copyPopulation === true;
  const source = sourceYear ? (await config(sourceYear).get()).data() : undefined;
  await reference.set({
    schoolYear, startDate, endDate, status: "current",
    populations: copyPopulation && source?.populations ? source.populations : {},
    createdAt: FieldValue.serverTimestamp(), createdBy: uid,
  });
  return {years: await listAcademicYears()};
});

export const closeAcademicYear = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  await requireAdmin(uid);
  const schoolYear = text(request.data?.schoolYear);
  if (!yearPattern.test(schoolYear)) throw new HttpsError("invalid-argument", "Choose a valid academic year.");
  const reference = config(schoolYear);
  const snapshot = await reference.get();
  if (!snapshot.exists) throw new HttpsError("not-found", "Academic year not found.");
  await reference.update({status: "closed", closedAt: FieldValue.serverTimestamp(), closedBy: uid});
  return {years: await listAcademicYears()};
});

export const saveCounselingPopulation = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  await requireAdmin(uid);
  const schoolYear = text(request.data?.schoolYear);
  if (!yearPattern.test(schoolYear)) {
    throw new HttpsError("invalid-argument", "Use a school year such as 2026-2027.");
  }
  const raw = request.data?.populations;
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new HttpsError("invalid-argument", "Department populations are required.");
  }
  const populations: Record<string, number> = {};
  const existing = await config(schoolYear).get();
  if (existing.data()?.status === "closed") {
    throw new HttpsError("failed-precondition", "Closed academic years are read-only.");
  }
  for (const department of REPORT_DEPARTMENTS) {
    const value = (raw as Record<string, unknown>)[department];
    if (!Number.isInteger(value) || (value as number) < 1 || (value as number) > 1000000) {
      throw new HttpsError("invalid-argument", `Enter a valid population for ${department}.`);
    }
    populations[department] = value as number;
  }
  await config(schoolYear).set({
    schoolYear,
    startDate: text(existing.data()?.startDate) || `${schoolYear.slice(0, 4)}-06-01`,
    endDate: text(existing.data()?.endDate) || `${schoolYear.slice(5, 9)}-05-31`,
    status: existing.data()?.status === "closed" ? "closed" : "current",
    populations,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: uid,
  });
  return readPopulationConfig(schoolYear);
});

import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {Timestamp, getFirestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import "./index";
import {
  closeAcademicYear,
  createAcademicYear,
  getAcademicYears,
  getCounselingPopulation,
  saveCounselingPopulation,
} from "./counseling_population";
import {getReportAnalytics} from "./report_generation";

const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const prefix = `ay-${Date.now()}`;
const uid = (name: string) => `${prefix}-${name}`;
const db = getFirestore();

type Callable<T> = {run: (r: {auth?: {uid: string}; data?: unknown}) => Promise<T>};
type YearList = {years: Array<{schoolYear: string; startDate: string; endDate: string; status: string}>};
const listYears = getAcademicYears as unknown as Callable<YearList>;
const createYear = createAcademicYear as unknown as Callable<YearList>;
const closeYear = closeAcademicYear as unknown as Callable<YearList>;
const getPop = getCounselingPopulation as unknown as Callable<Record<string, unknown>>;
const savePop = saveCounselingPopulation as unknown as Callable<Record<string, unknown>>;
const fetchReport = getReportAnalytics as unknown as Callable<{report: {appointments: {totalAppointments: number}; population: {schoolYear: string; status: string; totalPopulation: number}}}>;

const accounts: Record<string, {verified: boolean; profile: Record<string, unknown>}> = {
  admin: {verified: true, profile: {accessRole: "admin", accountStatus: "active", name: "Portal Admin"}},
  "suspended-admin": {verified: true, profile: {accessRole: "admin", accountStatus: "suspended"}},
  "unverified-admin": {verified: false, profile: {accessRole: "admin", accountStatus: "active"}},
  counselor: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active"}},
  staff: {verified: true, profile: {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active"}},
  student: {verified: true, profile: {accessRole: "appUser", role: "student", accountStatus: "active"}},
};

async function as<T>(callable: Callable<T>, actor: string, data?: Record<string, unknown>) {
  return callable.run({auth: {uid: uid(actor)}, data});
}
async function rejects(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (e: unknown) => e instanceof HttpsError && e.code === code);
}

before(async () => {
  if (!emulated) return;
  for (const [name, account] of Object.entries(accounts)) {
    await getAuth().createUser({uid: uid(name), email: `${uid(name)}@example.invalid`, emailVerified: account.verified});
    await db.doc(`users/${uid(name)}`).set(account.profile);
  }
});

after(async () => {
  if (!emulated) return;
  await Promise.all(Object.keys(accounts).map((name) => getAuth().deleteUser(uid(name)).catch(() => undefined)));
});

test("only active verified admins can list, create, close or edit academic years", {skip: !emulated}, async () => {
  for (const actor of ["counselor", "staff", "student", "suspended-admin", "unverified-admin"]) {
    await rejects(as(listYears, actor), "permission-denied");
    await rejects(as(createYear, actor, {schoolYear: "2030-2031"}), "permission-denied");
    await rejects(as(closeYear, actor, {schoolYear: "2030-2031"}), "permission-denied");
    await rejects(as(getPop, actor, {schoolYear: "2030-2031"}), "permission-denied");
    await rejects(as(savePop, actor, {schoolYear: "2030-2031", populations: {}}), "permission-denied");
  }
  await rejects(listYears.run({}), "unauthenticated");
  await rejects(createYear.run({data: {schoolYear: "2030-2031"}}), "unauthenticated");
  await rejects(getPop.run({data: {schoolYear: "2030-2031"}}), "unauthenticated");
  await rejects(savePop.run({data: {schoolYear: "2030-2031", populations: {}}}), "unauthenticated");
});

test("authorized admin creates, closes and cannot overwrite closed years, while historical reports remain intact", {skip: !emulated}, async () => {
  const created = await as(createYear, "admin", {
    schoolYear: "2030-2031",
    startDate: "2030-06-01",
    endDate: "2031-05-31",
  });
  const year30 = created.years.find((y) => y.schoolYear === "2030-2031");
  assert.deepEqual(year30, {schoolYear: "2030-2031", startDate: "2030-06-01", endDate: "2031-05-31", status: "current"});

  // Duplicate active year is rejected while 2030-2031 is open.
  await rejects(as(createYear, "admin", {schoolYear: "2031-2032"}), "failed-precondition");

  // Save population on open year.
  const populations: Record<string, number> = {};
  const popConfig = await db.doc("counseling_population/2030-2031").get();
  assert.equal(popConfig.exists, true);
  for (const dept of [
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
  ]) populations[dept] = 10;
  await as(savePop, "admin", {schoolYear: "2030-2031", populations});

  // Cannot implicitly create a new year via saveCounselingPopulation.
  await rejects(as(savePop, "admin", {schoolYear: "2039-2040", populations}), "failed-precondition");

  // Seed a historical appointment tagged with 2030-2031.
  const apptRef = db.doc(`appointments/${prefix}-hist-1`);
  await apptRef.set({
    userId: uid("student"),
    academicYearId: "2030-2031",
    status: "completed",
    scheduledAt: Timestamp.fromDate(new Date("2030-09-15T01:00:00Z")),
  });

  // Close 2030-2031.
  const closed = await as(closeYear, "admin", {schoolYear: "2030-2031"});
  assert.equal(closed.years.find((y) => y.schoolYear === "2030-2031")?.status, "closed");

  // Cannot re-close or edit population of closed year.
  await rejects(as(closeYear, "admin", {schoolYear: "2030-2031"}), "failed-precondition");
  await rejects(as(savePop, "admin", {schoolYear: "2030-2031", populations}), "failed-precondition");

  // Overlapping date range with closed 2030-2031 is rejected.
  await rejects(as(createYear, "admin", {
    schoolYear: "2031-2032",
    startDate: "2031-05-31",
    endDate: "2032-05-30",
  }), "failed-precondition");

  // Historical report & appointment academicYearId are preserved after close.
  assert.equal((await apptRef.get()).data()?.academicYearId, "2030-2031");
  const reportRes = await as(fetchReport, "counselor", {schoolYear: "2030-2031"});
  assert.equal(reportRes.report.population.schoolYear, "2030-2031");
  assert.equal(reportRes.report.population.status, "closed");
  assert.equal(reportRes.report.population.totalPopulation, 140);
  assert.equal(reportRes.report.appointments.totalAppointments, 1);

  // Audit events recorded for create, population update, and close.
  const createdAudits = await db.collection("admin_audit_logs")
    .where("action", "==", "ACADEMIC_YEAR_CREATED")
    .where("targetId", "==", "2030-2031").get();
  const popAudits = await db.collection("admin_audit_logs")
    .where("action", "==", "ACADEMIC_YEAR_POPULATION_UPDATED")
    .where("targetId", "==", "2030-2031").get();
  const closedAudits = await db.collection("admin_audit_logs")
    .where("action", "==", "ACADEMIC_YEAR_CLOSED")
    .where("targetId", "==", "2030-2031").get();
  assert.equal(createdAudits.size, 1);
  assert.equal(popAudits.size, 1);
  assert.equal(closedAudits.size, 1);
});

test("concurrent createAcademicYear calls allow at most one active year", {skip: !emulated}, async () => {
  // Ensure no active year exists from earlier tests.
  const existing = await as(listYears, "admin");
  for (const year of existing.years.filter((y) => y.status !== "closed")) {
    await as(closeYear, "admin", {schoolYear: year.schoolYear});
  }

  const results = await Promise.allSettled([
    as(createYear, "admin", {schoolYear: "2032-2033", startDate: "2032-06-01", endDate: "2033-05-31"}),
    as(createYear, "admin", {schoolYear: "2033-2034", startDate: "2033-06-01", endDate: "2034-05-31"}),
  ]);
  const fulfilled = results.filter((r) => r.status === "fulfilled");
  const rejected = results.filter((r) => r.status === "rejected");
  assert.equal(fulfilled.length, 1);
  assert.equal(rejected.length, 1);

  const afterList = await as(listYears, "admin");
  assert.equal(afterList.years.filter((y) => y.status !== "closed").length, 1);
});

import assert from "node:assert/strict";
import {after, before, beforeEach, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {Timestamp, getFirestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import "./index";
import {AcademicYearError} from "./academic_year";
import {
  activateAcademicYear,
  activateAcademicYearForActor,
  closeAcademicYear,
  createAcademicYear,
  createAcademicYearForActor,
  getAcademicYears,
  getCounselingPopulation,
  listAcademicYears,
  saveCounselingPopulation,
  voidAcademicYear,
  voidAcademicYearForActor,
} from "./counseling_population";
import {getReportAnalytics} from "./report_generation";

const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const prefix = `ay-${Date.now()}`;
const uid = (name: string) => `${prefix}-${name}`;
const db = getFirestore();

type Callable<T> = {run: (r: {auth?: {uid: string}; data?: unknown}) => Promise<T>};
type YearItem = {schoolYear: string; startDate: string; endDate: string; status: string; revision?: number; voidReason?: string | null};
type YearList = {years: YearItem[]};
type ReportRes = {
  report: {
    appointments: {totalAppointments: number};
    population: {schoolYear: string; status: string; totalPopulation: number; years: YearItem[]};
    comparison: {schoolYear: string} | null;
    trends: Array<{schoolYear: string}>;
  };
};

const listYears = getAcademicYears as unknown as Callable<YearList>;
const createYear = createAcademicYear as unknown as Callable<YearList>;
const activateYear = activateAcademicYear as unknown as Callable<YearList>;
const closeYear = closeAcademicYear as unknown as Callable<YearList>;
const voidYear = voidAcademicYear as unknown as Callable<YearList>;
const getPop = getCounselingPopulation as unknown as Callable<Record<string, unknown>>;
const savePop = saveCounselingPopulation as unknown as Callable<Record<string, unknown>>;
const fetchReport = getReportAnalytics as unknown as Callable<ReportRes>;

const accounts: Record<string, {verified: boolean; profile: Record<string, unknown>}> = {
  "super-admin": {verified: true, profile: {accessRole: "admin", accountStatus: "active", name: "Super Admin"}},
  admin: {verified: true, profile: {accessRole: "admin", accountStatus: "active", name: "Portal Admin"}},
  "suspended-admin": {verified: true, profile: {accessRole: "admin", accountStatus: "suspended"}},
  "unverified-admin": {verified: false, profile: {accessRole: "admin", accountStatus: "active"}},
  counselor: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: ["cite"]}},
  "unassigned-counselor": {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: []}},
  staff: {verified: true, profile: {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active"}},
  student: {verified: true, profile: {accessRole: "appUser", role: "student", accountStatus: "active", collegeId: "cite"}},
};

const allDepartments = [
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
];
const fullPopulations = Object.fromEntries(allDepartments.map((d) => [d, 10]));

async function as<T>(callable: Callable<T>, actor: string, data?: Record<string, unknown>) {
  return callable.run({auth: {uid: uid(actor)}, data});
}
async function rejects(promise: Promise<unknown>, code: string) {
  await assert.rejects(
    promise,
    (e: unknown) =>
      (e instanceof HttpsError && e.code === code) ||
      (e instanceof AcademicYearError && e.code === code),
  );
}

async function clearAcademicYearDocs() {
  const snap = await db.collection("counseling_population").get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}

let prevSuperAdmin: string | undefined;
before(async () => {
  if (!emulated) return;
  prevSuperAdmin = process.env.SUPER_ADMIN_UID;
  process.env.SUPER_ADMIN_UID = uid("super-admin");
  for (const [name, account] of Object.entries(accounts)) {
    await getAuth().createUser({uid: uid(name), email: `${uid(name)}@example.invalid`, emailVerified: account.verified});
    await db.doc(`users/${uid(name)}`).set(account.profile);
  }
});

beforeEach(async () => {
  if (!emulated) return;
  await clearAcademicYearDocs();
});

after(async () => {
  if (!emulated) return;
  if (prevSuperAdmin === undefined) delete process.env.SUPER_ADMIN_UID;
  else process.env.SUPER_ADMIN_UID = prevSuperAdmin;
  await Promise.all(Object.keys(accounts).map((name) => getAuth().deleteUser(uid(name)).catch(() => undefined)));
});

test("only active verified admins manage years; only configured super-admin can void", {skip: !emulated}, async () => {
  for (const actor of ["counselor", "staff", "student", "suspended-admin", "unverified-admin"]) {
    await rejects(as(listYears, actor), "permission-denied");
    await rejects(as(createYear, actor, {schoolYear: "2026-2027"}), "permission-denied");
    await rejects(as(activateYear, actor, {schoolYear: "2027-2028"}), "permission-denied");
    await rejects(as(closeYear, actor, {schoolYear: "2026-2027"}), "permission-denied");
    await rejects(as(getPop, actor, {schoolYear: "2026-2027"}), "permission-denied");
    await rejects(as(savePop, actor, {schoolYear: "2026-2027", populations: {}}), "permission-denied");
    await rejects(as(voidYear, actor, {schoolYear: "2028-2029"}), "permission-denied");
  }
  // Regular active admin cannot void academic years (super-admin only).
  await rejects(as(voidYear, "admin", {schoolYear: "2028-2029", confirmation: "VOID 2028-2029", reason: "Not super admin", expectedRevision: 0}), "permission-denied");

  await rejects(listYears.run({}), "unauthenticated");
  await rejects(createYear.run({data: {schoolYear: "2026-2027"}}), "unauthenticated");
  await rejects(activateYear.run({data: {schoolYear: "2027-2028"}}), "unauthenticated");
  await rejects(voidYear.run({data: {schoolYear: "2028-2029"}}), "unauthenticated");
});

test("default compat mode disables planned/voided writes until Batch B2 deploys, proving legacy safety", {skip: !emulated}, async () => {
  const nowNov2026 = new Date("2026-11-17T03:00:00Z"); // 2026-11-17 Manila
  await createAcademicYearForActor(uid("admin"), accounts.admin.profile, {
    schoolYear: "2026-2027",
    startDate: "2026-06-01",
    endDate: "2027-05-31",
  }, {now: nowNov2026, extendedLifecycleEnabled: false});

  // Future planned year (2027-2028) is blocked while extendedLifecycleEnabled=false.
  await rejects(
    createAcademicYearForActor(uid("admin"), accounts.admin.profile, {
      schoolYear: "2027-2028",
      startDate: "2027-06-01",
      endDate: "2028-05-31",
    }, {now: nowNov2026, extendedLifecycleEnabled: false}),
    "failed-precondition",
  );
  // Void & activate callables default to extendedLifecycleEnabled=false when param is unset.
  await db.doc("counseling_population/2028-2029").set({
    schoolYear: "2028-2029",
    startDate: "2028-06-01",
    endDate: "2029-05-31",
    status: "current",
  });
  await rejects(as(voidYear, "super-admin", {
    schoolYear: "2028-2029",
    confirmation: "VOID 2028-2029",
    reason: "Should reject before Batch B2 deploy",
    expectedRevision: 0,
  }), "failed-precondition");
  await rejects(as(activateYear, "admin", {schoolYear: "2027-2028"}), "failed-precondition");

  // Proof of why: legacy status reader (`status === "closed" ? "closed" : "current"`)
  // would treat "planned" or "voided" as "current" and leak into reports/trends.
  const legacyMapper = (rawStatus: unknown) => (rawStatus === "closed" ? "closed" : "current");
  assert.equal(legacyMapper("planned"), "current");
  assert.equal(legacyMapper("voided"), "current");
  // New reader never silently turns unknown/voided/planned into "current":
  await db.doc("counseling_population/2099-2100").set({
    schoolYear: "2099-2100",
    startDate: "2099-06-01",
    endDate: "2100-05-31",
    status: "draft_unknown",
  });
  const listed = await listAcademicYears();
  assert.equal(listed.some((y) => y.schoolYear === "2099-2100"), false);
  await db.doc("counseling_population/2099-2100").delete();
});

test("full lifecycle: Manila horizon, planned -> active -> closed, and closed immutability", {skip: !emulated}, async () => {
  const nov2026 = new Date("2026-11-17T03:00:00Z"); // 2026-11-17 11:00 Manila
  // Distant future 2028-2029 rejected in 2026.
  await rejects(
    createAcademicYearForActor(uid("admin"), accounts.admin.profile, {
      schoolYear: "2028-2029",
    }, {now: nov2026, extendedLifecycleEnabled: true}),
    "failed-precondition",
  );

  // Create current 2026-2027.
  const res26 = await createAcademicYearForActor(uid("admin"), accounts.admin.profile, {
    schoolYear: "2026-2027",
    startDate: "2026-06-01",
    endDate: "2027-05-31",
  }, {now: nov2026, extendedLifecycleEnabled: true});
  assert.equal(res26.years.find((y) => y.schoolYear === "2026-2027")?.status, "current");

  // Save population on 2026-2027.
  await as(savePop, "admin", {schoolYear: "2026-2027", populations: fullPopulations});

  // Plan next year 2027-2028 alongside current 2026-2027 -> status MUST be "planned", NOT "current".
  const res27 = await createAcademicYearForActor(uid("admin"), accounts.admin.profile, {
    schoolYear: "2027-2028",
    startDate: "2027-06-01",
    endDate: "2028-05-31",
    copyFrom: "2026-2027",
    copyPopulation: true,
  }, {now: nov2026, extendedLifecycleEnabled: true});
  const item27 = res27.years.find((y) => y.schoolYear === "2027-2028");
  assert.equal(item27?.status, "planned");

  // Direct callable bypass attempt: admin CANNOT close a "planned" year directly.
  await rejects(as(closeYear, "admin", {schoolYear: "2027-2028"}), "failed-precondition");
  const listAfterBypassAttempt = await as(listYears, "admin");
  assert.equal(listAfterBypassAttempt.years.find((y) => y.schoolYear === "2027-2028")?.status, "planned");

  // Updated reporting excludes "planned" and "unknown" from trends and comparison!
  await db.doc("counseling_population/2025-2026").set({
    schoolYear: "2025-2026",
    startDate: "2025-06-01",
    endDate: "2026-05-31",
    status: "legacy_corrupted",
    populations: {},
  });
  const preActivationReport = await as(fetchReport, "counselor", {schoolYear: "2026-2027"});
  assert.equal(preActivationReport.report.trends.some((t) => t.schoolYear === "2027-2028"), false);
  assert.equal(preActivationReport.report.trends.some((t) => t.schoolYear === "2025-2026"), false);
  assert.equal(preActivationReport.report.comparison, null);
  await db.doc("counseling_population/2025-2026").delete();

  // Cannot activate 2027-2028 before startDate OR while 2026-2027 is open.
  await rejects(
    activateAcademicYearForActor(uid("admin"), accounts.admin.profile, {schoolYear: "2027-2028"}, {now: nov2026, extendedLifecycleEnabled: true}),
    "failed-precondition",
  );
  await rejects(
    activateAcademicYearForActor(uid("admin"), accounts.admin.profile, {schoolYear: "2027-2028"}, {now: new Date("2027-06-02T03:00:00Z"), extendedLifecycleEnabled: true}),
    "failed-precondition",
  );

  // Seed historical appointment for 2026-2027.
  const apptRef = db.doc(`appointments/${prefix}-hist-26`);
  await apptRef.set({
    userId: uid("student"),
    collegeId: "cite",
    academicYearId: "2026-2027",
    status: "completed",
    scheduledAt: Timestamp.fromDate(new Date("2026-09-15T01:00:00Z")),
  });

  // Close 2026-2027 cleanly; verify closed immutability & historical preservation.
  const closed = await as(closeYear, "admin", {schoolYear: "2026-2027"});
  assert.equal(closed.years.find((y) => y.schoolYear === "2026-2027")?.status, "closed");
  await rejects(as(savePop, "admin", {schoolYear: "2026-2027", populations: fullPopulations}), "failed-precondition");
  await rejects(as(closeYear, "admin", {schoolYear: "2026-2027"}), "failed-precondition");

  // Cannot activate 2027-2028 one day early (May 31 23:59 Manila = 15:59 UTC).
  await rejects(
    activateAcademicYearForActor(uid("admin"), accounts.admin.profile, {schoolYear: "2027-2028"}, {now: new Date("2027-05-31T15:59:00Z"), extendedLifecycleEnabled: true}),
    "failed-precondition",
  );
  // Activates cleanly on June 1 00:01 Manila = May 31 16:01 UTC!
  const activated = await activateAcademicYearForActor(
    uid("admin"),
    accounts.admin.profile,
    {schoolYear: "2027-2028", expectedRevision: item27?.revision},
    {now: new Date("2027-05-31T16:01:00Z"), extendedLifecycleEnabled: true},
  );
  assert.equal(activated.years.find((y) => y.schoolYear === "2027-2028")?.status, "current");

  // Historical report for closed 2026-2027 remains accurate; planned/excluded behavior verified.
  await rejects(as(fetchReport, "unassigned-counselor", {schoolYear: "2026-2027"}), "permission-denied");
  const report26 = await as(fetchReport, "counselor", {schoolYear: "2026-2027"});
  assert.equal(report26.report.population.schoolYear, "2026-2027");
  assert.equal(report26.report.population.status, "closed");
  assert.equal(report26.report.population.totalPopulation, 140);
  assert.equal(report26.report.appointments.totalAppointments, 1);

  await apptRef.delete();
});

test("voidAcademicYear preserves audit & snapshot, blocks dependency refs, hides from reports, and allows future reinstatement", {skip: !emulated}, async () => {
  const nov2026 = new Date("2026-11-17T03:00:00Z");
  await createAcademicYearForActor(uid("admin"), accounts.admin.profile, {
    schoolYear: "2026-2027",
    startDate: "2026-06-01",
    endDate: "2027-05-31",
  }, {now: nov2026, extendedLifecycleEnabled: true});
  await as(savePop, "admin", {schoolYear: "2026-2027", populations: fullPopulations});

  // Seed erroneous 2028-2029 (status: current, populations: {}) + historical REPORT_VIEWED audit event.
  await db.doc("counseling_population/2028-2029").set({
    schoolYear: "2028-2029",
    startDate: "2028-06-01",
    endDate: "2029-05-31",
    status: "current",
    populations: {},
  });
  const viewAuditRef = db.collection("admin_audit_logs").doc();
  await viewAuditRef.set({
    actorId: uid("super-admin"),
    action: "REPORT_VIEWED",
    category: "REPORTS",
    targetType: "report",
    targetId: "2028-2029",
  });

  // Stale revision fails with aborted.
  await rejects(
    voidAcademicYearForActor(uid("super-admin"), accounts["super-admin"].profile, {
      schoolYear: "2028-2029",
      confirmation: "VOID 2028-2029",
      reason: "Erroneous future year cleanup.",
      expectedRevision: 99,
    }, {extendedLifecycleEnabled: true}),
    "aborted",
  );

  // Operational dependency blocks voiding (e.g. a report referencing 2028-2029).
  const blockerReport = db.collection("reports").doc();
  await blockerReport.set({academicYearId: "2028-2029"});
  await rejects(
    voidAcademicYearForActor(uid("super-admin"), accounts["super-admin"].profile, {
      schoolYear: "2028-2029",
      confirmation: "VOID 2028-2029",
      reason: "Erroneous future year cleanup.",
      expectedRevision: 0,
    }, {extendedLifecycleEnabled: true}),
    "failed-precondition",
  );
  await blockerReport.delete();

  // Legacy wire key confirmationText MUST NOT be accepted; only canonical "confirmation".
  await rejects(
    voidAcademicYearForActor(uid("super-admin"), accounts["super-admin"].profile, {
      schoolYear: "2028-2029",
      confirmationText: "VOID 2028-2029",
      reason: "Erroneous premature future academic year.",
      expectedRevision: 0,
    }, {extendedLifecycleEnabled: true}),
    "invalid-argument",
  );

  // Succeeds once zero operational/population dependencies exist.
  const afterVoid = await voidAcademicYearForActor(uid("super-admin"), accounts["super-admin"].profile, {
    schoolYear: "2028-2029",
    confirmation: "VOID 2028-2029",
    reason: "Erroneous premature future academic year.",
    expectedRevision: 0,
    includeVoided: true,
  }, {extendedLifecycleEnabled: true});
  const voided28 = afterVoid.years.find((y) => y.schoolYear === "2028-2029");
  assert.equal(voided28?.status, "voided");

  // Physical doc preserved with snapshot & subcollection void_history; prior REPORT_VIEWED audit preserved.
  const voidDoc = await db.doc("counseling_population/2028-2029").get();
  assert.equal(voidDoc.exists, true);
  assert.equal(voidDoc.data()?.voidedSnapshot?.status, "current");
  const voidHistSnap = await db.collection("counseling_population/2028-2029/void_history").get();
  assert.equal(voidHistSnap.size, 1);
  const rev1Before = (await db.doc("counseling_population/2028-2029/void_history/rev_1").get()).data();
  assert.ok(rev1Before);
  assert.equal((await viewAuditRef.get()).exists, true);
  const voidAuditsBefore = await db.collection("admin_audit_logs").where("action", "==", "ACADEMIC_YEAR_VOIDED").where("targetId", "==", "2028-2029").get();
  assert.equal(voidAuditsBefore.size, 1);
  const voidAuditDataBefore = voidAuditsBefore.docs[0].data();

  // Voided 2028-2029 excluded from default list, comparison, trends, and direct reporting!
  const defaultList = await as(listYears, "admin");
  assert.equal(defaultList.years.some((y) => y.schoolYear === "2028-2029"), false);
  await rejects(as(fetchReport, "counselor", {schoolYear: "2028-2029"}), "failed-precondition");
  const report26 = await as(fetchReport, "counselor", {schoolYear: "2026-2027"});
  assert.equal(report26.report.population.years.some((y) => y.schoolYear === "2028-2029"), false);
  assert.equal(report26.report.trends.some((t) => t.schoolYear === "2028-2029"), false);

  // Future reuse: rejects stale or malformed revision and oversized reinstateReason; succeeds with valid inputs.
  await as(closeYear, "admin", {schoolYear: "2026-2027"});
  await rejects(
    createAcademicYearForActor(uid("admin"), accounts.admin.profile, {
      schoolYear: "2028-2029",
      expectedRevision: "1",
    }, {now: new Date("2028-06-05T03:00:00Z"), extendedLifecycleEnabled: true}),
    "invalid-argument",
  );
  await rejects(
    createAcademicYearForActor(uid("admin"), accounts.admin.profile, {
      schoolYear: "2028-2029",
      expectedRevision: 0,
    }, {now: new Date("2028-06-05T03:00:00Z"), extendedLifecycleEnabled: true}),
    "aborted",
  );
  await rejects(
    createAcademicYearForActor(uid("admin"), accounts.admin.profile, {
      schoolYear: "2028-2029",
      reinstateReason: "x".repeat(501),
    }, {now: new Date("2028-06-05T03:00:00Z"), extendedLifecycleEnabled: true}),
    "invalid-argument",
  );
  const reinstated = await createAcademicYearForActor(uid("admin"), accounts.admin.profile, {
    schoolYear: "2028-2029",
    startDate: "2028-06-01",
    endDate: "2029-05-31",
    expectedRevision: 1,
    reinstateReason: "Confirmed SY 2028-2029 enrollment schedule",
  }, {now: new Date("2028-06-05T03:00:00Z"), extendedLifecycleEnabled: true});
  const active28 = reinstated.years.find((y) => y.schoolYear === "2028-2029");
  assert.equal(active28?.status, "current");
  assert.equal(active28?.revision, 2);

  // Original void_history/rev_1 AND original ACADEMIC_YEAR_VOIDED audit doc remain COMPLETELY UNCHANGED!
  const rev1After = (await db.doc("counseling_population/2028-2029/void_history/rev_1").get()).data();
  assert.deepEqual(rev1After, rev1Before);
  const voidAuditsAfter = await db.collection("admin_audit_logs").where("action", "==", "ACADEMIC_YEAR_VOIDED").where("targetId", "==", "2028-2029").get();
  assert.equal(voidAuditsAfter.size, 1);
  assert.deepEqual(voidAuditsAfter.docs[0].data(), voidAuditDataBefore);

  // Separate append-only reinstate_history + audit metadata record reinstateReason.
  const reinstateHist = await db.doc("counseling_population/2028-2029/reinstate_history/rev_2").get();
  assert.equal(reinstateHist.exists, true);
  assert.equal(reinstateHist.data()?.reinstateReason, "Confirmed SY 2028-2029 enrollment schedule");
  const reinstateAudits = await db.collection("admin_audit_logs").where("action", "==", "ACADEMIC_YEAR_REINSTATED").where("targetId", "==", "2028-2029").get();
  assert.equal(reinstateAudits.size, 1);
  assert.equal(reinstateAudits.docs[0].data()?.metadata?.reinstateReason, "Confirmed SY 2028-2029 enrollment schedule");

  // Second void -> reinstate cycle preserves rev_1, creates rev_3 and reinstate_history/rev_4!
  await voidAcademicYearForActor(uid("super-admin"), accounts["super-admin"].profile, {
    schoolYear: "2028-2029",
    confirmation: "VOID 2028-2029",
    reason: "Second void test for history preservation",
    expectedRevision: 2,
  }, {extendedLifecycleEnabled: true});
  await createAcademicYearForActor(uid("admin"), accounts.admin.profile, {
    schoolYear: "2028-2029",
    expectedRevision: 3,
    reinstateReason: "Second reinstatement",
  }, {now: new Date("2028-06-06T03:00:00Z"), extendedLifecycleEnabled: true});
  assert.deepEqual((await db.doc("counseling_population/2028-2029/void_history/rev_1").get()).data(), rev1Before);
  assert.equal((await db.doc("counseling_population/2028-2029/void_history/rev_3").get()).exists, true);
  assert.equal((await db.doc("counseling_population/2028-2029/reinstate_history/rev_2").get()).exists, true);
  assert.equal((await db.doc("counseling_population/2028-2029/reinstate_history/rev_4").get()).exists, true);
});

test("defensive validation blocks malformed stored dates, malformed revisions, invalid copy sources, and concurrent activations", {skip: !emulated}, async () => {
  // getAcademicYears surfaces extendedLifecycleEnabled=false cleanly by default.
  const meta = await listYears.run({auth: {uid: uid("admin")}, data: {}}) as unknown as {
    years: YearItem[];
    extendedLifecycleEnabled?: boolean;
  };
  assert.equal(meta.extendedLifecycleEnabled, false);

  // Corrupted stored dates fail cleanly instead of throwing Timestamp NaN error.
  await db.doc("counseling_population/2028-2029").set({
    schoolYear: "2028-2029",
    startDate: "2028-02-31",
    endDate: "2029-05-31",
    status: "current",
    populations: {},
  });
  await rejects(
    voidAcademicYearForActor(uid("super-admin"), accounts["super-admin"].profile, {
      schoolYear: "2028-2029",
      confirmation: "VOID 2028-2029",
      reason: "Cleanup corrupted dates",
      expectedRevision: 0,
    }, {extendedLifecycleEnabled: true}),
    "failed-precondition",
  );

  // Unknown stored status fails closed in void, close, activate, and listAcademicYears.
  await db.doc("counseling_population/2027-2028").set({
    schoolYear: "2027-2028",
    startDate: "2027-06-01",
    endDate: "2028-05-31",
    status: "unknown_state",
    populations: {},
  });
  await rejects(
    voidAcademicYearForActor(uid("super-admin"), accounts["super-admin"].profile, {
      schoolYear: "2027-2028",
      confirmation: "VOID 2027-2028",
      reason: "Trying to void unknown state",
      expectedRevision: 0,
    }, {extendedLifecycleEnabled: true}),
    "failed-precondition",
  );
  await rejects(as(closeYear, "admin", {schoolYear: "2027-2028"}), "failed-precondition");
  assert.equal((await listAcademicYears({includeUnknown: false})).some((y) => y.schoolYear === "2027-2028"), false);

  // Invalid copyPopulation sources (missing, unknown, voided) rejected; valid source filters non-department keys.
  await db.doc("counseling_population/2026-2027").set({
    schoolYear: "2026-2027",
    startDate: "2026-06-01",
    endDate: "2027-05-31",
    status: "current",
    populations: {...fullPopulations, UNKNOWN_DEPT: 999},
  });
  await db.doc("counseling_population/2028-2029").set({
    schoolYear: "2028-2029",
    startDate: "2028-06-01",
    endDate: "2029-05-31",
    status: "voided",
    populations: {},
  });
  await db.doc("counseling_population/2027-2028").delete();

  await rejects(
    createAcademicYearForActor(uid("admin"), accounts.admin.profile, {
      schoolYear: "2027-2028",
      copyFrom: "2025-2026",
      copyPopulation: true,
    }, {now: new Date("2026-11-17T03:00:00Z"), extendedLifecycleEnabled: true}),
    "not-found",
  );
  await rejects(
    createAcademicYearForActor(uid("admin"), accounts.admin.profile, {
      schoolYear: "2027-2028",
      copyFrom: "2028-2029",
      copyPopulation: true,
    }, {now: new Date("2026-11-17T03:00:00Z"), extendedLifecycleEnabled: true}),
    "failed-precondition",
  );
  await createAcademicYearForActor(uid("admin"), accounts.admin.profile, {
    schoolYear: "2027-2028",
    copyFrom: "2026-2027",
    copyPopulation: true,
  }, {now: new Date("2026-11-17T03:00:00Z"), extendedLifecycleEnabled: true});
  const copiedDoc = (await db.doc("counseling_population/2027-2028").get()).data();
  assert.equal("UNKNOWN_DEPT" in (copiedDoc?.populations ?? {}), false);

  // Malformed expectedRevision rejected on close & activate rather than ignored.
  await rejects(as(closeYear, "admin", {schoolYear: "2026-2027", expectedRevision: "0"}), "invalid-argument");
  await as(closeYear, "admin", {schoolYear: "2026-2027"});
  await rejects(
    activateAcademicYearForActor(uid("admin"), accounts.admin.profile, {
      schoolYear: "2027-2028",
      expectedRevision: -1,
    }, {now: new Date("2027-06-01T03:00:00Z"), extendedLifecycleEnabled: true}),
    "invalid-argument",
  );

  // Concurrent activations succeed at most once when expectedRevision is enforced.
  const rev27 = (await db.doc("counseling_population/2027-2028").get()).data()?.revision ?? 1;
  const race = await Promise.allSettled([
    activateAcademicYearForActor(uid("admin"), accounts.admin.profile, {
      schoolYear: "2027-2028",
      expectedRevision: rev27,
    }, {now: new Date("2027-06-01T03:00:00Z"), extendedLifecycleEnabled: true}),
    activateAcademicYearForActor(uid("admin"), accounts.admin.profile, {
      schoolYear: "2027-2028",
      expectedRevision: rev27,
    }, {now: new Date("2027-06-01T03:00:00Z"), extendedLifecycleEnabled: true}),
  ]);
  assert.equal(race.filter((r) => r.status === "fulfilled").length, 1);
});

test("concurrent createAcademicYear calls allow at most one active year", {skip: !emulated}, async () => {
  const results = await Promise.allSettled([
    createAcademicYearForActor(uid("admin"), accounts.admin.profile, {
      schoolYear: "2026-2027",
      startDate: "2026-06-01",
      endDate: "2027-05-31",
    }, {now: new Date("2026-11-17T03:00:00Z"), extendedLifecycleEnabled: true}),
    createAcademicYearForActor(uid("admin"), accounts.admin.profile, {
      schoolYear: "2026-2027",
      startDate: "2026-06-01",
      endDate: "2027-05-31",
    }, {now: new Date("2026-11-17T03:00:00Z"), extendedLifecycleEnabled: true}),
  ]);
  const fulfilled = results.filter((r) => r.status === "fulfilled");
  const rejected = results.filter((r) => r.status === "rejected");
  assert.equal(fulfilled.length, 1);
  assert.equal(rejected.length, 1);
  const afterList = await as(listYears, "admin");
  assert.equal(afterList.years.filter((y) => y.status === "current").length, 1);
});

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {after, before, test} from "node:test";

import {getApps, initializeApp as initializeAdminApp} from "firebase-admin/app";
import {getAuth as getAdminAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {deleteApp, initializeApp} from "firebase/app";
import {connectAuthEmulator, getAuth, signInWithEmailAndPassword} from "firebase/auth";
import {connectFunctionsEmulator, getFunctions, httpsCallable} from "firebase/functions";

import {resolveInquiry} from "./inquiry_routing_service";

const projectId = process.env.GCLOUD_PROJECT ?? "demo-mindmate-mood-v2-local";
const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
const [authHostname, authPort] = authHost.split(":");
const functionsHost = process.env.FUNCTIONS_EMULATOR_HOST ?? "127.0.0.1";
const functionsPort = Number(process.env.FUNCTIONS_EMULATOR_PORT ?? "5001");

if (!getApps().length) initializeAdminApp({projectId});
const db = getFirestore();
const adminAuth = getAdminAuth();

const prefix = `inq-http-${Date.now()}`;
const uid = (name: string) => `${prefix}-${name}`;
const collegeId = `${prefix}-cite`;
const password = "emulator-test-password-123";

function readEnvLocalSuperAdmin(): string {
  const candidates = [
    path.resolve(process.cwd(), ".env.local"),
    path.resolve(process.cwd(), "functions/.env.local"),
  ];
  for (const candidate of candidates) {
    if (!fs.existsSync(candidate)) continue;
    const content = fs.readFileSync(candidate, "utf8");
    for (const line of content.split(/\r?\n/)) {
      const match = line.match(/^\s*SUPER_ADMIN_UID\s*=\s*(.+?)\s*$/);
      if (match?.[1]) {
        return match[1].replace(/^["']|["']$/g, "").trim();
      }
    }
  }
  return "";
}

const emulatorSuperAdminUid = (process.env.SUPER_ADMIN_UID ?? "").trim() || readEnvLocalSuperAdmin();

type Callable = {run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<unknown>};

interface UserSeed {
  uid: string;
  email: string;
  emailVerified: boolean;
  disabled?: boolean;
  profile: Record<string, unknown>;
}

const staffSeeds: Record<string, UserSeed> = {
  c1: {
    uid: uid("c1"),
    email: `${uid("c1")}@example.invalid`,
    emailVerified: true,
    profile: {
      accessRole: "counselor",
      staffAccountStatus: "approved",
      accountStatus: "active",
      name: "Counselor One",
      assignedCollegeIds: [collegeId],
    },
  },
  legacyCounselor: {
    uid: uid("legacy-c"),
    email: `${uid("legacy-c")}@example.invalid`,
    emailVerified: true,
    profile: {
      role: "counselor",
      firstName: "",
      lastName: "",
      assignedCollegeIds: [collegeId],
    },
  },
  pendingStaff: {
    uid: uid("pending-c"),
    email: `${uid("pending-c")}@example.invalid`,
    emailVerified: true,
    profile: {
      accessRole: "counselor",
      staffAccountStatus: "pending",
      accountStatus: "active",
      name: "Pending Counselor",
      assignedCollegeIds: [collegeId],
    },
  },
  disabledCounselor: {
    uid: uid("disabled-c"),
    email: `${uid("disabled-c")}@example.invalid`,
    emailVerified: true,
    profile: {
      accessRole: "counselor",
      staffAccountStatus: "approved",
      accountStatus: "active",
      name: "Disabled Counselor",
      assignedCollegeIds: [collegeId],
    },
  },
  s1: {
    uid: uid("s1"),
    email: `${uid("s1")}@example.invalid`,
    emailVerified: true,
    profile: {
      accessRole: "portalStaff",
      staffAccountStatus: "approved",
      accountStatus: "active",
      name: "Monitor Staff",
    },
  },
  student: {
    uid: uid("student"),
    email: `${uid("student")}@example.invalid`,
    emailVerified: true,
    profile: {
      accessRole: "appUser",
      populationRole: "student",
      verificationStatus: "verified",
      collegeId,
    },
  },
};

let seq = 0;
let createdSuperAdminAuth = false;
let previousSuperAdminProfile: FirebaseFirestore.DocumentData | null | undefined;
let superAdminExistedInFirestore = false;

async function withClientCallable<T>(
  userUid: string,
  email: string,
  fn: (
    call: (name: string, payload: Record<string, unknown>) => Promise<Record<string, unknown>>,
    appName: string,
  ) => Promise<T>,
  options?: {disableAfterSignIn?: boolean},
): Promise<T> {
  seq += 1;
  const appName = `inq-http-client-${prefix}-${seq}`;
  const app = initializeApp(
    {projectId, apiKey: "emulator-only-api-key"},
    appName,
  );
  try {
    const auth = getAuth(app);
    connectAuthEmulator(auth, `http://${authHostname}:${authPort}`, {disableWarnings: true});
    await signInWithEmailAndPassword(auth, email, password);
    if (options?.disableAfterSignIn) {
      await adminAuth.updateUser(userUid, {disabled: true});
    }
    const functions = getFunctions(app, "us-central1");
    connectFunctionsEmulator(functions, functionsHost, functionsPort);
    const call = async (name: string, payload: Record<string, unknown>) => {
      const callable = httpsCallable<Record<string, unknown>, Record<string, unknown>>(functions, name);
      const result = await callable(payload);
      return result.data;
    };
    return await fn(call, appName);
  } finally {
    await deleteApp(app);
  }
}

let docSeq = 0;
async function seedInquiry(data: Record<string, unknown>): Promise<string> {
  const id = `${prefix}-inq-${++docSeq}`;
  await db.doc(`inquiries/${id}`).set(data);
  return id;
}

async function expectCallableRejects(
  promise: Promise<unknown>,
  expectedCode: string,
  messageSubstring?: string,
): Promise<void> {
  await assert.rejects(
    promise,
    (err: unknown) => {
      assert.ok(typeof err === "object" && err !== null, `Expected error object, got ${String(err)}`);
      const code = (err as {code?: string}).code;
      const message = String((err as {message?: string}).message ?? "");
      assert.equal(code, expectedCode, `Expected ${expectedCode}, got ${code}: ${message}`);
      if (messageSubstring) {
        assert.ok(
          message.includes(messageSubstring),
          `Expected message "${message}" to include "${messageSubstring}"`,
        );
      }
      return true;
    },
  );
}

async function auditEvents(inquiryId: string, action: string): Promise<FirebaseFirestore.DocumentData[]> {
  const snap = await db.collection("admin_audit_logs")
    .where("targetId", "==", inquiryId)
    .where("action", "==", action)
    .get();
  return snap.docs.map((d) => d.data());
}

async function waitFor<T>(
  probe: () => Promise<T | null>,
  timeoutMs = 10000,
  intervalMs = 150,
): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const value = await probe();
    if (value !== null) return value;
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  throw new Error(`Timed out after ${timeoutMs}ms waiting for emulator state.`);
}

before(async () => {
  if (!emulated) return;
  await db.doc(`colleges/${collegeId}`).set({name: "CITE", code: "CITE", active: true});
  for (const seed of Object.values(staffSeeds)) {
    await adminAuth.createUser({
      uid: seed.uid,
      email: seed.email,
      password,
      emailVerified: seed.emailVerified,
      disabled: seed.disabled === true,
    });
    await db.doc(`users/${seed.uid}`).set(seed.profile);
  }
  if (emulatorSuperAdminUid) {
    try {
      await adminAuth.getUser(emulatorSuperAdminUid);
      await adminAuth.updateUser(emulatorSuperAdminUid, {
        email: `${emulatorSuperAdminUid}@example.invalid`,
        password,
        emailVerified: true,
        disabled: false,
      });
    } catch {
      await adminAuth.createUser({
        uid: emulatorSuperAdminUid,
        email: `${emulatorSuperAdminUid}@example.invalid`,
        password,
        emailVerified: true,
        disabled: false,
      });
      createdSuperAdminAuth = true;
    }
    const userDoc = await db.doc(`users/${emulatorSuperAdminUid}`).get();
    superAdminExistedInFirestore = userDoc.exists;
    previousSuperAdminProfile = userDoc.data() ?? null;
    await db.doc(`users/${emulatorSuperAdminUid}`).set({
      accessRole: "admin",
      accountStatus: "active",
      name: "Emulator Super Admin",
    });
  }
});

after(async () => {
  if (!emulated) return;
  await Promise.all(
    Object.values(staffSeeds).map((s) => adminAuth.deleteUser(s.uid).catch(() => undefined)),
  );
  if (emulatorSuperAdminUid) {
    if (createdSuperAdminAuth) {
      await adminAuth.deleteUser(emulatorSuperAdminUid).catch(() => undefined);
    }
    if (superAdminExistedInFirestore && previousSuperAdminProfile) {
      await db.doc(`users/${emulatorSuperAdminUid}`).set(previousSuperAdminProfile);
    } else if (!superAdminExistedInFirestore) {
      await db.doc(`users/${emulatorSuperAdminUid}`).delete().catch(() => undefined);
    }
  }
});

test(
  "HTTP onCall resolveInquiry resolves staging-like fixtures cleanly (ack-only, reply-only, legacy missing/null revision, partial projection, legacy counselor, timestamp variants)",
  {skip: !emulated},
  async () => {
    const c1 = staffSeeds.c1;
    const legacyC = staffSeeds.legacyCounselor;

    // 1. acknowledgedAt only (no firstResponseAt, no acknowledgedBy)
    const ackOnlyId = await seedInquiry({
      userId: staffSeeds.student.uid,
      subject: "Ack only",
      message: "Body",
      category: "General",
      status: "in_progress",
      routingStatus: "routed",
      routingRevision: 2,
      assigneeIds: [c1.uid],
      acknowledgedAt: Timestamp.now(),
      createdAt: Timestamp.now(),
    });
    await withClientCallable(c1.uid, c1.email, async (call) => {
      const res = await call("resolveInquiry", {inquiryId: ackOnlyId, expectedRevision: 2});
      assert.deepEqual(res, {ok: true, changed: true, revision: 3});
    });
    const ackOnlyDoc = (await db.doc(`inquiries/${ackOnlyId}`).get()).data()!;
    assert.equal(ackOnlyDoc.status, "resolved");
    assert.equal(ackOnlyDoc.resolvedBy, c1.uid);
    assert.equal(ackOnlyDoc.routingRevision, 3);
    assert.equal((await auditEvents(ackOnlyId, "INQUIRY_RESOLVED")).length, 1);

    // 2. firstResponseAt only (no acknowledgedAt)
    const replyOnlyId = await seedInquiry({
      userId: staffSeeds.student.uid,
      subject: "Reply only",
      message: "Body",
      category: "General",
      status: "in_progress",
      routingStatus: "routed",
      routingRevision: 1,
      assigneeIds: [c1.uid],
      firstResponseAt: Timestamp.now(),
      createdAt: Timestamp.now(),
    });
    await withClientCallable(c1.uid, c1.email, async (call) => {
      const res = await call("resolveInquiry", {inquiryId: replyOnlyId, expectedRevision: 1});
      assert.deepEqual(res, {ok: true, changed: true, revision: 2});
    });

    // 3. Legacy missing routingRevision (undefined) & missing inquiry_statuses/{id} with expectedRevision: 0
    const legacyZeroId = await seedInquiry({
      userId: staffSeeds.student.uid,
      subject: "Legacy undefined revision",
      message: "Legacy body",
      status: "in_progress",
      assigneeIds: [c1.uid],
      acknowledgedAt: new Date("2026-11-20T10:00:00.000Z"),
      createdAt: new Date("2026-11-20T09:00:00.000Z"),
    });
    await withClientCallable(c1.uid, c1.email, async (call) => {
      const res = await call("resolveInquiry", {inquiryId: legacyZeroId, expectedRevision: 0});
      assert.deepEqual(res, {ok: true, changed: true, revision: 1});
    });
    assert.ok((await db.doc(`inquiry_statuses/${legacyZeroId}`).get()).exists);

    // 4. Legacy routingRevision: null & partial legacy inquiry_statuses/{id} with expectedRevision: null & omitted
    const legacyNullRevId = await seedInquiry({
      userId: staffSeeds.student.uid,
      subject: "Legacy null revision",
      message: "Body",
      status: "in_progress",
      routingRevision: null,
      assigneeIds: [c1.uid],
      acknowledgedAt: Date.now(),
      createdAt: Date.now(),
    });
    await db.doc(`inquiry_statuses/${legacyNullRevId}`).set({
      status: "in_progress",
      extraField: "legacy",
    });
    await withClientCallable(c1.uid, c1.email, async (call) => {
      const res = await call("resolveInquiry", {inquiryId: legacyNullRevId, expectedRevision: null});
      assert.deepEqual(res, {ok: true, changed: true, revision: 1});
    });
    assert.equal((await db.doc(`inquiry_statuses/${legacyNullRevId}`).get()).data()!.status, "resolved");

    const legacyOmittedExpId = await seedInquiry({
      userId: staffSeeds.student.uid,
      subject: "Legacy omitted expectedRevision",
      message: "Body",
      status: "in_progress",
      assigneeIds: [c1.uid],
      firstResponseAt: "2026-11-20T12:00:00.000Z",
      createdAt: "2026-11-20T11:00:00.000Z",
    });
    await withClientCallable(c1.uid, c1.email, async (call) => {
      const res = await call("resolveInquiry", {inquiryId: legacyOmittedExpId});
      assert.deepEqual(res, {ok: true, changed: true, revision: 1});
    });

    // 5. Legacy counselor profile missing accessRole (role: 'counselor', empty name fields)
    const legacyCounselorInqId = await seedInquiry({
      userId: staffSeeds.student.uid,
      subject: "Legacy counselor",
      message: "Body",
      status: "in_progress",
      assigneeIds: [legacyC.uid],
      acknowledgedAt: Timestamp.now(),
      createdAt: Timestamp.now(),
    });
    await withClientCallable(legacyC.uid, legacyC.email, async (call) => {
      const res = await call("resolveInquiry", {inquiryId: legacyCounselorInqId, expectedRevision: 0});
      assert.deepEqual(res, {ok: true, changed: true, revision: 1});
    });
    const legacyAudit = await auditEvents(legacyCounselorInqId, "INQUIRY_RESOLVED");
    assert.equal(legacyAudit.length, 1);
    assert.equal(typeof legacyAudit[0].actorNameSnapshot, "string");
    assert.ok(legacyAudit[0].actorNameSnapshot.length > 0);
  },
);

test(
  "HTTP onCall resolveInquiry & setInquiryStatus preserve c8a7189/f8e1801 security invariants and reject malformed empty/boolean timestamps",
  {skip: !emulated},
  async () => {
    const c1 = staffSeeds.c1;

    // 1. Direct pending -> resolved rejected
    const pendingId = await seedInquiry({
      userId: staffSeeds.student.uid,
      subject: "Pending",
      message: "Body",
      status: "pending",
      routingRevision: 1,
      assigneeIds: [c1.uid],
      createdAt: Timestamp.now(),
    });
    await withClientCallable(c1.uid, c1.email, async (call) => {
      await expectCallableRejects(
        call("resolveInquiry", {inquiryId: pendingId, expectedRevision: 1}),
        "functions/failed-precondition",
        "Acknowledge receipt before marking this inquiry as resolved.",
      );
      // Two-step bypass: setInquiryStatus("in_progress") without acknowledgment -> resolveInquiry still rejected
      const step1 = await call("setInquiryStatus", {
        inquiryId: pendingId,
        status: "in_progress",
        expectedRevision: 1,
      });
      assert.deepEqual(step1, {ok: true, changed: true, revision: 2});
      await expectCallableRejects(
        call("resolveInquiry", {inquiryId: pendingId, expectedRevision: 2}),
        "functions/failed-precondition",
        "Acknowledge receipt before marking this inquiry as resolved.",
      );
      await expectCallableRejects(
        call("setInquiryStatus", {inquiryId: pendingId, status: "resolved", expectedRevision: 2}),
        "functions/failed-precondition",
        "Acknowledge receipt before marking this inquiry as resolved.",
      );
    });

    // 2. Malformed timestamps on acknowledgedAt / firstResponseAt MUST be rejected (failed-precondition)
    for (const badFields of [
      {acknowledgedAt: ""},
      {acknowledgedAt: false},
      {acknowledgedAt: {}},
      {acknowledgedAt: []},
      {acknowledgedAt: {invalid: true}},
      {acknowledgedAt: "not-a-date"},
      {acknowledgedAt: 0},
      {acknowledgedAt: -1},
      {firstResponseAt: ""},
      {firstResponseAt: false},
      {firstResponseAt: {}},
      {firstResponseAt: []},
      {firstResponseAt: {invalid: true}},
      {firstResponseAt: "not-a-date"},
      {firstResponseAt: 0},
      {firstResponseAt: -1},
    ]) {
      const badId = await seedInquiry({
        userId: staffSeeds.student.uid,
        subject: "Malformed timestamp",
        message: "Body",
        status: "in_progress",
        routingRevision: 1,
        assigneeIds: [c1.uid],
        createdAt: Timestamp.now(),
        ...badFields,
      });
      await withClientCallable(c1.uid, c1.email, async (call) => {
        await expectCallableRejects(
          call("resolveInquiry", {inquiryId: badId, expectedRevision: 1}),
          "functions/failed-precondition",
          "Acknowledge receipt before marking this inquiry as resolved.",
        );
        await expectCallableRejects(
          call("setInquiryStatus", {inquiryId: badId, status: "resolved", expectedRevision: 1}),
          "functions/failed-precondition",
          "Acknowledge receipt before marking this inquiry as resolved.",
        );
      });
      assert.equal((await db.doc(`inquiries/${badId}`).get()).data()!.status, "in_progress");
    }

    // 2b. acknowledgeInquiry is NOT falsely blocked by malformed acknowledgedAt: {} on a legacy pending doc
    const malformedPendingId = await seedInquiry({
      userId: staffSeeds.student.uid,
      subject: "Malformed ack on pending",
      message: "Body",
      status: "pending",
      routingRevision: 1,
      assigneeIds: [c1.uid],
      acknowledgedAt: {},
      createdAt: Timestamp.now(),
    });
    await withClientCallable(c1.uid, c1.email, async (call) => {
      const ackRes = await call("acknowledgeInquiry", {inquiryId: malformedPendingId, expectedRevision: 1});
      assert.deepEqual(ackRes, {ok: true});
      const resolveRes = await call("resolveInquiry", {inquiryId: malformedPendingId, expectedRevision: 2});
      assert.deepEqual(resolveRes, {ok: true, changed: true, revision: 3});
    });

    // 3. Legitimate setInquiryStatus("resolved") succeeds when acknowledged
    const setStatusOkId = await seedInquiry({
      userId: staffSeeds.student.uid,
      subject: "Set status ok",
      message: "Body",
      status: "in_progress",
      routingRevision: 0,
      assigneeIds: [c1.uid],
      acknowledgedAt: Timestamp.now(),
      createdAt: Timestamp.now(),
    });
    await withClientCallable(c1.uid, c1.email, async (call) => {
      const res = await call("setInquiryStatus", {
        inquiryId: setStatusOkId,
        status: "resolved",
        expectedRevision: 0,
      });
      assert.deepEqual(res, {ok: true, changed: true, revision: 1});
    });
  },
);

test(
  "HTTP onCall resolveInquiry enforces takeover, super-admin access, disabled/pending staff denial, stale/duplicate/concurrent race protection, and notification archival",
  {skip: !emulated},
  async () => {
    const c1 = staffSeeds.c1;

    // 1. Disabled Auth user & pending staff rejected (permission-denied)
    const activeInqId = await seedInquiry({
      userId: staffSeeds.student.uid,
      subject: "Staff gate",
      message: "Body",
      status: "in_progress",
      routingRevision: 1,
      assigneeIds: [c1.uid, staffSeeds.pendingStaff.uid, staffSeeds.disabledCounselor.uid],
      acknowledgedAt: Timestamp.now(),
      createdAt: Timestamp.now(),
    });
    await withClientCallable(staffSeeds.pendingStaff.uid, staffSeeds.pendingStaff.email, async (call) => {
      await expectCallableRejects(
        call("resolveInquiry", {inquiryId: activeInqId, expectedRevision: 1}),
        "functions/permission-denied",
      );
    });
    await withClientCallable(
      staffSeeds.disabledCounselor.uid,
      staffSeeds.disabledCounselor.email,
      async (call) => {
        await expectCallableRejects(
          call("resolveInquiry", {inquiryId: activeInqId, expectedRevision: 1}),
          "functions/permission-denied",
        );
      },
      {disableAfterSignIn: true},
    );

    // 2. Stale revision & duplicate resolve rejected (failed-precondition)
    await withClientCallable(c1.uid, c1.email, async (call) => {
      await expectCallableRejects(
        call("resolveInquiry", {inquiryId: activeInqId, expectedRevision: 0}),
        "functions/failed-precondition",
        "updated by someone else",
      );
      const ok = await call("resolveInquiry", {inquiryId: activeInqId, expectedRevision: 1});
      assert.deepEqual(ok, {ok: true, changed: true, revision: 2});
      await expectCallableRejects(
        call("resolveInquiry", {inquiryId: activeInqId, expectedRevision: 2}),
        "functions/failed-precondition",
        "already resolved",
      );
    });

    // 3. Concurrent HTTP Promise.all race on legacy undefined-revision inquiry
    const raceId = await seedInquiry({
      userId: staffSeeds.student.uid,
      subject: "Concurrent race",
      message: "Body",
      status: "in_progress",
      assigneeIds: [c1.uid],
      acknowledgedAt: Timestamp.now(),
      createdAt: Timestamp.now(),
    });
    await withClientCallable(c1.uid, c1.email, async (call) => {
      const outcomes = await Promise.allSettled([
        call("resolveInquiry", {inquiryId: raceId, expectedRevision: 0}),
        call("resolveInquiry", {inquiryId: raceId}),
      ]);
      const fulfilled = outcomes.filter((o) => o.status === "fulfilled");
      const rejected = outcomes.filter((o) => o.status === "rejected");
      assert.equal(fulfilled.length, 1);
      assert.equal(rejected.length, 1);
      assert.equal((rejected[0] as PromiseRejectedResult & {reason: {code?: string}}).reason.code, "functions/failed-precondition");
    });
    assert.equal((await auditEvents(raceId, "INQUIRY_RESOLVED")).length, 1);

    // 4. resolvePortalInquiryNotifications archives portal notifications on resolve while keeping student notifications unarchived
    const notifyInqId = await seedInquiry({
      userId: staffSeeds.student.uid,
      subject: "Legacy notification archive",
      message: "Body",
      status: "in_progress",
      assigneeIds: [c1.uid],
      acknowledgedAt: Timestamp.now(),
      createdAt: Timestamp.now(),
      // Intentionally omit assignedTo, collegeId, studentId, routingRevision
    });
    const portalNoteRef = db.collection("notifications").doc(`portal_inquiry_${notifyInqId}_${c1.uid}`);
    const studentNoteRef = db.collection("notifications").doc(`${prefix}-student-note-${notifyInqId}`);
    await portalNoteRef.set({
      userId: c1.uid,
      type: "inquiry",
      audience: "portal",
      inquiryId: notifyInqId,
      title: "New inquiry",
      body: "Ready for review",
      createdAt: FieldValue.serverTimestamp(),
      readAt: null,
      resolvedAt: null,
      archiveEligibleAt: null,
      archivedAt: null,
      expiresAt: null,
    });
    await studentNoteRef.set({
      userId: staffSeeds.student.uid,
      type: "inquiry",
      inquiryId: notifyInqId,
      title: "Form received",
      body: "PACC received your inquiry.",
      createdAt: FieldValue.serverTimestamp(),
      readAt: null,
      archivedAt: null,
    });
    await withClientCallable(c1.uid, c1.email, async (call) => {
      await call("resolveInquiry", {inquiryId: notifyInqId, expectedRevision: 0});
    });
    const archivedPortalNote = await waitFor(async () => {
      const snap = await portalNoteRef.get();
      const data = snap.data();
      return data?.archivedAt != null ? data : null;
    });
    assert.ok(archivedPortalNote.resolvedAt != null);
    assert.ok(archivedPortalNote.expiresAt != null);
    assert.equal(archivedPortalNote.archiveEligibleAt, null);
    const studentNoteAfter = (await studentNoteRef.get()).data()!;
    assert.equal(studentNoteAfter.archivedAt ?? null, null);

    // 5. Super-admin HTTP onCall: unassigned inquiry + post-takeover inquiry
    if (emulatorSuperAdminUid) {
      const unassignedId = await seedInquiry({
        userId: staffSeeds.student.uid,
        subject: "Unassigned triage",
        message: "Body",
        status: "in_progress",
        routingStatus: "needs_triage",
        routingRevision: 1,
        assigneeIds: [],
        acknowledgedAt: Timestamp.now(),
        createdAt: Timestamp.now(),
      });
      await withClientCallable(emulatorSuperAdminUid, `${emulatorSuperAdminUid}@example.invalid`, async (call) => {
        const res = await call("resolveInquiry", {inquiryId: unassignedId, expectedRevision: 1});
        assert.deepEqual(res, {ok: true, changed: true, revision: 2});
      });

      const takeoverId = await seedInquiry({
        userId: staffSeeds.student.uid,
        subject: "Taken over inquiry",
        message: "Body",
        status: "in_progress",
        routingStatus: "routed",
        routingRevision: 2,
        assigneeIds: [c1.uid],
        acknowledgedAt: Timestamp.now(),
        createdAt: Timestamp.now(),
      });
      await withClientCallable(emulatorSuperAdminUid, `${emulatorSuperAdminUid}@example.invalid`, async (call) => {
        await call("takeOverInquiry", {
          inquiryId: takeoverId,
          expectedRevision: 2,
          reason: "Supervisor handling",
        });
      });
      await withClientCallable(c1.uid, c1.email, async (call) => {
        await expectCallableRejects(
          call("resolveInquiry", {inquiryId: takeoverId, expectedRevision: 3}),
          "functions/permission-denied",
        );
      });
      await withClientCallable(emulatorSuperAdminUid, `${emulatorSuperAdminUid}@example.invalid`, async (call) => {
        const res = await call("resolveInquiry", {inquiryId: takeoverId, expectedRevision: 3});
        assert.deepEqual(res, {ok: true, changed: true, revision: 4});
      });
    }
  },
);

test(
  "INQUIRY_REQUIRE_EXPECTED_REVISION=true rejects omitted expectedRevision on resolveInquiry",
  {skip: !emulated},
  async () => {
    const strictId = await seedInquiry({
      userId: staffSeeds.student.uid,
      subject: "Strict revision",
      message: "Body",
      status: "in_progress",
      routingRevision: 1,
      assigneeIds: [staffSeeds.c1.uid],
      acknowledgedAt: Timestamp.now(),
      createdAt: Timestamp.now(),
    });
    const prev = process.env.INQUIRY_REQUIRE_EXPECTED_REVISION;
    process.env.INQUIRY_REQUIRE_EXPECTED_REVISION = "true";
    try {
      await assert.rejects(
        (resolveInquiry as unknown as Callable).run({
          auth: {uid: staffSeeds.c1.uid},
          data: {inquiryId: strictId},
        }),
        (err: unknown) => err instanceof HttpsError && err.code === "invalid-argument",
      );
    } finally {
      if (prev === undefined) delete process.env.INQUIRY_REQUIRE_EXPECTED_REVISION;
      else process.env.INQUIRY_REQUIRE_EXPECTED_REVISION = prev;
    }
  },
);

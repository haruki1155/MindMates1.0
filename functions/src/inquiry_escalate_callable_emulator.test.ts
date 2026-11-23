import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {after, before, test} from "node:test";

import {getApps, initializeApp as initializeAdminApp} from "firebase-admin/app";
import {getAuth as getAdminAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {deleteApp, initializeApp} from "firebase/app";
import {connectAuthEmulator, getAuth, signInWithEmailAndPassword} from "firebase/auth";
import {connectFunctionsEmulator, getFunctions, httpsCallable} from "firebase/functions";

import {escalateInquiry} from "./inquiry_routing_service";

const projectId = process.env.GCLOUD_PROJECT ?? "demo-mindmate-mood-v2-local";
const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
const [authHostname, authPort] = authHost.split(":");
const functionsHost = process.env.FUNCTIONS_EMULATOR_HOST ?? "127.0.0.1";
const functionsPort = Number(process.env.FUNCTIONS_EMULATOR_PORT ?? "5001");

if (!getApps().length) initializeAdminApp({projectId});
const db = getFirestore();
const adminAuth = getAdminAuth();

const prefix = `inq-esc-http-${Date.now()}`;
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
  c2: {
    uid: uid("c2"),
    email: `${uid("c2")}@example.invalid`,
    emailVerified: true,
    profile: {
      accessRole: "counselor",
      staffAccountStatus: "approved",
      accountStatus: "active",
      name: "Counselor Two",
      assignedCollegeIds: [`${prefix}-cas`],
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
  ) => Promise<T>,
  options?: {disableAfterSignIn?: boolean},
): Promise<T> {
  seq += 1;
  const appName = `inq-esc-client-${prefix}-${seq}`;
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
    return await fn(call);
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

before(async () => {
  if (!emulated) return;
  await db.doc(`colleges/${collegeId}`).set({name: "CITE", code: "CITE", active: true});
  await db.doc(`colleges/${prefix}-cas`).set({name: "CAS", code: "CAS", active: true});
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
  "HTTP onCall escalateInquiry supports counselor confirmation without reason while enforcing revision, duplicate, takeover, audit, notification, and role contracts",
  {skip: !emulated},
  async () => {
    assert.ok(
      emulatorSuperAdminUid,
      "SUPER_ADMIN_UID (env or functions/.env.local) is required for emulated escalateInquiry tests.",
    );
    const c1 = staffSeeds.c1;
    const c2 = staffSeeds.c2;
    const s1 = staffSeeds.s1;

    const id = await seedInquiry({
      userId: staffSeeds.student.uid,
      subject: "Counselor escalation",
      message: "Confidential student concern",
      category: "General",
      collegeId,
      status: "in_progress",
      routingStatus: "routed",
      routingRevision: 2,
      assigneeIds: [c1.uid, staffSeeds.pendingStaff.uid, staffSeeds.disabledCounselor.uid],
      monitoringStaffIds: [s1.uid],
      createdAt: Timestamp.now(),
    });

    // Unauthorized callers rejected
    await withClientCallable(c2.uid, c2.email, async (call) => {
      await expectCallableRejects(
        call("escalateInquiry", {inquiryId: id, escalationType: "counselor_confirmation", expectedRevision: 2}),
        "functions/permission-denied",
      );
    });
    await withClientCallable(staffSeeds.pendingStaff.uid, staffSeeds.pendingStaff.email, async (call) => {
      await expectCallableRejects(
        call("escalateInquiry", {inquiryId: id, escalationType: "counselor_confirmation", expectedRevision: 2}),
        "functions/permission-denied",
      );
    });
    await withClientCallable(
      staffSeeds.disabledCounselor.uid,
      staffSeeds.disabledCounselor.email,
      async (call) => {
        await expectCallableRejects(
          call("escalateInquiry", {inquiryId: id, escalationType: "counselor_confirmation", expectedRevision: 2}),
          "functions/permission-denied",
        );
      },
      {disableAfterSignIn: true},
    );
    await withClientCallable(staffSeeds.student.uid, staffSeeds.student.email, async (call) => {
      await expectCallableRejects(
        call("escalateInquiry", {inquiryId: id, escalationType: "counselor_confirmation", expectedRevision: 2}),
        "functions/permission-denied",
      );
    });
    await withClientCallable(emulatorSuperAdminUid, `${emulatorSuperAdminUid}@example.invalid`, async (call) => {
      await expectCallableRejects(
        call("escalateInquiry", {inquiryId: id}),
        "functions/permission-denied",
      );
    });

    // portalStaff without reason rejected; stale expectedRevision rejected; invalid escalationType rejected
    await withClientCallable(s1.uid, s1.email, async (call) => {
      await expectCallableRejects(
        call("escalateInquiry", {inquiryId: id, expectedRevision: 2}),
        "functions/invalid-argument",
      );
      await expectCallableRejects(
        call("escalateInquiry", {inquiryId: id, escalationType: "counselor_confirmation", expectedRevision: 2}),
        "functions/invalid-argument",
      );
    });
    await withClientCallable(c1.uid, c1.email, async (call) => {
      await expectCallableRejects(
        call("escalateInquiry", {inquiryId: id, escalationType: "staff_reasoned", expectedRevision: 2}),
        "functions/invalid-argument",
      );
      await expectCallableRejects(
        call("escalateInquiry", {inquiryId: id, escalationType: "counselor_confirmation", expectedRevision: 1}),
        "functions/failed-precondition",
        "updated by someone else",
      );
    });

    // Concurrent confirmation calls: exactly one succeeds
    await withClientCallable(c1.uid, c1.email, async (call) => {
      const outcomes = await Promise.allSettled([
        call("escalateInquiry", {inquiryId: id, escalationType: "counselor_confirmation", expectedRevision: 2}),
        call("escalateInquiry", {inquiryId: id, escalationType: "counselor_confirmation", expectedRevision: 2}),
      ]);
      const fulfilled = outcomes.filter((o) => o.status === "fulfilled");
      const rejected = outcomes.filter((o) => o.status === "rejected");
      assert.equal(fulfilled.length, 1);
      assert.equal(rejected.length, 1);
      assert.equal((rejected[0] as PromiseRejectedResult & {reason: {code?: string}}).reason.code, "functions/failed-precondition");

      // Duplicate escalation rejected
      await expectCallableRejects(
        call("escalateInquiry", {inquiryId: id, escalationType: "counselor_confirmation", expectedRevision: 3}),
        "functions/failed-precondition",
        "already escalated",
      );
    });

    const doc = (await db.doc(`inquiries/${id}`).get()).data()!;
    assert.deepEqual(
      [doc.escalation.status, doc.escalation.type, doc.escalation.reason, doc.escalation.requestedBy, doc.routingRevision],
      ["requested", "counselor_confirmation", null, c1.uid, 3],
    );

    const proj = (await db.doc(`inquiry_statuses/${id}`).get()).data()!;
    assert.equal(proj.escalationStatus, "requested");
    assert.equal(proj.escalationType, undefined);
    assert.equal(proj.escalationReason, undefined);
    assert.ok(!JSON.stringify(proj).includes("counselor_confirmation"));

    const audits = await auditEvents(id, "INQUIRY_ESCALATED");
    assert.equal(audits.length, 1);
    assert.deepEqual(audits[0].metadata, {
      escalationType: "counselor_confirmation",
      reasonProvided: false,
      reason: null,
      recipient: emulatorSuperAdminUid,
      revision: 3,
      revisionChecked: true,
    });

    const noteSnap = await db.doc(`notifications/portal_inquiry_escalation_${id}_2`).get();
    assert.equal(noteSnap.exists, true);
    assert.equal(noteSnap.data()?.userId, emulatorSuperAdminUid);

    // Admin takeover & reassign still enforce 3-500 char reason and preserve escalation.type
    await withClientCallable(emulatorSuperAdminUid, `${emulatorSuperAdminUid}@example.invalid`, async (call) => {
      await expectCallableRejects(
        call("takeOverInquiry", {inquiryId: id, expectedRevision: 3, reason: "no"}),
        "functions/invalid-argument",
      );
      await expectCallableRejects(
        call("reassignInquiry", {inquiryId: id, assigneeIds: [c2.uid], expectedRevision: 3, reason: "no"}),
        "functions/invalid-argument",
      );
      await call("takeOverInquiry", {
        inquiryId: id,
        expectedRevision: 3,
        reason: "Administrator reviewing escalated inquiry",
      });
    });

    const takenDoc = (await db.doc(`inquiries/${id}`).get()).data()!;
    assert.equal(takenDoc.escalation.status, "handled");
    assert.equal(takenDoc.escalation.type, "counselor_confirmation");
    assert.equal(takenDoc.routingRevision, 4);

    // Post-takeover escalation is rejected with permission-denied
    const postTakeoverId = await seedInquiry({
      userId: staffSeeds.student.uid,
      subject: "Taken over before escalation",
      message: "Body",
      category: "General",
      collegeId,
      status: "in_progress",
      routingStatus: "routed",
      routingRevision: 2,
      assigneeIds: [c1.uid],
      takeover: {by: emulatorSuperAdminUid, byName: "Emulator Super Admin", reason: "Handling"},
      createdAt: Timestamp.now(),
    });
    await withClientCallable(c1.uid, c1.email, async (call) => {
      await expectCallableRejects(
        call("escalateInquiry", {inquiryId: postTakeoverId, escalationType: "counselor_confirmation", expectedRevision: 2}),
        "functions/permission-denied",
      );
    });

    // portalStaff reasoned escalation succeeds via HTTP callable
    const staffInqId = await seedInquiry({
      userId: staffSeeds.student.uid,
      subject: "Monitor escalation",
      message: "Body",
      category: "General",
      collegeId,
      status: "in_progress",
      routingStatus: "routed",
      routingRevision: 1,
      assigneeIds: [c1.uid],
      monitoringStaffIds: [s1.uid],
      createdAt: Timestamp.now(),
    });
    await withClientCallable(s1.uid, s1.email, async (call) => {
      const res = await call("escalateInquiry", {
        inquiryId: staffInqId,
        escalationType: "staff_reasoned",
        reason: "Operational SLA escalation",
        expectedRevision: 1,
      });
      assert.deepEqual(res, {ok: true});
    });
    const staffDoc = (await db.doc(`inquiries/${staffInqId}`).get()).data()!;
    assert.equal(staffDoc.escalation.type, "staff_reasoned");
    assert.equal(staffDoc.escalation.reason, "Operational SLA escalation");

    // Resolved inquiry cannot be escalated
    const resolvedId = await seedInquiry({
      userId: staffSeeds.student.uid,
      subject: "Resolved",
      message: "Body",
      category: "General",
      collegeId,
      status: "resolved",
      routingStatus: "routed",
      routingRevision: 2,
      assigneeIds: [c1.uid],
      createdAt: Timestamp.now(),
    });
    await withClientCallable(c1.uid, c1.email, async (call) => {
      await expectCallableRejects(
        call("escalateInquiry", {inquiryId: resolvedId, escalationType: "counselor_confirmation", expectedRevision: 2}),
        "functions/failed-precondition",
      );
    });
  },
);

test(
  "INQUIRY_REQUIRE_EXPECTED_REVISION=true rejects omitted expectedRevision on escalateInquiry",
  {skip: !emulated},
  async () => {
    const strictId = await seedInquiry({
      userId: staffSeeds.student.uid,
      subject: "Strict revision escalation",
      message: "Body",
      status: "in_progress",
      routingRevision: 1,
      assigneeIds: [staffSeeds.c1.uid],
      createdAt: Timestamp.now(),
    });
    const prev = process.env.INQUIRY_REQUIRE_EXPECTED_REVISION;
    const prevSuperAdmin = process.env.SUPER_ADMIN_UID;
    process.env.INQUIRY_REQUIRE_EXPECTED_REVISION = "true";
    process.env.SUPER_ADMIN_UID = emulatorSuperAdminUid || uid("strict-super-admin");
    try {
      await assert.rejects(
        (escalateInquiry as unknown as Callable).run({
          auth: {uid: staffSeeds.c1.uid},
          data: {inquiryId: strictId, escalationType: "counselor_confirmation"},
        }),
        (err: unknown) => err instanceof HttpsError && err.code === "invalid-argument",
      );
    } finally {
      if (prev === undefined) delete process.env.INQUIRY_REQUIRE_EXPECTED_REVISION;
      else process.env.INQUIRY_REQUIRE_EXPECTED_REVISION = prev;
      if (prevSuperAdmin === undefined) delete process.env.SUPER_ADMIN_UID;
      else process.env.SUPER_ADMIN_UID = prevSuperAdmin;
    }
  },
);

import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {deleteApp, initializeApp} from "firebase/app";
import {connectAuthEmulator, getAuth as getClientAuth, signInWithEmailAndPassword} from "firebase/auth";
import {
  collection,
  connectFirestoreEmulator,
  doc,
  getDoc,
  getDocs,
  getFirestore as getClientFirestore,
  query,
  where,
} from "firebase/firestore";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {canonicalLoginId} from "./account_recovery";
import {
  appointmentScopeSyncHooks,
  syncStudentAppointmentsCollegeScopeFromUserProfile,
} from "./appointment_approval_service";
import {
  createAppointmentRequest,
  importStudentRoster,
  reviewProfileVerification,
  reviewStudentCorrection,
  revokeStudentActivation,
  setStaffCollegeAssignments,
  syncStudentAppointmentCollegeScope,
  updateStudentRosterRecord,
} from "./index";
import {rosterTestHooks} from "./student_roster";

const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const projectId = process.env.GCLOUD_PROJECT ?? "demo-mindmate-test";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
const [authHostname, authPort] = authHost.split(":");
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
const [fsHostname, fsPort] = firestoreHost.split(":");

const prefix = `stage5-${Date.now()}`;
const uid = (name: string) => `${prefix}-${name}`;
const password = "stage5-test-password";
const studentNo = `${Date.now().toString().slice(-8)}`;
const studentKey = canonicalLoginId(studentNo);
const collegeA = `${prefix}-cite`;
const collegeB = `${prefix}-cas`;
const deptA = `${prefix}-dept-a`;
const deptB = `${prefix}-dept-b`;
const courseA = `${prefix}-course-a`;
const courseB = `${prefix}-course-b`;
const db = getFirestore();

type Callable = {run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<any>};
const call = (fn: unknown, actor: string, data: Record<string, unknown>) =>
  (fn as Callable).run({auth: {uid: uid(actor)}, data});

const accounts: Record<string, {verified: boolean; profile: Record<string, unknown>}> = {
  admin: {verified: true, profile: {accessRole: "admin", accountStatus: "active", name: "Super Admin"}},
  counselorA: {
    verified: true,
    profile: {
      accessRole: "counselor",
      staffAccountStatus: "approved",
      accountStatus: "active",
      name: "Counselor A",
      assignedCollegeIds: [collegeA],
      collegeAssignmentRevision: 0,
    },
  },
  counselorB: {
    verified: true,
    profile: {
      accessRole: "counselor",
      staffAccountStatus: "approved",
      accountStatus: "active",
      name: "Counselor B",
      assignedCollegeIds: [],
      collegeAssignmentRevision: 0,
    },
  },
  student: {
    verified: true,
    profile: {
      accessRole: "appUser",
      role: "student",
      populationRole: "student",
      accountStatus: "active",
      name: "Test Student",
      email: `${uid("student")}@example.invalid`,
      schoolId: studentNo,
      collegeId: collegeA,
      college: "College A",
      courseId: courseA,
      course: "BS Course A",
      departmentId: deptA,
      department: "Dept A",
      yearLevel: "2nd Year",
      verificationStatus: "verified",
    },
  },
};

let clientSeq = 0;
async function asClientFirestore(actorName: string) {
  clientSeq += 1;
  const app = initializeApp(
    {projectId, apiKey: "stage5-emulator-api-key"},
    `stage5-client-${clientSeq}`,
  );
  const clientAuth = getClientAuth(app);
  connectAuthEmulator(clientAuth, `http://${authHostname}:${authPort}`, {disableWarnings: true});
  await signInWithEmailAndPassword(clientAuth, `${uid(actorName)}@example.invalid`, password);
  const clientDb = getClientFirestore(app);
  connectFirestoreEmulator(clientDb, fsHostname, Number(fsPort));
  return {
    clientDb,
    close: () => deleteApp(app).catch(() => undefined),
  };
}

async function listCollegeAppointmentsAsCounselor(
  clientDb: ReturnType<typeof getClientFirestore>,
  targetCollegeId: string,
  studentId?: string,
) {
  const constraints = [
    where("studentVerificationStatus", "==", "verified"),
    where("collegeId", "in", [targetCollegeId]),
    ...(studentId ? [where("userId", "==", studentId)] : []),
  ];
  const snap = await getDocs(query(collection(clientDb, "appointments"), ...constraints));
  return snap.docs.map((d) => ({id: d.id, ...d.data()}));
}

const createdAppointmentIds: string[] = [];

let previousSuperAdmin: string | undefined;
before(async () => {
  if (!emulated) return;
  previousSuperAdmin = process.env.SUPER_ADMIN_UID;
  process.env.SUPER_ADMIN_UID = uid("admin");
  await db.doc("system_config/security").set({superAdminUid: uid("admin")});
  for (const [name, account] of Object.entries(accounts)) {
    await getAuth().createUser({
      uid: uid(name),
      email: `${uid(name)}@example.invalid`,
      password,
      emailVerified: account.verified,
    });
    await db.doc(`users/${uid(name)}`).set(account.profile);
  }
  await Promise.all([
    db.doc(`colleges/${collegeA}`).set({name: "College A", code: "CA", active: true}),
    db.doc(`colleges/${collegeB}`).set({name: "College B", code: "CB", active: true}),
    db.doc(`departments/${deptA}`).set({name: "Dept A", collegeId: collegeA, active: true}),
    db.doc(`departments/${deptB}`).set({name: "Dept B", collegeId: collegeB, active: true}),
    db.doc(`courses/${courseA}`).set({
      name: "BS Course A", code: "BSCA", collegeId: collegeA, departmentId: deptA, active: true,
    }),
    db.doc(`courses/${courseB}`).set({
      name: "BS Course B", code: "BSCB", collegeId: collegeB, departmentId: deptB, active: true,
    }),
    db.doc(`student_roster/${studentKey}`).set({
      studentNo,
      surname: "Student",
      firstName: "Test",
      middleName: "",
      dateOfBirthKey: "2004-01-15",
      dateOfBirth: Timestamp.fromDate(new Date("2004-01-15T00:00:00Z")),
      collegeId: collegeA,
      college: "College A",
      courseId: courseA,
      course: "BS Course A",
      departmentId: deptA,
      department: "Dept A",
      yearLevel: "2nd Year",
      activated: true,
      userId: uid("student"),
    }),
    db.doc("pacc_availability/current").set({
      openDays: [1, 2, 3, 4, 5], opensAt: "08:00", closesAt: "17:00",
      presence: "in_office", acceptsWalkIns: false, notice: "", blackoutDates: [],
    }),
  ]);
});

after(async () => {
  appointmentScopeSyncHooks.maxAtomicUpdates = undefined;
  appointmentScopeSyncHooks.maxProfileSyncChunkSize = undefined;
  appointmentScopeSyncHooks.maxProfileSyncPasses = undefined;
  appointmentScopeSyncHooks.beforeAtomicCommit = undefined;
  rosterTestHooks.batchLimit = undefined;
  rosterTestHooks.afterClassify = undefined;
  (rosterTestHooks as Record<string, unknown>).timeBudgetMs = undefined;
  (rosterTestHooks as Record<string, unknown>).beforeFinalize = undefined;
  (rosterTestHooks as Record<string, unknown>).afterStep = undefined;
  (rosterTestHooks as Record<string, unknown>).onCodeMinted = undefined;
  if (!emulated) return;
  if (previousSuperAdmin == null) delete process.env.SUPER_ADMIN_UID;
  else process.env.SUPER_ADMIN_UID = previousSuperAdmin;
  await Promise.all([
    ...Object.keys(accounts).map((name) => getAuth().deleteUser(uid(name)).catch(() => undefined)),
    ...Object.keys(accounts).map((name) => db.doc(`users/${uid(name)}`).delete().catch(() => undefined)),
    ...createdAppointmentIds.map((id) => db.doc(`appointments/${id}`).delete().catch(() => undefined)),
    db.doc(`student_roster/${studentKey}`).delete().catch(() => undefined),
    db.doc(`colleges/${collegeA}`).delete().catch(() => undefined),
    db.doc(`colleges/${collegeB}`).delete().catch(() => undefined),
    db.doc(`departments/${deptA}`).delete().catch(() => undefined),
    db.doc(`departments/${deptB}`).delete().catch(() => undefined),
    db.doc(`courses/${courseA}`).delete().catch(() => undefined),
    db.doc(`courses/${courseB}`).delete().catch(() => undefined),
  ]);
});

test(
  "atomic profile updates revoke Counselor A immediately, authorize Counselor B only when assigned, and handle revocation",
  {skip: !emulated},
  async () => {
    const apptId = `${prefix}-appt-main`;
    createdAppointmentIds.push(apptId);
    await db.doc(`appointments/${apptId}`).set({
      userId: uid("student"),
      fullName: "Test Student",
      status: "completed",
      collegeId: collegeA,
      studentVerificationStatus: "verified",
      scheduledAt: Timestamp.fromMillis(Date.now() - 86_400_000),
    });

    const clientA = await asClientFirestore("counselorA");
    const clientB = await asClientFirestore("counselorB");
    try {
      // Initial state: Counselor A lists College A appointment; Counselor B cannot list College B or A.
      const aInitial = await listCollegeAppointmentsAsCounselor(clientA.clientDb, collegeA, uid("student"));
      assert.deepEqual(aInitial.map((d) => d.id), [apptId]);
      await assert.rejects(listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeA, uid("student")));
      await assert.rejects(listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeB, uid("student")));

      // Student transfers from College A to College B via updateStudentRosterRecord (atomic tx).
      await call(updateStudentRosterRecord, "admin", {
        studentNo,
        fields: {college: "College B", course: "BS Course B"},
      });

      // Immediately after transaction: Counselor A sees 0 records in College A and cannot query College B.
      const aAfterTransfer = await listCollegeAppointmentsAsCounselor(clientA.clientDb, collegeA, uid("student"));
      assert.deepEqual(aAfterTransfer, []);
      await assert.rejects(listCollegeAppointmentsAsCounselor(clientA.clientDb, collegeB, uid("student")));

      // Counselor B is still unassigned -> still denied on College B list!
      await assert.rejects(listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeB, uid("student")));

      // Assign College B to Counselor B -> Counselor B immediately sees the appointment.
      await call(setStaffCollegeAssignments, "admin", {
        userId: uid("counselorB"),
        collegeIds: [collegeB],
        expectedRevision: 0,
        reason: "Cover College B",
      });
      const bAfterAssign = await listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeB, uid("student"));
      assert.deepEqual(bAfterAssign.map((d) => d.id), [apptId]);

      // Student verification is revoked -> Counselor B immediately sees 0 records atomically.
      await call(reviewProfileVerification, "admin", {
        userId: uid("student"),
        decision: "needsReview",
        reason: "Re-verification requested",
      });
      const bAfterRevoke = await listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeB, uid("student"));
      assert.deepEqual(bAfterRevoke, []);

      // Re-verify student & transfer back via reviewStudentCorrection(field: "college") cleanly.
      await call(reviewProfileVerification, "admin", {
        userId: uid("student"),
        decision: "verified",
        reason: "Re-verified",
      });
      const reqRef = db.collection("student_correction_requests").doc(`${prefix}-corr-1`);
      await reqRef.set({
        userId: uid("student"),
        studentKey,
        field: "college",
        requestedValue: collegeA,
        status: "pending",
      });
      // Update roster courseId temporarily to courseA first (required by reviewStudentCorrection invariant),
      // then reset user.collegeId to collegeB to test reviewStudentCorrection(college -> collegeA) in isolation.
      await db.doc(`student_roster/${studentKey}`).update({courseId: courseA, course: "BS Course A"});
      try {
        await call(reviewStudentCorrection, "admin", {
          requestId: reqRef.id,
          decision: "approve",
          reason: "Approved college correction",
        });
        const aAfterCorr = await listCollegeAppointmentsAsCounselor(clientA.clientDb, collegeA, uid("student"));
        assert.deepEqual(aAfterCorr.map((d) => d.id), [apptId]);
        const bAfterCorr = await listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeB, uid("student"));
        assert.deepEqual(bAfterCorr, []);
      } finally {
        await reqRef.delete().catch(() => undefined);
      }
    } finally {
      await clientA.close();
      await clientB.close();
    }
  },
);

test(
  "concurrent counselor assignment, appointment creation, many historical appointments, retries, and fail-closed overflow",
  {skip: !emulated},
  async () => {
    // Restore clean baseline state on College A + Counselor A.
    await db.doc(`users/${uid("student")}`).update({collegeId: collegeA, verificationStatus: "verified"});
    await db.doc(`student_roster/${studentKey}`).update({
      collegeId: collegeA, college: "College A", courseId: courseA, course: "BS Course A",
      departmentId: deptA, department: "Dept A",
    });
    const revA = Number((await db.doc(`users/${uid("counselorA")}`).get()).data()?.collegeAssignmentRevision ?? 0);
    await call(setStaffCollegeAssignments, "admin", {
      userId: uid("counselorA"),
      collegeIds: [collegeA],
      expectedRevision: revA,
      reason: "Reset Counselor A",
    });
    const revB = Number((await db.doc(`users/${uid("counselorB")}`).get()).data()?.collegeAssignmentRevision ?? 0);
    await call(setStaffCollegeAssignments, "admin", {
      userId: uid("counselorB"),
      collegeIds: [],
      expectedRevision: revB,
      reason: "Reset Counselor B",
    });

    // Seed 50 historical appointments for the student in College A.
    const bulkIds: string[] = [];
    const batch = db.batch();
    for (let i = 0; i < 50; i++) {
      const id = `${prefix}-hist-${i}`;
      bulkIds.push(id);
      createdAppointmentIds.push(id);
      batch.set(db.doc(`appointments/${id}`), {
        userId: uid("student"),
        fullName: "Test Student",
        status: "completed",
        collegeId: collegeA,
        studentVerificationStatus: "verified",
        scheduledAt: Timestamp.fromMillis(Date.now() - (i + 2) * 86_400_000),
      });
    }
    await batch.commit();

    // 1. Fail-closed check when stale appointments exceed safe transaction limit:
    // Verify ZERO partial updates to user, roster, correction request, or appointments.
    const overflowReq = db.collection("student_correction_requests").doc(`${prefix}-corr-overflow`);
    await overflowReq.set({
      userId: uid("student"),
      studentKey,
      field: "college",
      requestedValue: collegeB,
      status: "pending",
    });
    try {
      appointmentScopeSyncHooks.maxAtomicUpdates = 10;
      await assert.rejects(
        call(updateStudentRosterRecord, "admin", {
          studentNo,
          fields: {college: "College B", course: "BS Course B"},
        }),
        (err: unknown) => err instanceof HttpsError && err.code === "failed-precondition",
      );
      // Confirm ZERO partial commits happened anywhere.
      const userAfterFail = (await db.doc(`users/${uid("student")}`).get()).data()!;
      const rosterAfterFail = (await db.doc(`student_roster/${studentKey}`).get()).data()!;
      const sampleApptAfterFail = (await db.doc(`appointments/${bulkIds[0]}`).get()).data()!;
      assert.equal(userAfterFail.collegeId, collegeA);
      assert.equal(rosterAfterFail.collegeId, collegeA);
      assert.equal(sampleApptAfterFail.collegeId, collegeA);

      await assert.rejects(
        call(reviewProfileVerification, "admin", {
          userId: uid("student"),
          decision: "needsReview",
          reason: "Should fail closed atomically",
        }),
        (err: unknown) => err instanceof HttpsError && err.code === "failed-precondition",
      );
      assert.equal((await db.doc(`users/${uid("student")}`).get()).data()!.verificationStatus, "verified");
    } finally {
      appointmentScopeSyncHooks.maxAtomicUpdates = undefined;
      await overflowReq.delete().catch(() => undefined);
    }

    // 2. Genuine concurrent write contention on first attempt -> Firestore transaction retries and succeeds with 50 historical records.
    let attempt = 0;
    appointmentScopeSyncHooks.beforeAtomicCommit = async () => {
      attempt += 1;
      if (attempt === 1) {
        await db.doc(`users/${uid("student")}`).update({concurrentTouch: attempt});
      }
    };
    try {
      await call(updateStudentRosterRecord, "admin", {
        studentNo,
        fields: {college: "College B", course: "BS Course B"},
      });
    } finally {
      appointmentScopeSyncHooks.beforeAtomicCommit = undefined;
    }
    assert.ok(attempt >= 2, "expected Firestore transaction to retry after concurrent contention");

    // Verify all 50 historical appointments transferred atomically to College B.
    const transferredDocs = await db.collection("appointments").where("userId", "==", uid("student")).get();
    for (const docSnap of transferredDocs.docs) {
      assert.equal(docSnap.data().collegeId, collegeB);
      assert.equal(docSnap.data().studentVerificationStatus, "verified");
    }

    // 3. Concurrent counselor assignment + student transfer + new appointment creation race cleanly.
    const day = new Date(Date.now() + 75 * 86_400_000);
    while ([0, 6].includes(day.getUTCDay())) day.setUTCDate(day.getUTCDate() + 1);
    const slotMillis = Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), 3);
    const revB2 = Number((await db.doc(`users/${uid("counselorB")}`).get()).data()?.collegeAssignmentRevision ?? 0);

    const [rosterRes, assignRes, bookingRes] = await Promise.all([
      call(updateStudentRosterRecord, "admin", {
        studentNo,
        fields: {college: "College A", course: "BS Course A"},
      }),
      call(setStaffCollegeAssignments, "admin", {
        userId: uid("counselorB"),
        collegeIds: [collegeB],
        expectedRevision: revB2,
        reason: "Concurrent counselor assignment",
      }),
      call(createAppointmentRequest, "student", {
        concern: "Concurrent schedule booking",
        scheduledAt: slotMillis,
        requestId: `${prefix}_concurrent_book`,
      }),
    ]);
    assert.equal(rosterRes.ok, true);
    assert.equal(assignRes.ok, true);
    assert.equal(bookingRes.ok, true);
    createdAppointmentIds.push(bookingRes.appointmentId as string);

    // Whatever order the transactions serialized in, every student appointment MUST match users/{student}.collegeId!
    const finalUser = (await db.doc(`users/${uid("student")}`).get()).data()!;
    const finalAppts = await db.collection("appointments").where("userId", "==", uid("student")).get();
    assert.equal(finalUser.collegeId, collegeA);
    for (const docSnap of finalAppts.docs) {
      assert.equal(docSnap.data().collegeId, finalUser.collegeId);
      assert.equal(docSnap.data().studentVerificationStatus, finalUser.verificationStatus);
    }

    // Cleanup lock/slot created by concurrent booking.
    await db.doc(`appointment_user_locks/${uid("student")}`).delete().catch(() => undefined);
    await db.doc(`appointment_slots/pacc_${slotMillis}`).delete().catch(() => undefined);
  },
);

test(
  "delayed or out-of-order syncStudentAppointmentCollegeScope events never revert revocation or college transfer",
  {skip: !emulated},
  async () => {
    const delayedApptId = `${prefix}-appt-delayed-trigger`;
    createdAppointmentIds.push(delayedApptId);
    await db.doc(`users/${uid("student")}`).update({collegeId: collegeA, verificationStatus: "verified"});
    await db.doc(`student_roster/${studentKey}`).update({
      collegeId: collegeA, college: "College A", courseId: courseA, course: "BS Course A",
      departmentId: deptA, department: "Dept A",
    });
    const revA = Number((await db.doc(`users/${uid("counselorA")}`).get()).data()?.collegeAssignmentRevision ?? 0);
    await call(setStaffCollegeAssignments, "admin", {
      userId: uid("counselorA"),
      collegeIds: [collegeA],
      expectedRevision: revA,
      reason: "Ensure Counselor A covers College A",
    });
    const revB = Number((await db.doc(`users/${uid("counselorB")}`).get()).data()?.collegeAssignmentRevision ?? 0);
    await call(setStaffCollegeAssignments, "admin", {
      userId: uid("counselorB"),
      collegeIds: [collegeB],
      expectedRevision: revB,
      reason: "Ensure Counselor B covers College B",
    });
    await db.doc(`appointments/${delayedApptId}`).set({
      userId: uid("student"),
      fullName: "Test Student",
      status: "completed",
      collegeId: collegeA,
      studentVerificationStatus: "verified",
      scheduledAt: Timestamp.fromMillis(Date.now() - 86_400_000),
    });

    const clientA = await asClientFirestore("counselorA");
    const clientB = await asClientFirestore("counselorB");
    const trigger = syncStudentAppointmentCollegeScope as unknown as {run: (event: unknown) => Promise<void>};
    try {
      const beforeTransferSnap = await db.doc(`users/${uid("student")}`).get();
      await call(updateStudentRosterRecord, "admin", {
        studentNo,
        fields: {college: "College B", course: "BS Course B"},
      });
      const afterTransferSnap = await db.doc(`users/${uid("student")}`).get();

      await call(reviewProfileVerification, "admin", {
        userId: uid("student"),
        decision: "needsReview",
        reason: "Revoke before delayed E1 trigger arrives",
      });

      // Simulate stale E1 trigger (collegeA -> collegeB, verified) arriving AFTER revocation commit.
      await trigger.run({
        params: {userId: uid("student")},
        data: {before: beforeTransferSnap, after: afterTransferSnap},
      });
      const bAfterDelayedE1 = await listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeB, uid("student"));
      assert.deepEqual(bAfterDelayedE1.filter((d) => d.id === delayedApptId), []);

      // Re-verify in College B, capture E3 snapshot (needsReview -> verified in College B), then transfer to College A.
      const beforeReverifySnap = await db.doc(`users/${uid("student")}`).get();
      await call(reviewProfileVerification, "admin", {
        userId: uid("student"),
        decision: "verified",
        reason: "Re-verify in College B",
      });
      const afterReverifySnap = await db.doc(`users/${uid("student")}`).get();

      const reqRef = db.collection("student_correction_requests").doc(`${prefix}-corr-delayed`);
      await reqRef.set({
        userId: uid("student"),
        studentKey,
        field: "college",
        requestedValue: collegeA,
        status: "pending",
      });
      await db.doc(`student_roster/${studentKey}`).update({courseId: courseA, course: "BS Course A"});
      try {
        await call(reviewStudentCorrection, "admin", {
          requestId: reqRef.id,
          decision: "approve",
          reason: "Transfer back to College A before delayed E3 arrives",
        });

        // Simulate stale E3 trigger (needsReview -> verified in College B) arriving AFTER transfer to College A.
        await trigger.run({
          params: {userId: uid("student")},
          data: {before: beforeReverifySnap, after: afterReverifySnap},
        });
        const bAfterDelayedE3 = await listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeB, uid("student"));
        assert.deepEqual(bAfterDelayedE3.filter((d) => d.id === delayedApptId), []);
        const aAfterDelayedE3 = await listCollegeAppointmentsAsCounselor(clientA.clientDb, collegeA, uid("student"));
        assert.ok(aAfterDelayedE3.some((d) => d.id === delayedApptId));
      } finally {
        await reqRef.delete().catch(() => undefined);
      }
    } finally {
      await db.doc(`appointments/${delayedApptId}`).delete().catch(() => undefined);
      await clientA.close();
      await clientB.close();
    }
  },
);

test(
  "syncStudentAppointmentsCollegeScopeFromUserProfile fails loudly with standard Error at pass limit, logs, and makes idempotent forward progress on retry",
  {skip: !emulated},
  async () => {
    const passLimitUserId = uid("student-pass-limit");
    const apptIds = Array.from({length: 5}, (_, i) => `${prefix}-appt-pass-limit-${i}`);
    createdAppointmentIds.push(...apptIds);

    await db.doc(`users/${passLimitUserId}`).set({
      accessRole: "appUser",
      role: "student",
      populationRole: "student",
      accountStatus: "active",
      name: "Pass Limit Student",
      collegeId: collegeB,
      verificationStatus: "verified",
    });

    const seedBatch = db.batch();
    for (let i = 0; i < apptIds.length; i++) {
      seedBatch.set(db.doc(`appointments/${apptIds[i]}`), {
        userId: passLimitUserId,
        fullName: "Pass Limit Student",
        status: "completed",
        collegeId: collegeA,
        studentVerificationStatus: "verified",
        scheduledAt: Timestamp.fromMillis(Date.now() - (i + 1) * 86_400_000),
      });
    }
    await seedBatch.commit();

    const trigger = syncStudentAppointmentCollegeScope as unknown as {run: (event: unknown) => Promise<void>};
    const triggerEvent = {
      params: {userId: passLimitUserId},
      data: {
        before: {data: () => ({collegeId: collegeA, verificationStatus: "verified"})},
        after: {data: () => ({collegeId: collegeB, verificationStatus: "verified"})},
      },
    };

    const loggedErrors: Array<{message: unknown; meta: unknown}> = [];
    const originalConsoleError = console.error;
    console.error = (...args: unknown[]) => {
      loggedErrors.push({message: args[0], meta: args[1]});
      originalConsoleError(...args);
    };

    try {
      appointmentScopeSyncHooks.maxProfileSyncChunkSize = 2;
      appointmentScopeSyncHooks.maxProfileSyncPasses = 2;

      // 1. First trigger run reaches 2-pass * 2-doc limit (4 updated, 1 remaining) and throws standard Error.
      await assert.rejects(
        trigger.run(triggerEvent),
        (err: unknown) => {
          assert.ok(err instanceof Error, "expected standard Error");
          assert.ok(!(err instanceof HttpsError), "must not use HttpsError for background trigger");
          assert.match(err.message, /incomplete.*after 2 pass\(es\): 1 stale appointment\(s\) remain after updating 4/i);
          return true;
        },
      );

      assert.ok(
        loggedErrors.some(
          (entry) =>
            entry.message === "appointment_scope_sync_incomplete_after_max_passes" &&
            typeof entry.meta === "object" &&
            entry.meta !== null &&
            (entry.meta as Record<string, unknown>).userId === passLimitUserId &&
            (entry.meta as Record<string, unknown>).updated === 4 &&
            (entry.meta as Record<string, unknown>).remainingCount === 1,
        ),
        "expected structured error log for incomplete pass-limit condition",
      );

      // Verify 4 appointments committed forward progress to collegeB and 1 remains at collegeA.
      const snapsAfterFirstRun = await Promise.all(apptIds.map((id) => db.doc(`appointments/${id}`).get()));
      const syncedAfterFirst = snapsAfterFirstRun.filter((s) => s.data()?.collegeId === collegeB);
      const staleAfterFirst = snapsAfterFirstRun.filter((s) => s.data()?.collegeId === collegeA);
      assert.equal(syncedAfterFirst.length, 4);
      assert.equal(staleAfterFirst.length, 1);
      const syncedUpdateTimes = new Map(
        syncedAfterFirst.map((s) => [s.id, s.updateTime?.toMillis() ?? 0]),
      );

      // 2. Retry makes forward progress on the 1 remaining record without rewriting the 4 already-correct records.
      const retryUpdated = await syncStudentAppointmentsCollegeScopeFromUserProfile(passLimitUserId);
      assert.equal(retryUpdated, 1);

      const snapsAfterRetry = await Promise.all(apptIds.map((id) => db.doc(`appointments/${id}`).get()));
      for (const snap of snapsAfterRetry) {
        assert.equal(snap.data()?.collegeId, collegeB);
        assert.equal(snap.data()?.studentVerificationStatus, "verified");
        if (syncedUpdateTimes.has(snap.id)) {
          assert.equal(
            snap.updateTime?.toMillis() ?? 0,
            syncedUpdateTimes.get(snap.id),
            "already-correct appointment must not be rewritten on retry",
          );
        }
      }

      // 3. Subsequent trigger invocation when fully synchronized returns normally with 0 writes.
      await trigger.run(triggerEvent);
      assert.equal(await syncStudentAppointmentsCollegeScopeFromUserProfile(passLimitUserId), 0);
    } finally {
      console.error = originalConsoleError;
      appointmentScopeSyncHooks.maxProfileSyncChunkSize = undefined;
      appointmentScopeSyncHooks.maxProfileSyncPasses = undefined;
      await Promise.all([
        db.doc(`users/${passLimitUserId}`).delete().catch(() => undefined),
        ...apptIds.map((id) => db.doc(`appointments/${id}`).delete().catch(() => undefined)),
      ]);
    }
  },
);

async function resetMainAssignments() {
  const [snapA, snapB] = await Promise.all([
    db.doc(`users/${uid("counselorA")}`).get(),
    db.doc(`users/${uid("counselorB")}`).get(),
  ]);
  const revA = Number(snapA.data()?.collegeAssignmentRevision ?? 0);
  const colsA = (snapA.data()?.assignedCollegeIds as string[] | undefined) ?? [];
  if (colsA.length !== 1 || colsA[0] !== collegeA) {
    await call(setStaffCollegeAssignments, "admin", {
      userId: uid("counselorA"),
      collegeIds: [collegeA],
      expectedRevision: revA,
      reason: "Test setup assign College A",
    });
  }
  const revB = Number(snapB.data()?.collegeAssignmentRevision ?? 0);
  const colsB = (snapB.data()?.assignedCollegeIds as string[] | undefined) ?? [];
  if (colsB.length !== 1 || colsB[0] !== collegeB) {
    await call(setStaffCollegeAssignments, "admin", {
      userId: uid("counselorB"),
      collegeIds: [collegeB],
      expectedRevision: revB,
      reason: "Test setup assign College B",
    });
  }
}

async function cleanupImportArtifacts(importIds: string[]) {
  const uniqueIds = [...new Set(importIds.filter(Boolean))];
  if (!uniqueIds.length) return;
  const auditSnaps = await Promise.all(
    uniqueIds.map((id) => db.collection("admin_audit_logs").where("targetId", "==", id).get()),
  );
  await Promise.all([
    ...uniqueIds.map((id) => db.doc(`student_roster_imports/${id}`).delete().catch(() => undefined)),
    ...auditSnaps.flatMap((snap) => snap.docs.map((d) => d.ref.delete().catch(() => undefined))),
  ]);
}

test(
  "Step 11.3D Test A & B: importStudentRoster atomically transfers activated student College A -> College B and preserves same-college updates",
  {skip: !emulated},
  async () => {
    await resetMainAssignments();
    const courseA2 = `${prefix}-course-a2`;
    const localNo = `${Date.now().toString().slice(-6)}01`;
    const localKey = canonicalLoginId(localNo);
    const localUid = `${prefix}-roster-student-ab`;
    const apptId = `${prefix}-appt-roster-ab`;
    const importIds: string[] = [];

    await Promise.all([
      db.doc(`courses/${courseA2}`).set({
        name: "BS Course A2",
        code: "BSCA2",
        collegeId: collegeA,
        departmentId: deptA,
        active: true,
      }),
      getAuth().createUser({uid: localUid, email: `${localUid}@example.invalid`, password, emailVerified: true}),
      db.doc(`users/${localUid}`).set({
        accessRole: "appUser",
        role: "student",
        populationRole: "student",
        accountStatus: "active",
        name: "Roster Transfer Student",
        schoolId: localNo,
        collegeId: collegeA,
        college: "College A",
        courseId: courseA,
        course: "BS Course A",
        departmentId: deptA,
        department: "Dept A",
        yearLevel: "2nd Year",
        verificationStatus: "verified",
      }),
      db.doc(`student_roster/${localKey}`).set({
        studentNo: localNo,
        studentKey: localKey,
        surname: "Transfer",
        surnameNormalized: "transfer",
        firstName: "Roster",
        middleName: "",
        dateOfBirthKey: "2004-05-06",
        dateOfBirth: Timestamp.fromDate(new Date("2004-05-06T00:00:00Z")),
        collegeId: collegeA,
        college: "College A",
        courseId: courseA,
        course: "BS Course A",
        departmentId: deptA,
        department: "Dept A",
        yearLevel: "2nd Year",
        status: "active",
        activated: true,
        userId: localUid,
      }),
      db.doc(`appointments/${apptId}`).set({
        userId: localUid,
        fullName: "Roster Transfer Student",
        concern: "Private clinical concern",
        status: "confirmed",
        collegeId: collegeA,
        studentVerificationStatus: "verified",
        scheduledAt: Timestamp.fromMillis(Date.now() + 86_400_000),
      }),
    ]);

    const clientA = await asClientFirestore("counselorA");
    const clientB = await asClientFirestore("counselorB");
    try {
      // Test B: academic field & course update within College A preserves Counselor A access and denies Counselor B.
      const resSame = await call(importStudentRoster, "admin", {
        fileName: "same-college-update.csv",
        rows: [{
          studentNo: localNo,
          surname: "Transfer",
          firstName: "Roster",
          middleName: "",
          dateOfBirth: "2004-05-06",
          college: "College A",
          course: "BS Course A2",
          yearLevel: "3rd Year",
        }],
      });
      if (resSame.importId) importIds.push(resSame.importId);
      assert.equal(resSame.status, "complete");
      assert.deepEqual(resSame.counts, {new: 0, updated: 1, linked: 0});
      assert.equal((await db.doc(`users/${localUid}`).get()).data()?.yearLevel, "3rd Year");
      assert.equal((await db.doc(`users/${localUid}`).get()).data()?.courseId, courseA2);
      assert.deepEqual((await listCollegeAppointmentsAsCounselor(clientA.clientDb, collegeA, localUid)).map((d) => d.id), [apptId]);
      await assert.rejects(getDoc(doc(clientB.clientDb, "appointments", apptId)));

      // Counselor B unassigned vs assigned behavior around College A -> College B import transfer.
      const revB0 = Number((await db.doc(`users/${uid("counselorB")}`).get()).data()?.collegeAssignmentRevision ?? 0);
      await call(setStaffCollegeAssignments, "admin", {
        userId: uid("counselorB"),
        collegeIds: [],
        expectedRevision: revB0,
        reason: "Temporarily unassign Counselor B before transfer",
      });

      // Test A: transfer College A -> College B via importStudentRoster.
      const resTransfer = await call(importStudentRoster, "admin", {
        fileName: "transfer-a-to-b.csv",
        rows: [{
          studentNo: localNo,
          surname: "Transfer",
          firstName: "Roster",
          middleName: "",
          dateOfBirth: "2004-05-06",
          college: "College B",
          course: "BS Course B",
          yearLevel: "3rd Year",
        }],
      });
      if (resTransfer.importId) importIds.push(resTransfer.importId);
      assert.equal(resTransfer.status, "complete");
      assert.deepEqual(resTransfer.counts, {new: 0, updated: 1, linked: 0});

      // Immediately after callable returns: profile and appointment projections match collegeB.
      const userAfter = (await db.doc(`users/${localUid}`).get()).data()!;
      const apptAfter = (await db.doc(`appointments/${apptId}`).get()).data()!;
      assert.equal(userAfter.collegeId, collegeB);
      assert.equal(apptAfter.collegeId, collegeB);
      assert.equal(apptAfter.studentVerificationStatus, "verified");

      // Counselor A is immediately blocked on both GET and LIST.
      await assert.rejects(getDoc(doc(clientA.clientDb, "appointments", apptId)));
      assert.deepEqual(await listCollegeAppointmentsAsCounselor(clientA.clientDb, collegeA, localUid), []);

      // Counselor B is denied while unassigned, then gains access once assigned College B.
      await assert.rejects(getDoc(doc(clientB.clientDb, "appointments", apptId)));
      await assert.rejects(listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeB, localUid));
      await resetMainAssignments();
      assert.equal((await getDoc(doc(clientB.clientDb, "appointments", apptId))).exists(), true);
      assert.deepEqual((await listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeB, localUid)).map((d) => d.id), [apptId]);
    } finally {
      await clientA.close();
      await clientB.close();
      await cleanupImportArtifacts(importIds);
      await Promise.all([
        getAuth().deleteUser(localUid).catch(() => undefined),
        db.doc(`users/${localUid}`).delete().catch(() => undefined),
        db.doc(`student_roster/${localKey}`).delete().catch(() => undefined),
        db.doc(`appointments/${apptId}`).delete().catch(() => undefined),
        db.doc(`courses/${courseA2}`).delete().catch(() => undefined),
      ]);
    }
  },
);

test(
  "Step 11.3D Test C: importStudentRoster links existing accounts atomically for both verified and unverified students",
  {skip: !emulated},
  async () => {
    await resetMainAssignments();
    const verifiedNo = `${Date.now().toString().slice(-6)}02`;
    const unverifiedNo = `${Date.now().toString().slice(-6)}03`;
    const verifiedKey = canonicalLoginId(verifiedNo);
    const unverifiedKey = canonicalLoginId(unverifiedNo);
    const verifiedUid = `${prefix}-link-verified`;
    const unverifiedUid = `${prefix}-link-unverified`;
    const apptVerId = `${prefix}-appt-link-ver`;
    const apptUnvId = `${prefix}-appt-link-unv`;
    const importIds: string[] = [];

    await Promise.all([
      getAuth().createUser({uid: verifiedUid, email: `${verifiedUid}@example.invalid`, password, emailVerified: true}),
      getAuth().createUser({uid: unverifiedUid, email: `${unverifiedUid}@example.invalid`, password, emailVerified: true}),
      db.doc(`users/${verifiedUid}`).set({
        accessRole: "appUser",
        role: "student",
        populationRole: "student",
        accountStatus: "active",
        firstName: "Verified",
        lastName: "Linker",
        collegeId: collegeA,
        verificationStatus: "verified",
      }),
      db.doc(`users/${unverifiedUid}`).set({
        accessRole: "appUser",
        role: "student",
        populationRole: "student",
        accountStatus: "active",
        firstName: "Pending",
        lastName: "Linker",
        collegeId: collegeA,
        verificationStatus: "needsReview",
      }),
      db.doc(`student_id_reservations/${verifiedKey}`).set({userId: verifiedUid}),
      db.doc(`student_id_reservations/${unverifiedKey}`).set({userId: unverifiedUid}),
      db.doc(`appointments/${apptVerId}`).set({
        userId: verifiedUid,
        fullName: "Verified Linker",
        status: "confirmed",
        collegeId: collegeA,
        studentVerificationStatus: "verified",
        scheduledAt: Timestamp.fromMillis(Date.now() + 86_400_000),
      }),
      db.doc(`appointments/${apptUnvId}`).set({
        userId: unverifiedUid,
        fullName: "Pending Linker",
        status: "requested",
        collegeId: collegeA,
        studentVerificationStatus: "needsReview",
        scheduledAt: Timestamp.fromMillis(Date.now() + 172_800_000),
      }),
    ]);

    const clientA = await asClientFirestore("counselorA");
    const clientB = await asClientFirestore("counselorB");
    try {
      const res = await call(importStudentRoster, "admin", {
        fileName: "link-transfer.csv",
        rows: [
          {
            studentNo: verifiedNo,
            surname: "Linker",
            firstName: "Verified",
            middleName: "",
            dateOfBirth: "2004-05-06",
            college: "College B",
            course: "BS Course B",
            yearLevel: "1st Year",
          },
          {
            studentNo: unverifiedNo,
            surname: "Linker",
            firstName: "Pending",
            middleName: "",
            dateOfBirth: "2004-05-06",
            college: "College B",
            course: "BS Course B",
            yearLevel: "1st Year",
          },
        ],
      });
      if (res.importId) importIds.push(res.importId);
      assert.equal(res.status, "complete");
      assert.deepEqual(res.counts, {new: 0, updated: 0, linked: 2});

      // Verified linked student moved atomically to College B; Counselor A blocked, Counselor B authorized.
      assert.equal((await db.doc(`appointments/${apptVerId}`).get()).data()?.collegeId, collegeB);
      assert.equal((await db.doc(`appointments/${apptVerId}`).get()).data()?.studentVerificationStatus, "verified");
      await assert.rejects(getDoc(doc(clientA.clientDb, "appointments", apptVerId)));
      assert.deepEqual(await listCollegeAppointmentsAsCounselor(clientA.clientDb, collegeA, verifiedUid), []);
      assert.deepEqual((await listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeB, verifiedUid)).map((d) => d.id), [apptVerId]);

      // Unverified linked student keeps non-verified status; neither counselor can access appointment.
      const unvAppt = (await db.doc(`appointments/${apptUnvId}`).get()).data()!;
      assert.equal(unvAppt.collegeId, collegeB);
      assert.equal(unvAppt.studentVerificationStatus, "needsReview");
      await assert.rejects(getDoc(doc(clientA.clientDb, "appointments", apptUnvId)));
      await assert.rejects(getDoc(doc(clientB.clientDb, "appointments", apptUnvId)));
      assert.deepEqual(await listCollegeAppointmentsAsCounselor(clientA.clientDb, collegeA, unverifiedUid), []);
      assert.deepEqual(await listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeB, unverifiedUid), []);
    } finally {
      await clientA.close();
      await clientB.close();
      await cleanupImportArtifacts(importIds);
      await Promise.all([
        getAuth().deleteUser(verifiedUid).catch(() => undefined),
        getAuth().deleteUser(unverifiedUid).catch(() => undefined),
        db.doc(`users/${verifiedUid}`).delete().catch(() => undefined),
        db.doc(`users/${unverifiedUid}`).delete().catch(() => undefined),
        db.doc(`student_roster/${verifiedKey}`).delete().catch(() => undefined),
        db.doc(`student_roster/${unverifiedKey}`).delete().catch(() => undefined),
        db.doc(`student_id_reservations/${verifiedKey}`).delete().catch(() => undefined),
        db.doc(`student_id_reservations/${unverifiedKey}`).delete().catch(() => undefined),
        db.doc(`appointments/${apptVerId}`).delete().catch(() => undefined),
        db.doc(`appointments/${apptUnvId}`).delete().catch(() => undefined),
      ]);
    }
  },
);

test(
  "Step 11.3D Test D, E & F: handles atomic overflow safely, resists delayed triggers, and preserves mixed import semantics",
  {skip: !emulated},
  async () => {
    await resetMainAssignments();
    const baseNo = Date.now().toString().slice(-6);
    const overflowNo = `${baseNo}04`;
    const overflowKey = canonicalLoginId(overflowNo);
    const overflowUid = `${prefix}-overflow-uid`;
    const newNo1 = `${baseNo}05`;
    const newKey1 = canonicalLoginId(newNo1);
    const linkNo = `${baseNo}06`;
    const linkKey = canonicalLoginId(linkNo);
    const linkUid = `${prefix}-mixed-link-uid`;
    const updNo = `${baseNo}07`;
    const updKey = canonicalLoginId(updNo);
    const updUid = `${prefix}-mixed-upd-uid`;
    const newNo2 = `${baseNo}08`;
    const newKey2 = canonicalLoginId(newNo2);
    const blockedLinkNo = `${baseNo}09`;
    const blockedLinkKey = canonicalLoginId(blockedLinkNo);
    const blockedLinkUid = `${prefix}-mixed-blocked-link-uid`;

    const overflowAppts = [0, 1, 2].map((i) => `${prefix}-ov-appt-${i}`);
    const linkAppt = `${prefix}-mixed-link-appt`;
    const updAppt = `${prefix}-mixed-upd-appt`;
    const importIds: string[] = [];

    await Promise.all([
      db.doc(`users/${overflowUid}`).set({
        accessRole: "appUser",
        role: "student",
        populationRole: "student",
        accountStatus: "active",
        name: "Overflow Student",
        collegeId: collegeA,
        college: "College A",
        verificationStatus: "verified",
      }),
      db.doc(`student_roster/${overflowKey}`).set({
        studentNo: overflowNo,
        studentKey: overflowKey,
        surname: "Overflow",
        surnameNormalized: "overflow",
        firstName: "Student",
        middleName: "",
        dateOfBirthKey: "2004-05-06",
        dateOfBirth: Timestamp.fromDate(new Date("2004-05-06T00:00:00Z")),
        collegeId: collegeA,
        college: "College A",
        courseId: courseA,
        course: "BS Course A",
        departmentId: deptA,
        department: "Dept A",
        yearLevel: "2nd Year",
        status: "active",
        activated: true,
        userId: overflowUid,
      }),
      ...overflowAppts.map((id, i) => db.doc(`appointments/${id}`).set({
        userId: overflowUid,
        fullName: "Overflow Student",
        status: "completed",
        collegeId: collegeA,
        studentVerificationStatus: "verified",
        scheduledAt: Timestamp.fromMillis(Date.now() - (i + 1) * 86_400_000),
      })),
      db.doc(`users/${linkUid}`).set({
        accessRole: "appUser",
        role: "student",
        populationRole: "student",
        firstName: "PreLink",
        lastName: "Student",
        yearLevel: "1st Year",
        collegeId: collegeA,
        verificationStatus: "verified",
      }),
      db.doc(`student_id_reservations/${linkKey}`).set({userId: linkUid}),
      db.doc(`appointments/${linkAppt}`).set({
        userId: linkUid,
        fullName: "PreLink Student",
        status: "confirmed",
        collegeId: collegeA,
        studentVerificationStatus: "verified",
        scheduledAt: Timestamp.fromMillis(Date.now() + 86_400_000),
      }),
      db.doc(`users/${updUid}`).set({
        accessRole: "appUser",
        role: "student",
        populationRole: "student",
        firstName: "PreUpd",
        lastName: "Student",
        collegeId: collegeA,
        verificationStatus: "verified",
      }),
      db.doc(`student_roster/${updKey}`).set({
        studentNo: updNo,
        studentKey: updKey,
        surname: "Student",
        surnameNormalized: "student",
        firstName: "PreUpd",
        middleName: "",
        dateOfBirthKey: "2004-05-06",
        dateOfBirth: Timestamp.fromDate(new Date("2004-05-06T00:00:00Z")),
        collegeId: collegeA,
        college: "College A",
        courseId: courseA,
        course: "BS Course A",
        departmentId: deptA,
        department: "Dept A",
        yearLevel: "2nd Year",
        status: "active",
        activated: true,
        userId: updUid,
      }),
      db.doc(`appointments/${updAppt}`).set({
        userId: updUid,
        fullName: "PreUpd Student",
        status: "confirmed",
        collegeId: collegeA,
        studentVerificationStatus: "verified",
        scheduledAt: Timestamp.fromMillis(Date.now() + 172_800_000),
      }),
      db.doc(`users/${blockedLinkUid}`).set({
        accessRole: "appUser",
        role: "student",
        populationRole: "student",
        collegeId: collegeA,
        verificationStatus: "verified",
      }),
      db.doc(`student_id_reservations/${blockedLinkKey}`).set({userId: blockedLinkUid}),
    ]);

    const clientA = await asClientFirestore("counselorA");
    const clientB = await asClientFirestore("counselorB");
    const trigger = syncStudentAppointmentCollegeScope as unknown as {run: (event: unknown) => Promise<void>};
    try {
      // Test D & F (partial mixed import with atomic overflow on row 2):
      // [newRow2, overflowRow, blockedLinkRow]
      appointmentScopeSyncHooks.maxAtomicUpdates = 2;
      const partialRes = await call(importStudentRoster, "admin", {
        fileName: "mixed-overflow.csv",
        rows: [
          {
            studentNo: newNo2,
            surname: "PartialNew",
            firstName: "One",
            middleName: "",
            dateOfBirth: "2004-05-06",
            college: "College B",
            course: "BS Course B",
            yearLevel: "1st Year",
          },
          {
            studentNo: overflowNo,
            surname: "Overflow",
            firstName: "Student",
            middleName: "",
            dateOfBirth: "2004-05-06",
            college: "College B",
            course: "BS Course B",
            yearLevel: "3rd Year",
          },
          {
            studentNo: blockedLinkNo,
            surname: "Blocked",
            firstName: "Link",
            middleName: "",
            dateOfBirth: "2004-05-06",
            college: "College B",
            course: "BS Course B",
            yearLevel: "1st Year",
          },
        ],
      });
      if (partialRes.importId) importIds.push(partialRes.importId);
      assert.equal(partialRes.status, "partial");
      assert.deepEqual(partialRes.counts, {new: 1, updated: 0, linked: 0});
      assert.deepEqual(partialRes.codes, [], "no activation codes are created");
      assert.deepEqual(partialRes.failedRows.map((f: {studentNo: string}) => f.studentNo), [overflowNo, blockedLinkNo]);
      // Zero partial commit on overflowing student; Counselor B cannot read overflow student appointments.
      assert.equal((await db.doc(`users/${overflowUid}`).get()).data()?.collegeId, collegeA);
      assert.equal((await db.doc(`student_roster/${overflowKey}`).get()).data()?.collegeId, collegeA);
      for (const id of overflowAppts) {
        assert.equal((await db.doc(`appointments/${id}`).get()).data()?.collegeId, collegeA);
      }
      assert.deepEqual(await listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeB, overflowUid), []);
      assert.equal((await db.doc(`student_roster/${blockedLinkKey}`).get()).exists, false);
      const partialImportDoc = (await db.doc(`student_roster_imports/${partialRes.importId}`).get()).data()!;
      assert.equal(partialImportDoc.status, "partial");
      assert.deepEqual(partialImportDoc.counts, {new: 1, updated: 0, linked: 0});

      // Test F (successful mixed import with new + link + activated update):
      appointmentScopeSyncHooks.maxAtomicUpdates = undefined;
      const mixedRes = await call(importStudentRoster, "admin", {
        fileName: "mixed-complete.csv",
        rows: [
          {
            studentNo: newNo1,
            surname: "MixedNew",
            firstName: "First",
            middleName: "",
            dateOfBirth: "2004-05-06",
            college: "College B",
            course: "BS Course B",
            yearLevel: "1st Year",
          },
          {
            studentNo: linkNo,
            surname: "Student",
            firstName: "PreLink",
            middleName: "",
            dateOfBirth: "2004-05-06",
            college: "College B",
            course: "BS Course B",
            yearLevel: "2nd Year",
          },
          {
            studentNo: updNo,
            surname: "Student",
            firstName: "PreUpd",
            middleName: "",
            dateOfBirth: "2004-05-06",
            college: "College B",
            course: "BS Course B",
            yearLevel: "4th Year",
          },
        ],
      });
      if (mixedRes.importId) importIds.push(mixedRes.importId);
      assert.equal(mixedRes.status, "complete");
      assert.deepEqual(mixedRes.counts, {new: 1, updated: 1, linked: 1});
      assert.deepEqual(mixedRes.codes, [], "no activation codes are created");
      assert.equal((await db.doc(`student_roster/${newKey1}`).get()).data()!.activationCode, null);
      assert.equal((await db.doc(`appointments/${linkAppt}`).get()).data()?.collegeId, collegeB);
      assert.equal((await db.doc(`appointments/${updAppt}`).get()).data()?.collegeId, collegeB);
      assert.deepEqual(await listCollegeAppointmentsAsCounselor(clientA.clientDb, collegeA, linkUid), []);
      assert.deepEqual(await listCollegeAppointmentsAsCounselor(clientA.clientDb, collegeA, updUid), []);
      assert.deepEqual((await listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeB, linkUid)).map((d) => d.id), [linkAppt]);
      assert.deepEqual((await listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeB, updUid)).map((d) => d.id), [updAppt]);
      const auditSnap = await db.collection("admin_audit_logs").where("targetId", "==", mixedRes.importId).get();
      assert.equal(auditSnap.size, 1);
      assert.equal(auditSnap.docs[0].data().action, "STUDENT_ROSTER_IMPORTED");
      assert.deepEqual(auditSnap.docs[0].data().metadata.counts, {new: 1, updated: 1, linked: 1});
      assert.equal(auditSnap.docs[0].data().metadata.linkedPreviousValues[0].userId, linkUid);
      assert.equal(auditSnap.docs[0].data().metadata.linkedPreviousValues[0].previous.collegeId, collegeA);

      // Test E: capture snapshot before transfer back to College A, then replay stale A->B event.
      const beforeBackSnap = await db.doc(`users/${updUid}`).get();
      const backRes = await call(importStudentRoster, "admin", {
        fileName: "back-to-a.csv",
        rows: [{
          studentNo: updNo,
          surname: "Student",
          firstName: "PreUpd",
          middleName: "",
          dateOfBirth: "2004-05-06",
          college: "College A",
          course: "BS Course A",
          yearLevel: "4th Year",
        }],
      });
      if (backRes.importId) importIds.push(backRes.importId);
      const afterBackSnap = await db.doc(`users/${updUid}`).get();
      assert.equal(afterBackSnap.data()?.collegeId, collegeA);
      assert.equal((await db.doc(`appointments/${updAppt}`).get()).data()?.collegeId, collegeA);

      // Replay out-of-order College A -> College B event after student moved back to College A.
      await trigger.run({
        params: {userId: updUid},
        data: {
          before: afterBackSnap,
          after: beforeBackSnap,
        },
      });
      assert.equal((await db.doc(`appointments/${updAppt}`).get()).data()?.collegeId, collegeA);
      assert.deepEqual(await listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeB, updUid), []);
      assert.deepEqual((await listCollegeAppointmentsAsCounselor(clientA.clientDb, collegeA, updUid)).map((d) => d.id), [updAppt]);
    } finally {
      appointmentScopeSyncHooks.maxAtomicUpdates = undefined;
      await clientA.close();
      await clientB.close();
      await cleanupImportArtifacts(importIds);
      await Promise.all([
        ...[overflowUid, linkUid, updUid, blockedLinkUid].map((id) => db.doc(`users/${id}`).delete().catch(() => undefined)),
        ...[overflowKey, newKey1, linkKey, updKey, newKey2, blockedLinkKey].map((k) => db.doc(`student_roster/${k}`).delete().catch(() => undefined)),
        ...[linkKey, blockedLinkKey].map((k) => db.doc(`student_id_reservations/${k}`).delete().catch(() => undefined)),
        ...[...overflowAppts, linkAppt, updAppt].map((id) => db.doc(`appointments/${id}`).delete().catch(() => undefined)),
      ]);
    }
  },
);

test(
  "Step 11.3D Test G: concurrent profile verification updates and roster imports keep profile and appointments synchronized",
  {skip: !emulated},
  async () => {
    await resetMainAssignments();
    const concNo = `${Date.now().toString().slice(-6)}10`;
    const concKey = canonicalLoginId(concNo);
    const concUid = `${prefix}-conc-import-uid`;
    const concApptId = `${prefix}-conc-import-appt`;
    const importIds: string[] = [];

    await Promise.all([
      db.doc(`users/${concUid}`).set({
        accessRole: "appUser",
        role: "student",
        populationRole: "student",
        accountStatus: "active",
        name: "Concurrent Student",
        collegeId: collegeA,
        college: "College A",
        verificationStatus: "verified",
      }),
      db.doc(`student_roster/${concKey}`).set({
        studentNo: concNo,
        studentKey: concKey,
        surname: "Concurrent",
        surnameNormalized: "concurrent",
        firstName: "Student",
        middleName: "",
        dateOfBirthKey: "2004-05-06",
        dateOfBirth: Timestamp.fromDate(new Date("2004-05-06T00:00:00Z")),
        collegeId: collegeA,
        college: "College A",
        courseId: courseA,
        course: "BS Course A",
        departmentId: deptA,
        department: "Dept A",
        yearLevel: "2nd Year",
        status: "active",
        activated: true,
        userId: concUid,
      }),
      db.doc(`appointments/${concApptId}`).set({
        userId: concUid,
        fullName: "Concurrent Student",
        status: "confirmed",
        collegeId: collegeA,
        studentVerificationStatus: "verified",
        scheduledAt: Timestamp.fromMillis(Date.now() + 86_400_000),
      }),
    ]);

    try {
      const [importRes, verifyRes] = await Promise.all([
        call(importStudentRoster, "admin", {
          fileName: "concurrent-transfer.csv",
          rows: [{
            studentNo: concNo,
            surname: "Concurrent",
            firstName: "Student",
            middleName: "",
            dateOfBirth: "2004-05-06",
            college: "College B",
            course: "BS Course B",
            yearLevel: "3rd Year",
          }],
        }),
        call(reviewProfileVerification, "admin", {
          userId: concUid,
          decision: "needsReview",
          reason: "Concurrent verification status change",
        }),
      ]);
      if (importRes.importId) importIds.push(importRes.importId);
      assert.equal(importRes.status, "complete");
      assert.equal(verifyRes.ok, true);

      const finalUser = (await db.doc(`users/${concUid}`).get()).data()!;
      const finalAppt = (await db.doc(`appointments/${concApptId}`).get()).data()!;
      assert.equal(finalUser.collegeId, collegeB);
      assert.equal(finalUser.verificationStatus, "needsReview");
      assert.equal(finalAppt.collegeId, finalUser.collegeId);
      assert.equal(finalAppt.studentVerificationStatus, finalUser.verificationStatus);
    } finally {
      await cleanupImportArtifacts(importIds);
      await Promise.all([
        db.doc(`users/${concUid}`).delete().catch(() => undefined),
        db.doc(`student_roster/${concKey}`).delete().catch(() => undefined),
        db.doc(`appointments/${concApptId}`).delete().catch(() => undefined),
      ]);
    }
  },
);

test(
  "Step 11.3D hardening: rejects stale batch update when unactivated roster row activates between classify and commit",
  {skip: !emulated},
  async () => {
    await resetMainAssignments();
    const baseNo = Date.now().toString().slice(-6);
    const batchNewNo = `${baseNo}11`;
    const batchNewKey = canonicalLoginId(batchNewNo);
    const raceNo = `${baseNo}12`;
    const raceKey = canonicalLoginId(raceNo);
    const claimantUid = `${prefix}-race-activate-uid`;
    const claimantApptId = `${prefix}-race-activate-appt`;
    const importIds: string[] = [];

    await Promise.all([
      db.doc(`users/${claimantUid}`).set({
        accessRole: "appUser",
        role: "student",
        populationRole: "student",
        accountStatus: "active",
        name: "Race Claimant",
        schoolId: raceNo,
        collegeId: collegeA,
        college: "College A",
        verificationStatus: "verified",
      }),
      db.doc(`student_roster/${raceKey}`).set({
        studentNo: raceNo,
        studentKey: raceKey,
        surname: "Claimant",
        surnameNormalized: "claimant",
        firstName: "Race",
        middleName: "",
        dateOfBirthKey: "2004-05-06",
        dateOfBirth: Timestamp.fromDate(new Date("2004-05-06T00:00:00Z")),
        collegeId: collegeA,
        college: "College A",
        courseId: courseA,
        course: "BS Course A",
        departmentId: deptA,
        department: "Dept A",
        yearLevel: "2nd Year",
        status: "active",
        activated: false,
        userId: null,
      }),
      db.doc(`appointments/${claimantApptId}`).set({
        userId: claimantUid,
        fullName: "Race Claimant",
        status: "confirmed",
        collegeId: collegeA,
        studentVerificationStatus: "verified",
        scheduledAt: Timestamp.fromMillis(Date.now() + 86_400_000),
      }),
    ]);

    const clientA = await asClientFirestore("counselorA");
    const clientB = await asClientFirestore("counselorB");
    try {
      // Simulate concurrent student activation right after classify() and before batch commit.
      rosterTestHooks.batchLimit = 1;
      rosterTestHooks.afterClassify = async () => {
        await db.doc(`student_roster/${raceKey}`).update({
          activated: true,
          userId: claimantUid,
          activationCode: null,
          updatedAt: Timestamp.now(),
        });
      };

      const res = await call(importStudentRoster, "admin", {
        fileName: "concurrent-activation-race.csv",
        rows: [
          {
            studentNo: batchNewNo,
            surname: "FreshBatch",
            firstName: "Student",
            middleName: "",
            dateOfBirth: "2004-05-06",
            college: "College A",
            course: "BS Course A",
            yearLevel: "1st Year",
          },
          {
            studentNo: raceNo,
            surname: "Claimant",
            firstName: "Race",
            middleName: "",
            dateOfBirth: "2004-05-06",
            college: "College B",
            course: "BS Course B",
            yearLevel: "3rd Year",
          },
        ],
      });
      if (res.importId) importIds.push(res.importId);

      // Concurrent change must reject the stale batch update through partial-import reporting
      // while preserving earlier valid batch writes, codes, counts, and audit records.
      assert.equal(res.status, "partial");
      assert.deepEqual(res.counts, {new: 1, updated: 0, linked: 0});
      assert.deepEqual(res.codes, [], "no activation codes are created");
      assert.deepEqual(res.failedRows.map((f: {studentNo: string}) => f.studentNo), [raceNo]);
      assert.equal((await db.doc(`student_roster/${batchNewKey}`).get()).data()!.activationCode, null);

      const auditSnap = await db.collection("admin_audit_logs").where("targetId", "==", res.importId).get();
      assert.equal(auditSnap.size, 1);
      assert.equal(auditSnap.docs[0].data().metadata.partial, true);
      assert.deepEqual(auditSnap.docs[0].data().metadata.counts, {new: 1, updated: 0, linked: 0});

      // Roster, user profile, and appointment projections must all remain consistent at College A.
      const rosterData = (await db.doc(`student_roster/${raceKey}`).get()).data()!;
      const userData = (await db.doc(`users/${claimantUid}`).get()).data()!;
      const apptData = (await db.doc(`appointments/${claimantApptId}`).get()).data()!;
      assert.equal(rosterData.activated, true);
      assert.equal(rosterData.userId, claimantUid);
      assert.equal(rosterData.collegeId, collegeA);
      assert.equal(userData.collegeId, collegeA);
      assert.equal(apptData.collegeId, collegeA);
      assert.deepEqual((await listCollegeAppointmentsAsCounselor(clientA.clientDb, collegeA, claimantUid)).map((d) => d.id), [claimantApptId]);
      assert.deepEqual(await listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeB, claimantUid), []);

      // Re-importing the now-activated row without stale hooks executes atomically across roster, user, and appointments.
      rosterTestHooks.batchLimit = undefined;
      rosterTestHooks.afterClassify = undefined;
      const retryRes = await call(importStudentRoster, "admin", {
        fileName: "concurrent-activation-retry.csv",
        rows: [{
          studentNo: raceNo,
          surname: "Claimant",
          firstName: "Race",
          middleName: "",
          dateOfBirth: "2004-05-06",
          college: "College B",
          course: "BS Course B",
          yearLevel: "3rd Year",
        }],
      });
      if (retryRes.importId) importIds.push(retryRes.importId);
      assert.equal(retryRes.status, "complete");
      assert.deepEqual(retryRes.counts, {new: 0, updated: 1, linked: 0});
      assert.equal((await db.doc(`student_roster/${raceKey}`).get()).data()?.collegeId, collegeB);
      assert.equal((await db.doc(`users/${claimantUid}`).get()).data()?.collegeId, collegeB);
      assert.equal((await db.doc(`appointments/${claimantApptId}`).get()).data()?.collegeId, collegeB);
      assert.deepEqual(await listCollegeAppointmentsAsCounselor(clientA.clientDb, collegeA, claimantUid), []);
      assert.deepEqual((await listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeB, claimantUid)).map((d) => d.id), [claimantApptId]);
    } finally {
      rosterTestHooks.batchLimit = undefined;
      rosterTestHooks.afterClassify = undefined;
      await clientA.close();
      await clientB.close();
      await cleanupImportArtifacts(importIds);
      await Promise.all([
        db.doc(`users/${claimantUid}`).delete().catch(() => undefined),
        db.doc(`student_roster/${raceKey}`).delete().catch(() => undefined),
        db.doc(`student_roster/${batchNewKey}`).delete().catch(() => undefined),
        db.doc(`appointments/${claimantApptId}`).delete().catch(() => undefined),
      ]);
    }
  },
);

test(
  "Step 11.3F Test A & F: shared batch (batchLimit >= 2) rolls back sibling new row on lastUpdateTime conflict with zero code leakage",
  {skip: !emulated},
  async () => {
    await resetMainAssignments();
    const baseNo = Date.now().toString().slice(-6);
    const siblingNewNo = `${baseNo}21`;
    const siblingNewKey = canonicalLoginId(siblingNewNo);
    const conflictNo = `${baseNo}22`;
    const conflictKey = canonicalLoginId(conflictNo);
    const conflictUid = `${prefix}-shared-batch-uid`;
    const conflictApptId = `${prefix}-shared-batch-appt`;
    const importIds: string[] = [];

    await Promise.all([
      db.doc(`users/${conflictUid}`).set({
        accessRole: "appUser",
        role: "student",
        populationRole: "student",
        accountStatus: "active",
        name: "Shared Conflict Student",
        collegeId: collegeA,
        verificationStatus: "verified",
      }),
      db.doc(`student_roster/${conflictKey}`).set({
        studentNo: conflictNo,
        studentKey: conflictKey,
        surname: "Conflict",
        surnameNormalized: "conflict",
        firstName: "Shared",
        middleName: "",
        dateOfBirthKey: "2004-05-06",
        dateOfBirth: Timestamp.fromDate(new Date("2004-05-06T00:00:00Z")),
        collegeId: collegeA,
        college: "College A",
        courseId: courseA,
        course: "BS Course A",
        departmentId: deptA,
        department: "Dept A",
        yearLevel: "2nd Year",
        status: "active",
        activated: false,
        userId: null,
      }),
      db.doc(`appointments/${conflictApptId}`).set({
        userId: conflictUid,
        fullName: "Shared Conflict Student",
        status: "confirmed",
        collegeId: collegeA,
        studentVerificationStatus: "verified",
        scheduledAt: Timestamp.fromMillis(Date.now() + 86_400_000),
      }),
    ]);

    const capturedErrors: unknown[] = [];
    const origError = console.error;
    console.error = (...args: unknown[]) => {
      capturedErrors.push(args);
      origError(...args);
    };
    try {
      rosterTestHooks.batchLimit = 10;
      rosterTestHooks.afterClassify = async () => {
        await db.doc(`student_roster/${conflictKey}`).update({
          activated: true,
          userId: conflictUid,
          activationCode: null,
          updatedAt: Timestamp.now(),
        });
      };

      const res = await call(importStudentRoster, "admin", {
        fileName: "shared-batch-conflict.csv",
        rows: [
          {
            studentNo: siblingNewNo,
            surname: "Sibling",
            firstName: "New",
            middleName: "",
            dateOfBirth: "2004-05-06",
            college: "College A",
            course: "BS Course A",
            yearLevel: "1st Year",
          },
          {
            studentNo: conflictNo,
            surname: "Conflict",
            firstName: "Shared",
            middleName: "",
            dateOfBirth: "2004-05-06",
            college: "College B",
            course: "BS Course B",
            yearLevel: "3rd Year",
          },
        ],
      });
      if (res.importId) importIds.push(res.importId);

      // Shared batch must roll back atomically: sibling new row NOT created, zero codes returned.
      assert.equal(res.status, "partial");
      assert.deepEqual(res.counts, {new: 0, updated: 0, linked: 0});
      assert.deepEqual(res.codes, []);
      assert.deepEqual(res.failedRows.map((f: {studentNo: string}) => f.studentNo), [siblingNewNo, conflictNo]);
      assert.equal((await db.doc(`student_roster/${siblingNewKey}`).get()).exists, false);
      assert.equal((await db.doc(`student_roster/${conflictKey}`).get()).data()?.collegeId, collegeA);
      assert.equal((await db.doc(`users/${conflictUid}`).get()).data()?.collegeId, collegeA);
      assert.equal((await db.doc(`appointments/${conflictApptId}`).get()).data()?.collegeId, collegeA);

      // Failure must be logged safely and recorded with sanitized failureCode on import + audit.
      const importDoc = (await db.doc(`student_roster_imports/${res.importId}`).get()).data()!;
      assert.equal(importDoc.status, "partial");
      assert.deepEqual(importDoc.counts, {new: 0, updated: 0, linked: 0});
      assert.equal(typeof importDoc.failureCode, "string");
      assert.ok(importDoc.failureCode.length > 0);
      assert.equal(importDoc.failedRows.length, 2);

      const auditSnap = await db.collection("admin_audit_logs").where("targetId", "==", res.importId).get();
      assert.equal(auditSnap.size, 1);
      assert.equal(auditSnap.docs[0].data().metadata.partial, true);
      assert.equal(auditSnap.docs[0].data().metadata.failureCode, importDoc.failureCode);

      assert.ok(
        capturedErrors.some((entry) => JSON.stringify(entry).includes("student_roster_import_step_failed")),
        "expected structured step failure log",
      );
      const serializedSensitiveSurface = JSON.stringify({capturedErrors, importDoc, audit: auditSnap.docs[0].data()});
      assert.doesNotMatch(serializedSensitiveSurface, /Shared Conflict Student|2004-05-06/);
    } finally {
      console.error = origError;
      rosterTestHooks.batchLimit = undefined;
      rosterTestHooks.afterClassify = undefined;
      await cleanupImportArtifacts(importIds);
      await Promise.all([
        db.doc(`users/${conflictUid}`).delete().catch(() => undefined),
        db.doc(`student_roster/${siblingNewKey}`).delete().catch(() => undefined),
        db.doc(`student_roster/${conflictKey}`).delete().catch(() => undefined),
        db.doc(`appointments/${conflictApptId}`).delete().catch(() => undefined),
      ]);
    }
  },
);

test(
  "Step 11.3F Test B: concurrent link rejection protects against stolen reservation or concurrent activation",
  {skip: !emulated},
  async () => {
    await resetMainAssignments();
    const baseNo = Date.now().toString().slice(-6);
    const linkNo = `${baseNo}23`;
    const linkKey = canonicalLoginId(linkNo);
    const linkUid = `${prefix}-link-race-uid`;
    const otherUid = `${prefix}-link-thief-uid`;
    const apptId = `${prefix}-link-race-appt`;
    const importIds: string[] = [];

    await Promise.all([
      db.doc(`users/${linkUid}`).set({
        accessRole: "appUser",
        role: "student",
        populationRole: "student",
        accountStatus: "active",
        firstName: "Orig",
        lastName: "Student",
        collegeId: collegeA,
        verificationStatus: "verified",
      }),
      db.doc(`users/${otherUid}`).set({
        accessRole: "appUser",
        role: "student",
        populationRole: "student",
        accountStatus: "active",
        firstName: "Other",
        lastName: "User",
        collegeId: collegeA,
        verificationStatus: "verified",
      }),
      db.doc(`student_id_reservations/${linkKey}`).set({userId: linkUid}),
      db.doc(`appointments/${apptId}`).set({
        userId: linkUid,
        fullName: "Orig Student",
        status: "confirmed",
        collegeId: collegeA,
        studentVerificationStatus: "verified",
        scheduledAt: Timestamp.fromMillis(Date.now() + 86_400_000),
      }),
    ]);

    try {
      rosterTestHooks.afterClassify = async () => {
        await db.doc(`student_id_reservations/${linkKey}`).set({userId: otherUid});
      };
      const res = await call(importStudentRoster, "admin", {
        fileName: "concurrent-link-reject.csv",
        rows: [{
          studentNo: linkNo,
          surname: "Student",
          firstName: "Orig",
          middleName: "",
          dateOfBirth: "2004-05-06",
          college: "College B",
          course: "BS Course B",
          yearLevel: "2nd Year",
        }],
      });
      if (res.importId) importIds.push(res.importId);

      assert.equal(res.status, "partial");
      assert.deepEqual(res.counts, {new: 0, updated: 0, linked: 0});
      assert.deepEqual(res.failedRows.map((f: {studentNo: string}) => f.studentNo), [linkNo]);
      assert.equal((await db.doc(`student_roster/${linkKey}`).get()).exists, false);
      assert.equal((await db.doc(`users/${linkUid}`).get()).data()?.collegeId, collegeA);
      assert.equal((await db.doc(`users/${otherUid}`).get()).data()?.collegeId, collegeA);
      assert.equal((await db.doc(`appointments/${apptId}`).get()).data()?.collegeId, collegeA);
    } finally {
      rosterTestHooks.afterClassify = undefined;
      await cleanupImportArtifacts(importIds);
      await Promise.all([
        db.doc(`users/${linkUid}`).delete().catch(() => undefined),
        db.doc(`users/${otherUid}`).delete().catch(() => undefined),
        db.doc(`student_id_reservations/${linkKey}`).delete().catch(() => undefined),
        db.doc(`student_roster/${linkKey}`).delete().catch(() => undefined),
        db.doc(`appointments/${apptId}`).delete().catch(() => undefined),
      ]);
    }
  },
);

test(
  "Step 11.3F Test C: concurrent student activation revocation blocks stale import transfer without leaking access",
  {skip: !emulated},
  async () => {
    await resetMainAssignments();
    const revNo = `${Date.now().toString().slice(-6)}24`;
    const revKey = canonicalLoginId(revNo);
    const revUid = `${prefix}-revoke-race-uid`;
    const revApptId = `${prefix}-revoke-race-appt`;
    const importIds: string[] = [];

    await getAuth().createUser({uid: revUid, email: `${revUid}@example.invalid`, password, emailVerified: true});
    await Promise.all([
      db.doc(`users/${revUid}`).set({
        accessRole: "appUser",
        role: "student",
        populationRole: "student",
        accountStatus: "active",
        firstName: "Revoke",
        lastName: "Student",
        collegeId: collegeA,
        verificationStatus: "verified",
      }),
      db.doc(`student_id_reservations/${revKey}`).set({userId: revUid}),
      db.doc(`student_roster/${revKey}`).set({
        studentNo: revNo,
        studentKey: revKey,
        surname: "Student",
        surnameNormalized: "student",
        firstName: "Revoke",
        middleName: "",
        dateOfBirthKey: "2004-05-06",
        dateOfBirth: Timestamp.fromDate(new Date("2004-05-06T00:00:00Z")),
        collegeId: collegeA,
        college: "College A",
        courseId: courseA,
        course: "BS Course A",
        departmentId: deptA,
        department: "Dept A",
        yearLevel: "2nd Year",
        status: "active",
        activated: true,
        userId: revUid,
      }),
      db.doc(`appointments/${revApptId}`).set({
        userId: revUid,
        fullName: "Revoke Student",
        status: "confirmed",
        collegeId: collegeA,
        studentVerificationStatus: "verified",
        scheduledAt: Timestamp.fromMillis(Date.now() + 86_400_000),
      }),
    ]);

    const clientA = await asClientFirestore("counselorA");
    const clientB = await asClientFirestore("counselorB");
    try {
      rosterTestHooks.afterClassify = async () => {
        await call(revokeStudentActivation, "admin", {
          studentNo: revNo,
          reason: "Revoked concurrently during roster import",
        });
      };
      const res = await call(importStudentRoster, "admin", {
        fileName: "concurrent-revoke.csv",
        rows: [{
          studentNo: revNo,
          surname: "Student",
          firstName: "Revoke",
          middleName: "",
          dateOfBirth: "2004-05-06",
          college: "College B",
          course: "BS Course B",
          yearLevel: "3rd Year",
        }],
      });
      if (res.importId) importIds.push(res.importId);

      assert.equal(res.status, "partial");
      assert.deepEqual(res.counts, {new: 0, updated: 0, linked: 0});
      assert.deepEqual(res.failedRows.map((f: {studentNo: string}) => f.studentNo), [revNo]);

      const rosterData = (await db.doc(`student_roster/${revKey}`).get()).data()!;
      const userData = (await db.doc(`users/${revUid}`).get()).data()!;
      const apptData = (await db.doc(`appointments/${revApptId}`).get()).data()!;
      assert.equal(rosterData.activated, false);
      assert.equal(rosterData.userId, null);
      assert.equal(rosterData.collegeId, collegeA);
      assert.equal(userData.accountStatus, "revoked");
      assert.equal(userData.collegeId, collegeA);
      assert.equal(apptData.collegeId, collegeA);
      assert.deepEqual(await listCollegeAppointmentsAsCounselor(clientB.clientDb, collegeB, revUid), []);
      await assert.rejects(getDoc(doc(clientB.clientDb, "appointments", revApptId)));
    } finally {
      rosterTestHooks.afterClassify = undefined;
      await clientA.close();
      await clientB.close();
      await cleanupImportArtifacts(importIds);
      const revAudits = await db.collection("admin_audit_logs").where("targetId", "==", revKey).get();
      await Promise.all([
        getAuth().deleteUser(revUid).catch(() => undefined),
        db.doc(`users/${revUid}`).delete().catch(() => undefined),
        db.doc(`student_roster/${revKey}`).delete().catch(() => undefined),
        db.doc(`student_id_reservations/${revKey}`).delete().catch(() => undefined),
        db.doc(`appointments/${revApptId}`).delete().catch(() => undefined),
        ...revAudits.docs.map((d) => d.ref.delete().catch(() => undefined)),
      ]);
    }
  },
);

test(
  "Step 11.3F Test D & F: execution deadline safeguard stops cleanly with finalized partial status, codes for committed rows only, and safe resume",
  {skip: !emulated},
  async () => {
    await resetMainAssignments();
    const baseNo = Date.now().toString().slice(-6);
    const n1 = `${baseNo}31`;
    const u1 = `${baseNo}32`;
    const l1 = `${baseNo}33`;
    const n2 = `${baseNo}34`;
    const kN1 = canonicalLoginId(n1);
    const kU1 = canonicalLoginId(u1);
    const kL1 = canonicalLoginId(l1);
    const kN2 = canonicalLoginId(n2);
    const u1Uid = `${prefix}-budget-u1`;
    const l1Uid = `${prefix}-budget-l1`;
    const u1Appt = `${prefix}-budget-u1-appt`;
    const l1Appt = `${prefix}-budget-l1-appt`;
    const importIds: string[] = [];

    await Promise.all([
      db.doc(`users/${u1Uid}`).set({accessRole: "appUser", populationRole: "student", collegeId: collegeA, verificationStatus: "verified"}),
      db.doc(`users/${l1Uid}`).set({accessRole: "appUser", populationRole: "student", collegeId: collegeA, verificationStatus: "verified"}),
      db.doc(`student_id_reservations/${kL1}`).set({userId: l1Uid}),
      db.doc(`student_roster/${kU1}`).set({
        studentNo: u1, studentKey: kU1, surname: "Upd", surnameNormalized: "upd", firstName: "One", middleName: "",
        dateOfBirthKey: "2004-05-06", dateOfBirth: Timestamp.fromDate(new Date("2004-05-06T00:00:00Z")),
        collegeId: collegeA, college: "College A", courseId: courseA, course: "BS Course A",
        departmentId: deptA, department: "Dept A", yearLevel: "2nd Year", status: "active", activated: true, userId: u1Uid,
      }),
      db.doc(`appointments/${u1Appt}`).set({
        userId: u1Uid, fullName: "Upd One", status: "confirmed", collegeId: collegeA, studentVerificationStatus: "verified",
        scheduledAt: Timestamp.fromMillis(Date.now() + 86_400_000),
      }),
      db.doc(`appointments/${l1Appt}`).set({
        userId: l1Uid, fullName: "Link One", status: "confirmed", collegeId: collegeA, studentVerificationStatus: "verified",
        scheduledAt: Timestamp.fromMillis(Date.now() + 86_400_000),
      }),
    ]);

    const hookBag = rosterTestHooks as {
      batchLimit?: number;
      timeBudgetMs?: number;
      afterStep?: (stepIndex: number) => Promise<void>;
    };
    const capturedLogs: unknown[] = [];
    const origWarn = console.warn;
    console.warn = (...args: unknown[]) => {
      capturedLogs.push(args);
      origWarn(...args);
    };
    try {
      // Force budget expiration right after step 0 commits cleanly (step 0 = n1).
      hookBag.timeBudgetMs = 60_000;
      hookBag.afterStep = async (stepIndex) => {
        if (stepIndex === 0) hookBag.timeBudgetMs = 0;
      };
      const rows = [
        {studentNo: n1, surname: "New", firstName: "One", middleName: "", dateOfBirth: "2004-05-06", college: "College B", course: "BS Course B", yearLevel: "1st Year"},
        {studentNo: u1, surname: "Upd", firstName: "One", middleName: "", dateOfBirth: "2004-05-06", college: "College B", course: "BS Course B", yearLevel: "3rd Year"},
        {studentNo: l1, surname: "Link", firstName: "One", middleName: "", dateOfBirth: "2004-05-06", college: "College B", course: "BS Course B", yearLevel: "2nd Year"},
        {studentNo: n2, surname: "New", firstName: "Two", middleName: "", dateOfBirth: "2004-05-06", college: "College B", course: "BS Course B", yearLevel: "1st Year"},
      ];
      const partialRes = await call(importStudentRoster, "admin", {fileName: "budget-stop.csv", rows});
      if (partialRes.importId) importIds.push(partialRes.importId);

      assert.equal(partialRes.status, "partial");
      assert.deepEqual(partialRes.counts, {new: 1, updated: 0, linked: 0});
      assert.deepEqual(partialRes.codes, [], "no activation codes are created");
      assert.deepEqual(partialRes.failedRows.map((f: {studentNo: string}) => f.studentNo), [u1, l1, n2]);
      assert.equal((await db.doc(`student_roster/${kN1}`).get()).exists, true);
      assert.equal((await db.doc(`student_roster/${kN2}`).get()).exists, false);
      assert.equal((await db.doc(`users/${u1Uid}`).get()).data()?.collegeId, collegeA);
      assert.equal((await db.doc(`appointments/${u1Appt}`).get()).data()?.collegeId, collegeA);

      assert.equal((await db.doc(`student_roster/${kN1}`).get()).data()!.activationCode, null);

      const rec = (await db.doc(`student_roster_imports/${partialRes.importId}`).get()).data()!;
      assert.equal(rec.status, "partial");
      assert.equal(rec.failureCode, "time-budget-exceeded");
      assert.deepEqual(rec.counts, {new: 1, updated: 0, linked: 0});

      const auditSnap = await db.collection("admin_audit_logs").where("targetId", "==", partialRes.importId).get();
      assert.equal(auditSnap.size, 1);
      assert.equal(auditSnap.docs[0].data().metadata.partial, true);
      assert.equal(auditSnap.docs[0].data().metadata.failureCode, "time-budget-exceeded");
      assert.doesNotMatch(JSON.stringify([capturedLogs, rec, auditSnap.docs[0].data()]), /[A-Z2-9]{5}-[A-Z2-9]{5}/);

      // Resume remaining failed rows + check re-importing n1 does not duplicate activation codes.
      hookBag.timeBudgetMs = undefined;
      hookBag.afterStep = undefined;
      const resumeRes = await call(importStudentRoster, "admin", {fileName: "budget-resume.csv", rows});
      if (resumeRes.importId) importIds.push(resumeRes.importId);
      assert.equal(resumeRes.status, "complete");
      assert.deepEqual(resumeRes.counts, {new: 1, updated: 2, linked: 1});
      assert.deepEqual(resumeRes.codes, [], "no activation codes are created");
      assert.equal((await db.doc(`student_roster/${kN1}`).get()).data()!.activationCode, null);
      assert.equal((await db.doc(`users/${u1Uid}`).get()).data()?.collegeId, collegeB);
      assert.equal((await db.doc(`users/${u1Uid}`).get()).data()?.college, "College B");
      assert.equal((await db.doc(`appointments/${u1Appt}`).get()).data()?.collegeId, collegeB);
      assert.equal((await db.doc(`users/${l1Uid}`).get()).data()?.collegeId, collegeB);
      assert.equal((await db.doc(`appointments/${l1Appt}`).get()).data()?.collegeId, collegeB);
    } finally {
      console.warn = origWarn;
      hookBag.timeBudgetMs = undefined;
      hookBag.afterStep = undefined;
      await cleanupImportArtifacts(importIds);
      await Promise.all([
        db.doc(`users/${u1Uid}`).delete().catch(() => undefined),
        db.doc(`users/${l1Uid}`).delete().catch(() => undefined),
        db.doc(`student_id_reservations/${kL1}`).delete().catch(() => undefined),
        ...[kN1, kU1, kL1, kN2].map((k) => db.doc(`student_roster/${k}`).delete().catch(() => undefined)),
        db.doc(`appointments/${u1Appt}`).delete().catch(() => undefined),
        db.doc(`appointments/${l1Appt}`).delete().catch(() => undefined),
      ]);
    }
  },
);

test(
  "Step 11.3F Test E: finalization retry is idempotent (no duplicate audit) and persistent finalization failure never reports complete",
  {skip: !emulated},
  async () => {
    await resetMainAssignments();
    const baseNo = Date.now().toString().slice(-6);
    const no1 = `${baseNo}41`;
    const no2 = `${baseNo}42`;
    const key1 = canonicalLoginId(no1);
    const key2 = canonicalLoginId(no2);
    const importIds: string[] = [];

    const hookBag = rosterTestHooks as {
      beforeFinalize?: (attempt: number) => Promise<void>;
    };
    const origError = console.error;
    const loggedErrors: unknown[] = [];
    console.error = (...args: unknown[]) => {
      loggedErrors.push(args);
      origError(...args);
    };
    try {
      // 1. Transient failure on finalization attempt 1 -> retry succeeds with exactly ONE audit doc.
      let seenAttempts = 0;
      hookBag.beforeFinalize = async (attempt: number) => {
        seenAttempts = attempt;
        if (attempt === 1) throw new Error("Simulated transient finalization failure");
      };
      const okAfterRetry = await call(importStudentRoster, "admin", {
        fileName: "finalize-retry.csv",
        rows: [{studentNo: no1, surname: "Final", firstName: "Retry", middleName: "", dateOfBirth: "2004-05-06", college: "College A", course: "BS Course A", yearLevel: "1st Year"}],
      });
      if (okAfterRetry.importId) importIds.push(okAfterRetry.importId);
      assert.equal(seenAttempts, 2);
      assert.equal(okAfterRetry.status, "complete");
      assert.deepEqual(okAfterRetry.counts, {new: 1, updated: 0, linked: 0});
      const auditsRetry = await db.collection("admin_audit_logs").where("targetId", "==", okAfterRetry.importId).get();
      assert.equal(auditsRetry.size, 1, "finalization retry must never write duplicate audit rows");
      const recRetry = (await db.doc(`student_roster_imports/${okAfterRetry.importId}`).get()).data()!;
      assert.equal(recRetry.status, "complete");

      // 2. Persistent finalization failure across all retries -> must throw HttpsError, never return false complete, never log codes.
      hookBag.beforeFinalize = async () => {
        throw new Error("Simulated persistent finalization outage");
      };
      const beforeImportsSnap = await db.collection("student_roster_imports").where("actorId", "==", uid("admin")).get();
      const beforeIds = new Set(beforeImportsSnap.docs.map((d) => d.id));
      await assert.rejects(
        call(importStudentRoster, "admin", {
          fileName: "finalize-persistent-fail.csv",
          rows: [{studentNo: no2, surname: "Final", firstName: "Fail", middleName: "", dateOfBirth: "2004-05-06", college: "College A", course: "BS Course A", yearLevel: "1st Year"}],
        }),
        (err: unknown) => err instanceof HttpsError && err.code === "aborted",
      );
      const afterImportsSnap = await db.collection("student_roster_imports").where("actorId", "==", uid("admin")).get();
      const createdImport = afterImportsSnap.docs.find((d) => !beforeIds.has(d.id));
      assert.ok(createdImport, "import summary record should exist after committed rows");
      importIds.push(createdImport!.id);
      const failedSummary = createdImport!.data();
      assert.notEqual(failedSummary.status, "complete");
      assert.equal(failedSummary.counts.new, 1);
      assert.equal(failedSummary.failureCode, "finalization-failed");
      assert.ok(
        loggedErrors.some((entry) => JSON.stringify(entry).includes("student_roster_import_finalize_failed")),
        "expected structured finalization failure log",
      );
      assert.doesNotMatch(JSON.stringify(loggedErrors), /[A-Z2-9]{5}-[A-Z2-9]{5}/);
    } finally {
      console.error = origError;
      hookBag.beforeFinalize = undefined;
      await cleanupImportArtifacts(importIds);
      await Promise.all([
        db.doc(`student_roster/${key1}`).delete().catch(() => undefined),
        db.doc(`student_roster/${key2}`).delete().catch(() => undefined),
      ]);
    }
  },
);

test(
  "Step 11.3G.1 Test D: expired execution budget before step 0 halts cleanly without writes or codes",
  {skip: !emulated},
  async () => {
    await resetMainAssignments();
    const baseNo = Date.now().toString().slice(-6);
    const nNew = `${baseNo}51`;
    const uNo = `${baseNo}52`;
    const kNew = canonicalLoginId(nNew);
    const uKey = canonicalLoginId(uNo);
    const uUid = `${prefix}-3gd-upd-uid`;
    const apptId = `${prefix}-3gd-appt`;
    const importIds: string[] = [];
    const hookBag = rosterTestHooks as {
      timeBudgetMs?: number;
      afterStep?: (stepIndex: number) => Promise<void>;
      onCodeMinted?: (studentNo: string) => void;
    };
    const mintedNos: string[] = [];
    try {
      await Promise.all([
        db.doc(`users/${uUid}`).set({
          accessRole: "appUser",
          populationRole: "student",
          collegeId: collegeA,
          college: "College A",
          verificationStatus: "verified",
          schoolId: uNo,
        }),
        db.doc(`student_roster/${uKey}`).set({
          studentNo: uNo,
          studentKey: uKey,
          surname: "Upd",
          surnameNormalized: "upd",
          firstName: "One",
          middleName: "",
          dateOfBirthKey: "2004-05-06",
          dateOfBirth: Timestamp.fromDate(new Date("2004-05-06T00:00:00Z")),
          collegeId: collegeA,
          college: "College A",
          courseId: courseA,
          course: "BS Course A",
          departmentId: deptA,
          department: "Dept A",
          yearLevel: "2nd Year",
          status: "active",
          activated: true,
          userId: uUid,
        }),
        db.doc(`appointments/${apptId}`).set({
          userId: uUid,
          fullName: "Upd One",
          status: "confirmed",
          collegeId: collegeA,
          studentVerificationStatus: "verified",
          scheduledAt: Timestamp.fromMillis(Date.now() + 86_400_000),
        }),
      ]);

      hookBag.timeBudgetMs = 0;
      hookBag.onCodeMinted = (no) => mintedNos.push(no);
      const res = await call(importStudentRoster, "admin", {
        fileName: "expired-before-step0.csv",
        rows: [
          {
            studentNo: nNew,
            surname: "Zero",
            firstName: "New",
            middleName: "",
            dateOfBirth: "2004-05-06",
            college: "College B",
            course: "BS Course B",
            yearLevel: "1st Year",
          },
          {
            studentNo: uNo,
            surname: "Upd",
            firstName: "One",
            middleName: "",
            dateOfBirth: "2004-05-06",
            college: "College B",
            course: "BS Course B",
            yearLevel: "3rd Year",
          },
        ],
      });
      if (res.importId) importIds.push(res.importId);

      assert.equal(res.status, "partial");
      assert.equal(res.failureCode, "time-budget-exceeded");
      assert.deepEqual(res.counts, {new: 0, updated: 0, linked: 0});
      assert.deepEqual(res.codes, []);
      assert.deepEqual(mintedNos, []);
      assert.deepEqual(res.failedRows.map((r: {studentNo: string}) => r.studentNo), [nNew, uNo]);

      assert.equal((await db.doc(`student_roster/${kNew}`).get()).exists, false);
      assert.equal((await db.doc(`users/${uUid}`).get()).data()?.collegeId, collegeA);
      assert.equal((await db.doc(`appointments/${apptId}`).get()).data()?.collegeId, collegeA);

      const summary = (await db.doc(`student_roster_imports/${res.importId}`).get()).data()!;
      assert.equal(summary.status, "partial");
      assert.equal(summary.failureCode, "time-budget-exceeded");
      assert.deepEqual(summary.counts, {new: 0, updated: 0, linked: 0});

      const audit = (
        await db.collection("admin_audit_logs").doc(`student_roster_import_${res.importId}`).get()
      ).data()!;
      assert.deepEqual(audit.metadata.counts, {new: 0, updated: 0, linked: 0});
      assert.equal(audit.metadata.partial, true);
      assert.equal(audit.metadata.failureCode, "time-budget-exceeded");
    } finally {
      hookBag.timeBudgetMs = undefined;
      hookBag.afterStep = undefined;
      hookBag.onCodeMinted = undefined;
      await cleanupImportArtifacts(importIds);
      await Promise.all([
        db.doc(`student_roster/${kNew}`).delete().catch(() => undefined),
        db.doc(`student_roster/${uKey}`).delete().catch(() => undefined),
        db.doc(`users/${uUid}`).delete().catch(() => undefined),
        db.doc(`appointments/${apptId}`).delete().catch(() => undefined),
      ]);
    }
  },
);

test(
  "Step 11.3G.1 Test E: no activation code is minted for executed batches",
  {skip: !emulated},
  async () => {
    await resetMainAssignments();
    const baseNo = Date.now().toString().slice(-6);
    const nos = [61, 62, 63, 64].map((suffix) => `${baseNo}${suffix}`);
    const keys = nos.map((n) => canonicalLoginId(n));
    const importIds: string[] = [];
    const hookBag = rosterTestHooks as {
      batchLimit?: number;
      timeBudgetMs?: number;
      afterStep?: (stepIndex: number) => Promise<void>;
      onCodeMinted?: (studentNo: string) => void;
    };
    const mintedNos: string[] = [];
    const warnLogs: unknown[] = [];
    const origWarn = console.warn;
    console.warn = (...args: unknown[]) => {
      warnLogs.push(args);
      origWarn(...args);
    };
    try {
      hookBag.batchLimit = 2;
      hookBag.timeBudgetMs = 60_000;
      hookBag.onCodeMinted = (no) => mintedNos.push(no);
      hookBag.afterStep = async (stepIndex) => {
        if (stepIndex === 0) {
          hookBag.timeBudgetMs = 0;
        }
      };

      const rows = nos.map((studentNo, i) => ({
        studentNo,
        surname: `Lazy${i}`,
        firstName: "Student",
        middleName: "",
        dateOfBirth: "2004-05-06",
        college: "College B",
        course: "BS Course B",
        yearLevel: "1st Year",
      }));

      const res = await call(importStudentRoster, "admin", {fileName: "lazy-codes.csv", rows});
      if (res.importId) importIds.push(res.importId);

      assert.equal(res.status, "partial");
      assert.equal(res.failureCode, "time-budget-exceeded");
      assert.deepEqual(res.counts, {new: 2, updated: 0, linked: 0});
      assert.deepEqual(res.codes, [], "no activation codes are created");
      assert.deepEqual(mintedNos, []);
      assert.deepEqual(res.failedRows.map((r: {studentNo: string}) => r.studentNo), [nos[2], nos[3]]);

      const [r0, r1, r2, r3] = await Promise.all(keys.map((k) => db.doc(`student_roster/${k}`).get()));
      assert.equal(r0.exists, true);
      assert.equal(r1.exists, true);
      assert.equal(r2.exists, false);
      assert.equal(r3.exists, false);
      assert.equal(r0.data()!.activationCode, null);
      assert.equal(r1.data()!.activationCode, null);
      assert.doesNotMatch(JSON.stringify(warnLogs), /[A-Z2-9]{5}-[A-Z2-9]{5}/);
    } finally {
      console.warn = origWarn;
      hookBag.batchLimit = undefined;
      hookBag.timeBudgetMs = undefined;
      hookBag.afterStep = undefined;
      hookBag.onCodeMinted = undefined;
      await cleanupImportArtifacts(importIds);
      await Promise.all(keys.map((k) => db.doc(`student_roster/${k}`).delete().catch(() => undefined)));
    }
  },
);

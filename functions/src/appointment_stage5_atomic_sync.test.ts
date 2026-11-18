import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {deleteApp, initializeApp} from "firebase/app";
import {connectAuthEmulator, getAuth as getClientAuth, signInWithEmailAndPassword} from "firebase/auth";
import {
  collection,
  connectFirestoreEmulator,
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
  reviewProfileVerification,
  reviewStudentCorrection,
  setStaffCollegeAssignments,
  syncStudentAppointmentCollegeScope,
  updateStudentRosterRecord,
} from "./index";

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

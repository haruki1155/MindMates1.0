import assert from "node:assert/strict";
import {after, before, beforeEach, test} from "node:test";
import {getApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";

import {downloadClinicalSessionEvidence} from "./index";
import {ensureAuthUser} from "./test_auth_helper";

type Callable = {
  run: (request: {auth?: {uid: string}; data?: Record<string, unknown>}) => Promise<{
    name: string;
    contentType: string;
    size: number;
    dataBase64: string;
  }>;
};

const callable = downloadClinicalSessionEvidence as unknown as Callable;
const db = getFirestore();
const prefix = `evidence-dl-${Date.now()}`;
const citeCollege = `${prefix}-cite`;
const casCollege = `${prefix}-cas`;
const superAdminId = `${prefix}-super-admin`;
const otherAdminId = `${prefix}-other-admin`;
const unverifiedAdminId = `${prefix}-unverified-admin`;
const counselorCiteId = `${prefix}-counselor-cite`;
const counselorUploaderId = `${prefix}-counselor-uploader`;
const counselorCasId = `${prefix}-counselor-cas`;
const counselorPendingId = `${prefix}-counselor-pending`;
const counselorRejectedId = `${prefix}-counselor-rejected`;
const counselorSuspendedId = `${prefix}-counselor-suspended`;
const counselorDisabledStatusId = `${prefix}-counselor-disabled-status`;
const counselorAuthDisabledId = `${prefix}-counselor-auth-disabled`;
const counselorUnverifiedEmailId = `${prefix}-counselor-unverified`;
const portalStaffId = `${prefix}-portal-staff`;
const studentId = `${prefix}-student`;
const triageStudentId = `${prefix}-triage-student`;

const appointmentId = `${prefix}-apt-verified`;
const legacyAppointmentId = `${prefix}-apt-legacy`;
const triageAppointmentId = `${prefix}-apt-triage`;

const pdfNonce = "0123456789abcdef0123456789abcdef";
const altNonce = "fedcba9876543210fedcba9876543210";
const validPath = `counseling_session_files/${appointmentId}/${counselorUploaderId}/${pdfNonce}.pdf`;
const legacyPath = `counseling_session_files/${legacyAppointmentId}/${counselorUploaderId}/${pdfNonce}.pdf`;
const triagePath = `counseling_session_files/${triageAppointmentId}/${counselorUploaderId}/${pdfNonce}.pdf`;
const unreferencedPath = `counseling_session_files/${appointmentId}/${counselorUploaderId}/${altNonce}.pdf`;
const missingStoragePath = `counseling_session_files/${appointmentId}/${counselorUploaderId}/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.pdf`;

const samplePdfBytes = Buffer.from("%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n", "utf8");

function testBucket() {
  const configured =
    getApp().options.storageBucket ||
    process.env.FIREBASE_STORAGE_BUCKET ||
    (() => {
      try {
        const parsed = JSON.parse(process.env.FIREBASE_CONFIG ?? "{}") as {storageBucket?: string};
        return parsed.storageBucket;
      } catch {
        return undefined;
      }
    })() ||
    `${process.env.GCLOUD_PROJECT || "mindmate-staging"}.appspot.com`;
  return getStorage().bucket(configured);
}

async function seedStorageFile(
  filePath: string,
  bytes: Buffer,
  options: {contentType?: string; uploadedBy?: string; appointmentId?: string} = {},
) {
  const file = testBucket().file(filePath);
  await file.save(bytes, {
    resumable: false,
    contentType: options.contentType ?? "application/pdf",
    metadata: {
      contentType: options.contentType ?? "application/pdf",
      metadata: {
        uploadedBy: options.uploadedBy ?? counselorUploaderId,
        appointmentId: options.appointmentId ?? appointmentId,
      },
    },
  });
}

async function expectCallableCode(promise: Promise<unknown>, expectedCode: string): Promise<Error> {
  let caught: unknown;
  try {
    await promise;
  } catch (error) {
    caught = error;
  }
  assert.ok(caught, `Expected callable to fail with ${expectedCode}, but it succeeded.`);
  const code = (caught as {code?: unknown})?.code;
  assert.equal(code, expectedCode, `Expected error code "${expectedCode}", got "${String(code)}" (${String(caught)})`);
  return caught as Error;
}

async function clearRunAudits() {
  const snap = await db
    .collection("admin_audit_logs")
    .where("targetId", "in", [appointmentId, legacyAppointmentId, triageAppointmentId])
    .get();
  await Promise.all(snap.docs.map((doc) => doc.ref.delete()));
}

async function countRunAudits(): Promise<FirebaseFirestore.QueryDocumentSnapshot[]> {
  const snap = await db
    .collection("admin_audit_logs")
    .where("targetId", "in", [appointmentId, legacyAppointmentId, triageAppointmentId])
    .get();
  return snap.docs;
}

let previousSuperAdmin: string | undefined;

before(async () => {
  if (
    !process.env.FIRESTORE_EMULATOR_HOST ||
    !process.env.FIREBASE_AUTH_EMULATOR_HOST ||
    !process.env.FIREBASE_STORAGE_EMULATOR_HOST
  ) {
    throw new Error(
      "FIRESTORE_EMULATOR_HOST, FIREBASE_AUTH_EMULATOR_HOST, and FIREBASE_STORAGE_EMULATOR_HOST are required.",
    );
  }
  previousSuperAdmin = process.env.SUPER_ADMIN_UID;
  process.env.SUPER_ADMIN_UID = superAdminId;

  await Promise.all([
    ensureAuthUser(superAdminId, true),
    ensureAuthUser(otherAdminId, true),
    ensureAuthUser(unverifiedAdminId, false),
    ensureAuthUser(counselorCiteId, true),
    ensureAuthUser(counselorUploaderId, true),
    ensureAuthUser(counselorCasId, true),
    ensureAuthUser(counselorPendingId, true),
    ensureAuthUser(counselorRejectedId, true),
    ensureAuthUser(counselorSuspendedId, true),
    ensureAuthUser(counselorDisabledStatusId, true),
    ensureAuthUser(counselorAuthDisabledId, true),
    ensureAuthUser(counselorUnverifiedEmailId, false),
    ensureAuthUser(portalStaffId, true),
    ensureAuthUser(studentId, true),
    ensureAuthUser(triageStudentId, true),
  ]);
  await getAuth().updateUser(counselorAuthDisabledId, {disabled: true});

  await Promise.all([
    db.doc(`colleges/${citeCollege}`).set({name: "CITE", code: "CITE", active: true}),
    db.doc(`colleges/${casCollege}`).set({name: "CAS", code: "CAS", active: true}),
    db.doc(`users/${superAdminId}`).set({accessRole: "admin", accountStatus: "active", name: "Super Admin"}),
    db.doc(`users/${otherAdminId}`).set({accessRole: "admin", accountStatus: "active", name: "Ordinary Admin"}),
    db.doc(`users/${unverifiedAdminId}`).set({accessRole: "admin", accountStatus: "active", name: "Unverified Admin"}),
    db.doc(`users/${counselorCiteId}`).set({
      accessRole: "counselor",
      staffAccountStatus: "approved",
      accountStatus: "active",
      assignedCollegeIds: [citeCollege],
      name: "CITE Counselor",
    }),
    db.doc(`users/${counselorUploaderId}`).set({
      accessRole: "counselor",
      staffAccountStatus: "approved",
      accountStatus: "active",
      assignedCollegeIds: [citeCollege],
      name: "Uploader Counselor",
    }),
    db.doc(`users/${counselorCasId}`).set({
      accessRole: "counselor",
      staffAccountStatus: "approved",
      accountStatus: "active",
      assignedCollegeIds: [casCollege],
      name: "CAS Counselor",
    }),
    db.doc(`users/${counselorPendingId}`).set({
      accessRole: "counselor",
      staffAccountStatus: "pending",
      accountStatus: "active",
      assignedCollegeIds: [citeCollege],
      name: "Pending Counselor",
    }),
    db.doc(`users/${counselorRejectedId}`).set({
      accessRole: "counselor",
      staffAccountStatus: "rejected",
      accountStatus: "active",
      assignedCollegeIds: [citeCollege],
      name: "Rejected Counselor",
    }),
    db.doc(`users/${counselorSuspendedId}`).set({
      accessRole: "counselor",
      staffAccountStatus: "approved",
      accountStatus: "suspended",
      assignedCollegeIds: [citeCollege],
      name: "Suspended Counselor",
    }),
    db.doc(`users/${counselorDisabledStatusId}`).set({
      accessRole: "counselor",
      staffAccountStatus: "disabled",
      accountStatus: "active",
      assignedCollegeIds: [citeCollege],
      name: "Disabled Status Counselor",
    }),
    db.doc(`users/${counselorAuthDisabledId}`).set({
      accessRole: "counselor",
      staffAccountStatus: "approved",
      accountStatus: "active",
      assignedCollegeIds: [citeCollege],
      name: "Disabled Auth Counselor",
    }),
    db.doc(`users/${counselorUnverifiedEmailId}`).set({
      accessRole: "counselor",
      staffAccountStatus: "approved",
      accountStatus: "active",
      assignedCollegeIds: [citeCollege],
      name: "Unverified Counselor",
    }),
    db.doc(`users/${portalStaffId}`).set({
      accessRole: "portalStaff",
      staffAccountStatus: "approved",
      accountStatus: "active",
      name: "PAACC Staff",
    }),
  ]);
});

beforeEach(async () => {
  await clearRunAudits();
  await Promise.all([
    db.doc(`users/${studentId}`).set({
      accessRole: "appUser",
      verificationStatus: "verified",
      collegeId: citeCollege,
    }),
    db.doc(`users/${triageStudentId}`).set({
      accessRole: "appUser",
      verificationStatus: "needsReview",
      collegeId: citeCollege,
    }),
    db.doc(`appointments/${appointmentId}`).set({
      userId: studentId,
      status: "completed",
      collegeId: citeCollege,
      studentVerificationStatus: "verified",
    }),
    db.doc(`appointments/${appointmentId}/clinical_notes/session`).set({
      appointmentId,
      summary: "Private notes",
      attachments: [
        {
          path: validPath,
          name: "Session Worksheet.pdf",
          contentType: "application/pdf",
          size: samplePdfBytes.length,
        },
        {
          path: missingStoragePath,
          name: "Deleted File.pdf",
          contentType: "application/pdf",
          size: samplePdfBytes.length,
        },
      ],
    }),
    // Legacy appointment missing collegeId and studentVerificationStatus projections.
    db.doc(`appointments/${legacyAppointmentId}`).set({
      userId: studentId,
      status: "completed",
    }),
    db.doc(`appointments/${legacyAppointmentId}/clinical_notes/session`).set({
      appointmentId: legacyAppointmentId,
      summary: "Legacy notes",
      attachments: [
        {
          path: legacyPath,
          name: "Legacy Worksheet.pdf",
          contentType: "application/pdf",
          size: samplePdfBytes.length,
        },
      ],
    }),
    // Unverified triage appointment.
    db.doc(`appointments/${triageAppointmentId}`).set({
      userId: triageStudentId,
      status: "completed",
      collegeId: citeCollege,
      studentVerificationStatus: "needsReview",
    }),
    db.doc(`appointments/${triageAppointmentId}/clinical_notes/session`).set({
      appointmentId: triageAppointmentId,
      summary: "Triage notes",
      attachments: [
        {
          path: triagePath,
          name: "Triage Form.pdf",
          contentType: "application/pdf",
          size: samplePdfBytes.length,
        },
      ],
    }),
    seedStorageFile(validPath, samplePdfBytes, {appointmentId}),
    seedStorageFile(legacyPath, samplePdfBytes, {appointmentId: legacyAppointmentId}),
    seedStorageFile(triagePath, samplePdfBytes, {appointmentId: triageAppointmentId}),
    seedStorageFile(unreferencedPath, samplePdfBytes, {appointmentId}),
  ]);
  await testBucket().file(missingStoragePath).delete({ignoreNotFound: true});
});

after(async () => {
  if (previousSuperAdmin == null) delete process.env.SUPER_ADMIN_UID;
  else process.env.SUPER_ADMIN_UID = previousSuperAdmin;
  await clearRunAudits();
  await Promise.all([
    testBucket().file(validPath).delete({ignoreNotFound: true}),
    testBucket().file(legacyPath).delete({ignoreNotFound: true}),
    testBucket().file(triagePath).delete({ignoreNotFound: true}),
    testBucket().file(unreferencedPath).delete({ignoreNotFound: true}),
    testBucket().file(missingStoragePath).delete({ignoreNotFound: true}),
    db.doc(`appointments/${appointmentId}/clinical_notes/session`).delete(),
    db.doc(`appointments/${legacyAppointmentId}/clinical_notes/session`).delete(),
    db.doc(`appointments/${triageAppointmentId}/clinical_notes/session`).delete(),
    db.doc(`appointments/${appointmentId}`).delete(),
    db.doc(`appointments/${legacyAppointmentId}`).delete(),
    db.doc(`appointments/${triageAppointmentId}`).delete(),
    db.doc(`colleges/${citeCollege}`).delete(),
    db.doc(`colleges/${casCollege}`).delete(),
    ...[
      superAdminId,
      otherAdminId,
      unverifiedAdminId,
      counselorCiteId,
      counselorUploaderId,
      counselorCasId,
      counselorPendingId,
      counselorRejectedId,
      counselorSuspendedId,
      counselorDisabledStatusId,
      counselorAuthDisabledId,
      counselorUnverifiedEmailId,
      portalStaffId,
      studentId,
      triageStudentId,
    ].map((uid) => db.doc(`users/${uid}`).delete()),
  ]);
});

test("authorized assigned counselor, legacy verified appointment, and super-admin download private attachments with audit and no public tokens", async () => {
  // 1. Assigned counselor downloads verified student's attachment (uploaded by another CITE counselor).
  const counselorRes = await callable.run({
    auth: {uid: counselorCiteId},
    data: {appointmentId, path: validPath},
  });
  assert.equal(counselorRes.name, "Session Worksheet.pdf");
  assert.equal(counselorRes.contentType, "application/pdf");
  assert.equal(counselorRes.size, samplePdfBytes.length);
  assert.deepEqual(Buffer.from(counselorRes.dataBase64, "base64"), samplePdfBytes);
  assert.equal(JSON.stringify(counselorRes).includes("firebaseStorageDownloadTokens"), false);
  assert.equal(JSON.stringify(counselorRes).includes("https://"), false);

  // Storage object must still have no firebaseStorageDownloadTokens minted.
  const [storageMeta] = await testBucket().file(validPath).getMetadata();
  assert.equal(storageMeta.metadata?.firebaseStorageDownloadTokens, undefined);

  // 2. Assigned counselor downloads legacy appointment attachment missing collegeId/studentVerificationStatus projections.
  const legacyRes = await callable.run({
    auth: {uid: counselorCiteId},
    data: {appointmentId: legacyAppointmentId, path: legacyPath},
  });
  assert.equal(legacyRes.name, "Legacy Worksheet.pdf");
  assert.deepEqual(Buffer.from(legacyRes.dataBase64, "base64"), samplePdfBytes);

  // 3. Super-admin downloads unverified-student triage appointment attachment.
  const adminRes = await callable.run({
    auth: {uid: superAdminId},
    data: {appointmentId: triageAppointmentId, path: triagePath},
  });
  assert.equal(adminRes.name, "Triage Form.pdf");
  assert.deepEqual(Buffer.from(adminRes.dataBase64, "base64"), samplePdfBytes);

  // Verify audit logs for all 3 downloads without filename, raw path, or bytes.
  const audits = await countRunAudits();
  assert.equal(audits.length, 3);
  for (const doc of audits) {
    const data = doc.data();
    assert.equal(data.action, "CLINICAL_ATTACHMENT_DOWNLOADED");
    assert.equal(data.category, "SECURITY");
    assert.equal(data.targetType, "appointment");
    const serialized = JSON.stringify(data);
    assert.equal(serialized.includes("Session Worksheet.pdf"), false);
    assert.equal(serialized.includes("Legacy Worksheet.pdf"), false);
    assert.equal(serialized.includes("Triage Form.pdf"), false);
    assert.equal(serialized.includes("counseling_session_files/"), false);
    assert.equal(serialized.includes("%PDF"), false);
    assert.ok(typeof data.metadata?.attachmentPathHash === "string" && data.metadata.attachmentPathHash.length > 0);
  }
});

test("denies unauthenticated, unauthorized roles, lifecycle-revoked staff, missing appointments, and live student scope revocations with zero audit rows", async () => {
  await expectCallableCode(callable.run({data: {appointmentId, path: validPath}}), "unauthenticated");

  const deniedUids = [
    studentId,
    portalStaffId,
    otherAdminId,
    unverifiedAdminId,
    counselorCasId,
    counselorPendingId,
    counselorRejectedId,
    counselorSuspendedId,
    counselorDisabledStatusId,
    counselorAuthDisabledId,
    counselorUnverifiedEmailId,
  ];
  for (const uid of deniedUids) {
    await expectCallableCode(
      callable.run({auth: {uid}, data: {appointmentId, path: validPath}}),
      "permission-denied",
    );
  }

  // Counselor cannot access unverified triage appointment.
  await expectCallableCode(
    callable.run({auth: {uid: counselorCiteId}, data: {appointmentId: triageAppointmentId, path: triagePath}}),
    "permission-denied",
  );

  // Missing appointment for counselor -> permission-denied (no enumeration).
  const missingAptId = `${prefix}-missing-apt`;
  await expectCallableCode(
    callable.run({
      auth: {uid: counselorCiteId},
      data: {
        appointmentId: missingAptId,
        path: `counseling_session_files/${missingAptId}/${counselorUploaderId}/${pdfNonce}.pdf`,
      },
    }),
    "permission-denied",
  );

  // Live student verification revoked -> immediate permission-denied for CITE counselor.
  await db.doc(`users/${studentId}`).update({verificationStatus: "needsReview"});
  await expectCallableCode(
    callable.run({auth: {uid: counselorCiteId}, data: {appointmentId, path: validPath}}),
    "permission-denied",
  );

  // Live student college changed -> CITE counselor immediately denied.
  await db.doc(`users/${studentId}`).update({verificationStatus: "verified", collegeId: casCollege});
  await expectCallableCode(
    callable.run({auth: {uid: counselorCiteId}, data: {appointmentId, path: validPath}}),
    "permission-denied",
  );

  assert.equal((await countRunAudits()).length, 0);
});

test("rejects unreferenced clinical paths, missing storage objects safely, mismatches, oversized files, and tampered metadata", async () => {
  // Path exists in Storage but not in clinical_notes/session.attachments -> not-found
  await expectCallableCode(
    callable.run({auth: {uid: counselorCiteId}, data: {appointmentId, path: unreferencedPath}}),
    "not-found",
  );

  // Missing clinical_notes/session -> not-found
  await db.doc(`appointments/${appointmentId}/clinical_notes/session`).delete();
  await expectCallableCode(
    callable.run({auth: {uid: counselorCiteId}, data: {appointmentId, path: validPath}}),
    "not-found",
  );

  // Restore clinical_notes/session and test missing Storage object -> safe not-found
  await db.doc(`appointments/${appointmentId}/clinical_notes/session`).set({
    appointmentId,
    summary: "Private notes",
    attachments: [
      {
        path: missingStoragePath,
        name: "Deleted File.pdf",
        contentType: "application/pdf",
        size: samplePdfBytes.length,
      },
      {
        path: validPath,
        name: "Session Worksheet.pdf",
        contentType: "application/pdf",
        size: samplePdfBytes.length,
      },
    ],
  });
  const missingErr = await expectCallableCode(
    callable.run({auth: {uid: counselorCiteId}, data: {appointmentId, path: missingStoragePath}}),
    "not-found",
  );
  assert.equal(missingErr.message.includes("counseling_session_files/"), false);
  assert.equal(missingErr.message.includes(testBucket().name), false);

  // Mismatch / traversal -> invalid-argument
  await expectCallableCode(
    callable.run({auth: {uid: counselorCiteId}, data: {appointmentId, path: legacyPath}}),
    "invalid-argument",
  );
  await expectCallableCode(
    callable.run({
      auth: {uid: counselorCiteId},
      data: {
        appointmentId,
        path: `counseling_session_files/${appointmentId}/${counselorUploaderId}/../${pdfNonce}.pdf`,
      },
    }),
    "invalid-argument",
  );

  // Oversized (> 5 MiB) Storage object -> failed-precondition
  await seedStorageFile(validPath, Buffer.alloc(5 * 1024 * 1024 + 1, 0x41), {appointmentId});
  await expectCallableCode(
    callable.run({auth: {uid: counselorCiteId}, data: {appointmentId, path: validPath}}),
    "failed-precondition",
  );

  // Tampered metadata (uploadedBy / appointmentId / MIME) -> failed-precondition
  await seedStorageFile(validPath, samplePdfBytes, {
    appointmentId,
    uploadedBy: "forged-uploader",
  });
  await expectCallableCode(
    callable.run({auth: {uid: counselorCiteId}, data: {appointmentId, path: validPath}}),
    "failed-precondition",
  );

  await seedStorageFile(validPath, samplePdfBytes, {
    appointmentId: "wrong-appointment",
    uploadedBy: counselorUploaderId,
  });
  await expectCallableCode(
    callable.run({auth: {uid: counselorCiteId}, data: {appointmentId, path: validPath}}),
    "failed-precondition",
  );

  await seedStorageFile(validPath, samplePdfBytes, {
    appointmentId,
    contentType: "image/png",
  });
  await expectCallableCode(
    callable.run({auth: {uid: counselorCiteId}, data: {appointmentId, path: validPath}}),
    "failed-precondition",
  );

  assert.equal((await countRunAudits()).length, 0);
});

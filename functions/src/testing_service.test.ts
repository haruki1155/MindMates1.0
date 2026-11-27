import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import "./index";
import {
  acceptTestingServiceSchedule,
  proposeTestingServiceSchedule,
  requestTestingServiceReschedule,
  submitTestingServiceInquiry,
  uploadTestingServiceDocument,
} from "./testing_service";

const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const prefix = `ts-${Date.now()}`;
const uid = (name: string) => `${prefix}-${name}`;
const db = getFirestore();
const cite = `${prefix}-cite`;

type Callable = {run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<any>};
const call = (fn: unknown, actor: string, data: Record<string, unknown>) =>
  (fn as Callable).run({auth: {uid: uid(actor)}, data});

async function rejects(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (error: unknown) => error instanceof HttpsError && error.code === code);
}

const accounts: Record<string, {verified: boolean; profile: Record<string, unknown>}> = {
  admin: {verified: true, profile: {accessRole: "admin", accountStatus: "active", name: "Super Admin"}},
  counselor: {
    verified: true,
    profile: {
      accessRole: "counselor",
      staffAccountStatus: "approved",
      accountStatus: "active",
      name: "Counselor Cite",
      assignedCollegeIds: [cite],
    },
  },
  ojtStudent: {
    verified: true,
    profile: {accessRole: "appUser", accountStatus: "active", populationRole: "student", verificationStatus: "verified", collegeId: cite, name: "OJT Student"},
  },
  teaching: {
    verified: true,
    profile: {accessRole: "appUser", accountStatus: "active", populationRole: "teaching", name: "Prof. Santos"},
  },
  nonTeaching: {
    verified: true,
    profile: {accessRole: "appUser", accountStatus: "active", populationRole: "nonTeaching", name: "Staff Cruz"},
  },
  portalStaff: {
    verified: true,
    profile: {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active", populationRole: "nonTeaching"},
  },
};

const samplePayload = (kind: string) => ({
  kind,
  name: `${kind}.pdf`,
  contentType: "application/pdf",
  size: 16,
  dataBase64: Buffer.from("0123456789abcdef").toString("base64"),
});

let previousSuperAdmin: string | undefined;
before(async () => {
  if (!emulated) return;
  previousSuperAdmin = process.env.SUPER_ADMIN_UID;
  process.env.SUPER_ADMIN_UID = uid("admin");
  for (const [name, account] of Object.entries(accounts)) {
    await getAuth().createUser({
      uid: uid(name),
      email: `${uid(name)}@example.invalid`,
      emailVerified: account.verified,
    });
    await db.doc(`users/${uid(name)}`).set(account.profile);
  }
  await db.doc(`colleges/${cite}`).set({name: cite, code: cite, active: true});
});

after(async () => {
  if (!emulated) return;
  if (previousSuperAdmin == null) delete process.env.SUPER_ADMIN_UID;
  else process.env.SUPER_ADMIN_UID = previousSuperAdmin;
  await Promise.all(Object.keys(accounts).map((name) => getAuth().deleteUser(uid(name)).catch(() => undefined)));
});

test("Testing Service end-to-end flow: document upload, eligibility, proposal, one-time reschedule, accept lock, and zero appointments writes", {skip: !emulated}, async () => {
  await rejects(call(uploadTestingServiceDocument, "portalStaff", samplePayload("endorsement_letter")), "permission-denied");

  const [ojtEndorse, ojtReceipt] = await Promise.all([
    call(uploadTestingServiceDocument, "ojtStudent", samplePayload("endorsement_letter")),
    call(uploadTestingServiceDocument, "ojtStudent", samplePayload("official_receipt")),
  ]);

  const baseInput = {
    endorsementLetterConfirmed: true,
    officialReceiptConfirmed: true,
    personalDataSheetConfirmed: true,
    informedConsentConfirmed: true,
    mobileNumber: "09171234567",
    endorsementLetter: ojtEndorse.document,
    officialReceipt: ojtReceipt.document,
    personalDataSheet: {
      fullName: "OJT Student",
      email: "ojt@ucu.edu.ph",
      idNumber: "2023-100",
      officeOrCollege: "CITE",
      courseOrPosition: "BSIT",
    },
  };

  await rejects(call(submitTestingServiceInquiry, "ojtStudent", {
    ...baseInput,
    isStudentForOjt: false,
  }), "failed-precondition");

  const created = await call(submitTestingServiceInquiry, "ojtStudent", {
    ...baseInput,
    isStudentForOjt: true,
    message: "OJT psychological testing request",
  });
  const inquiryId = String(created.inquiryId);

  const mondayNineAm = Date.UTC(2030, 0, 7, 1, 0);
  const proposal1 = await call(proposeTestingServiceSchedule, "counselor", {
    inquiryId,
    scheduledAtMillis: mondayNineAm,
    expectedRevision: 1,
    requestId: `${prefix}-prop-1`,
    note: "Bring endorsement letter and official receipt.",
  });
  assert.equal(proposal1.scheduleRevision, 1);

  const resched = await call(requestTestingServiceReschedule, "ojtStudent", {
    inquiryId,
    reason: "Conflict with OJT orientation.",
    expectedScheduleRevision: 1,
  });
  assert.equal(resched.rescheduleCount, 1);

  const tuesdayTwoPm = Date.UTC(2030, 0, 8, 6, 0);
  const proposal2 = await call(proposeTestingServiceSchedule, "counselor", {
    inquiryId,
    scheduledAtMillis: tuesdayTwoPm,
    expectedRevision: resched.revision,
    requestId: `${prefix}-prop-2`,
  });
  assert.equal(proposal2.scheduleRevision, 3);

  await rejects(call(requestTestingServiceReschedule, "ojtStudent", {
    inquiryId,
    reason: "Second reschedule attempt",
    expectedScheduleRevision: proposal2.scheduleRevision,
  }), "failed-precondition");

  const accepted = await call(acceptTestingServiceSchedule, "ojtStudent", {
    inquiryId,
    expectedScheduleRevision: proposal2.scheduleRevision,
  });
  assert.equal(accepted.status, "confirmed");

  await rejects(call(proposeTestingServiceSchedule, "counselor", {
    inquiryId,
    scheduledAtMillis: Date.UTC(2030, 0, 9, 2, 0),
    expectedRevision: accepted.revision,
    requestId: `${prefix}-prop-3`,
  }), "failed-precondition");

  const appointments = await db.collection("appointments")
    .where("userId", "==", uid("ojtStudent"))
    .get();
  assert.equal(appointments.size, 0);
});

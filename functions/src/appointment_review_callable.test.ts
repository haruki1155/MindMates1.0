import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getFirestore} from "firebase-admin/firestore";

import {respondToAppointment, reviewAppointment} from "./index";

type Callable = {
  run: (request: {auth?: {uid: string}; data?: Record<string, unknown>}) => Promise<unknown>;
};

const db = getFirestore();
const prefix = `appointment-review-${Date.now()}`;
const studentId = `${prefix}-student`;
const adminId = `${prefix}-admin`;
const counselorId = `${prefix}-counselor`;
const otherCounselorId = `${prefix}-other-counselor`;
const portalStaffId = `${prefix}-portal-staff`;
const review = reviewAppointment as unknown as Callable;
const respond = respondToAppointment as unknown as Callable;
const availability = db.collection("pacc_availability").doc("current");

async function futureWeekdaySlot(): Promise<number> {
  for (let offset = 1; offset <= 14; offset += 1) {
    const candidate = new Date(Date.now() + offset * 24 * 60 * 60 * 1_000);
    const weekday = candidate.getUTCDay();
    if (weekday >= 1 && weekday <= 5) {
      const slot = Date.UTC(candidate.getUTCFullYear(), candidate.getUTCMonth(), candidate.getUTCDate(), 1);
      const claimed = await db.collection("appointment_slots").doc(`pacc_${slot}`).get();
      if (!claimed.exists) return slot;
    }
  }
  throw new Error("No future weekday slot found.");
}

async function expectCallableFailure(promise: Promise<unknown>, code: string): Promise<void> {
  await assert.rejects(promise, (error: {code?: unknown}) => error?.code === code);
}

async function seedAppointment(id: string, assignedStaffId = counselorId) {
  const appointment = db.collection("appointments").doc(`${prefix}-${id}`);
  await appointment.set({
    userId: studentId,
    status: "confirmed",
    assignedStaffId,
    scheduledAt: new Date(Date.now() + 24 * 60 * 60 * 1_000),
    scheduledTime: "9:00 AM",
    concern: "Academic pressure",
  });
  return appointment;
}

before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("FIRESTORE_EMULATOR_HOST is required for appointment callable tests.");
  }
  await Promise.all([
    db.collection("users").doc(studentId).set({accessRole: "appUser"}),
    db.collection("users").doc(adminId).set({accessRole: "admin", name: "Test Admin"}),
    db.collection("users").doc(counselorId).set({accessRole: "counselor", name: "Assigned Counselor"}),
    db.collection("users").doc(otherCounselorId).set({accessRole: "counselor", name: "Other Counselor"}),
    db.collection("users").doc(portalStaffId).set({accessRole: "portalStaff", name: "Portal Staff"}),
    availability.set({
      openDays: [1, 2, 3, 4, 5], opensAt: "09:00", closesAt: "17:00",
      presence: "in_office", acceptsWalkIns: false, notice: "", blackoutDates: [],
    }),
  ]);
});

after(async () => {
  const appointments = await db.collection("appointments").where("userId", "==", studentId).get();
  const notifications = await db.collection("notifications").where("userId", "==", studentId).get();
  const slots = await db.collection("appointment_slots").get();
  const appointmentIds = new Set(appointments.docs.map((snapshot) => snapshot.id));
  for (const appointment of appointments.docs) {
    const [notes, history] = await Promise.all([
      appointment.ref.collection("clinical_notes").get(),
      appointment.ref.collection("history").get(),
    ]);
    await Promise.all([
      ...notes.docs.map((snapshot) => snapshot.ref.delete()),
      ...history.docs.map((snapshot) => snapshot.ref.delete()),
    ]);
    await appointment.ref.delete();
  }
  await Promise.all([
    db.collection("users").doc(studentId).delete(),
    db.collection("users").doc(adminId).delete(),
    db.collection("users").doc(counselorId).delete(),
    db.collection("users").doc(otherCounselorId).delete(),
    db.collection("users").doc(portalStaffId).delete(),
    ...notifications.docs.map((snapshot) => snapshot.ref.delete()),
    ...slots.docs
      .filter((snapshot) => appointmentIds.has(String(snapshot.data().appointmentId ?? "")))
      .map((snapshot) => snapshot.ref.delete()),
  ]);
});

test("only authorized clinical staff can complete a session and the summary remains private", async () => {
  const appointment = await seedAppointment("completion");
  const completion = {
    appointmentId: appointment.id,
    action: "completed",
    reply: "Appointment completed.",
    sessionSummary: "Private clinical summary that must not be client-visible.",
    offerFollowUp: true,
    followUpMessage: "Please book a follow-up when you are ready.",
  };

  await expectCallableFailure(review.run({auth: {uid: studentId}, data: completion}), "permission-denied");
  await expectCallableFailure(review.run({auth: {uid: portalStaffId}, data: completion}), "permission-denied");
  await expectCallableFailure(review.run({auth: {uid: otherCounselorId}, data: completion}), "permission-denied");
  await assert.doesNotReject(review.run({auth: {uid: counselorId}, data: completion}));

  const [updated, note, history, notifications] = await Promise.all([
    appointment.get(),
    appointment.collection("clinical_notes").doc("session").get(),
    appointment.collection("history").get(),
    db.collection("notifications").where("appointmentId", "==", appointment.id).get(),
  ]);
  assert.equal(updated.data()?.status, "completed");
  assert.equal(updated.data()?.followUpStatus, "offered");
  assert.equal(updated.data()?.sessionSummary, undefined);
  assert.equal(note.data()?.summary, completion.sessionSummary);
  assert.equal(history.docs.some((snapshot) => JSON.stringify(snapshot.data()).includes(completion.sessionSummary)), false);
  assert.equal(notifications.size, 1);
  assert.equal(notifications.docs[0].data().type, "appointment_follow_up_offer");
  assert.equal(notifications.docs[0].data().title, "Follow-up session offered");
  assert.equal(notifications.docs[0].data().body, completion.followUpMessage);
  assert.equal(JSON.stringify(notifications.docs[0].data()).includes(completion.sessionSummary), false);
});

test("admin can mark Did Not Attend and clients receive the approved wording", async () => {
  const appointment = await seedAppointment("attendance");
  await assert.doesNotReject(review.run({
    auth: {uid: adminId},
    data: {
      appointmentId: appointment.id,
      action: "no_show",
      reply: "The student did not attend the confirmed appointment.",
    },
  }));
  const notifications = await db.collection("notifications").where("appointmentId", "==", appointment.id).get();
  assert.equal((await appointment.get()).data()?.status, "no_show");
  assert.equal(notifications.docs[0].data().title, "Appointment marked as Did Not Attend");
  assert.equal(notifications.docs[0].data().body, "Your appointment was marked as Did Not Attend.");
});

test("admin can complete and staff rescheduling requires a client-safe reason", async () => {
  const adminCompletion = await seedAppointment("admin-completion", adminId);
  await assert.doesNotReject(review.run({
    auth: {uid: adminId},
    data: {
      appointmentId: adminCompletion.id,
      action: "completed",
      reply: "Appointment completed.",
      sessionSummary: "Private administrative session summary.",
      offerFollowUp: false,
    },
  }));
  assert.equal((await adminCompletion.get()).data()?.status, "completed");
  assert.equal(
    (await adminCompletion.collection("clinical_notes").doc("session").get()).data()?.authorId,
    adminId,
  );

  const reschedule = await seedAppointment("reschedule");
  const proposedAt = await futureWeekdaySlot();
  await expectCallableFailure(review.run({
    auth: {uid: counselorId},
    data: {
      appointmentId: reschedule.id,
      action: "reschedule_proposed",
      reply: "A new schedule is proposed.",
      proposedScheduledAt: proposedAt,
    },
  }), "invalid-argument");
  await assert.doesNotReject(review.run({
    auth: {uid: counselorId},
    data: {
      appointmentId: reschedule.id,
      action: "reschedule_proposed",
      reply: "A new schedule is proposed.",
      proposedScheduledAt: proposedAt,
      rescheduleReason: "Counselor schedule conflict",
    },
  }));
  const updated = await reschedule.get();
  assert.equal(updated.data()?.status, "reschedule_proposed");
  assert.equal(updated.data()?.rescheduleReason, "Counselor schedule conflict");
});

test("a client can accept only a valid staff schedule proposal", async () => {
  const appointment = await seedAppointment("accept-reschedule");
  const proposedAt = await futureWeekdaySlot();
  await appointment.update({
    status: "reschedule_proposed",
    proposedScheduledAt: new Date(proposedAt),
    proposedScheduledTime: "9:00 AM",
    proposedBy: "counselor",
    rescheduleReason: "Office schedule adjustment",
  });
  await expectCallableFailure(respond.run({
    auth: {uid: studentId},
    data: {appointmentId: appointment.id, action: "cancel"},
  }), "invalid-argument");
  await expectCallableFailure(respond.run({
    auth: {uid: studentId},
    data: {appointmentId: appointment.id, action: "propose_reschedule"},
  }), "invalid-argument");
  await assert.doesNotReject(respond.run({
    auth: {uid: studentId},
    data: {appointmentId: appointment.id, action: "accept_reschedule"},
  }));
  const updated = await appointment.get();
  assert.equal(updated.data()?.status, "confirmed");
  assert.equal(updated.data()?.rescheduleReason, "Office schedule adjustment");
  assert.equal(updated.data()?.proposedScheduledAt, undefined);
});

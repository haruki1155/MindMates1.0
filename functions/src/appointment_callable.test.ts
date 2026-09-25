import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getFirestore} from "firebase-admin/firestore";

import {createAppointmentRequest} from "./index";

type Callable = {
  run: (request: {auth?: {uid: string}; data?: Record<string, unknown>}) => Promise<unknown>;
};

const db = getFirestore();
const prefix = `appointment-callable-${Date.now()}`;
const userId = `${prefix}-student`;
const availability = db.collection("pacc_availability").doc("current");
const lock = db.collection("appointment_user_locks").doc(userId);
const create = createAppointmentRequest as unknown as Callable;

async function nextWeekdaySlots(startOffset = 1): Promise<[number, number, number]> {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Manila",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  for (let offset = startOffset; offset <= startOffset + 14; offset += 1) {
    const local = Object.fromEntries(
      parts.formatToParts(new Date(Date.now() + offset * 24 * 60 * 60 * 1_000))
        .filter((part) => part.type !== "literal")
        .map((part) => [part.type, part.value]),
    );
    const year = Number(local.year);
    const month = Number(local.month);
    const day = Number(local.day);
    const first = Date.UTC(year, month - 1, day, 1); // 9:00 AM in Manila
    if (new Date(first).getUTCDay() >= 1 && new Date(first).getUTCDay() <= 5 && first > Date.now()) {
      const candidates = [first, first + 60 * 60 * 1_000, first + 2 * 60 * 60 * 1_000];
      const claimed = await Promise.all(candidates.map((millis) =>
        db.collection("appointment_slots").doc(`pacc_${millis}`).get(),
      ));
      if (claimed.every((snapshot) => !snapshot.exists)) return candidates as [number, number, number];
    }
  }
  throw new Error("No future weekday slot found.");
}

function booking(scheduledAt: number, parentAppointmentId?: string): Record<string, unknown> {
  return {
    scheduledAt,
    concern: "Support with academic pressure",
    fullName: "Appointment Test Student",
    contactNumber: "09123456789",
    email: "student@example.com",
    preferredContactMethod: "Email",
    bestTime: "Morning",
    address: "Urdaneta City",
    sex: "Prefer not to say",
    course: "BS Information Technology",
    yearLevel: "Fourth Year",
    therapyBefore: "No",
    ...(parentAppointmentId ? {parentAppointmentId} : {}),
  };
}

async function expectCallableFailure(promise: Promise<unknown>, code: string): Promise<void> {
  await assert.rejects(promise, (error: {code?: unknown}) => error?.code === code);
}

before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("FIRESTORE_EMULATOR_HOST is required for appointment callable tests.");
  }
  await Promise.all([
    db.collection("users").doc(userId).set({
      name: "Appointment Test Student",
      email: "student@example.com",
      phone: "09123456789",
      course: "BS Information Technology",
    }),
    availability.set({
      openDays: [1, 2, 3, 4, 5],
      opensAt: "09:00",
      closesAt: "17:00",
      presence: "in_office",
      acceptsWalkIns: false,
      notice: "",
      blackoutDates: [],
    }),
  ]);
});

after(async () => {
  const appointments = await db.collection("appointments").where("userId", "==", userId).get();
  const slots = await db.collection("appointment_slots").get();
  const deletes = [
    db.collection("users").doc(userId).delete(),
    availability.delete(),
    lock.delete(),
    ...appointments.docs.map((snapshot) => snapshot.ref.delete()),
    ...slots.docs
      .filter((snapshot) => snapshot.data().appointmentId?.startsWith(prefix))
      .map((snapshot) => snapshot.ref.delete()),
  ];
  await Promise.all(deletes);
});

test("the real booking callable serializes concurrent active appointments", async () => {
  const [firstSlot, secondSlot, thirdSlot] = await nextWeekdaySlots();
  const results = await Promise.allSettled([
    create.run({auth: {uid: userId}, data: booking(firstSlot)}),
    create.run({auth: {uid: userId}, data: booking(secondSlot)}),
  ]);

  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  const rejected = results.find((result) => result.status === "rejected");
  assert.equal(rejected?.status, "rejected");
  if (rejected?.status === "rejected") assert.equal((rejected.reason as {code?: string}).code, "resource-exhausted");

  const active = await db.collection("appointments").where("userId", "==", userId).get();
  assert.equal(active.size, 1);
  assert.equal((await lock.get()).data()?.appointmentId, active.docs[0].id);

  await active.docs[0].ref.update({status: "completed"});
  await lock.delete();
  await assert.doesNotReject(create.run({auth: {uid: userId}, data: booking(thirdSlot)}));
  const afterTerminalBooking = await db.collection("appointments").where("userId", "==", userId).get();
  const current = afterTerminalBooking.docs.find((snapshot) => snapshot.data().status === "requested");
  assert.ok(current, "the later terminal booking should create a new requested appointment");
  await Promise.all([current.ref.update({status: "completed"}), lock.delete()]);
});

test("the real booking callable rejects a forged or unoffered follow-up parent", async () => {
  const [unofferedSlot, offeredSlot, retrySlot] = await nextWeekdaySlots(8);
  const parent = db.collection("appointments").doc(`${prefix}-unoffered-parent`);
  await parent.set({userId, status: "completed", followUpRecommended: false, followUpStatus: "none"});
  await expectCallableFailure(
    create.run({auth: {uid: userId}, data: booking(unofferedSlot, parent.id)}),
    "permission-denied",
  );
  await parent.delete();

  const offeredParent = db.collection("appointments").doc(`${prefix}-offered-parent`);
  await offeredParent.set({
    userId,
    status: "completed",
    followUpRecommended: true,
    followUpMessage: "Please book a follow-up when ready.",
    followUpStatus: "offered",
  });
  const result = await create.run({auth: {uid: userId}, data: booking(offeredSlot, offeredParent.id)}) as {appointmentId: string};
  const [child, updatedParent] = await Promise.all([
    db.collection("appointments").doc(result.appointmentId).get(),
    offeredParent.get(),
  ]);
  assert.equal(child.data()?.parentAppointmentId, offeredParent.id);
  assert.equal(updatedParent.data()?.followUpStatus, "booked");
  assert.equal(updatedParent.data()?.followUpAppointmentId, result.appointmentId);

  await Promise.all([
    child.ref.update({status: "completed"}),
    lock.delete(),
  ]);
  await expectCallableFailure(
    create.run({auth: {uid: userId}, data: booking(retrySlot, offeredParent.id)}),
    "permission-denied",
  );
});

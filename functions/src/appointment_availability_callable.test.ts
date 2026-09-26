import assert from "node:assert/strict";
import {after, before, beforeEach, test} from "node:test";
import {getFirestore} from "firebase-admin/firestore";

import {savePaccAvailability} from "./index";

type Callable = {run: (request: {auth?: {uid: string}; data?: Record<string, unknown>}) => Promise<unknown>};
const db = getFirestore();
const prefix = `availability-save-${Date.now()}`;
const adminId = `${prefix}-admin`;
const current = db.collection("pacc_availability").doc("current");
const save = savePaccAvailability as unknown as Callable;
const v1 = {openDays: [1, 2, 3, 4, 5], opensAt: "09:00", closesAt: "17:00", presence: "in_office", acceptsWalkIns: false, notice: "", blackoutDates: []};
const v2 = {
  schemaVersion: 2, timezone: "Asia/Manila", notice: "",
  weekdays: Object.fromEntries(Array.from({length: 7}, (_, index) => [String(index + 1), {enabled: index < 5, opensAt: "09:00", closesAt: "17:00", presence: index < 5 ? "in_office" : "out_of_office", appointmentsEnabled: index < 5, acceptsWalkIns: false}])),
  overrides: [],
};
const request = (availability: Record<string, unknown>, expectedRevision: number, confirmConflicts = true) => save.run({auth: {uid: adminId}, data: {availability, expectedRevision, confirmConflicts}});
async function rejects(promise: Promise<unknown>, code: string) { await assert.rejects(promise, (error: {code?: string}) => error.code === code); }

before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("FIRESTORE_EMULATOR_HOST is required for availability callable tests.");
  await db.collection("users").doc(adminId).set({accessRole: "admin", name: "Availability Test Admin"});
});
beforeEach(async () => {
  await current.set(v1);
  const appointments = await db.collection("appointments").where("testOwner", "==", prefix).get();
  await Promise.all(appointments.docs.map((doc) => doc.ref.delete()));
  const audits = await db.collection("admin_audit_logs").where("actorId", "==", adminId).get();
  await Promise.all(audits.docs.map((doc) => doc.ref.delete()));
});
after(async () => {
  await db.collection("users").doc(adminId).delete();
  await current.set(v1);
});

test("missing revision behaves as zero and V1 to V2 saves replace legacy fields", async () => {
  const result = await request(v2, 0) as {ok: boolean; revision: number; conflicts: unknown[]};
  const stored = (await current.get()).data()!;
  assert.equal(result.ok, true);
  assert.equal(result.revision, 1);
  assert.equal(stored.revision, 1);
  assert.equal(stored.schemaVersion, 2);
  for (const field of ["openDays", "opensAt", "closesAt", "presence", "acceptsWalkIns", "blackoutDates"]) assert.equal(stored[field], undefined);
});

test("correct revisions save, stale revisions fail without mutation, and concurrent saves increment once", async () => {
  await request(v2, 0);
  await assert.doesNotReject(request({...v2, notice: "revision two"}, 1));
  const beforeStale = (await current.get()).data()!;
  await rejects(request({...v2, notice: "stale"}, 1), "failed-precondition");
  assert.deepEqual((await current.get()).data(), beforeStale);
  const sameRevision = beforeStale.revision as number;
  const results = await Promise.allSettled([request({...v2, notice: "A"}, sameRevision), request({...v2, notice: "B"}, sameRevision)]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1, JSON.stringify(results));
  assert.equal(results.filter((result) => result.status === "rejected").length, 1, JSON.stringify(results));
  assert.equal((await current.get()).data()?.revision, sameRevision + 1);
});

test("V1 writes remain allowed only while stored schedule is V1 and V2 cannot be downgraded", async () => {
  await assert.doesNotReject(request({...v1, notice: "legacy"}, 0));
  assert.equal((await current.get()).data()?.schemaVersion, undefined);
  await request(v2, 1);
  await rejects(request(v1, 2), "failed-precondition");
  assert.equal((await current.get()).data()?.schemaVersion, 2);
});

test("conflicts require confirmation, preserve appointments, recalculate at save, and emit bounded audit metadata", async () => {
  const appointment = db.collection("appointments").doc(`${prefix}-conflict`);
  const scheduledAt = new Date("2027-01-04T01:00:00.000Z");
  await appointment.set({testOwner: prefix, status: "confirmed", scheduledAt, concern: "private concern", sessionSummary: "private summary", contactNumber: "09123456789"});
  const closed = {...v2, overrides: [{date: "2027-01-04", closedAllDay: true, reason: "University event"}]};
  await rejects(request(closed, 0, false), "failed-precondition");
  assert.equal((await current.get()).data()?.revision, undefined);
  const unchanged = (await appointment.get()).data()!;
  assert.equal(unchanged.status, "confirmed");
  assert.equal(unchanged.scheduledAt.toMillis(), scheduledAt.getTime());
  assert.equal(unchanged.concern, "private concern");
  assert.equal(unchanged.sessionSummary, "private summary");
  assert.equal(unchanged.contactNumber, "09123456789");
  const result = await request(closed, 0, true) as {revision: number; conflicts: Array<{appointmentId: string}>};
  assert.equal(result.revision, 1);
  assert.equal(result.conflicts.some((conflict) => conflict.appointmentId === appointment.id), true);
  assert.equal((await appointment.get()).data()?.status, "confirmed");
  const audit = (await db.collection("admin_audit_logs").where("actorId", "==", adminId).get()).docs.at(-1)?.data();
  assert.equal(audit?.action, "SCHEDULE_UPDATED");
  assert.deepEqual(Object.keys(audit?.metadata ?? {}).sort(), ["changedWeekdays", "conflictCount", "conflictsConfirmed", "newRevision", "overridesAdded", "overridesRemoved", "overridesUpdated", "previousRevision", "schemaVersion"].sort());
  assert.equal(JSON.stringify(audit?.metadata).includes("private concern"), false);
  assert.equal(JSON.stringify(audit?.metadata).includes("private summary"), false);
  await appointment.delete();
});

import assert from "node:assert/strict";
import {beforeEach, test} from "node:test";

import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";

import {
  createMoodEntryForUser,
  createMoodEntryHandler,
  manilaDateKey,
  moodEntryDocumentId,
  parseMoodEntryInput,
} from "./mood_entries";

const db = getFirestore();
let sequence = 0;

function userId(): string {
  sequence += 1;
  return `mood-v2-test-user-${sequence}`;
}

function requestId(seed: number): string {
  return `00000000-0000-4000-8000-${seed.toString().padStart(12, "0")}`;
}

function payload(seed = 1): Record<string, unknown> {
  return {
    level: 4,
    label: "Steady",
    note: "Private note kept out of errors and logs.",
    entryMethod: "manual",
    expressionAssistUsed: false,
    expressionSuggestionAccepted: false,
    clientRequestId: requestId(seed),
  };
}

async function seedEligibleProfile(uid: string): Promise<void> {
  await db.collection("users").doc(uid).set({
    accessRole: "appUser",
    populationRole: "student",
    accountStatus: "active",
    verificationStatus: "verified",
    dayStreak: 7,
  });
}

function callable(uid: string | undefined, data: unknown): CallableRequest {
  return {auth: uid ? {uid} : undefined, data} as CallableRequest;
}

beforeEach(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("mood_entries.test.ts requires the Firestore emulator.");
  }
});

test("requires Firebase authentication before reading or writing a mood entry", async () => {
  await assert.rejects(
    () => createMoodEntryHandler(callable(undefined, payload())),
    (error: unknown) => error instanceof HttpsError && error.code === "unauthenticated",
  );
});

test("creates one immutable server-authoritative V2 entry without touching legacy mood or streak data", async () => {
  const uid = userId();
  await seedEligibleProfile(uid);
  await db.collection("moods").doc(`legacy-${uid}`).set({userId: uid, level: 2});
  const instant = Timestamp.fromDate(new Date("2026-01-01T16:00:00.000Z"));

  const created = await createMoodEntryForUser(uid, parseMoodEntryInput(payload(2)), instant);
  const entry = await db.collection("moodEntries").doc(moodEntryDocumentId(uid, requestId(2))).get();

  assert.equal(entry.exists, true);
  assert.equal(entry.data()?.userId, uid);
  assert.equal(entry.data()?.dateKey, "2026-01-02");
  assert.equal(entry.data()?.calculationAuthority, "server");
  assert.equal(entry.data()?.occurredAt.toDate().toISOString(), "2026-01-01T16:00:00.000Z");
  assert.equal(created.userId, uid);
  assert.equal(created.dateKey, "2026-01-02");
  assert.equal((await db.collection("moods").doc(`legacy-${uid}`).get()).data()?.level, 2);
  assert.equal((await db.collection("users").doc(uid).get()).data()?.dayStreak, 7);
});

test("same request ID returns the original entry while a conflicting payload is rejected", async () => {
  const uid = userId();
  await seedEligibleProfile(uid);
  const first = await createMoodEntryForUser(
    uid,
    parseMoodEntryInput(payload(3)),
    Timestamp.fromDate(new Date("2026-01-01T15:59:00.000Z")),
  );
  const retry = await createMoodEntryForUser(
    uid,
    parseMoodEntryInput(payload(3)),
    Timestamp.fromDate(new Date("2026-01-01T16:01:00.000Z")),
  );
  assert.equal(retry.entryId, first.entryId);
  assert.equal(retry.occurredAt, first.occurredAt);
  assert.equal(retry.dateKey, first.dateKey);

  await assert.rejects(
    () => createMoodEntryForUser(uid, parseMoodEntryInput({...payload(3), level: 1})),
    (error: unknown) => error instanceof HttpsError && error.code === "already-exists",
  );
});

test("concurrent identical requests create exactly one stable entry", async () => {
  const uid = userId();
  await seedEligibleProfile(uid);
  const input = parseMoodEntryInput(payload(4));
  const [left, right] = await Promise.all([
    createMoodEntryForUser(uid, input),
    createMoodEntryForUser(uid, input),
  ]);
  const entries = await db.collection("moodEntries").where("userId", "==", uid).get();
  assert.equal(entries.size, 1);
  assert.equal(left.entryId, right.entryId);
  assert.equal(left.occurredAt, right.occurredAt);
});

test("rejects malformed IDs, arbitrary fields, invalid levels, and sensitive client authority fields", () => {
  for (const invalid of [
    {...payload(5), clientRequestId: "not-a-uuid"},
    {...payload(5), level: 6},
    {...payload(5), userId: "other-user"},
    {...payload(5), occurredAt: "2026-01-01T00:00:00Z"},
    {...payload(5), rawCameraFrame: "sensitive"},
  ]) {
    assert.throws(() => parseMoodEntryInput(invalid), HttpsError);
  }
});

test("ineligible profiles cannot write and errors do not echo private notes", async () => {
  const uid = userId();
  await db.collection("users").doc(uid).set({
    accessRole: "appUser", populationRole: "student", accountStatus: "suspended",
  });
  const privateNote = "do-not-echo-sensitive-note";
  await assert.rejects(
    () => createMoodEntryForUser(uid, parseMoodEntryInput({...payload(6), note: privateNote})),
    (error: unknown) => {
      assert.equal(error instanceof HttpsError, true);
      assert.equal(String(error).includes(privateNote), false);
      return error instanceof HttpsError && error.code === "failed-precondition";
    },
  );
});

test("Manila date keys use one server instant across the midnight boundary", () => {
  assert.equal(manilaDateKey(new Date("2026-01-01T15:59:59.999Z")), "2026-01-01");
  assert.equal(manilaDateKey(new Date("2026-01-01T16:00:00.000Z")), "2026-01-02");
});

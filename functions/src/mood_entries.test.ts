import assert from "node:assert/strict";
import {createServer} from "node:http";
import {AddressInfo} from "node:net";
import {beforeEach, test} from "node:test";

import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";

import {
  createMoodEntry,
  createMoodEntryDev,
  moodV2RolloutGate,
  createMoodEntryForUser,
  createMoodEntryHandler,
  MoodV2RolloutGate,
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

function stagingGate(uid: string): MoodV2RolloutGate {
  return {projectId: "mindmate-staging", pilotUserIds: new Set([uid])};
}

beforeEach((context) => {
  if (!process.env.FIRESTORE_EMULATOR_HOST && !context.name.startsWith("offline authorization:")) {
    throw new Error("mood_entries.test.ts requires the Firestore emulator.");
  }
});

// Stop at the transaction boundary: these cases exercise the actual profile
// and rollout checks without contacting an emulator or a Firebase service.
async function offlineAuthorization(
  profile: Record<string, unknown> | null,
  gate: MoodV2RolloutGate,
  protectedPath = true,
  invoke?: () => Promise<unknown>,
): Promise<string> {
  const collectionDescriptor = Object.getOwnPropertyDescriptor(db, "collection");
  const transactionDescriptor = Object.getOwnPropertyDescriptor(db, "runTransaction");
  const boundary = new Error("offline transaction boundary");
  Object.defineProperty(db, "collection", {
    configurable: true,
    value: (name: string) => {
      assert.equal(name, "users");
      return {doc: (uid: string) => {
        assert.equal(uid, "offline-user");
        return {get: async () => ({exists: profile != null, data: () => profile ?? undefined})};
      }};
    },
  });
  Object.defineProperty(db, "runTransaction", {
    configurable: true,
    value: async () => { throw boundary; },
  });
  try {
    await (invoke ? invoke() : createMoodEntryForUser(
      "offline-user", parseMoodEntryInput(payload()), Timestamp.now(), gate, protectedPath,
    ));
    throw new Error("The transaction boundary must not be crossed.");
  } catch (error) {
    if (error === boundary) return "allowed";
    if (error instanceof HttpsError) return error.code;
    throw error;
  } finally {
    if (collectionDescriptor) Object.defineProperty(db, "collection", collectionDescriptor);
    else Reflect.deleteProperty(db, "collection");
    if (transactionDescriptor) Object.defineProperty(db, "runTransaction", transactionDescriptor);
    else Reflect.deleteProperty(db, "runTransaction");
  }
}

const offlineGate: MoodV2RolloutGate = {
  projectId: "mindmate-staging", pilotUserIds: new Set(), studentRolloutEnabled: true,
};

for (const [label, profile] of Object.entries({
  "student": {populationRole: "student", declaredRole: "student", role: "student"},
  "student population-only": {populationRole: "student"},
  "student declared-only": {declaredRole: "student"},
  "student legacy-only": {role: "student"},
  "teaching faculty": {populationRole: "teaching", declaredRole: "teaching", role: "faculty"},
  "teaching canonical legacy": {populationRole: "teaching", declaredRole: "teaching", role: "teaching"},
  "nonTeaching staff": {populationRole: "nonTeaching", declaredRole: "nonTeaching", role: "staff"},
  "nonTeaching canonical legacy": {populationRole: "nonTeaching", declaredRole: "nonTeaching", role: "nonTeaching"},
  "teaching declared-only": {declaredRole: "teaching", role: "faculty"},
  "nonTeaching population-only": {populationRole: "nonTeaching"},
})) {
  test(`offline authorization: accepts ${label}`, async () => {
    assert.equal(await offlineAuthorization({accessRole: "appUser", ...profile}, offlineGate), "allowed");
    assert.equal(await offlineAuthorization({accessRole: "appUser", accountStatus: "active", ...profile}, offlineGate), "allowed");
  });
}

for (const [label, profile] of Object.entries({
  "canonical conflict": {populationRole: "teaching", declaredRole: "student", role: "faculty"},
  "legacy conflict": {populationRole: "nonTeaching", declaredRole: "nonTeaching", role: "faculty"},
  "student conflict": {populationRole: "student", declaredRole: "student", role: "staff"},
  "legacy-only staff": {role: "staff"},
  "legacy-only faculty": {role: "faculty"},
  "legacy-only teaching": {role: "teaching"},
  "legacy-only nonTeaching": {role: "nonTeaching"},
  "unknown role": {populationRole: "other", role: "staff"},
  "privileged legacy role": {populationRole: "nonTeaching", role: "admin"},
  "null canonical field": {populationRole: null, declaredRole: "student", role: "student"},
  "null legacy role": {populationRole: "student", role: null},
  "null status": {populationRole: "student", accountStatus: null},
  "inactive": {populationRole: "nonTeaching", accountStatus: "suspended"},
  "pending account": {populationRole: "teaching", accountStatus: "pending"},
  "disabled account": {populationRole: "student", accountStatus: "disabled"},
  "invalid status": {populationRole: "student", accountStatus: 1},
  "staff marker": {populationRole: "nonTeaching", role: "staff", staffAccountStatus: "approved"},
  "pending staff marker": {populationRole: "nonTeaching", role: "staff", staffAccountStatus: "pending"},
  "disabled staff marker": {populationRole: "nonTeaching", role: "staff", staffAccountStatus: "disabled"},
})) {
  test(`offline authorization: rejects ${label}`, async () => {
    assert.notEqual(await offlineAuthorization({accessRole: "appUser", ...profile}, offlineGate), "allowed");
  });
}

test("offline authorization: rejects missing, privileged and unauthenticated profiles", async () => {
  assert.equal(await offlineAuthorization(null, offlineGate), "failed-precondition");
  for (const accessRole of ["admin", "counselor", "portalStaff", "invalid"]) {
    assert.equal(await offlineAuthorization({accessRole, populationRole: "nonTeaching", role: "staff"}, offlineGate), "failed-precondition");
  }
  await assert.rejects(() => createMoodEntryHandler(callable(undefined, payload())), {code: "unauthenticated"});
});

test("offline authorization: keeps flag, Dev, production and pilot boundaries", async () => {
  const profile = {accessRole: "appUser", populationRole: "teaching", declaredRole: "teaching", role: "faculty"};
  for (const [populationRole, role] of [["student", "student"], ["teaching", "faculty"], ["nonTeaching", "staff"]]) {
    const user = {accessRole: "appUser", populationRole, declaredRole: populationRole, role};
    assert.equal(await offlineAuthorization(user, {...offlineGate, studentRolloutEnabled: false}), "permission-denied");
    assert.equal(await offlineAuthorization(user, offlineGate, false), "permission-denied");
    assert.equal(await offlineAuthorization(user, {...offlineGate, projectId: "mind-mates-cd2cf"}), "permission-denied");
    assert.equal(await offlineAuthorization(user, {...offlineGate, projectId: "mind-mates-cd2cf", pilotUserIds: new Set(["offline-user"])}), "permission-denied");
  }
  assert.equal(await offlineAuthorization(profile, {...offlineGate, pilotUserIds: new Set(["offline-user"]), studentRolloutEnabled: false}, false), "allowed");
  assert.equal(await offlineAuthorization({...profile, accountStatus: null}, {...offlineGate, pilotUserIds: new Set(["offline-user"])}, false), "allowed");
});

test("offline authorization: exported protected handler permits roles while Dev stays pilot-only", async () => {
  const keys = ["GCLOUD_PROJECT", "MOOD_V2_STAGING_STUDENT_ROLLOUT_ENABLED", "MOOD_V2_STAGING_PILOT_UIDS"];
  const previous = keys.map((key) => process.env[key]);
  try {
    process.env.GCLOUD_PROJECT = "mindmate-staging";
    process.env.MOOD_V2_STAGING_STUDENT_ROLLOUT_ENABLED = "true";
    process.env.MOOD_V2_STAGING_PILOT_UIDS = "";
    for (const [populationRole, role] of [["student", "student"], ["teaching", "faculty"], ["nonTeaching", "staff"]]) {
      const profile = {accessRole: "appUser", populationRole, declaredRole: populationRole, role};
      const request = callable("offline-user", payload());
      assert.equal(await offlineAuthorization(profile, offlineGate, true, () => createMoodEntry.run(request)), "allowed");
      assert.equal(await offlineAuthorization(profile, offlineGate, false, () => createMoodEntryDev.run(request)), "permission-denied");
    }
  } finally {
    keys.forEach((key, index) => {
      if (previous[index] === undefined) delete process.env[key];
      else process.env[key] = previous[index];
    });
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

  const created = await createMoodEntryForUser(uid, parseMoodEntryInput(payload(2)), instant, stagingGate(uid));
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
    Timestamp.fromDate(new Date("2026-01-01T15:59:00.000Z")), stagingGate(uid),
  );
  const retry = await createMoodEntryForUser(
    uid,
    parseMoodEntryInput(payload(3)),
    Timestamp.fromDate(new Date("2026-01-01T16:01:00.000Z")), stagingGate(uid),
  );
  assert.equal(retry.entryId, first.entryId);
  assert.equal(retry.occurredAt, first.occurredAt);
  assert.equal(retry.dateKey, first.dateKey);

  await assert.rejects(
    () => createMoodEntryForUser(uid, parseMoodEntryInput({...payload(3), level: 1}), Timestamp.now(), stagingGate(uid)),
    (error: unknown) => error instanceof HttpsError && error.code === "already-exists",
  );
});

test("concurrent identical requests create exactly one stable entry", async () => {
  const uid = userId();
  await seedEligibleProfile(uid);
  const input = parseMoodEntryInput(payload(4));
  const [left, right] = await Promise.all([
    createMoodEntryForUser(uid, input, Timestamp.now(), stagingGate(uid)),
    createMoodEntryForUser(uid, input, Timestamp.now(), stagingGate(uid)),
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
    () => createMoodEntryForUser(uid, parseMoodEntryInput({...payload(6), note: privateNote}), Timestamp.now(), stagingGate(uid)),
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

test("closed rollout gate rejects eligible users without creating V2 records", async () => {
  const uid = userId();
  await seedEligibleProfile(uid);
  await assert.rejects(
    () => createMoodEntryForUser(uid, parseMoodEntryInput(payload(7)), Timestamp.now(), {
      projectId: "mindmate-staging", pilotUserIds: new Set(),
    }),
    (error: unknown) => error instanceof HttpsError && error.code === "permission-denied",
  );
  assert.equal((await db.collection("moodEntries").where("userId", "==", uid).get()).empty, true);
});

// Only the protected server handler may opt into the general-student path.
const studentGate = {projectId: "mindmate-staging", pilotUserIds: new Set<string>(), studentRolloutEnabled: true};

test("student rollout permits two distinct same-day events and idempotent retries", async () => {
  const uid = userId();
  await seedEligibleProfile(uid);
  const instant = Timestamp.fromDate(new Date("2026-01-01T12:00:00Z"));
  const save = (seed: number, level = 4) => createMoodEntryForUser(
    uid, parseMoodEntryInput({...payload(seed), level}), instant, studentGate, true,
  );
  const first = await save(100);
  const second = await save(101);
  const retry = await save(100);
  assert.notEqual(first.entryId, second.entryId);
  assert.equal(first.dateKey, second.dateKey);
  assert.equal(first.entryId, retry.entryId);
  await assert.rejects(() => save(100, 1), {code: "already-exists"});
  assert.equal((await db.collection("moodEntries").where("userId", "==", uid).get()).size, 2);
});

test("student rollout accepts legitimately provisioned profiles with absent accountStatus", async () => {
  const uid = userId();
  await db.collection("users").doc(uid).set({accessRole: "appUser", populationRole: "student", declaredRole: "student", role: "student"});
  await createMoodEntryForUser(uid, parseMoodEntryInput(payload(102)), Timestamp.now(), studentGate, true);
});

test("eligible teaching and nonTeaching users persist independent idempotent same-day events", async () => {
  for (const [populationRole, role] of [["teaching", "faculty"], ["nonTeaching", "staff"]]) {
    const uid = userId();
    await db.collection("users").doc(uid).set({
      accessRole: "appUser", populationRole, declaredRole: populationRole, role, accountStatus: "active",
    });
    const instant = Timestamp.fromDate(new Date("2026-01-01T12:00:00Z"));
    const firstInput = parseMoodEntryInput(payload(201));
    const first = await createMoodEntryForUser(uid, firstInput, instant, studentGate, true);
    const second = await createMoodEntryForUser(uid, parseMoodEntryInput(payload(202)), instant, studentGate, true);
    const retry = await createMoodEntryForUser(uid, firstInput, instant, studentGate, true);
    assert.notEqual(first.entryId, second.entryId);
    assert.equal(first.dateKey, second.dateKey);
    assert.equal(first.entryId, retry.entryId);
    await assert.rejects(
      () => createMoodEntryForUser(uid, parseMoodEntryInput({...payload(201), level: 1}), instant, studentGate, true),
      {code: "already-exists"},
    );
    assert.equal((await db.collection("moodEntries").where("userId", "==", uid).get()).size, 2);
  }
});

for (const [label, gate, protectedPath] of [
  ["disabled", {...studentGate, studentRolloutEnabled: false}, true],
  ["omitted flag", {projectId: "mindmate-staging", pilotUserIds: new Set<string>()}, true],
  ["production", {...studentGate, projectId: "mind-mates-cd2cf"}, true],
  ["unknown project", {...studentGate, projectId: "demo-local"}, true],
  ["Dev execution path", studentGate, false],
] as const) {
  test(`student rollout rejects ${label} without persistence`, async () => {
    const uid = userId();
    await seedEligibleProfile(uid);
    await assert.rejects(() => createMoodEntryForUser(uid, parseMoodEntryInput(payload(103)), Timestamp.now(), gate, protectedPath), {code: "permission-denied"});
    assert.equal((await db.collection("moodEntries").where("userId", "==", uid).get()).empty, true);
  });
}

for (const [label, overrides] of Object.entries({
  inactive: {accountStatus: "suspended"}, pending: {accountStatus: "pending"},
  nullStatus: {accountStatus: null}, invalidStatus: {accountStatus: 1},
  teachingConflict: {populationRole: "teaching", declaredRole: "student"},
  nonTeachingConflict: {populationRole: "nonTeaching", role: "faculty"},
  invalidRole: {populationRole: "unknown"}, admin: {accessRole: "admin"}, staff: {accessRole: "portalStaff"},
  staffMarker: {staffAccountStatus: "approved"}, conflictingRole: {role: "admin"},
})) {
  test(`student rollout rejects ${label} profile`, async () => {
    const uid = userId();
    await db.collection("users").doc(uid).set({accessRole: "appUser", populationRole: "student", accountStatus: "active", ...overrides});
    await assert.rejects(() => createMoodEntryForUser(uid, parseMoodEntryInput(payload(104)), Timestamp.now(), studentGate, true));
    assert.equal((await db.collection("moodEntries").where("userId", "==", uid).get()).empty, true);
  });
}

test("student rollout rejects a missing profile", async () => {
  await assert.rejects(() => createMoodEntryForUser(userId(), parseMoodEntryInput(payload(105)), Timestamp.now(), studentGate, true), {code: "failed-precondition"});
});

test("pilot compatibility is retained on both server execution paths", async () => {
  for (const protectedPath of [false, true]) {
    const uid = userId();
    await db.collection("users").doc(uid).set({accessRole: "appUser", populationRole: "teaching"});
    await createMoodEntryForUser(uid, parseMoodEntryInput(payload(106)), Timestamp.now(), stagingGate(uid), protectedPath);
    await assert.rejects(() => createMoodEntryForUser(uid, parseMoodEntryInput(payload(107)), Timestamp.now(), {...stagingGate(uid), projectId: "mind-mates-cd2cf"}, protectedPath), {code: "permission-denied"});
  }
});

test("clients cannot submit authorization or execution-path overrides", () => {
  for (const key of ["studentRolloutEnabled", "allowStudentRollout", "accountStatus", "populationRole", "MOOD_V2_STAGING_STUDENT_ROLLOUT_ENABLED"]) {
    assert.throws(() => parseMoodEntryInput({...payload(108), [key]: true}), {code: "invalid-argument"});
  }
});

test("deployed exports select protected versus pilot-only handlers with server configuration", async () => {
  const keys = ["GCLOUD_PROJECT", "MOOD_V2_STAGING_STUDENT_ROLLOUT_ENABLED", "MOOD_V2_STAGING_PILOT_UIDS"];
  const previous = keys.map((key) => process.env[key]);
  try {
    process.env.GCLOUD_PROJECT = "mindmate-staging";
    process.env.MOOD_V2_STAGING_PILOT_UIDS = "";
    delete process.env.MOOD_V2_STAGING_STUDENT_ROLLOUT_ENABLED;
    assert.equal(moodV2RolloutGate().studentRolloutEnabled, false);
    const uid = userId();
    await seedEligibleProfile(uid);
    await assert.rejects(() => createMoodEntry.run(callable(uid, payload(110))), {code: "permission-denied"});
    process.env.MOOD_V2_STAGING_STUDENT_ROLLOUT_ENABLED = "true";
    assert.equal(moodV2RolloutGate().studentRolloutEnabled, true);
    const result = await createMoodEntry.run(callable(uid, payload(111)));
    assert.equal(result.userId, uid);
    await assert.rejects(() => createMoodEntryDev.run(callable(uid, payload(112))), {code: "permission-denied"});
    await assert.rejects(() => createMoodEntryDev.run(callable(undefined, payload(112))), {code: "unauthenticated"});
  } finally {
    keys.forEach((key, index) => {
      if (previous[index] === undefined) delete process.env[key];
      else process.env[key] = previous[index];
    });
  }
});


test("protected HTTP wrapper rejects missing App Check before the callable handler", async () => {
  // Minimal Express transport adapter; the Firebase callable middleware itself
  // is real. This checks missing-token enforcement, not valid-token acceptance.
  const server = createServer(async (request, response) => {
    const chunks: Buffer[] = [];
    for await (const chunk of request) chunks.push(Buffer.from(chunk));
    Object.assign(request, {
      body: JSON.parse(Buffer.concat(chunks).toString()),
      header: (name: string) => request.headers[name.toLowerCase()]?.toString(),
    });
    Object.assign(response, {
      status: (code: number) => { response.statusCode = code; return response; },
      send: (body: unknown) => response.end(JSON.stringify(body)),
    });
    await createMoodEntry(request as never, response as never);
  });
  try {
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const address = server.address() as AddressInfo;
    const result = await fetch(`http://127.0.0.1:${address.port}`, {
      method: "POST", headers: {"Content-Type": "application/json"},
      body: JSON.stringify({data: payload(113)}),
    });
    assert.equal(result.status, 401);
    const body = await result.json() as {error: {message: string}};
    // The business handler would instead return "Sign in is required."
    assert.equal(body.error.message, "Unauthenticated");
  } finally {
    await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
});

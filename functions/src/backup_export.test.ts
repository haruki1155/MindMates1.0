import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {GeoPoint, getFirestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {recordAuditEvent} from "./index";
import {
  BACKUP_EXPORT_SCOPE,
  BackupExportDeps,
  collectionKeyForPath,
  exportBackupPage,
  exportFirestoreBackupPage,
  isAllowedBackupCollectionPath,
  redactSensitiveBackupFields,
  serializeFirestoreValue,
} from "./backup_export";

const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const prefix = `backup-export-${Date.now()}`;
const adminUid = `${prefix}-admin`;
const counselorUid = `${prefix}-counselor`;
const portalStaffUid = `${prefix}-staff`;
const actor = {uid: adminUid, name: "Export Admin", role: "admin"};

// --- Pure unit tests (no emulator required) ---

type MockDocSpec = {
  exists: boolean;
  data?: Record<string, unknown>;
  createTime?: Date;
  updateTime?: Date;
  subcollections?: string[];
};

function makeMockDb(
  rootCollections: string[],
  collectionsData: Record<string, string[]>,
  docsData: Record<string, MockDocSpec>,
  options: {failCollection?: string; failAudit?: boolean} = {},
) {
  const audits: Array<Record<string, unknown>> = [];

  const makeDocRef = (path: string): FirebaseFirestore.DocumentReference => {
    const segments = path.split("/");
    const id = segments[segments.length - 1];
    return {
      id,
      path,
      listCollections: async () => {
        const subNames = docsData[path]?.subcollections ?? [];
        return subNames.map((sub) => makeColRef(`${path}/${sub}`));
      },
    } as unknown as FirebaseFirestore.DocumentReference;
  };

  const makeColRef = (colPath: string): FirebaseFirestore.CollectionReference => {
    return {
      id: colPath.split("/").pop()!,
      path: colPath,
      doc: (id = `auto-${audits.length + 1}`) => makeDocRef(`${colPath}/${id}`),
      listDocuments: async () => {
        if (options.failCollection === colPath) {
          throw new Error(`Simulated read failure on ${colPath}`);
        }
        const ids = collectionsData[colPath] ?? [];
        return ids.map((id) => makeDocRef(`${colPath}/${id}`));
      },
    } as unknown as FirebaseFirestore.CollectionReference;
  };

  const db = {
    listCollections: async () => rootCollections.map((c) => makeColRef(c)),
    collection: (colPath: string) => makeColRef(colPath),
    getAll: async (...refs: FirebaseFirestore.DocumentReference[]) => {
      return refs.map((ref) => {
        const spec = docsData[ref.path];
        if (!spec || !spec.exists) {
          return {
            id: ref.id,
            ref,
            exists: false,
            data: (): Record<string, unknown> | undefined => undefined,
          };
        }
        return {
          id: ref.id,
          ref,
          exists: true,
          createTime: spec.createTime ? Timestamp.fromDate(spec.createTime) : undefined,
          updateTime: spec.updateTime ? Timestamp.fromDate(spec.updateTime) : undefined,
          data: (): Record<string, unknown> => spec.data ?? {},
        };
      });
    },
    runTransaction: async (fn: (tx: FirebaseFirestore.Transaction) => Promise<unknown>) => {
      if (options.failAudit) {
        throw new Error("Simulated audit failure");
      }
      const tx = {
        create: (_ref: unknown, payload: Record<string, unknown>) => {
          audits.push(payload);
        },
      } as unknown as FirebaseFirestore.Transaction;
      return fn(tx);
    },
  } as unknown as FirebaseFirestore.Firestore;

  return {db, audits};
}

test("collectionKeyForPath maps root and nested subcollections deterministically", () => {
  assert.equal(collectionKeyForPath("colleges"), "colleges");
  assert.equal(collectionKeyForPath("counseling_population/2026-2027/void_history"), "counseling_population__void_history");
  assert.equal(collectionKeyForPath("analytics_daily/2026-11-20/users"), "analytics_daily__users");
});

test("fail-closed allowlist allows approved admin collections and rejects unknown, clinical, chat, and internal paths", () => {
  assert.equal(BACKUP_EXPORT_SCOPE.mode, "explicit-allowlist-fail-closed");

  // Explicitly authorized root collections & subcollections
  for (const allowed of [
    "colleges",
    "departments",
    "courses",
    "announcements",
    "admin_audit_logs",
    "student_roster",
    "users",
    "counseling_population",
    "counseling_population/2026-2027/void_history",
    "counseling_population/2026-2027/reinstate_history",
    "analytics_daily",
    "analytics_daily/2026-11-20/users",
  ]) {
    assert.equal(isAllowedBackupCollectionPath(allowed), true, `Expected allowed: ${allowed}`);
  }

  // Unknown, internal, clinical, assessment, conversation, and anonymity collections MUST be rejected (fail-closed)
  for (const deniedPath of [
    "unknown_future_collection",
    "secret_tokens",
    "_analytics_events",
    "_mind_aid_rate_limits",
    "pending_registration_cancellations",
    "student_activation_attempts",
    "user_devices",
    "user_devices/u1/tokens",
    "appointment_user_locks",
    "appointment_booking_requests",
    "appointment_slots",
    "assessment_limits",
    "appointments",
    "appointments/a1/clinical_notes",
    "appointments/a1/case_remarks",
    "appointments/a1/case_remarks/current/versions",
    "assessments",
    "inquiries",
    "inquiries/i1/replies",
    "counselor_threads",
    "counselor_threads/u1/messages",
    "counselor_inbox_reads",
    "counselor_inbox_reads/c1/threads",
    "mind_aid_messages",
    "mind_aid_dialogue_state",
    "mind_aid_dialogue_state/u1/conversations",
    "mind_aid_emergency_alerts",
    "secret_chat_profiles",
    "secret_chat_aliases",
    "secret_chats",
    "student_personal_info",
    "counseling_population/2026-2027/unknown_sub",
    "users/u1/private_tokens",
    "colleges/cas/nested/too/deep",
  ]) {
    assert.equal(isAllowedBackupCollectionPath(deniedPath), false, `Expected denied: ${deniedPath}`);
  }
});

test("redactSensitiveBackupFields recursively redacts credentials at any depth", () => {
  const redacted = redactSensitiveBackupFields("student_roster", {
    studentNo: "2026-0001",
    activated: false,
    activationCode: {
      hash: "secret-hash",
      salt: "secret-salt",
      issuedAt: "2026-11-20T00:00:00.000Z",
    },
    consumedActivationCode: {
      hash: "old-hash",
      salt: "old-salt",
      userId: "u1",
    },
    nested: {
      device: {fcmToken: "nested-token", os: "android"},
      history: [{accessToken: "tok-1", note: "kept"}],
    },
    privateKey: "pem-key",
  });

  assert.equal(redacted.studentNo, "2026-0001");
  assert.equal(redacted.privateKey, "[REDACTED]");
  assert.deepEqual(redacted.activationCode, {
    hash: "[REDACTED]",
    salt: "[REDACTED]",
    issuedAt: "2026-11-20T00:00:00.000Z",
  });
  assert.deepEqual(redacted.consumedActivationCode, {
    hash: "[REDACTED]",
    salt: "[REDACTED]",
    userId: "u1",
  });
  assert.deepEqual(redacted.nested, {
    device: {fcmToken: "[REDACTED]", os: "android"},
    history: [{accessToken: "[REDACTED]", note: "kept"}],
  });
});

test("serializeFirestoreValue preserves timestamps, references, geopoints, bytes, and nested maps", () => {
  const fakeRef = {path: "users/u-1", id: "u-1", firestore: {}};
  const serialized = serializeFirestoreValue({
    ts: Timestamp.fromDate(new Date("2026-11-20T01:02:03.456Z")),
    ref: fakeRef,
    geo: new GeoPoint(15.975, 120.571),
    bin: Buffer.from("hello"),
    nested: {when: new Date("2026-11-20T00:00:00.000Z"), refs: [fakeRef]},
  }) as Record<string, unknown>;

  assert.equal(serialized.ts, "2026-11-20T01:02:03.456Z");
  assert.equal(serialized.ref, "ref:users/u-1");
  assert.deepEqual(serialized.geo, {_type: "geopoint", latitude: 15.975, longitude: 120.571});
  assert.deepEqual(serialized.bin, {_type: "bytes", base64: Buffer.from("hello").toString("base64")});
  assert.deepEqual(serialized.nested, {
    refs: ["ref:users/u-1"],
    when: "2026-11-20T00:00:00.000Z",
  });
});

test("exportBackupPage exports only allowlisted collections/subcollections and excludes unknown, clinical, and conversation data", async () => {
  const {db, audits} = makeMockDb(
    [
      "users",
      "counseling_population",
      "analytics_daily",
      "appointments",
      "assessments",
      "counselor_threads",
      "mind_aid_messages",
      "secret_chat_profiles",
      "unknown_collection",
    ],
    {
      users: ["u2", "u1", "u3"],
      counseling_population: ["2026-2027"],
      "counseling_population/2026-2027/void_history": ["v1"],
      "counseling_population/2026-2027/unexpected_sub": ["x1"],
      analytics_daily: ["2026-11-20"],
      "analytics_daily/2026-11-20/users": ["u1"],
      appointments: ["a1"],
      "appointments/a1/clinical_notes": ["cn1"],
      "appointments/a1/case_remarks": ["cr1"],
      assessments: ["as1"],
      counselor_threads: ["u1"],
      "counselor_threads/u1/messages": ["m1"],
      mind_aid_messages: ["ma1"],
      secret_chat_profiles: ["u1"],
      unknown_collection: ["unk1"],
    },
    {
      "users/u1": {exists: true, data: {name: "Alice"}, createTime: new Date("2026-11-01T00:00:00Z")},
      "users/u2": {exists: true, data: {name: "Bob"}},
      "users/u3": {exists: true, data: {name: "Carol"}},
      "counseling_population/2026-2027": {exists: true, data: {status: "open"}, subcollections: ["void_history", "unexpected_sub"]},
      "counseling_population/2026-2027/void_history/v1": {exists: true, data: {reason: "Correction"}},
      "counseling_population/2026-2027/unexpected_sub/x1": {exists: true, data: {secret: "nope"}},
      "analytics_daily/2026-11-20": {exists: false, subcollections: ["users"]},
      "analytics_daily/2026-11-20/users/u1": {exists: true, data: {logins: 2}},
      "appointments/a1": {exists: true, data: {concern: "Sensitive"}, subcollections: ["clinical_notes", "case_remarks"]},
      "appointments/a1/clinical_notes/cn1": {exists: true, data: {note: "CLINICAL"}},
      "appointments/a1/case_remarks/cr1": {exists: true, data: {text: "REMARK"}},
      "assessments/as1": {exists: true, data: {score: 99}},
      "counselor_threads/u1": {exists: false, subcollections: ["messages"]},
      "counselor_threads/u1/messages/m1": {exists: true, data: {text: "PRIVATE"}},
      "mind_aid_messages/ma1": {exists: true, data: {text: "AI PRIVATE"}},
      "secret_chat_profiles/u1": {exists: true, data: {alias: "BlueJay"}},
      "unknown_collection/unk1": {exists: true, data: {foo: "bar"}},
    },
  );

  const deps: BackupExportDeps = {
    db,
    now: () => new Date("2026-11-20T02:00:00Z"),
    newExportId: () => "exp-1",
  };

  const allDocs: Array<{collectionKey: string; documentId: string; parentDocumentId: string | null}> = [];
  const visited = new Set<string>();
  let cursor: unknown = null;
  let pages = 0;

  while (true) {
    pages++;
    const page = await exportBackupPage(deps, actor, {
      exportId: "exp-1",
      cursor,
      pageSize: 2,
      format: "csv",
    });
    assert.equal(page.exportId, "exp-1");
    for (const v of page.visitedCollections) visited.add(v.collectionKey);
    for (const d of page.documents) {
      allDocs.push({
        collectionKey: d.collectionKey,
        documentId: d.documentId,
        parentDocumentId: d.parentDocumentId,
      });
    }
    if (!page.hasMore) {
      assert.equal(page.nextCursor, null);
      break;
    }
    assert.ok(page.nextCursor != null);
    cursor = page.nextCursor;
  }

  assert.ok(pages > 1);
  assert.ok(visited.has("users"));
  assert.ok(visited.has("counseling_population"));
  assert.ok(visited.has("counseling_population__void_history"));
  assert.ok(visited.has("analytics_daily__users"));

  // Disallowed / unknown / clinical / conversation / anonymity collections never appear.
  for (const forbidden of [
    "appointments",
    "appointments__clinical_notes",
    "appointments__case_remarks",
    "assessments",
    "counselor_threads",
    "counselor_threads__messages",
    "mind_aid_messages",
    "secret_chat_profiles",
    "unknown_collection",
    "counseling_population__unexpected_sub",
  ]) {
    assert.equal(visited.has(forbidden), false, `Forbidden collection visited: ${forbidden}`);
  }

  assert.deepEqual(
    allDocs.map((d) => `${d.collectionKey}:${d.parentDocumentId ?? ""}:${d.documentId}`).sort(),
    [
      "analytics_daily__users:2026-11-20:u1",
      "counseling_population::2026-2027",
      "counseling_population__void_history:2026-2027:v1",
      "users::u1",
      "users::u2",
      "users::u3",
    ],
  );
  assert.deepEqual(
    audits.map((a) => a.action),
    ["BACKUP_EXPORT_STARTED", "BACKUP_EXPORT_COMPLETED"],
  );
});

test("exportBackupPage respects maxResponseBytes without skipping or duplicating documents", async () => {
  const {db} = makeMockDb(
    ["announcements"],
    {announcements: ["n1", "n2", "n3"]},
    {
      "announcements/n1": {exists: true, data: {body: "x".repeat(400)}},
      "announcements/n2": {exists: true, data: {body: "y".repeat(400)}},
      "announcements/n3": {exists: true, data: {body: "z".repeat(400)}},
    },
  );

  const deps: BackupExportDeps = {
    db,
    now: () => new Date("2026-11-20T02:00:00Z"),
    newExportId: () => "exp-bytes",
    maxResponseBytes: 500,
  };

  const ids: string[] = [];
  let cursor: unknown = null;
  let pages = 0;
  while (true) {
    pages++;
    const page = await exportBackupPage(deps, actor, {exportId: "exp-bytes", cursor, pageSize: 50});
    ids.push(...page.documents.map((d) => d.documentId));
    if (!page.hasMore) break;
    cursor = page.nextCursor;
  }
  assert.equal(pages >= 3, true);
  assert.deepEqual(ids, ["n1", "n2", "n3"]);
});

test("exportBackupPage rejects invalid arguments, tampered cursors, and propagates read failures", async () => {
  const {db} = makeMockDb(
    ["colleges"],
    {colleges: []},
    {},
    {failCollection: "colleges"},
  );
  const deps: BackupExportDeps = {
    db,
    now: () => new Date("2026-11-20T02:00:00Z"),
    newExportId: () => "exp-err",
  };

  await assert.rejects(
    exportBackupPage(deps, actor, {format: "pdf"}),
    (e: unknown) => e instanceof HttpsError && e.code === "invalid-argument",
  );
  await assert.rejects(
    exportBackupPage(deps, actor, {pageSize: 0}),
    (e: unknown) => e instanceof HttpsError && e.code === "invalid-argument",
  );
  // Attempting to resume a cursor pointing at a disallowed or unknown collection fails closed.
  await assert.rejects(
    exportBackupPage(deps, actor, {
      cursor: {currentCollection: "appointments/a1/clinical_notes", afterDocId: null, queue: []},
      exportId: "e1",
    }),
    (e: unknown) => e instanceof HttpsError && e.code === "invalid-argument",
  );
  await assert.rejects(
    exportBackupPage(deps, actor, {
      cursor: {currentCollection: "colleges", afterDocId: null, queue: ["unknown_collection"]},
      exportId: "e1",
    }),
    (e: unknown) => e instanceof HttpsError && e.code === "invalid-argument",
  );
  await assert.rejects(
    exportBackupPage(deps, actor, {format: "xlsx"}),
    /Simulated read failure/,
  );
});

// --- Firestore + Auth emulator tests ---

const emuDb = getFirestore();

async function denied(promise: Promise<unknown>, code: string): Promise<void> {
  await assert.rejects(promise, (error: unknown) => error instanceof HttpsError && error.code === code);
}

before(async () => {
  if (!emulated) return;
  await getAuth().createUser({uid: adminUid, email: `${adminUid}@example.invalid`, emailVerified: true});
  await getAuth().createUser({uid: counselorUid, email: `${counselorUid}@example.invalid`, emailVerified: true});
  await getAuth().createUser({uid: portalStaffUid, email: `${portalStaffUid}@example.invalid`, emailVerified: true});
  await emuDb.doc(`users/${adminUid}`).set({accessRole: "admin", accountStatus: "active", name: "Export Admin"});
  await emuDb.doc(`users/${counselorUid}`).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active"});
  await emuDb.doc(`users/${portalStaffUid}`).set({accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active"});
});

after(async () => {
  if (!emulated) return;
  await Promise.all([
    emuDb.doc(`users/${adminUid}`).delete().catch(() => undefined),
    emuDb.doc(`users/${counselorUid}`).delete().catch(() => undefined),
    emuDb.doc(`users/${portalStaffUid}`).delete().catch(() => undefined),
    getAuth().deleteUser(adminUid).catch(() => undefined),
    getAuth().deleteUser(counselorUid).catch(() => undefined),
    getAuth().deleteUser(portalStaffUid).catch(() => undefined),
  ]);
});

test("exportFirestoreBackupPage enforces fail-closed allowlist, super-admin authorization, and redaction on emulators", {skip: !emulated}, async () => {
  const callable = exportFirestoreBackupPage as unknown as {
    run: (req: {auth?: {uid: string} | null; data?: unknown}) => Promise<{
      exportId: string;
      scope: typeof BACKUP_EXPORT_SCOPE;
      documents: Array<{
        documentId: string;
        documentPath: string;
        collectionKey: string;
        parentCollection: string | null;
        parentDocumentId: string | null;
        fields: Record<string, unknown>;
      }>;
      visitedCollections: Array<{collectionKey: string; collectionPath: string}>;
      hasMore: boolean;
      nextCursor: unknown;
    }>;
  };
  const otherAdminUid = `${prefix}-other-admin`;
  const previous = process.env.SUPER_ADMIN_UID;
  process.env.SUPER_ADMIN_UID = adminUid;
  await getAuth().createUser({uid: otherAdminUid, email: `${otherAdminUid}@example.invalid`, emailVerified: true});
  await emuDb.doc(`users/${otherAdminUid}`).set({accessRole: "admin", accountStatus: "active", name: "Other Admin"});

  try {
    await denied(callable.run({auth: null, data: {}}), "unauthenticated");
    await denied(callable.run({auth: {uid: counselorUid}, data: {}}), "permission-denied");
    await denied(callable.run({auth: {uid: portalStaffUid}, data: {}}), "permission-denied");
    await denied(callable.run({auth: {uid: otherAdminUid}, data: {}}), "permission-denied");

    await getAuth().updateUser(adminUid, {emailVerified: false});
    await denied(callable.run({auth: {uid: adminUid}, data: {}}), "permission-denied");
    await getAuth().updateUser(adminUid, {emailVerified: true});

    await emuDb.doc(`users/${adminUid}`).update({accountStatus: "suspended"});
    await denied(callable.run({auth: {uid: adminUid}, data: {}}), "permission-denied");
    await emuDb.doc(`users/${adminUid}`).update({accountStatus: "active"});

    // Seed authorized administrative fixtures + disallowed sensitive/unknown records.
    await Promise.all([
      emuDb.doc(`colleges/${prefix}-cas`).set({
        name: "CAS",
        active: true,
        updatedAt: Timestamp.fromDate(new Date("2026-11-20T01:00:00Z")),
      }),
      emuDb.doc(`counseling_population/${prefix}-2026`).set({status: "open", target: 500}),
      emuDb.doc(`counseling_population/${prefix}-2026/void_history/v1`).set({reason: "Typo"}),
      emuDb.doc(`counseling_population/${prefix}-2026/unknown_sub/s1`).set({hidden: true}),
      emuDb.doc(`student_roster/${prefix}-sr-1`).set({
        studentNo: "2026-9999",
        activationCode: {hash: "hash-val", salt: "salt-val"},
        nestedMeta: {pushToken: "secret-push"},
      }),
      // Disallowed collections that must never be exported:
      emuDb.doc(`appointments/${prefix}-appt-1`).set({concern: "Private concern"}),
      emuDb.doc(`appointments/${prefix}-appt-1/clinical_notes/session`).set({note: "CLINICAL NOTE"}),
      emuDb.doc(`appointments/${prefix}-appt-1/case_remarks/current`).set({text: "COUNSELOR ONLY REMARK"}),
      emuDb.doc(`assessments/${prefix}-assess-1`).set({answers: [1, 2, 3]}),
      emuDb.doc(`counselor_threads/${adminUid}/messages/m1`).set({body: "PRIVATE CHAT"}),
      emuDb.doc(`mind_aid_messages/${prefix}-ma-1`).set({body: "AI CHAT"}),
      emuDb.doc(`secret_chat_profiles/${adminUid}`).set({alias: "HiddenOwl"}),
      emuDb.doc(`user_devices/${adminUid}/tokens/t1`).set({fcmToken: "secret-fcm-token"}),
      emuDb.doc(`_analytics_events/${prefix}-ev-1`).set({internal: true}),
      emuDb.doc(`unknown_future_collection/${prefix}-u-1`).set({secret: "should-not-export"}),
    ]);

    const allDocs: Array<{documentPath: string; collectionKey: string; parentDocumentId: string | null; fields: Record<string, unknown>}> = [];
    const visitedKeys = new Set<string>();
    let cursor: unknown = null;
    let exportId: string | undefined;
    let pages = 0;

    while (true) {
      pages++;
      const res = await callable.run({
        auth: {uid: adminUid},
        data: {format: "xlsx", pageSize: 2, exportId, cursor},
      });
      exportId ??= res.exportId;
      assert.equal(res.scope.mode, "explicit-allowlist-fail-closed");
      for (const v of res.visitedCollections) visitedKeys.add(v.collectionKey);
      allDocs.push(...res.documents);
      if (!res.hasMore) break;
      cursor = res.nextCursor;
    }

    assert.ok(pages >= 3);
    assert.ok(visitedKeys.has("colleges"));
    assert.ok(visitedKeys.has("counseling_population"));
    assert.ok(visitedKeys.has("counseling_population__void_history"));
    assert.ok(visitedKeys.has("student_roster"));

    // All sensitive, clinical, conversation, anonymity, and unknown collections are excluded.
    for (const forbidden of [
      "appointments",
      "appointments__clinical_notes",
      "appointments__case_remarks",
      "assessments",
      "counselor_threads",
      "counselor_threads__messages",
      "mind_aid_messages",
      "secret_chat_profiles",
      "user_devices",
      "user_devices__tokens",
      "_analytics_events",
      "unknown_future_collection",
      "counseling_population__unknown_sub",
    ]) {
      assert.equal(visitedKeys.has(forbidden), false, `Forbidden collection exported: ${forbidden}`);
    }

    const collegeDoc = allDocs.find((d) => d.documentPath === `colleges/${prefix}-cas`)!;
    assert.equal(collegeDoc.fields.updatedAt, "2026-11-20T01:00:00.000Z");

    const voidDoc = allDocs.find(
      (d) => d.documentPath === `counseling_population/${prefix}-2026/void_history/v1`,
    )!;
    assert.equal(voidDoc.parentDocumentId, `${prefix}-2026`);

    const rosterDoc = allDocs.find((d) => d.documentPath === `student_roster/${prefix}-sr-1`)!;
    assert.deepEqual(rosterDoc.fields.activationCode, {hash: "[REDACTED]", salt: "[REDACTED]"});
    assert.deepEqual(rosterDoc.fields.nestedMeta, {pushToken: "[REDACTED]"});

    const audits = await emuDb.collection("admin_audit_logs").where("targetId", "==", exportId).get();
    assert.deepEqual(
      audits.docs.map((d) => d.data().action).sort(),
      ["BACKUP_EXPORT_COMPLETED", "BACKUP_EXPORT_STARTED"],
    );

    const auditCallable = recordAuditEvent as unknown as {
      run: (req: {auth?: {uid: string}; data?: unknown}) => Promise<unknown>;
    };
    for (const action of ["BACKUP_EXPORT_STARTED", "BACKUP_EXPORT_COMPLETED"]) {
      await denied(
        auditCallable.run({
          auth: {uid: counselorUid},
          data: {action, category: "SYSTEM", targetType: "backup_export", targetId: "forged"},
        }),
        "invalid-argument",
      );
    }
  } finally {
    await Promise.all([
      emuDb.doc(`colleges/${prefix}-cas`).delete().catch(() => undefined),
      emuDb.doc(`counseling_population/${prefix}-2026/void_history/v1`).delete().catch(() => undefined),
      emuDb.doc(`counseling_population/${prefix}-2026/unknown_sub/s1`).delete().catch(() => undefined),
      emuDb.doc(`counseling_population/${prefix}-2026`).delete().catch(() => undefined),
      emuDb.doc(`student_roster/${prefix}-sr-1`).delete().catch(() => undefined),
      emuDb.doc(`appointments/${prefix}-appt-1/clinical_notes/session`).delete().catch(() => undefined),
      emuDb.doc(`appointments/${prefix}-appt-1/case_remarks/current`).delete().catch(() => undefined),
      emuDb.doc(`appointments/${prefix}-appt-1`).delete().catch(() => undefined),
      emuDb.doc(`assessments/${prefix}-assess-1`).delete().catch(() => undefined),
      emuDb.doc(`counselor_threads/${adminUid}/messages/m1`).delete().catch(() => undefined),
      emuDb.doc(`mind_aid_messages/${prefix}-ma-1`).delete().catch(() => undefined),
      emuDb.doc(`secret_chat_profiles/${adminUid}`).delete().catch(() => undefined),
      emuDb.doc(`user_devices/${adminUid}/tokens/t1`).delete().catch(() => undefined),
      emuDb.doc(`_analytics_events/${prefix}-ev-1`).delete().catch(() => undefined),
      emuDb.doc(`unknown_future_collection/${prefix}-u-1`).delete().catch(() => undefined),
      emuDb.doc(`users/${otherAdminUid}`).delete().catch(() => undefined),
      getAuth().deleteUser(otherAdminUid).catch(() => undefined),
      getAuth().updateUser(adminUid, {emailVerified: true}).catch(() => undefined),
    ]);
    if (previous == null) delete process.env.SUPER_ADMIN_UID;
    else process.env.SUPER_ADMIN_UID = previous;
  }
});

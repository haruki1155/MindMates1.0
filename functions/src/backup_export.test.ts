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
  isExcludedBackupCollectionPath,
  redactSensitiveBackupFields,
  serializeFirestoreValue,
} from "./backup_export";

const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const prefix = `backup-export-${Date.now()}`;
const adminUid = `${prefix}-admin`;
const counselorUid = `${prefix}-counselor`;
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
  assert.equal(collectionKeyForPath("users"), "users");
  assert.equal(collectionKeyForPath("appointments/appt-1/history"), "appointments__history");
  assert.equal(collectionKeyForPath("appointments/appt-1/clinical_notes"), "appointments__clinical_notes");
  assert.equal(collectionKeyForPath("a/1/b/2/c"), "a__b__c");
});

test("isExcludedBackupCollectionPath and redactSensitiveBackupFields block sensitive internal, credential, and case_remarks data", () => {
  assert.equal(BACKUP_EXPORT_SCOPE.mode, "all-firestore-excluding-internal-and-credentials");
  assert.equal(BACKUP_EXPORT_SCOPE.excludedPrefix, "_");
  assert.deepEqual(BACKUP_EXPORT_SCOPE.excludedSubcollections, ["case_remarks"]);
  assert.ok(BACKUP_EXPORT_SCOPE.excludedRootCollections.includes("user_devices"));
  assert.ok(BACKUP_EXPORT_SCOPE.excludedRootCollections.includes("pending_registration_cancellations"));

  assert.equal(isExcludedBackupCollectionPath("users"), false);
  assert.equal(isExcludedBackupCollectionPath("appointments/a1/history"), false);
  assert.equal(isExcludedBackupCollectionPath("appointments/a1/clinical_notes"), false);
  assert.equal(isExcludedBackupCollectionPath("student_roster"), false);

  assert.equal(isExcludedBackupCollectionPath("_analytics_events"), true);
  assert.equal(isExcludedBackupCollectionPath("_mind_aid_rate_limits"), true);
  assert.equal(isExcludedBackupCollectionPath("pending_registration_cancellations"), true);
  assert.equal(isExcludedBackupCollectionPath("student_activation_attempts"), true);
  assert.equal(isExcludedBackupCollectionPath("user_devices"), true);
  assert.equal(isExcludedBackupCollectionPath("user_devices/u1/tokens"), true);
  assert.equal(isExcludedBackupCollectionPath("appointments/a1/case_remarks"), true);
  assert.equal(isExcludedBackupCollectionPath("appointments/a1/case_remarks/current/versions"), true);

  const redacted = redactSensitiveBackupFields("student_roster", {
    studentNo: "2026-0001",
    activated: false,
    activationCode: {hash: "secret-hash", salt: "secret-salt", issuedAt: "2026-11-20T00:00:00.000Z"},
    consumedActivationCode: {hash: "old-hash", salt: "old-salt", userId: "u1"},
    fcmToken: "live-token-123",
  });
  assert.equal(redacted.studentNo, "2026-0001");
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
  assert.equal(redacted.fcmToken, "[REDACTED]");
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

test("exportBackupPage paginates all collections, subcollections, phantom parents, and empty collections", async () => {
  const {db, audits} = makeMockDb(
    ["users", "empty_col", "counselor_threads", "appointments", "user_devices"],
    {
      empty_col: [],
      users: ["u2", "u1", "u3"],
      counselor_threads: ["u1"],
      "counselor_threads/u1/messages": ["msg-1"],
      appointments: ["a1"],
      "appointments/a1/history": ["h1", "h2"],
      user_devices: ["u1"],
      "user_devices/u1/tokens": ["tok-1"],
    },
    {
      "users/u1": {exists: true, data: {name: "Alice"}, createTime: new Date("2026-11-01T00:00:00Z")},
      "users/u2": {exists: true, data: {name: "Bob"}},
      "users/u3": {exists: true, data: {name: "Carol"}},
      "counselor_threads/u1": {exists: false, subcollections: ["messages"]},
      "counselor_threads/u1/messages/msg-1": {exists: true, data: {text: "hello"}},
      "appointments/a1": {exists: true, data: {status: "confirmed"}, subcollections: ["history"]},
      "appointments/a1/history/h1": {exists: true, data: {event: "created"}},
      "appointments/a1/history/h2": {exists: true, data: {event: "confirmed"}},
      "user_devices/u1": {exists: false, subcollections: ["tokens"]},
      "user_devices/u1/tokens/tok-1": {exists: true, data: {fcmToken: "fcm-1"}},
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
  assert.deepEqual([...visited].sort(), [
    "appointments",
    "appointments__history",
    "counselor_threads",
    "counselor_threads__messages",
    "empty_col",
    "users",
  ]);
  assert.deepEqual(
    allDocs.map((d) => `${d.collectionKey}:${d.parentDocumentId ?? ""}:${d.documentId}`).sort(),
    [
      "appointments::a1",
      "appointments__history:a1:h1",
      "appointments__history:a1:h2",
      "counselor_threads__messages:u1:msg-1",
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
    ["notes"],
    {notes: ["n1", "n2", "n3"]},
    {
      "notes/n1": {exists: true, data: {body: "x".repeat(400)}},
      "notes/n2": {exists: true, data: {body: "y".repeat(400)}},
      "notes/n3": {exists: true, data: {body: "z".repeat(400)}},
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
  assert.equal(pages, 3);
  assert.deepEqual(ids, ["n1", "n2", "n3"]);
});

test("exportBackupPage rejects invalid arguments and propagates collection read failures", async () => {
  const {db} = makeMockDb(
    ["broken"],
    {broken: []},
    {},
    {failCollection: "broken"},
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
  await assert.rejects(
    exportBackupPage(deps, actor, {cursor: {currentCollection: "users/u1", afterDocId: null, queue: []}, exportId: "e1"}),
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
  await emuDb.doc(`users/${adminUid}`).set({accessRole: "admin", accountStatus: "active", name: "Export Admin"});
  await emuDb.doc(`users/${counselorUid}`).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active"});
});

after(async () => {
  if (!emulated) return;
  await Promise.all([
    emuDb.doc(`users/${adminUid}`).delete().catch(() => undefined),
    emuDb.doc(`users/${counselorUid}`).delete().catch(() => undefined),
    getAuth().deleteUser(adminUid).catch(() => undefined),
    getAuth().deleteUser(counselorUid).catch(() => undefined),
  ]);
});

test("exportFirestoreBackupPage enforces super-admin authorization and prevents audit forging", {skip: !emulated}, async () => {
  const callable = exportFirestoreBackupPage as unknown as {
    run: (req: {auth?: {uid: string} | null; data?: unknown}) => Promise<{
      exportId: string;
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
    await denied(callable.run({auth: {uid: otherAdminUid}, data: {}}), "permission-denied");

    await getAuth().updateUser(adminUid, {emailVerified: false});
    await denied(callable.run({auth: {uid: adminUid}, data: {}}), "permission-denied");
    await getAuth().updateUser(adminUid, {emailVerified: true});

    await emuDb.doc(`users/${adminUid}`).update({accountStatus: "suspended"});
    await denied(callable.run({auth: {uid: adminUid}, data: {}}), "permission-denied");
    await emuDb.doc(`users/${adminUid}`).update({accountStatus: "active"});

    // Seed synthetic staging-like records + sensitive records that must be excluded/redacted.
    await Promise.all([
      emuDb.doc(`colleges/${prefix}-cas`).set({name: "CAS", active: true}),
      emuDb.doc(`appointments/${prefix}-appt-1`).set({
        userRef: emuDb.doc(`users/${adminUid}`),
        scheduledAt: Timestamp.fromDate(new Date("2026-11-21T09:00:00Z")),
        status: "confirmed",
      }),
      emuDb.doc(`appointments/${prefix}-appt-1/history/h1`).set({action: "created"}),
      emuDb.doc(`appointments/${prefix}-appt-1/case_remarks/current`).set({text: "COUNSELOR ONLY REMARK"}),
      emuDb.doc(`user_devices/${adminUid}/tokens/t1`).set({fcmToken: "secret-fcm-token"}),
      emuDb.doc(`_analytics_events/${prefix}-ev-1`).set({internal: true}),
      emuDb.doc(`student_roster/${prefix}-sr-1`).set({
        studentNo: "2026-9999",
        activationCode: {hash: "hash-val", salt: "salt-val"},
      }),
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
      for (const v of res.visitedCollections) visitedKeys.add(v.collectionKey);
      allDocs.push(...res.documents);
      if (!res.hasMore) break;
      cursor = res.nextCursor;
    }

    assert.ok(pages >= 2);
    assert.ok(visitedKeys.has("colleges"));
    assert.ok(visitedKeys.has("appointments"));
    assert.ok(visitedKeys.has("appointments__history"));
    assert.ok(visitedKeys.has("student_roster"));

    // Sensitive internal, device credential, and counselor-exclusive collections are excluded.
    assert.equal(visitedKeys.has("appointments__case_remarks"), false);
    assert.equal(visitedKeys.has("user_devices"), false);
    assert.equal(visitedKeys.has("user_devices__tokens"), false);
    assert.equal(visitedKeys.has("_analytics_events"), false);

    const apptDoc = allDocs.find((d) => d.documentPath === `appointments/${prefix}-appt-1`)!;
    assert.equal(apptDoc.fields.userRef, `ref:users/${adminUid}`);
    assert.equal(apptDoc.fields.scheduledAt, "2026-11-21T09:00:00.000Z");

    const histDoc = allDocs.find((d) => d.documentPath === `appointments/${prefix}-appt-1/history/h1`)!;
    assert.equal(histDoc.parentDocumentId, `${prefix}-appt-1`);

    const rosterDoc = allDocs.find((d) => d.documentPath === `student_roster/${prefix}-sr-1`)!;
    assert.deepEqual(rosterDoc.fields.activationCode, {hash: "[REDACTED]", salt: "[REDACTED]"});

    // Server-side audit logs recorded start + completion.
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
      emuDb.doc(`appointments/${prefix}-appt-1/history/h1`).delete().catch(() => undefined),
      emuDb.doc(`appointments/${prefix}-appt-1/case_remarks/current`).delete().catch(() => undefined),
      emuDb.doc(`appointments/${prefix}-appt-1`).delete().catch(() => undefined),
      emuDb.doc(`user_devices/${adminUid}/tokens/t1`).delete().catch(() => undefined),
      emuDb.doc(`_analytics_events/${prefix}-ev-1`).delete().catch(() => undefined),
      emuDb.doc(`student_roster/${prefix}-sr-1`).delete().catch(() => undefined),
      emuDb.doc(`users/${otherAdminUid}`).delete().catch(() => undefined),
      getAuth().deleteUser(otherAdminUid).catch(() => undefined),
      getAuth().updateUser(adminUid, {emailVerified: true}).catch(() => undefined),
    ]);
    if (previous == null) delete process.env.SUPER_ADMIN_UID;
    else process.env.SUPER_ADMIN_UID = previous;
  }
});

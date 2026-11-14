import {test} from "node:test";
import assert from "node:assert/strict";
import {initializeApp, deleteApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {saveAnnouncement} from "./announcements";

test("transaction persists publication and audit atomically and checks current role", {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const app = initializeApp({projectId: "demo-announcements"}, "announcement-transactions");
  const db = getFirestore(app);
  try {
    await db.doc("users/publisher").set({accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active"});
    const post = {kind: "original", category: "careerGuidance", title: "Career talk", body: "Join us"};
    const saved = await saveAnnouncement(db, "publisher", {expectedRevision: 0, action: "publish", post});
    assert.equal((await db.doc(`announcements/${saved.id}`).get()).data()?.status, "published");
    assert.equal((await db.collection("admin_audit_logs").where("targetId", "==", saved.id).get()).size, 1);
    await assert.rejects(saveAnnouncement(db, "publisher", {id: saved.id, expectedRevision: 0, action: "publish", post}));
    await db.doc("users/publisher").update({accountStatus: "suspended"});
    await assert.rejects(saveAnnouncement(db, "publisher", {id: saved.id, expectedRevision: 1, action: "archive"}));
    assert.equal((await db.doc(`announcements/${saved.id}`).get()).data()?.revision, 1);
  } finally { await deleteApp(app); }
});

import {test} from "node:test";
import assert from "node:assert/strict";
import {initializeApp, deleteApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {backfillAnnouncements} from "./backfill_announcements";

test("announcement backfill patches only missing targeting fields and is idempotent", {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const app = initializeApp({projectId: "demo-announcements"}, "announcement-backfill");
  const db = getFirestore(app);
  const at = Timestamp.fromMillis(1_700_000_000_000);
  const legacy = {kind: "link", category: "placements", title: "T", body: "B", imageUrl: "", sourceUrl: "https://example.com", authorId: "author", revision: 3, createdAt: at, publishedAt: at, updatedAt: at};
  try {
    for (const doc of (await db.collection("announcements").get()).docs) await doc.ref.delete();
    await db.doc("announcements/published").set({...legacy, status: "published"});
    await db.doc("announcements/draft").set({...legacy, status: "draft", publishedAt: null, postType: null});
    await db.doc("announcements/archived").set({...legacy, status: "archived", mediaType: "video"});
    await db.doc("announcements/current").set({...legacy, status: "published", postType: "information", audienceRoles: ["teaching"], mediaType: "standard"});
    await db.doc("announcements/odd").set({...legacy, status: "published", postType: "announcement", audienceRoles: "student", mediaType: "standard"});

    const dry = await backfillAnnouncements(db, {dryRun: true});
    assert.deepEqual(dry, {mode: "dry-run", scanned: 5, changed: 3, skipped: 2, anomalies: 1});
    assert.equal((await db.doc("announcements/published").get()).data()?.audienceRoles, undefined);

    const applied = await backfillAnnouncements(db, {dryRun: false});
    assert.deepEqual(applied, {mode: "apply", scanned: 5, changed: 3, skipped: 2, anomalies: 1});
    const published = (await db.doc("announcements/published").get()).data()!;
    assert.deepEqual(published.audienceRoles, ["student", "teaching", "nonTeaching"]);
    assert.equal(published.postType, "announcement"); assert.equal(published.mediaType, "standard");
    for (const key of ["category", "authorId", "revision", "status", "kind", "title", "sourceUrl"]) assert.deepEqual(published[key], {...legacy, status: "published"}[key as keyof typeof legacy]);
    for (const key of ["updatedAt", "publishedAt", "createdAt"]) assert.ok((published[key] as Timestamp).isEqual(at), key);
    assert.equal((await db.doc("announcements/draft").get()).data()?.postType, "announcement");
    assert.equal((await db.doc("announcements/draft").get()).data()?.publishedAt, null);
    assert.equal((await db.doc("announcements/archived").get()).data()?.mediaType, "video");
    assert.deepEqual((await db.doc("announcements/current").get()).data()?.audienceRoles, ["teaching"]);
    assert.equal((await db.doc("announcements/odd").get()).data()?.audienceRoles, "student");

    assert.deepEqual(await backfillAnnouncements(db, {dryRun: true}), {mode: "dry-run", scanned: 5, changed: 0, skipped: 5, anomalies: 1});
  } finally { await deleteApp(app); }
});

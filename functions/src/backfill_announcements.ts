import {getApps, initializeApp} from "firebase-admin/app";
import {Firestore, getFirestore} from "firebase-admin/firestore";
import {ANNOUNCEMENT_AUDIENCE_ROLES} from "./announcements";

export type AnnouncementBackfillResult = {mode: "dry-run"|"apply"; scanned: number; changed: number; skipped: number; anomalies: number};

const DEFAULTS: Record<string, unknown> = {audienceRoles: [...ANNOUNCEMENT_AUDIENCE_ROLES], postType: "announcement", mediaType: "standard"};
const VALID: Record<string, (value: unknown) => boolean> = {
  audienceRoles: (value) => Array.isArray(value) && value.length > 0 && value.every((role) => (ANNOUNCEMENT_AUDIENCE_ROLES as readonly unknown[]).includes(role)),
  postType: (value) => value === "announcement" || value === "information",
  mediaType: (value) => value === "standard" || value === "video",
};

/** Adds only missing/null targeting fields; never touches timestamps, status, author, revision or category. */
export async function backfillAnnouncements(db: Firestore, {dryRun}: {dryRun: boolean}): Promise<AnnouncementBackfillResult> {
  const snapshot = await db.collection("announcements").get();
  const writer = dryRun ? null : db.bulkWriter();
  let changed = 0; let anomalies = 0;
  for (const document of snapshot.docs) {
    const data = document.data();
    const patch: Record<string, unknown> = {};
    let anomaly = false;
    for (const [key, fallback] of Object.entries(DEFAULTS)) {
      if (data[key] == null) patch[key] = fallback;
      else if (!VALID[key](data[key])) anomaly = true;
    }
    if (anomaly) anomalies++;
    if (!Object.keys(patch).length) continue;
    changed++;
    writer?.update(document.ref, patch);
  }
  if (writer) await writer.close();
  return {mode: dryRun ? "dry-run" : "apply", scanned: snapshot.size, changed, skipped: snapshot.size - changed, anomalies};
}

if (require.main === module) {
  // Imported lazily so loading this module (e.g. in tests) never initializes the default app.
  const {resolveProjectId} = require("./backfill_profiles") as typeof import("./backfill_profiles");
  if (!getApps().length) initializeApp({projectId: resolveProjectId()});
  const apply = process.argv.includes("--apply");
  backfillAnnouncements(getFirestore(), {dryRun: !apply})
    .then((result) => console.log(JSON.stringify(result)))
    .catch((error) => { console.error(error instanceof Error ? error.message : String(error)); process.exitCode = 1; });
}

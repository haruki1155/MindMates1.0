import {FieldValue, Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {actorName, AUDIT_CATEGORIES, writeAudit} from "./audit";
type Profile = Record<string, unknown>;
export type AnnouncementInput = {kind: "original"|"link"; category: "careerGuidance"|"placements"; title: string; body: string; imageUrl: string; sourceUrl: string};
export function canManageAnnouncements(actor: Profile): boolean {
  const role = actor.accessRole ?? actor.role;
  return ["portalStaff", "admin"].includes(String(role)) && (actor.accountStatus == null || actor.accountStatus === "active") && (role === "admin" || actor.staffAccountStatus == null || actor.staffAccountStatus === "approved");
}
export function announcementUrl(value: unknown, required = false): string {
  if (value == null || value === "") { if (required) throw new HttpsError("invalid-argument", "A source link is required."); return ""; }
  if (typeof value !== "string" || value.length > 2048) throw new HttpsError("invalid-argument", "Invalid link.");
  try { const url = new URL(value.trim()); if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) throw new Error(); return url.href; }
  catch { throw new HttpsError("invalid-argument", "Use an http or https link without credentials."); }
}
export function validateAnnouncementPayload(value: unknown): AnnouncementInput {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new HttpsError("invalid-argument", "Enter announcement details.");
  const data = value as Profile;
  if (Object.keys(data).some((key) => !["kind", "category", "title", "body", "imageUrl", "sourceUrl"].includes(key))) throw new HttpsError("invalid-argument", "Unexpected announcement field.");
  if (!["original", "link"].includes(String(data.kind)) || !["careerGuidance", "placements"].includes(String(data.category))) throw new HttpsError("invalid-argument", "Choose a post type and category.");
  const text = (key: string, max: number) => { const v = data[key]; if (typeof v !== "string" || !v.trim() || v.length > max) throw new HttpsError("invalid-argument", `Invalid ${key}.`); return v.trim(); };
  const sourceUrl = announcementUrl(data.sourceUrl, data.kind === "link");
  if (data.kind === "original" && sourceUrl) throw new HttpsError("invalid-argument", "Original posts cannot have a source link.");
  return {kind: data.kind as AnnouncementInput["kind"], category: data.category as AnnouncementInput["category"], title: text("title", 160), body: text("body", 10000), imageUrl: announcementUrl(data.imageUrl), sourceUrl};
}
export function announcementMutation(before: Profile|null, input: Profile, uid: string, now: unknown): Profile {
  if (!Number.isSafeInteger(input.expectedRevision) || Number(input.expectedRevision) < 0) throw new HttpsError("invalid-argument", "Invalid revision.");
  if (Number(input.expectedRevision) !== (before?.revision ?? 0)) throw new HttpsError("aborted", "This announcement changed. Reload before saving.");
  if (!["saveDraft", "publish", "archive"].includes(String(input.action))) throw new HttpsError("invalid-argument", "Invalid action.");
  if (before?.status === "archived" || (!before && input.action === "archive") || (before?.status === "published" && input.action === "saveDraft")) throw new HttpsError("failed-precondition", "This action is unavailable for the current post status.");
  const post = input.action === "archive" ? before! : validateAnnouncementPayload(input.post);
  return {...post, authorId: before?.authorId ?? uid, createdAt: before?.createdAt ?? now, publishedAt: before?.publishedAt ?? (input.action === "publish" ? now : null), updatedAt: now, status: input.action === "archive" ? "archived" : input.action === "publish" ? "published" : "draft", revision: Number(input.expectedRevision) + 1};
}
export async function saveAnnouncement(db: Firestore, actorUid: string, input: Profile): Promise<{id: string; revision: number}> {
  const id = input.id;
  if (id != null && (typeof id !== "string" || !/^[a-zA-Z0-9_-]{1,128}$/.test(id))) throw new HttpsError("invalid-argument", "Invalid announcement ID.");
  const ref = id ? db.collection("announcements").doc(String(id)) : db.collection("announcements").doc();
  return db.runTransaction(async (tx) => {
    const [actor, current] = await Promise.all([tx.get(db.doc(`users/${actorUid}`)), tx.get(ref)]);
    const profile = actor.data() ?? {};
    if (!canManageAnnouncements(profile)) throw new HttpsError("permission-denied", "Staff or administrator access is required.");
    if (id && !current.exists) throw new HttpsError("not-found", "Announcement no longer exists.");
    const next = announcementMutation(current.data() ?? null, input, actorUid, FieldValue.serverTimestamp());
    tx.set(ref, next);
    writeAudit(tx, db, {actorId: actorUid, actorNameSnapshot: actorName(profile), actorRoleSnapshot: String(profile.accessRole ?? profile.role), action: input.action === "archive" ? "ANNOUNCEMENT_ARCHIVED" : input.action === "publish" ? "ANNOUNCEMENT_PUBLISHED" : "ANNOUNCEMENT_DRAFT_SAVED", category: AUDIT_CATEGORIES.system, targetType: "announcement", targetId: ref.id, metadata: {status: next.status, revision: next.revision}});
    return {id: ref.id, revision: Number(next.revision)};
  });
}

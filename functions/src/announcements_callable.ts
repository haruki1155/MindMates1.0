import {getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {saveAnnouncement as persistAnnouncement} from "./announcements";
import {admitAnnouncementPreview, getAnnouncementLinkPreview} from "./announcement_link_preview";

export const saveAnnouncement = onCall({maxInstances: 5}, async (request) => {
  if (!request.auth || request.auth.token.email_verified !== true) throw new HttpsError("permission-denied", "Sign in with a verified email.");
  return persistAnnouncement(getFirestore(), request.auth.uid, request.data ?? {});
});
export const previewAnnouncementLink = onCall({maxInstances: 3, concurrency: 10, timeoutSeconds: 15}, async (request) => {
  if (!request.auth || request.auth.token.email_verified !== true) throw new HttpsError("permission-denied", "Sign in with a verified email.");
  if (typeof request.data?.url !== "string") throw new HttpsError("invalid-argument", "Enter a link.");
  await admitAnnouncementPreview(getFirestore(), request.auth.uid);
  return getAnnouncementLinkPreview(request.data.url);
});

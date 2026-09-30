import {createHash} from "node:crypto";

import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";

if (!getApps().length) initializeApp();

const db = getFirestore();
const REGION = "asia-southeast1";
const ACTIVE_ALERTS = "_mind_aid_active_emergency_alerts";
const ALERTS = "mind_aid_emergency_alerts";

export type EmergencyAlertStatus = "open" | "acknowledged" | "resolved";

function publicUserId(uid: string, value: unknown): string {
  const configured = String(value ?? "").trim();
  if (/^USR-[A-Za-z0-9_-]{4,40}$/.test(configured)) return configured;
  return `USR-${createHash("sha256").update(uid).digest("hex").slice(0, 8).toUpperCase()}`;
}

function isActiveClinicalAccount(data: FirebaseFirestore.DocumentData): boolean {
  const role = String(data.accessRole ?? data.role ?? "").toLowerCase();
  if (role !== "counselor" && role !== "admin") return false;
  return data.staffAccountStatus == null ||
    (data.staffAccountStatus === "approved" && data.accountStatus === "active");
}

async function notificationRecipients(): Promise<FirebaseFirestore.QueryDocumentSnapshot[]> {
  const people = await db.collection("users")
    .where("accessRole", "in", ["counselor", "admin"])
    .get();
  const eligible = people.docs.filter((document) => isActiveClinicalAccount(document.data()));
  const counselors = eligible.filter((document) => String(document.data().accessRole).toLowerCase() === "counselor");
  // Counselors receive the immediate alert. Administrators retain clinical
  // record access and are notified only if no active counselor exists.
  return counselors.length
    ? counselors
    : eligible.filter((document) => String(document.data().accessRole).toLowerCase() === "admin");
}

export async function createOrUpdateMindAidEmergencyAlert({
  userId,
  conversationId,
  triggerMessageId,
}: {
  userId: string;
  conversationId: string;
  triggerMessageId: string;
}): Promise<{alertId: string; notified: boolean}> {
  const user = await db.collection("users").doc(userId).get();
  const active = db.collection(ACTIVE_ALERTS).doc(userId);
  let alertId = "";
  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(active);
    if (current.exists) {
      const existingId = String(current.data()?.alertId ?? "");
      const existing = existingId ? await transaction.get(db.collection(ALERTS).doc(existingId)) : null;
      if (existing?.exists && existing.data()?.status === "open") {
        alertId = existing.id;
        transaction.update(existing.ref, {
          lastTriggeredAt: FieldValue.serverTimestamp(),
          triggerCount: FieldValue.increment(1),
        });
        return;
      }
    }
    const alert = db.collection(ALERTS).doc();
    alertId = alert.id;
    transaction.create(alert, {
      alertId,
      userId,
      publicUserId: publicUserId(userId, user.data()?.publicUserId),
      conversationId,
      triggerMessageId,
      safetyLevel: "crisisOrImmediateRisk",
      source: "mind_aid_deterministic_safety_classifier",
      status: "open" satisfies EmergencyAlertStatus,
      createdAt: FieldValue.serverTimestamp(),
      lastTriggeredAt: FieldValue.serverTimestamp(),
      triggerCount: 1,
      acknowledgedAt: null,
      acknowledgedBy: null,
      resolvedAt: null,
      resolvedBy: null,
      resolutionDisposition: null,
    });
    transaction.set(active, {alertId, userId, updatedAt: FieldValue.serverTimestamp()});
  });

  try {
    const recipients = await notificationRecipients();
    if (!recipients.length) return {alertId, notified: false};
    await Promise.all(recipients.map(async (recipient) => {
      const notification = db.collection("notifications").doc(`mind_aid_emergency_${alertId}_${recipient.id}`);
      await notification.set({
        userId: recipient.id,
        audience: "portal",
        type: "mind_aid_emergency",
        emergencyAlertId: alertId,
        title: "Emergency Alert",
        // Never include the user's message or any conversation excerpt in a
        // durable portal notification or lock-screen push preview.
        body: "A MindAid safety alert requires counselor review.",
        createdAt: FieldValue.serverTimestamp(),
        readAt: null,
        resolvedAt: null,
        archiveEligibleAt: null,
        archivedAt: null,
        expiresAt: null,
      }, {merge: false});
    }));
    return {alertId, notified: true};
  } catch (_) {
    // The alert record remains available for the bounded clinical workflow,
    // but the caller must not claim PAACC was notified.
    return {alertId, notified: false};
  }
}

async function requireClinical(uid: string): Promise<FirebaseFirestore.DocumentData> {
  const user = await db.collection("users").doc(uid).get();
  const data = user.data() ?? {};
  if (!isActiveClinicalAccount(data)) {
    throw new HttpsError("permission-denied", "Counselor or administrator access is required.");
  }
  return data;
}

function alertIdFrom(request: CallableRequest): string {
  const value = String(request.data?.alertId ?? "").trim();
  if (!value || value.length > 180 || value.includes("/")) {
    throw new HttpsError("invalid-argument", "Choose a valid emergency alert.");
  }
  return value;
}

export async function acknowledgeMindAidEmergencyAlertHandler(request: CallableRequest) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  const actor = await requireClinical(uid);
  const alert = db.collection(ALERTS).doc(alertIdFrom(request));
  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(alert);
    if (!current.exists) throw new HttpsError("not-found", "Emergency alert not found.");
    if (current.data()?.status !== "open") throw new HttpsError("failed-precondition", "Only open alerts can be acknowledged.");
    transaction.update(alert, {
      status: "acknowledged" satisfies EmergencyAlertStatus,
      acknowledgedAt: FieldValue.serverTimestamp(),
      acknowledgedBy: uid,
      acknowledgedByName: String(actor.name ?? actor.displayName ?? actor.email ?? "PAACC counselor").slice(0, 120),
    });
  });
  return {ok: true};
}

export const acknowledgeMindAidEmergencyAlert = onCall({region: REGION}, acknowledgeMindAidEmergencyAlertHandler);

export async function resolveMindAidEmergencyAlertHandler(request: CallableRequest) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  const actor = await requireClinical(uid);
  const disposition = String(request.data?.resolutionDisposition ?? "").trim();
  const allowed = new Set(["contacted_user", "referred_immediate_support", "emergency_services_contacted", "false_positive", "other"]);
  if (!allowed.has(disposition)) throw new HttpsError("invalid-argument", "Choose a valid resolution.");
  const alert = db.collection(ALERTS).doc(alertIdFrom(request));
  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(alert);
    if (!current.exists) throw new HttpsError("not-found", "Emergency alert not found.");
    const data = current.data() ?? {};
    if (data.status !== "acknowledged") throw new HttpsError("failed-precondition", "Acknowledge the alert before resolving it.");
    transaction.update(alert, {
      status: "resolved" satisfies EmergencyAlertStatus,
      resolvedAt: FieldValue.serverTimestamp(),
      resolvedBy: uid,
      resolvedByName: String(actor.name ?? actor.displayName ?? actor.email ?? "PAACC counselor").slice(0, 120),
      resolutionDisposition: disposition,
    });
    transaction.delete(db.collection(ACTIVE_ALERTS).doc(String(data.userId ?? "")));
  });
  return {ok: true};
}

export const resolveMindAidEmergencyAlert = onCall({region: REGION}, resolveMindAidEmergencyAlertHandler);

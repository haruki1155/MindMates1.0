import {FieldValue, Timestamp} from "firebase-admin/firestore";
import type {Firestore} from "firebase-admin/firestore";

export type SelfCareReminderKind = "mood" | "breathing";

const SELF_CARE_DELIVERY_WINDOW_MS = 15 * 60 * 1000;

export function manilaDateKey(date: Date): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Manila",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${value.year}${value.month}${value.day}`;
}

export function isSelfCareReminderDue(
  now: Date,
  selectedTime: string,
  updatedAt: Date | Timestamp | null,
): boolean {
  if (!/^(?:[01][0-9]|2[0-3]):[0-5][0-9]$/.test(selectedTime)) return false;

  const dateKey = manilaDateKey(now);
  const year = Number(dateKey.slice(0, 4));
  const month = Number(dateKey.slice(4, 6));
  const day = Number(dateKey.slice(6, 8));
  const [hour, minute] = selectedTime.split(":").map(Number);
  // Manila stays at UTC+8 year-round; the product schedule is fixed to this zone.
  const target = Date.UTC(year, month - 1, day, hour - 8, minute);
  const nowMillis = now.getTime();
  if (nowMillis < target || nowMillis > target + SELF_CARE_DELIVERY_WINDOW_MS) {
    return false;
  }

  const changedMillis = updatedAt instanceof Timestamp
    ? updatedAt.toMillis()
    : updatedAt?.getTime() ?? Number.NEGATIVE_INFINITY;
  return changedMillis <= target;
}

export function selfCareReminderNotificationId(
  userId: string,
  kind: SelfCareReminderKind,
  dateKey: string,
): string {
  return `self_care_${kind}_reminder_${userId}_${dateKey}`;
}

export async function createSelfCareReminderIfDue(
  db: Firestore,
  userId: string,
  kind: SelfCareReminderKind,
  now: Date,
): Promise<void> {
  if (!userId.trim()) return;

  const dateKey = manilaDateKey(now);
  const preferenceRef = db.collection("reminder_preferences").doc(userId);
  const notificationRef = db.collection("notifications").doc(
    selfCareReminderNotificationId(userId, kind, dateKey),
  );
  const enabledField = kind === "mood" ? "moodDailyEnabled" : "breathingDailyEnabled";
  const timeField = kind === "mood" ? "moodDailyTime" : "breathingDailyTime";
  const updatedAtField = kind === "mood" ? "moodDailyUpdatedAt" : "breathingDailyUpdatedAt";

  await db.runTransaction(async (transaction) => {
    const [preferenceSnapshot, notificationSnapshot] = await Promise.all([
      transaction.get(preferenceRef),
      transaction.get(notificationRef),
    ]);
    if (!preferenceSnapshot.exists || notificationSnapshot.exists) return;

    const preference = preferenceSnapshot.data() ?? {};
    const updatedAtValue = preference[updatedAtField];
    const updatedAt = updatedAtValue instanceof Timestamp || updatedAtValue instanceof Date
      ? updatedAtValue
      : null;
    if (preference[enabledField] !== true ||
        typeof preference[timeField] !== "string" ||
        !isSelfCareReminderDue(now, preference[timeField], updatedAt)) return;

    transaction.create(notificationRef, {
      userId,
      type: `${kind}_reminder`,
      title: "MindMate Reminder",
      body: kind === "mood"
        ? "Take a moment to check in with yourself."
        : "Take a short mindful breathing break.",
      createdAt: FieldValue.serverTimestamp(),
      readAt: null,
    });
  });
}

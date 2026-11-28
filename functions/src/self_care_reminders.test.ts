import assert from "node:assert/strict";
import {test} from "node:test";
import {deleteApp, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";

import {
  createSelfCareReminderIfDue,
  isSelfCareReminderDue,
  manilaDateKey,
  selfCareReminderNotificationId,
} from "./self_care_reminders";

test("self-care reminder dates follow the Asia/Manila calendar day", () => {
  assert.equal(manilaDateKey(new Date("2026-11-28T15:59:59.000Z")), "20261128");
  assert.equal(manilaDateKey(new Date("2026-11-28T16:00:00.000Z")), "20261129");
});

test("self-care reminders are due only during the 15-minute window", () => {
  const changedBeforeTime = new Date("2026-11-28T11:00:00.000Z");

  assert.equal(
    isSelfCareReminderDue(new Date("2026-11-28T11:59:59.000Z"), "20:00", changedBeforeTime),
    false,
  );
  assert.equal(
    isSelfCareReminderDue(new Date("2026-11-28T12:00:00.000Z"), "20:00", changedBeforeTime),
    true,
  );
  assert.equal(
    isSelfCareReminderDue(new Date("2026-11-28T12:15:00.000Z"), "20:00", changedBeforeTime),
    true,
  );
  assert.equal(
    isSelfCareReminderDue(new Date("2026-11-28T12:15:01.000Z"), "20:00", changedBeforeTime),
    false,
  );
});

test("a schedule changed after its selected time is skipped for that day", () => {
  assert.equal(
    isSelfCareReminderDue(
      new Date("2026-11-28T12:05:00.000Z"),
      "20:00",
      new Date("2026-11-28T12:01:00.000Z"),
    ),
    false,
  );
  assert.equal(
    isSelfCareReminderDue(
      new Date("2026-11-28T12:05:00.000Z"),
      "not-a-time",
      new Date("2026-11-28T11:00:00.000Z"),
    ),
    false,
  );
});

test("a reminder due shortly after Manila midnight uses the new calendar date", () => {
  const now = new Date("2026-11-28T16:05:00.000Z");
  assert.equal(manilaDateKey(now), "20261129");
  assert.equal(
    isSelfCareReminderDue(now, "00:00", new Date("2026-11-28T15:00:00.000Z")),
    true,
  );
});

test("notification ids are stable for one user, kind, and Manila date", () => {
  assert.equal(
    selfCareReminderNotificationId("user_1", "mood", "20261128"),
    "self_care_mood_reminder_user_1_20261128",
  );
  assert.notEqual(
    selfCareReminderNotificationId("user_1", "mood", "20261128"),
    selfCareReminderNotificationId("user_1", "breathing", "20261128"),
  );
});

test("concurrent daily scheduler retries create one generic inbox notification", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  const app = initializeApp({projectId: "demo-self-care-reminders"}, `self-care-${process.pid}`);
  const db = getFirestore(app);
  const userId = `retry-user-${Date.now()}`;
  const now = new Date("2026-11-28T12:05:00.000Z");
  try {
    await db.collection("reminder_preferences").doc(userId).set({
      appointment24HourEnabled: true,
      appointment1HourEnabled: true,
      moodDailyEnabled: true,
      moodDailyTime: "20:00",
      moodDailyUpdatedAt: new Date("2026-11-28T11:00:00.000Z"),
      breathingDailyEnabled: false,
      breathingDailyTime: "21:00",
      breathingDailyUpdatedAt: new Date("2026-11-28T12:01:00.000Z"),
      updatedAt: new Date("2026-11-28T11:00:00.000Z"),
    });

    await Promise.all([
      createSelfCareReminderIfDue(db, userId, "mood", now),
      createSelfCareReminderIfDue(db, userId, "mood", now),
    ]);

    const notifications = await db.collection("notifications").get();
    const created = notifications.docs.filter((document) =>
      document.data().userId === userId && document.data().type === "mood_reminder",
    );
    assert.equal(created.length, 1);
    assert.equal(created[0].data().body, "Take a moment to check in with yourself.");
    assert.equal("moodText" in created[0].data(), false);
  } finally {
    await deleteApp(app);
  }
});

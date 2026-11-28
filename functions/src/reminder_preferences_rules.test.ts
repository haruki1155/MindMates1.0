import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {test} from "node:test";
import {assertFails, assertSucceeds, initializeTestEnvironment} from "@firebase/rules-unit-testing";
import {deleteDoc, doc, getDoc, serverTimestamp, setDoc} from "firebase/firestore";

const validPreferences = () => ({
  appointment24HourEnabled: true,
  appointment1HourEnabled: true,
  moodDailyEnabled: false,
  moodDailyTime: "20:00",
  moodDailyUpdatedAt: serverTimestamp(),
  breathingDailyEnabled: false,
  breathingDailyTime: "21:00",
  breathingDailyUpdatedAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
});

test("reminder preferences are owner-only and enforce the complete contract", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  const env = await initializeTestEnvironment({
    projectId: "demo-reminder-preferences",
    firestore: {
      rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8"),
    },
  });
  try {
    const owner = env.authenticatedContext("owner").firestore();
    const otherUser = env.authenticatedContext("other-user").firestore();
    const anonymous = env.unauthenticatedContext().firestore();
    const ownerRef = doc(owner, "reminder_preferences/owner");

    await assertSucceeds(setDoc(ownerRef, validPreferences()));
    await assertSucceeds(getDoc(ownerRef));
    await assertFails(getDoc(doc(otherUser, "reminder_preferences/owner")));
    await assertFails(
      setDoc(doc(otherUser, "reminder_preferences/owner"), validPreferences()),
    );
    await assertFails(getDoc(doc(anonymous, "reminder_preferences/owner")));
    await assertFails(
      setDoc(doc(anonymous, "reminder_preferences/anonymous"), validPreferences()),
    );

    await assertSucceeds(setDoc(ownerRef, {
      appointment24HourEnabled: false,
      updatedAt: serverTimestamp(),
    }, {merge: true}));
    await assertSucceeds(setDoc(ownerRef, {
      moodDailyEnabled: true,
      moodDailyUpdatedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }, {merge: true}));
    await assertSucceeds(setDoc(ownerRef, {
      breathingDailyTime: "06:45",
      breathingDailyUpdatedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }, {merge: true}));

    await assertFails(setDoc(ownerRef, {
      moodDailyTime: "25:00",
      moodDailyUpdatedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }, {merge: true}));
    await assertFails(setDoc(ownerRef, {
      breathingDailyEnabled: true,
      updatedAt: serverTimestamp(),
    }, {merge: true}));
    await assertFails(setDoc(ownerRef, {
      moodDailyUpdatedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }, {merge: true}));
    await assertFails(setDoc(ownerRef, {
      extraField: true,
      updatedAt: serverTimestamp(),
    }, {merge: true}));
    await assertFails(deleteDoc(ownerRef));
  } finally {
    await env.cleanup();
  }
});

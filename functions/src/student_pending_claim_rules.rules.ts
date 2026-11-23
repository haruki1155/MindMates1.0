import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {after, before, test} from "node:test";
import {assertFails} from "@firebase/rules-unit-testing";
import {RulesTestEnvironment, initializeTestEnvironment} from "@firebase/rules-unit-testing";
import {collection, doc, getDoc, getDocs, query, setDoc, updateDoc, where} from "firebase/firestore";

/**
 * A student whose setup is verified but not yet approved by PACC: a signed-in Auth user on the Student ID alias with a
 * verified email and NO profile. They must not read other people's records, any roster or recovery record, and must not
 * be able to create the profile, roster link or reservation that approval alone creates.
 */
let environment: RulesTestEnvironment;
const PENDING = "pending-student-uid";
const OTHER = "approved-student-uid";

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: "mind-mates-pending-claim-rules-test",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `users/${OTHER}`), {
      id: OTHER, schoolId: "2021-0001", role: "student", accessRole: "appUser", email: "other@example.com", rosterLinked: true,
    });
    await setDoc(doc(db, "student_roster/20210001"), {studentNo: "2021-0001", dateOfBirthKey: "2004-05-06", userId: OTHER, activated: true});
    await setDoc(doc(db, "student_id_reservations/20210001"), {userId: OTHER});
    await setDoc(doc(db, `student_personal_info/${OTHER}`), {surname: "Cruz"});
    await setDoc(doc(db, `student_claim_pending/${PENDING}`), {uid: PENDING, studentKey: "20210002", status: "awaiting-approval"});
    await setDoc(doc(db, `student_recovery_contacts/${PENDING}`), {uid: PENDING, email: "pending@example.com"});
    await setDoc(doc(db, "appointments/a1"), {studentId: OTHER, status: "pending"});
    await setDoc(doc(db, `counselor_threads/${OTHER}`), {userId: OTHER});
    await setDoc(doc(db, "moods/m1"), {userId: OTHER, mood: "happy"});
    await setDoc(doc(db, "assessments/as1"), {userId: OTHER});
    await setDoc(doc(db, "admin_audit_logs/log1"), {action: "X"});
  });
});
after(async () => environment.cleanup());

const pendingDb = () => environment.authenticatedContext(PENDING, {
  email: "20210002@students.mindmate.local", email_verified: true,
}).firestore();

test("a pending student cannot read another student's profile, roster, reservation, personal data or care records", async () => {
  const db = pendingDb();
  for (const path of [
    `users/${OTHER}`, "student_roster/20210001", "student_id_reservations/20210001", `student_personal_info/${OTHER}`,
    "appointments/a1", `counselor_threads/${OTHER}`, "moods/m1", "assessments/as1", "admin_audit_logs/log1",
  ]) {
    await assertFails(getDoc(doc(db, path)));
  }
  await assertFails(getDocs(query(collection(db, "appointments"), where("studentId", "==", OTHER))));
  await assertFails(getDocs(collection(db, "student_roster")));
});

test("a pending student cannot read or write their own claim, recovery contact or verification records", async () => {
  const db = pendingDb();
  for (const path of [`student_claim_pending/${PENDING}`, `student_recovery_contacts/${PENDING}`, `student_recovery_verifications/${PENDING}`]) {
    await assertFails(getDoc(doc(db, path)));
    await assertFails(setDoc(doc(db, path), {status: "approved", verifiedAt: new Date()}));
  }
  await assertFails(updateDoc(doc(db, `student_claim_pending/${PENDING}`), {status: "approved"}));
});

test("a pending student cannot create the profile, roster link or reservation that only approval creates", async () => {
  const db = pendingDb();
  await assertFails(setDoc(doc(db, `users/${PENDING}`), {
    id: PENDING, schoolId: "2021-0002", role: "student", accessRole: "appUser", rosterLinked: true, email: "pending@example.com",
  }));
  await assertFails(setDoc(doc(db, "student_id_reservations/20210002"), {userId: PENDING}));
  await assertFails(updateDoc(doc(db, "student_roster/20210002"), {activated: true, userId: PENDING}));
  await assertFails(setDoc(doc(db, "student_roster/20210002"), {studentNo: "2021-0002", activated: true, userId: PENDING}));
  await assertFails(setDoc(doc(db, `student_personal_info/${PENDING}`), {surname: "Cruz"}));
});

import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireAdmin} from "./access";
import {AUDIT_CATEGORIES, writeAudit} from "./audit";
import {
  assertDevEndpointAllowed, callerIp, consumeWindow, currentProjectId,
} from "./student_account_recovery";
import {
  authEmailTaken, clearAttempts, createAliasUser, reserveAttempt,
} from "./student_activation";
import {studentAuthAliasEmail, isStudentAuthAlias} from "./student_auth_alias";
import {
  NormalizedIdentity, claimIdentityMatches, isAllowedPersonalEmail, readSetupPassword, readStudentClaimInput,
  storedIdentityMatches,
} from "./student_claim_domain";
import {rosterStudentProfile} from "./student_profile";
import {
  CLAIM_PENDING, RECOVERY_CONTACTS, RECOVERY_EMAILS, normalizeRecoveryContactEmail, readRecoveryRecords,
  recoveryEmailHash, releaseRecoveryRecords,
} from "./student_recovery_contacts";

if (!getApps().length) initializeApp();

/**
 * No-code student account setup. A student is found in the imported roster by Student Number + full name + date of
 * birth (knowledge, not secrets), chooses a personal email and a password, and proves control of that email with an
 * emailed code (student_account_recovery.ts). Only then is the roster record claimed. Until that final step nothing
 * about the roster, the Student ID reservation or a profile changes.
 */
const db = () => getFirestore();
const PENDING_WINDOW_MS = 15 * 60 * 1000;
const START_IP_LIMIT = 20;
const CLAIM_METHOD = "self-roster-match";
const APPROVAL_WINDOW_MS = 14 * 24 * 60 * 60 * 1000;
const AWAITING = "awaiting-approval";
const GENERIC = "We couldn't verify these details. Check them and try again.";

export type SetupDeps = {now: () => number};
export const defaultSetupDeps: SetupDeps = {now: () => Date.now()};
type Req = {auth?: {uid: string} | null; data?: unknown; rawRequest?: {ip?: string; socket?: {remoteAddress?: string}}};

const mismatch = () => new HttpsError("not-found", GENERIC);
const emailUnusable = () => new HttpsError("already-exists", "That email address can't be used. Try a different one.");
const inProgress = () => new HttpsError("resource-exhausted", "Setup for this record is already in progress. Wait a few minutes and try again.");
const unavailableRecord = () => new HttpsError("already-exists", "This Student ID can't be set up right now. Contact the PACC office.");

function requireUid(request: Req): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  return uid;
}

function eligible(row: FirebaseFirestore.DocumentData | undefined): row is FirebaseFirestore.DocumentData {
  return !!row && row.status === "active" && row.activated !== true;
}

// ------------------------------------------------------------------ start

export async function startAccountSetup(request: Req, deps: SetupDeps = defaultSetupDeps) {
  const raw = request.data;
  const input = readStudentClaimInput(raw);
  const fields = raw as Record<string, unknown>;
  const email = normalizeRecoveryContactEmail(fields.email);
  if (!email || !isAllowedPersonalEmail(email)) {
    throw new HttpsError("invalid-argument", "Enter a valid personal email address.");
  }
  const password = readSetupPassword(fields.password);
  const now = deps.now();

  await consumeWindow("setup_ip", callerIp(request), START_IP_LIMIT, now);
  // Every attempt is counted against the Student ID before any identity check; five failures lock it for a while.
  if (!(await reserveAttempt(input.studentKey))) throw mismatch();
  const rosterRef = db().collection("student_roster").doc(input.studentKey);
  const row = (await rosterRef.get()).data();
  if (!eligible(row) || !claimIdentityMatches(input, row)) throw mismatch();
  await clearAttempts(input.studentKey);

  if (await authEmailTaken(email)) throw emailUnusable();

  const alias = studentAuthAliasEmail(input.studentKey);
  const uid = await createSetupUser(alias, password, row, input.studentKey, now);
  const identity: NormalizedIdentity = {
    firstName: input.firstName, middleName: input.middleName, lastName: input.lastName, dateOfBirthKey: input.dateOfBirthKey,
  };
  const emailHash = recoveryEmailHash(email);
  try {
    await db().runTransaction(async (transaction) => {
      const [live, emailReservation] = await Promise.all([
        transaction.get(rosterRef), transaction.get(db().collection(RECOVERY_EMAILS).doc(emailHash)),
      ]);
      if (!eligible(live.data()) || !claimIdentityMatches(input, live.data()!)) throw mismatch();
      if (emailReservation.exists && emailReservation.data()?.uid !== uid) throw emailUnusable();
      transaction.create(db().collection(CLAIM_PENDING).doc(uid), {
        uid, studentKey: input.studentKey, identity, createdAt: FieldValue.serverTimestamp(),
        expiresAt: Timestamp.fromMillis(now + PENDING_WINDOW_MS),
      });
      transaction.create(db().collection(RECOVERY_CONTACTS).doc(uid), {
        uid, studentKey: input.studentKey, email, emailHash, verifiedAt: null,
        createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.create(db().collection(RECOVERY_EMAILS).doc(emailHash), {uid, studentKey: input.studentKey, createdAt: FieldValue.serverTimestamp()});
    });
  } catch (error) {
    await getAuth().deleteUser(uid).catch(() => undefined);
    throw error;
  }
  return {ok: true, authEmail: alias, email};
}

/**
 * Creates the Student ID login. If the alias is already held, the holder is only ever replaced when it is the
 * system's own pending setup for this same Student ID that has expired unclaimed (no profile, no reservation).
 * Any other holder is an unrelated account and is left untouched.
 */
async function createSetupUser(
  alias: string, password: string, row: FirebaseFirestore.DocumentData, key: string, now: number,
): Promise<string> {
  try {
    return await createAliasUser(alias, password, row);
  } catch (error) {
    if ((error as {code?: string})?.code !== "auth/email-already-exists") throw error;
  }
  const occupant = await getAuth().getUserByEmail(alias).catch(() => null);
  if (!occupant) throw unavailableRecord();
  const pendingRef = db().collection(CLAIM_PENDING).doc(occupant.uid);
  const pending = (await pendingRef.get()).data();
  if (!pending || pending.studentKey !== key) throw unavailableRecord();
  const expiresAt = pending.expiresAt instanceof Timestamp ? pending.expiresAt.toMillis() : 0;
  if (expiresAt > now) throw inProgress();

  const [profile, reservation] = await Promise.all([
    db().collection("users").doc(occupant.uid).get(), db().collection("student_id_reservations").doc(key).get(),
  ]);
  if (profile.exists || reservation.data()?.userId === occupant.uid) throw unavailableRecord();

  // Free the alias first (so a failure can never leave it stuck), then release the abandoned setup's records.
  await getAuth().deleteUser(occupant.uid).catch((e) => {
    if ((e as {code?: string})?.code !== "auth/user-not-found") throw e;
  });
  await db().runTransaction(async (transaction) => {
    const records = await readRecoveryRecords(transaction, occupant.uid);
    releaseRecoveryRecords(transaction, occupant.uid, records);
    transaction.delete(pendingRef);
  });
  try {
    return await createAliasUser(alias, password, row);
  } catch (error) {
    if ((error as {code?: string})?.code === "auth/email-already-exists") throw inProgress();
    throw error;
  }
}

// ------------------------------------------------------------------ complete (submit for approval)

/**
 * Called after the personal email was verified. Email ownership proves only that the student controls a mailbox, not
 * that they are the person on the roster record (the name and birth date are knowledge, not secrets), so this does
 * NOT claim the record. It submits the setup for approval by a PACC administrator; the claim becomes active only in
 * {@link approveAccountClaim}.
 */
export async function completeAccountSetup(request: Req, deps: SetupDeps = defaultSetupDeps) {
  const uid = requireUid(request);
  const now = deps.now();
  const user = await getAuth().getUser(uid);
  if (!isStudentAuthAlias(user.email)) {
    throw new HttpsError("failed-precondition", "No account setup is in progress.");
  }
  const profileRef = db().collection("users").doc(uid);
  const existing = (await profileRef.get()).data();
  if (existing?.rosterLinked === true && typeof existing.schoolId === "string") {
    return {ok: true, alreadyComplete: true, status: "approved"};
  }
  const pendingRef = db().collection(CLAIM_PENDING).doc(uid);
  const contactRef = db().collection(RECOVERY_CONTACTS).doc(uid);
  const [pendingSnap, contactSnap] = await Promise.all([pendingRef.get(), contactRef.get()]);
  const pending = pendingSnap.data();
  const contact = contactSnap.data();
  if (!pending || !contact) throw new HttpsError("failed-precondition", "No account setup is in progress.");
  const expiresAt = pending.expiresAt instanceof Timestamp ? pending.expiresAt.toMillis() : 0;
  if (expiresAt <= now) throw new HttpsError("failed-precondition", "This setup has expired. Start again.");
  // Email ownership must be proven, on both the recovery contact and the Firebase account.
  if (!contact.verifiedAt || !user.emailVerified) {
    throw new HttpsError("failed-precondition", "Verify your email address first.");
  }
  const live = (await db().collection("student_roster").doc(String(pending.studentKey)).get()).data();
  if (!eligible(live) || !storedIdentityMatches(pending.identity, live)) throw mismatch();

  await db().runTransaction(async (transaction) => {
    const snap = await transaction.get(pendingRef);
    if (!snap.exists) throw new HttpsError("failed-precondition", "No account setup is in progress.");
    if (snap.data()?.status === AWAITING) return;
    transaction.update(pendingRef, {
      status: AWAITING, submittedAt: FieldValue.serverTimestamp(), expiresAt: Timestamp.fromMillis(now + APPROVAL_WINDOW_MS),
    });
  });
  return {ok: true, alreadyComplete: false, status: "awaiting-approval"};
}

// ------------------------------------------------------------------ administrator review

/** Pending submissions an administrator can review: who asked, for which record, with which email. */
export async function listAccountClaims() {
  const snap = await db().collection(CLAIM_PENDING).where("status", "==", AWAITING).limit(200).get();
  const items = await Promise.all(snap.docs.map(async (doc) => {
    const pending = doc.data();
    const [contact, roster] = await Promise.all([
      db().collection(RECOVERY_CONTACTS).doc(doc.id).get(), db().collection("student_roster").doc(String(pending.studentKey)).get(),
    ]);
    const row = roster.data() ?? {};
    const toIso = (v: unknown) => (v instanceof Timestamp ? v.toDate().toISOString() : "");
    return {
      uid: doc.id, studentNo: String(row.studentNo ?? pending.studentKey),
      name: [row.firstName, row.middleName, row.surname].map((v) => String(v ?? "")).filter(Boolean).join(" "),
      college: String(row.college ?? ""), course: String(row.course ?? ""), yearLevel: String(row.yearLevel ?? ""),
      email: String(contact.data()?.email ?? ""), submittedAt: toIso(pending.submittedAt),
      rosterAlreadyClaimed: row.activated === true,
    };
  }));
  items.sort((a, b) => a.submittedAt.localeCompare(b.submittedAt));
  return {claims: items};
}

type Reviewer = {id: string; name: string; role: string};

export async function approveAccountClaim(reviewer: Reviewer, rawUid: unknown, deps: SetupDeps = defaultSetupDeps) {
  const uid = typeof rawUid === "string" ? rawUid.trim() : "";
  if (!uid || uid.length > 128) throw new HttpsError("invalid-argument", "A claim to approve is required.");
  const now = deps.now();
  const user = await getAuth().getUser(uid).catch(() => null);
  if (!user || !isStudentAuthAlias(user.email)) throw new HttpsError("failed-precondition", "This claim is no longer available.");
  const profileRef = db().collection("users").doc(uid);
  const pendingRef = db().collection(CLAIM_PENDING).doc(uid);
  const contactRef = db().collection(RECOVERY_CONTACTS).doc(uid);

  await db().runTransaction(async (transaction) => {
    const [profile, pendingSnap, contactSnap] = await Promise.all([
      transaction.get(profileRef), transaction.get(pendingRef), transaction.get(contactRef),
    ]);
    const pending = pendingSnap.data();
    const contact = contactSnap.data();
    if (profile.exists || !pending || !contact || pending.status !== AWAITING) {
      throw new HttpsError("failed-precondition", "This claim is no longer available.");
    }
    const expiresAt = pending.expiresAt instanceof Timestamp ? pending.expiresAt.toMillis() : 0;
    if (expiresAt <= now) throw new HttpsError("failed-precondition", "This request has expired. The student must start again.");
    // Both halves of email ownership are still required at approval time.
    if (!contact.verifiedAt || !user.emailVerified) throw new HttpsError("failed-precondition", "The student's email is not verified.");

    const key = String(pending.studentKey);
    const rosterRef = db().collection("student_roster").doc(key);
    const reservationRef = db().collection("student_id_reservations").doc(key);
    const [roster, reservation] = await Promise.all([transaction.get(rosterRef), transaction.get(reservationRef)]);
    const live = roster.data();
    // Re-evaluate the identity captured at the start against the current roster, so a stale request cannot claim.
    if (!eligible(live) || live.studentKey !== key || !storedIdentityMatches(pending.identity, live)) {
      throw new HttpsError("failed-precondition", "This record can no longer be claimed. Reject the request.");
    }
    if (reservation.exists && reservation.data()?.userId !== uid) {
      throw new HttpsError("failed-precondition", "This Student ID is already claimed. Reject the request.");
    }

    const studentNo = String(live.studentNo ?? key);
    transaction.create(profileRef, rosterStudentProfile(live, {
      uid, email: String(contact.email), studentNo, emailVerified: true, claimMethod: CLAIM_METHOD,
    }));
    if (!reservation.exists) {
      transaction.create(reservationRef, {userId: uid, studentId: studentNo, createdAt: FieldValue.serverTimestamp()});
    }
    transaction.update(rosterRef, {
      activated: true, userId: uid, activationCode: null, claimMethod: CLAIM_METHOD,
      activatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.delete(pendingRef);
    writeAudit(transaction, db(), {
      actorId: reviewer.id, actorNameSnapshot: reviewer.name, actorRoleSnapshot: reviewer.role,
      action: "STUDENT_ACCOUNT_CLAIMED", category: AUDIT_CATEGORIES.userManagement,
      targetType: "student", targetId: key, metadata: {studentNo, userId: uid, claimMethod: CLAIM_METHOD, approvedBy: reviewer.id},
    });
  });
  return {ok: true};
}

export async function rejectAccountClaim(reviewer: Reviewer, rawUid: unknown) {
  const uid = typeof rawUid === "string" ? rawUid.trim() : "";
  if (!uid || uid.length > 128) throw new HttpsError("invalid-argument", "A claim to reject is required.");
  const pendingRef = db().collection(CLAIM_PENDING).doc(uid);
  const [pending, profile] = await Promise.all([pendingRef.get(), db().collection("users").doc(uid).get()]);
  // Only the system's own unapproved setup can be rejected: never an approved account or an unrelated one.
  if (!pending.exists || profile.exists) throw new HttpsError("failed-precondition", "This claim is no longer available.");
  const studentKey = String(pending.data()?.studentKey ?? "");
  await getAuth().deleteUser(uid).catch((e) => {
    if ((e as {code?: string})?.code !== "auth/user-not-found") throw e;
  });
  await db().runTransaction(async (transaction) => {
    const records = await readRecoveryRecords(transaction, uid);
    releaseRecoveryRecords(transaction, uid, records);
    transaction.delete(pendingRef);
    writeAudit(transaction, db(), {
      actorId: reviewer.id, actorNameSnapshot: reviewer.name, actorRoleSnapshot: reviewer.role,
      action: "STUDENT_ACCOUNT_CLAIM_REJECTED", category: AUDIT_CATEGORIES.userManagement,
      targetType: "student", targetId: studentKey, metadata: {userId: uid, rejectedBy: reviewer.id},
    });
  });
  return {ok: true};
}

// ------------------------------------------------------------------ cancel

/** Abandons an unfinished setup (for example to correct a mistyped email) so the student can start again. */
export async function cancelAccountSetup(request: Req) {
  const uid = requireUid(request);
  const pendingRef = db().collection(CLAIM_PENDING).doc(uid);
  const [pending, profile] = await Promise.all([pendingRef.get(), db().collection("users").doc(uid).get()]);
  if (!pending.exists || profile.exists) {
    throw new HttpsError("failed-precondition", "There is no unfinished account setup to cancel.");
  }
  // Free the login first so a failure can never leave the Student ID's alias held by a dead setup.
  await getAuth().deleteUser(uid).catch((e) => {
    if ((e as {code?: string})?.code !== "auth/user-not-found") throw e;
  });
  await db().runTransaction(async (transaction) => {
    const records = await readRecoveryRecords(transaction, uid);
    releaseRecoveryRecords(transaction, uid, records);
    transaction.delete(pendingRef);
  });
  return {ok: true};
}

// ------------------------------------------------------------------ callables

export const startStudentAccountSetup = onCall({enforceAppCheck: true}, (request) => startAccountSetup(request));
export const startStudentAccountSetupDev = onCall({enforceAppCheck: false}, (request) => {
  assertDevEndpointAllowed(currentProjectId());
  return startAccountSetup(request);
});
export const completeStudentAccountSetup = onCall({enforceAppCheck: true}, (request) => completeAccountSetup(request));
export const completeStudentAccountSetupDev = onCall({enforceAppCheck: false}, (request) => {
  assertDevEndpointAllowed(currentProjectId());
  return completeAccountSetup(request);
});
export const cancelStudentAccountSetup = onCall({enforceAppCheck: true}, (request) => cancelAccountSetup(request));
export const cancelStudentAccountSetupDev = onCall({enforceAppCheck: false}, (request) => {
  assertDevEndpointAllowed(currentProjectId());
  return cancelAccountSetup(request);
});

async function reviewerOf(request: Req): Promise<Reviewer> {
  const id = requireUid(request);
  const actor = await requireAdmin(id);
  const name = [actor.firstName, actor.lastName].map((v) => String(v ?? "")).filter(Boolean).join(" ") || String(actor.displayName ?? "");
  return {id, name: name || "PACC administrator", role: String(actor.accessRole ?? "admin")};
}

export const listStudentAccountClaims = onCall(async (request) => {
  await reviewerOf(request);
  return listAccountClaims();
});
export const approveStudentAccountClaim = onCall(async (request) =>
  approveAccountClaim(await reviewerOf(request), (request.data as {uid?: unknown} | undefined)?.uid));
export const rejectStudentAccountClaim = onCall(async (request) =>
  rejectAccountClaim(await reviewerOf(request), (request.data as {uid?: unknown} | undefined)?.uid));

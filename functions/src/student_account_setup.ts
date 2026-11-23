import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

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

// ------------------------------------------------------------------ complete

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
    return {ok: true, alreadyComplete: true};
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

  const key = String(pending.studentKey);
  const rosterRef = db().collection("student_roster").doc(key);
  const reservationRef = db().collection("student_id_reservations").doc(key);
  const name = await db().runTransaction(async (transaction) => {
    const [roster, reservation, profile, livePending] = await Promise.all([
      transaction.get(rosterRef), transaction.get(reservationRef), transaction.get(profileRef), transaction.get(pendingRef),
    ]);
    if (profile.exists) return null;
    if (!livePending.exists) throw new HttpsError("failed-precondition", "No account setup is in progress.");
    const live = roster.data();
    // Re-evaluate the identity captured at the start against the current roster, so a stale precheck cannot claim.
    if (!eligible(live) || live.studentKey !== key || !storedIdentityMatches(pending.identity, live)) throw mismatch();
    if (reservation.exists && reservation.data()?.userId !== uid) throw mismatch();

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
    const display = [live.firstName, live.middleName, live.surname].map((v) => String(v ?? "")).filter(Boolean).join(" ");
    writeAudit(transaction, db(), {
      actorId: uid, actorNameSnapshot: display, actorRoleSnapshot: "student",
      action: "STUDENT_ACCOUNT_CLAIMED", category: AUDIT_CATEGORIES.userManagement,
      targetType: "student", targetId: key, metadata: {studentNo, userId: uid, claimMethod: CLAIM_METHOD},
    });
    return display;
  });
  return {ok: true, alreadyComplete: name === null};
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

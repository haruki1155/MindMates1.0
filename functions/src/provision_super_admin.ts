import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth, UserRecord} from "firebase-admin/auth";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {randomBytes} from "node:crypto";
import {writeFile} from "node:fs/promises";
import {resolve} from "node:path";

function argument(name: string, fallback: string): string {
  const index = process.argv.indexOf(`--${name}`);
  return (index >= 0 ? process.argv[index + 1] : fallback)?.trim() ?? "";
}

const ALLOWED_PROJECTS = new Set(["mindmate-staging", "mind-mates-cd2cf"]);
const project = argument("project", process.env.GCLOUD_PROJECT ?? "mindmate-staging");
if (!ALLOWED_PROJECTS.has(project)) {
  throw new Error(`Refusing project ${project}. Use mindmate-staging or mind-mates-cd2cf.`);
}
if (!getApps().length) initializeApp({projectId: project});
const db = getFirestore();
const auth = getAuth();

function temporaryPassword(): string {
  return `Mm!${randomBytes(18).toString("base64url")}9a`;
}

async function authUserForEmail(email: string): Promise<UserRecord | null> {
  try {
    return await auth.getUserByEmail(email);
  } catch (error) {
    if ((error as {code?: string}).code === "auth/user-not-found") return null;
    throw error;
  }
}

async function authUserForUid(uid: string): Promise<UserRecord | null> {
  if (!uid) return null;
  try {
    return await auth.getUser(uid);
  } catch (error) {
    if ((error as {code?: string}).code === "auth/user-not-found") return null;
    throw error;
  }
}

async function main(): Promise<void> {
  const apply = process.argv.includes("--apply");
  const email = argument("email", "").toLowerCase();
  const employeeId = argument("employee-id", "");
  const firstName = argument("first-name", "Test");
  const middleName = argument("middle-name", "");
  const lastName = argument("last-name", "Administrator");
  const position = argument("position", "System Administrator");
  const department = argument("department", "Administration");
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    throw new Error("Provide the temporary administrator email with --email.");
  }
  if (!employeeId) {
    throw new Error("Provide a temporary administrator ID with --employee-id.");
  }
  const employeeIdKey = employeeId.toUpperCase().replace(/[^A-Z0-9]/g, "");

  const security = await db.collection("system_config").doc("security").get();
  const configuredUid = String(security.data()?.superAdminUid ?? "");
  const [emailAuth, configuredAuth, reservation, admins] = await Promise.all([
    authUserForEmail(email), authUserForUid(configuredUid),
    db.collection("employee_id_reservations").doc(employeeIdKey).get(),
    db.collection("users").where("accessRole", "==", "admin").get(),
  ]);
  if (emailAuth && configuredAuth && emailAuth.uid !== configuredAuth.uid) {
    throw new Error("The email and configured super-admin UID belong to different accounts.");
  }
  if (configuredAuth && configuredAuth.email?.toLowerCase() !== email) {
    throw new Error("The configured super-admin UID already uses a different email.");
  }
  const existingAuth = emailAuth ?? configuredAuth;
  // A staging Auth reset does not delete the guarded security document. Reuse
  // that exact UID rather than weakening or deleting the one-admin boundary.
  const candidateUid = existingAuth?.uid ??
    (project === "mindmate-staging" && configuredUid ? configuredUid : null);
  const candidateProfile = candidateUid ? await db.collection("users").doc(candidateUid).get() : null;
  const reassigningOrphanedStagingUid = project === "mindmate-staging" &&
    configuredUid.length > 0 && configuredAuth == null && emailAuth != null &&
    configuredUid !== emailAuth.uid && candidateProfile?.exists !== true && admins.empty;
  const conflictingAdmin = admins.docs.find((doc) => candidateUid == null || doc.id !== candidateUid);
  if (conflictingAdmin) throw new Error(`Another administrator already exists: ${conflictingAdmin.id}`);
  if (configuredUid && candidateUid && configuredUid !== candidateUid && !reassigningOrphanedStagingUid) {
    throw new Error(`Security configuration belongs to another UID: ${configuredUid}`);
  }
  if (configuredUid && !candidateUid) throw new Error(`Security configuration already reserves UID ${configuredUid}`);
  if (reservation.exists && candidateUid && reservation.data()?.userId !== candidateUid) throw new Error("Employee ID belongs to another account.");
  if (reservation.exists && !candidateUid) throw new Error("Employee ID is already reserved.");

  console.log(JSON.stringify({mode: apply ? "apply" : "dry-run", project, email, employeeId,
    existingAuth: existingAuth != null, restoringConfiguredUid: existingAuth == null && candidateUid != null,
    reassigningOrphanedStagingUid,
    configuredUid: configuredUid || null, existingAdmins: admins.size}));
  if (!apply) return;

  const password = temporaryPassword();
  const displayName = [firstName, middleName, lastName].filter(Boolean).join(" ");
  const user = existingAuth == null ? await auth.createUser({uid: candidateUid ?? undefined, email, password, emailVerified: true, displayName}) :
    await auth.updateUser(existingAuth.uid, {password, emailVerified: true, displayName, disabled: false});
  const userRef = db.collection("users").doc(user.uid);
  const reservationRef = db.collection("employee_id_reservations").doc(employeeIdKey);
  const securityRef = db.collection("system_config").doc("security");
  await db.runTransaction(async (transaction) => {
    const [profile, currentReservation, currentSecurity] = await Promise.all([
      transaction.get(userRef), transaction.get(reservationRef), transaction.get(securityRef),
    ]);
    if (profile.exists && String(profile.data()?.email ?? "").toLowerCase() !== email) throw new Error("UID profile email conflict.");
    if (currentReservation.exists && currentReservation.data()?.userId !== user.uid) throw new Error("Employee ID conflict.");
    if (currentSecurity.exists && currentSecurity.data()?.superAdminUid !== user.uid &&
      !reassigningOrphanedStagingUid) throw new Error("Super-admin UID conflict.");
    transaction.set(reservationRef, {userId: user.uid, employeeId, createdAt: currentReservation.data()?.createdAt ?? FieldValue.serverTimestamp()}, {merge: true});
    transaction.set(userRef, {
      id: user.uid, email, firstName, middleName, lastName, name: displayName,
      employeeId, employeeIdKey, position, department, populationRole: "nonTeaching",
      declaredRole: "nonTeaching", role: "staff", accessRole: "admin",
      staffAccountStatus: "approved", verificationStatus: "verified", verifiedBy: user.uid,
      verifiedAt: profile.data()?.verifiedAt ?? FieldValue.serverTimestamp(), mustChangePassword: true,
      profileVersion: 3, createdAt: profile.data()?.createdAt ?? FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(securityRef, {superAdminUid: user.uid, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  });
  const envPath = resolve(process.cwd(), `.env.${project}`);
  await writeFile(envPath, `SUPER_ADMIN_UID=${user.uid}\n`, {encoding: "utf8", mode: 0o600});
  console.log(`ADMIN_UID=${user.uid}`);
  console.log(`ADMIN_EMAIL=${email}`);
  console.log(`TEMPORARY_PASSWORD=${password}`);
  console.log(`ENV_FILE=${envPath}`);
  console.log("IMPORTANT: This password was not stored by the provisioning script. Change it on first login.");
}

void main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});

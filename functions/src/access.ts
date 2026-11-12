import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {HttpsError} from "firebase-functions/v2/https";
import {defineString} from "firebase-functions/params";

export const superAdminUid = defineString("SUPER_ADMIN_UID");

export function requireUid(request: {auth?: {uid: string} | null}): string {
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Sign in is required.");
  return userId;
}

export async function requireStaff(uid: string): Promise<FirebaseFirestore.DocumentData> {
  const user = await getFirestore().collection("users").doc(uid).get();
  const profile = user.data() ?? {};
  const legacyRole = String(profile.role ?? "").toLowerCase();
  const accessRole = String(profile.accessRole ??
    (legacyRole === "admin" || legacyRole === "counselor" ? legacyRole : "appUser"));
  if (!["portalStaff", "counselor", "admin"].includes(accessRole)) {
    throw new HttpsError("permission-denied", "Staff access is required.");
  }
  // New PACC access requests must pass all three gates.  Older privileged
  // records remain readable while they are migrated, but no newly registered
  // staff account can reach protected functions until verification is synced.
  if (accessRole !== "admin" && profile.staffAccountStatus != null) {
    const authUser = await getAuth().getUser(uid);
    if (profile.staffAccountStatus !== "approved" ||
        profile.accountStatus !== "active" ||
        !authUser.emailVerified) {
      throw new HttpsError("permission-denied", "Your PACC portal access is not active.");
    }
  }
  return {...profile, accessRole};
}

export function configuredSuperAdminUid(): string {
  const value = superAdminUid.value().trim();
  if (!value) throw new HttpsError("failed-precondition", "SUPER_ADMIN_UID is not configured.");
  return value;
}

export async function requireAdmin(uid: string): Promise<FirebaseFirestore.DocumentData> {
  if (uid !== configuredSuperAdminUid()) {
    throw new HttpsError("permission-denied", "Super-administrator access is required.");
  }
  const actor = await requireStaff(uid);
  if (actor.accessRole !== "admin") {
    throw new HttpsError("permission-denied", "The configured account is not an administrator.");
  }
  await getFirestore().collection("system_config").doc("security").set(
    {superAdminUid: uid, updatedAt: FieldValue.serverTimestamp()}, {merge: true},
  );
  return actor;
}

export const requireSuperAdmin = requireAdmin;

/** accessRole, falling back to the legacy role field, trimmed. */
export function roleOf(data: FirebaseFirestore.DocumentData): string {
  return String(data?.accessRole ?? data?.role ?? "").trim();
}

export async function requireClinical(uid: string): Promise<FirebaseFirestore.DocumentData> {
  const snapshot = await getFirestore().collection("users").doc(uid).get();
  const data = snapshot.data() ?? {};
  const role = roleOf(data);
  if (role !== "counselor" && role !== "admin") {
    throw new HttpsError("permission-denied", "Counselor or administrator access is required.");
  }
  return data;
}

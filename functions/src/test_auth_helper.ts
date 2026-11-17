import {getAuth} from "firebase-admin/auth";

/**
 * Ensures an Auth emulator user exists with the given verification status so
 * staff-gated callable tests exercise role/authorization logic rather than
 * failing on an absent Auth record.
 */
export async function ensureAuthUser(uid: string, emailVerified = true): Promise<void> {
  if (!uid) return;
  const auth = getAuth();
  try {
    await auth.updateUser(uid, {emailVerified, disabled: false});
  } catch (error) {
    if ((error as {code?: string})?.code === "auth/user-not-found") {
      const safeLocal = uid.replace(/[^a-zA-Z0-9._-]/g, "_").toLowerCase();
      await auth.createUser({
        uid,
        email: `${safeLocal}@example.invalid`,
        emailVerified,
        disabled: false,
      });
      return;
    }
    throw error;
  }
}

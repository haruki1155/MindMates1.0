import {getAuth} from "firebase-admin/auth";

// Test support only. Since PR #46, functions/src/access.ts::requireStaff also
// requires an enabled, email-verified Firebase Auth user for every portal
// account. Emulator suites that create staff profiles must therefore create
// the matching Auth user too. This refuses to run outside the Auth emulator so
// a misconfigured test can never create users in a real project.
export async function ensureVerifiedAuthUser(uid: string): Promise<void> {
  if (!process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error("ensureVerifiedAuthUser requires the Firebase Auth emulator (FIREBASE_AUTH_EMULATOR_HOST).");
  }
  try {
    await getAuth().createUser({uid, email: `${uid}@example.invalid`, emailVerified: true});
  } catch (error: unknown) {
    const code = (error as {code?: string; errorInfo?: {code?: string}})?.errorInfo?.code ?? (error as {code?: string})?.code;
    if (code !== "auth/uid-already-exists" && code !== "auth/email-already-exists") throw error;
  }
}

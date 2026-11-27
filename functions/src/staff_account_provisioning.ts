import {randomInt, randomUUID} from "node:crypto";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {error as logError} from "firebase-functions/logger";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {
  accountEmailTransporter,
  brandedEmailShell,
  escapeHtml,
  normalizeRecoveryEmail,
  resolveStaffVerificationWebUrl,
  smtpAppPassword,
  smtpSender,
} from "./account_recovery";
import {requireSuperAdmin, requireUid} from "./access";
import {actorName, AUDIT_CATEGORIES, writeAudit} from "./audit";

if (!getApps().length) initializeApp();

export const STAFF_PROVISION_ROLES = ["counselor", "portalStaff"] as const;
export type StaffProvisionRole = typeof STAFF_PROVISION_ROLES[number];

const UPPER = "ABCDEFGHJKLMNPQRSTUVWXYZ";
const LOWER = "abcdefghijkmnopqrstuvwxyz";
const DIGITS = "23456789";
const SYMBOLS = "!@#$%&*?";
const ALL_CHARS = UPPER + LOWER + DIGITS + SYMBOLS;
const TEMP_PASSWORD_LENGTH = 14;

/** Generates a 14-character temporary password containing uppercase, lowercase, digit, and symbol characters. */
export function generateStaffTemporaryPassword(): string {
  const chars = [
    UPPER[randomInt(UPPER.length)],
    LOWER[randomInt(LOWER.length)],
    DIGITS[randomInt(DIGITS.length)],
    SYMBOLS[randomInt(SYMBOLS.length)],
  ];
  while (chars.length < TEMP_PASSWORD_LENGTH) {
    chars.push(ALL_CHARS[randomInt(ALL_CHARS.length)]);
  }
  for (let i = chars.length - 1; i > 0; i--) {
    const j = randomInt(i + 1);
    const tmp = chars[i];
    chars[i] = chars[j];
    chars[j] = tmp;
  }
  return chars.join("");
}

function optionalNamePart(value: unknown, label: string): string {
  if (value == null) return "";
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${label} must be text.`);
  }
  const trimmed = value.trim();
  if (trimmed.length > 80) {
    throw new HttpsError("invalid-argument", `${label} is too long.`);
  }
  return trimmed;
}

export type ProvisioningDeps = {
  requireSuperAdmin: (uid: string) => Promise<FirebaseFirestore.DocumentData>;
  findAuthUidByEmail: (email: string) => Promise<string | null>;
  hasFirestoreEmail: (email: string) => Promise<boolean>;
  createAuthUser: (input: {email: string; password: string; displayName?: string}) => Promise<{uid: string}>;
  deleteAuthUser: (uid: string) => Promise<void>;
  writeStaffProfileAndAudit: (input: {
    uid: string;
    email: string;
    firstName: string;
    lastName: string;
    displayName: string;
    role: StaffProvisionRole;
    roleLabel: string;
    position: string;
    actorId: string;
    actorDisplayName: string;
    actorRole: string;
  }) => Promise<void>;
  deleteUserProfile: (uid: string) => Promise<void>;
  generatePassword: () => string;
  sendMail: (message: {to: string; subject: string; text: string; html: string}) => Promise<void>;
  portalUrl: () => string;
};

function defaultDeps(): ProvisioningDeps {
  const db = getFirestore();
  return {
    requireSuperAdmin,
    findAuthUidByEmail: async (email) => {
      try {
        const existing = await getAuth().getUserByEmail(email);
        return existing.uid;
      } catch (error) {
        if ((error as {code?: string})?.code === "auth/user-not-found") return null;
        throw error;
      }
    },
    hasFirestoreEmail: async (email) => {
      const snap = await db.collection("users").where("email", "==", email).limit(1).get();
      return !snap.empty;
    },
    createAuthUser: ({email, password, displayName}) =>
      getAuth().createUser({
        email,
        password,
        emailVerified: true,
        disabled: false,
        ...(displayName ? {displayName} : {}),
      }),
    deleteAuthUser: (uid) => getAuth().deleteUser(uid),
    writeStaffProfileAndAudit: async (input) => {
      await db.runTransaction(async (transaction) => {
        const userRef = db.collection("users").doc(input.uid);
        const existing = await transaction.get(userRef);
        if (existing.exists) {
          throw new HttpsError("already-exists", "An account profile already exists.");
        }
        transaction.create(userRef, {
          id: input.uid,
          email: input.email,
          firstName: input.firstName,
          lastName: input.lastName,
          name: input.displayName,
          position: input.position,
          office: "PACC / Guidance Office",
          populationRole: "nonTeaching",
          declaredRole: "nonTeaching",
          role: input.role === "counselor" ? "counselor" : "staff",
          accessRole: input.role,
          approvedRole: input.role,
          staffAccountStatus: "approved",
          verificationStatus: "verified",
          registrationStatus: "approved",
          accountStatus: "active",
          mustChangePassword: true,
          createdByAdminId: input.actorId,
          profileVersion: 3,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        writeAudit(transaction, db, {
          actorId: input.actorId,
          actorNameSnapshot: input.actorDisplayName,
          actorRoleSnapshot: input.actorRole,
          action: "STAFF_ACCOUNT_CREATED_BY_ADMIN",
          category: AUDIT_CATEGORIES.userManagement,
          targetType: "staff",
          targetId: input.uid,
          metadata: {
            email: input.email,
            role: input.role,
            roleLabel: input.roleLabel,
            createdBy: input.actorId,
          },
        });
      });
    },
    deleteUserProfile: (uid) => db.collection("users").doc(uid).delete().then(() => undefined),
    generatePassword: generateStaffTemporaryPassword,
    sendMail: async (message) => {
      await accountEmailTransporter().sendMail({
        from: `MindMate <${smtpSender.value().trim()}>`,
        ...message,
      });
    },
    portalUrl: () => resolveStaffVerificationWebUrl(),
  };
}

export async function createStaffAccountByAdminHandler(
  request: {auth?: {uid: string} | null; data?: unknown},
  deps: ProvisioningDeps = defaultDeps(),
) {
  const actorId = requireUid(request);
  const actor = await deps.requireSuperAdmin(actorId);

  const raw = request.data && typeof request.data === "object"
    ? request.data as Record<string, unknown>
    : {};
  const email = normalizeRecoveryEmail(raw.email);
  const roleValue = String(raw.role ?? "").trim();
  if (!STAFF_PROVISION_ROLES.includes(roleValue as StaffProvisionRole)) {
    throw new HttpsError("invalid-argument", "Choose Counselor or Portal Staff.");
  }
  const role = roleValue as StaffProvisionRole;
  const roleLabel = role === "counselor" ? "Counselor" : "Portal Staff";
  const position = role === "counselor" ? "Guidance Counselor" : "PACC Staff";

  const firstName = optionalNamePart(raw.firstName, "First name");
  const lastName = optionalNamePart(raw.lastName, "Last name");
  const fullName = [firstName, lastName].filter(Boolean).join(" ").trim();
  const displayName = fullName || email;

  const [existingUid, existingProfile] = await Promise.all([
    deps.findAuthUidByEmail(email),
    deps.hasFirestoreEmail(email),
  ]);
  if (existingUid || existingProfile) {
    throw new HttpsError("already-exists", "An account with this email address already exists.");
  }

  const temporaryPassword = deps.generatePassword();
  const created = await deps.createAuthUser({
    email,
    password: temporaryPassword,
    ...(fullName ? {displayName: fullName} : {}),
  });

  try {
    await deps.writeStaffProfileAndAudit({
      uid: created.uid,
      email,
      firstName,
      lastName,
      displayName,
      role,
      roleLabel,
      position,
      actorId,
      actorDisplayName: actorName(actor),
      actorRole: String(actor.accessRole ?? "admin"),
    });
  } catch (error) {
    await deps.deleteAuthUser(created.uid).catch(() => undefined);
    throw error;
  }

  const signInUrl = deps.portalUrl();
  const safeName = escapeHtml(fullName || "there");
  const safeEmail = escapeHtml(email);
  const safeRole = escapeHtml(roleLabel);
  const safePassword = escapeHtml(temporaryPassword);

  try {
    await deps.sendMail({
      to: email,
      subject: "Your MindMate PACC Portal Account",
      text: [
        "MindMate — PACC Portal Account Created",
        "",
        `Hello ${fullName || "there"},`,
        "",
        `A MindMate Administrator created a ${roleLabel} account for you.`,
        `Sign in at: ${signInUrl}`,
        `Email: ${email}`,
        `Temporary password: ${temporaryPassword}`,
        "",
        "For your security, you will be required to change this temporary password upon your first login.",
      ].join("\n"),
      html: brandedEmailShell({
        heading: "Your PACC Portal Account",
        body: `<p>Hello ${safeName},</p>`
          + `<p>A MindMate Administrator has created a <strong>${safeRole}</strong> account for you.</p>`
          + `<div style="background:#f6f5f1;border:1px solid #e5e2da;border-radius:10px;padding:16px;margin:18px 0">`
          + `<p style="margin:0 0 8px"><strong>Email:</strong> ${safeEmail}</p>`
          + `<p style="margin:0 0 8px"><strong>Assigned Role:</strong> ${safeRole}</p>`
          + `<p style="margin:0"><strong>Temporary Password:</strong> `
          + `<span style="font-family:monospace;font-size:16px;font-weight:700;background:#ffffff;padding:3px 8px;border-radius:6px;border:1px solid #dcd8cf">${safePassword}</span></p>`
          + `</div>`
          + `<p>Sign in with these credentials. Upon first login, you will be asked to choose your own permanent password.</p>`,
        actionLabel: "Sign in to MindMate Portal",
        actionUrl: signInUrl,
        footer: "MindMate · Counseling Management System",
      }),
    });
  } catch (error) {
    const correlationId = randomUUID();
    logError("Staff provisioning credential email failed", {
      correlationId,
      uid: created.uid,
      role,
      error: error instanceof Error ? error.message : String(error),
    });
    await deps.deleteUserProfile(created.uid).catch(() => undefined);
    await deps.deleteAuthUser(created.uid).catch(() => undefined);
    throw new HttpsError(
      "unavailable",
      "We could not send the temporary password email, so the account was not created. Please check email delivery settings and try again.",
      {correlationId},
    );
  }

  return {
    ok: true as const,
    uid: created.uid,
    email,
    role,
    roleLabel,
  };
}

export const createStaffAccountByAdmin = onCall(
  {secrets: [smtpAppPassword]},
  (request) => createStaffAccountByAdminHandler(request),
);

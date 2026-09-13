import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {createHash, randomUUID} from "node:crypto";
import nodemailer from "nodemailer";
import {error as logError} from "firebase-functions/logger";
import {defineSecret, defineString} from "firebase-functions/params";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";

if (!getApps().length) initializeApp();

const db = getFirestore();
const smtpAppPassword = defineSecret("SMTP_APP_PASSWORD");
const adminWebUrl = defineString("ADMIN_WEB_URL", {
  default: "https://mindmate-admin-staging.vercel.app",
});
const smtpHost = defineString("SMTP_HOST", {default: "smtp.gmail.com"});
const smtpPort = defineString("SMTP_PORT", {default: "587"});
const smtpUsername = defineString("SMTP_USERNAME", {
  default: "dev.guntang@gmail.com",
});
const smtpSender = defineString("SMTP_SENDER", {
  default: "dev.guntang@gmail.com",
});

const RESET_WINDOW_MS = 15 * 60 * 1000;
const RESET_EMAIL_LIMIT = 3;
const RESET_IP_LIMIT = 12;
const resetLimits = db.collection("_password_reset_limits");
const VERIFICATION_EMAIL_LIMIT = 3;
const verificationLimits = db.collection("_email_verification_limits");

export function authEmailForSchoolId(schoolId: string): string {
  const normalized = schoolId.trim().toLowerCase()
    .replace(/[^a-z0-9]+/g, ".")
    .replace(/\.+/g, ".")
    .replace(/^\.|\.$/g, "");
  if (!normalized) {
    throw new HttpsError("invalid-argument", "Enter a valid School ID.");
  }
  return `${normalized}@mindmate.local`;
}

export function canonicalLoginId(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "Enter a valid School ID.");
  }
  const canonical = value.trim().toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (canonical.length < 3 || canonical.length > 40) {
    throw new HttpsError("invalid-argument", "Enter a valid School ID.");
  }
  return canonical;
}

async function resolveSchoolIdAuthEmailHandler(request: CallableRequest) {
  const rawSchoolId = request.data?.schoolId;
  const canonical = canonicalLoginId(rawSchoolId);
  const entered = String(rawSchoolId).trim();

  // Student and employee IDs are reserved during profile provisioning. Using
  // these server-only indexes also makes this work for accounts created before
  // School-ID sign-in was introduced.
  const [studentReservation, employeeReservation] = await Promise.all([
    db.collection("student_id_reservations").doc(canonical).get(),
    db.collection("employee_id_reservations").doc(canonical).get(),
  ]);
  const reservation = studentReservation.exists
    ? studentReservation
    : employeeReservation.exists
      ? employeeReservation
      : null;
  let userId = reservation?.data()?.userId;

  // Older profiles may predate the reservation collections. Fall back to the
  // protected profile data so already-registered users are not locked out.
  if (typeof userId !== "string" || userId.length === 0) {
    const candidateValues = [...new Set([entered, canonical])];
    const profileQueries = candidateValues.flatMap((value) => [
      db.collection("users").where("schoolId", "==", value).limit(1).get(),
      db.collection("users").where("employeeId", "==", value).limit(1).get(),
    ]);
    const profileResults = await Promise.all(profileQueries);
    const matchedProfile = profileResults.find((result) => !result.empty);
    userId = matchedProfile?.docs[0]?.id;
  }

  if (typeof userId === "string" && userId.length > 0) {
    const user = await getAuth().getUser(userId);
    if (user.email) return {email: user.email};
  }

  // Retain support for legacy accounts whose Firebase credential was created
  // directly from the School ID but whose profile was never provisioned.
  try {
    const legacy = await getAuth().getUserByEmail(
      authEmailForSchoolId(String(rawSchoolId)),
    );
    if (legacy.email) return {email: legacy.email};
  } catch (error: unknown) {
    const code = (error as {code?: string})?.code;
    if (code !== "auth/user-not-found") throw error;
  }

  // Keep the response generic so callers cannot distinguish an unknown ID
  // from another invalid credential using the message alone.
  throw new HttpsError("not-found", "School ID or password is incorrect.");
}

export function normalizeRecoveryEmail(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "Enter a valid email address.");
  }
  const email = value.trim().toLowerCase();
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpsError("invalid-argument", "Enter a valid email address.");
  }
  return email;
}

function digest(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function requestIp(request: CallableRequest): string {
  return request.rawRequest.ip || request.rawRequest.socket.remoteAddress || "unknown";
}

async function enforcePasswordResetRateLimit(email: string, ip: string): Promise<void> {
  const emailRef = resetLimits.doc(`email_${digest(email)}`);
  const ipRef = resetLimits.doc(`ip_${digest(ip)}`);
  const now = Date.now();

  await db.runTransaction(async (transaction) => {
    const [emailSnapshot, ipSnapshot] = await Promise.all([
      transaction.get(emailRef),
      transaction.get(ipRef),
    ]);

    const nextValue = (
      snapshot: FirebaseFirestore.DocumentSnapshot,
      limit: number,
    ): {startedAt: Timestamp; count: number; expiresAt: Timestamp} => {
      const previousStart = snapshot.data()?.startedAt instanceof Timestamp ?
        snapshot.data()!.startedAt.toMillis() : 0;
      const inWindow = now - previousStart < RESET_WINDOW_MS;
      const count = inWindow ? Number(snapshot.data()?.count ?? 0) : 0;
      if (count >= limit) {
        throw new HttpsError(
          "resource-exhausted",
          "Too many reset requests. Please wait 15 minutes and try again.",
        );
      }
      const startedAt = inWindow ? previousStart : now;
      return {
        startedAt: Timestamp.fromMillis(startedAt),
        count: count + 1,
        expiresAt: Timestamp.fromMillis(startedAt + RESET_WINDOW_MS * 2),
      };
    };

    transaction.set(emailRef, {
      ...nextValue(emailSnapshot, RESET_EMAIL_LIMIT),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(ipRef, {
      ...nextValue(ipSnapshot, RESET_IP_LIMIT),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

export function directPasswordResetLink(firebaseLink: string, webBaseUrl: string): string {
  return directEmailActionLink(firebaseLink, webBaseUrl, "/__/auth/action");
}

export function directEmailActionLink(
  firebaseLink: string,
  webBaseUrl: string,
  actionPath = "/verify-email",
): string {
  const source = new URL(firebaseLink);
  const destination = new URL(actionPath, webBaseUrl);
  source.searchParams.forEach((value, key) => destination.searchParams.set(key, value));
  return destination.toString();
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>'"]/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "'": "&#39;",
    "\"": "&quot;",
  })[character] ?? character);
}

function accountEmailTransporter() {
  return nodemailer.createTransport({
    host: smtpHost.value().trim(),
    port: Number(smtpPort.value()),
    secure: false,
    requireTLS: true,
    auth: {user: smtpUsername.value().trim(), pass: smtpAppPassword.value()},
    tls: {minVersion: "TLSv1.2"},
  });
}

function brandedEmailShell({
  heading,
  body,
  actionLabel,
  actionUrl,
  footer,
}: {
  heading: string;
  body: string;
  actionLabel: string;
  actionUrl: string;
  footer: string;
}): string {
  return `<!doctype html>
<html><body style="margin:0;background:#f6f5f1;font-family:Arial,Helvetica,sans-serif;color:#242424">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f6f5f1"><tr><td style="padding:32px 16px">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;margin:auto;background:#ffffff;border:1px solid #e5e2da;border-radius:14px">
      <tr><td style="padding:32px 36px 12px;text-align:center">
        <div style="display:inline-block;background:#fff1b0;border-radius:12px;padding:10px 13px;font-size:22px;line-height:22px">&#128161;</div>
        <div style="margin-top:12px;font-size:22px;font-weight:700">MindMate</div>
        <div style="margin-top:4px;color:#6d6b66;font-size:12px;letter-spacing:.4px">COUNSELING MANAGEMENT SYSTEM</div>
      </td></tr>
      <tr><td style="padding:20px 36px 8px">
        <h1 style="margin:0 0 16px;font-size:25px;line-height:1.25;text-align:center">${heading}</h1>
        <div style="color:#56534e;font-size:16px;line-height:1.55">${body}</div>
      </td></tr>
      <tr><td style="padding:24px 36px;text-align:center">
        <a href="${escapeHtml(actionUrl)}" style="display:inline-block;background:#242424;color:#ffffff;text-decoration:none;padding:14px 22px;border-radius:8px;font-size:16px;font-weight:700">${actionLabel}</a>
      </td></tr>
      <tr><td style="padding:0 36px 30px;color:#77736d;font-size:12px;line-height:1.5">
        <p style="margin:0 0 14px">Having trouble with the button? Copy and paste this link into your browser:</p>
        <p style="margin:0;word-break:break-all"><a href="${escapeHtml(actionUrl)}" style="color:#56534e">${escapeHtml(actionUrl)}</a></p>
        <hr style="border:0;border-top:1px solid #ece9e2;margin:24px 0 14px" />
        <p style="margin:0">${footer}</p>
        <p style="margin:8px 0 0">This is an automated security email. Please do not reply.</p>
      </td></tr>
    </table>
  </td></tr></table>
</body></html>`;
}

async function enforceVerificationRateLimit(userId: string, ip: string): Promise<void> {
  const userRef = verificationLimits.doc(`user_${digest(userId)}`);
  const ipRef = verificationLimits.doc(`ip_${digest(ip)}`);
  const now = Date.now();
  await db.runTransaction(async (transaction) => {
    const [userSnapshot, ipSnapshot] = await Promise.all([
      transaction.get(userRef), transaction.get(ipRef),
    ]);
    const nextValue = (snapshot: FirebaseFirestore.DocumentSnapshot, limit: number) => {
      const previous = snapshot.data()?.startedAt instanceof Timestamp ?
        snapshot.data()!.startedAt.toMillis() : 0;
      const inWindow = now - previous < RESET_WINDOW_MS;
      const count = inWindow ? Number(snapshot.data()?.count ?? 0) : 0;
      if (count >= limit) {
        throw new HttpsError("resource-exhausted", "Too many verification emails were requested. Please wait 15 minutes and try again.");
      }
      const startedAt = inWindow ? previous : now;
      return {startedAt: Timestamp.fromMillis(startedAt), count: count + 1,
        expiresAt: Timestamp.fromMillis(startedAt + RESET_WINDOW_MS * 2), updatedAt: FieldValue.serverTimestamp()};
    };
    transaction.set(userRef, nextValue(userSnapshot, VERIFICATION_EMAIL_LIMIT));
    transaction.set(ipRef, nextValue(ipSnapshot, RESET_IP_LIMIT));
  });
}

async function requestStaffEmailVerificationHandler(request: CallableRequest) {
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Sign in is required.");
  const [authUser, profile] = await Promise.all([
    getAuth().getUser(userId), db.collection("users").doc(userId).get(),
  ]);
  if (!profile.exists || profile.data()?.staffAccountStatus == null) {
    throw new HttpsError("not-found", "PAACC access request not found.");
  }
  if (authUser.emailVerified) return {alreadyVerified: true};
  const email = authUser.email;
  if (!email) throw new HttpsError("failed-precondition", "This account does not have an email address.");
  await enforceVerificationRateLimit(userId, requestIp(request));
  const firebaseLink = await getAuth().generateEmailVerificationLink(email, {
    url: `${adminWebUrl.value().replace(/\/$/, "")}/verify-email`,
  });
  const verificationLink = directEmailActionLink(firebaseLink, adminWebUrl.value());
  const name = String(profile.data()?.firstName ?? profile.data()?.name ?? "there").trim();
  const safeName = escapeHtml(name || "there");
  const safeEmail = escapeHtml(email);
  try {
    await accountEmailTransporter().sendMail({
      from: `MindMate <${smtpSender.value().trim()}>`,
      to: email,
      subject: "Verify your MindMate PAACC Portal email",
      text: [
        "MindMate — Verify your email",
        "",
        `Hello ${name || "there"},`,
        "",
        "You requested access to the MindMate PAACC Portal.",
        `Verify that ${email} belongs to you using this secure link:`,
        verificationLink,
        "",
        "After verification, your request will be sent for administrator review.",
        "If you did not request this account, you can safely ignore this email.",
      ].join("\n"),
      html: brandedEmailShell({
        heading: "Verify your email address",
        body: `<p>Hello ${safeName},</p><p>Thanks for requesting access to the MindMate PAACC Portal.</p><p>Please verify that <strong>${safeEmail}</strong> belongs to you before your access request can be reviewed.</p><p>After verification, your request will be sent to a MindMate administrator for review.</p><p>If you did not request access to MindMate, you can safely ignore this email.</p>`,
        actionLabel: "Verify email address",
        actionUrl: verificationLink,
        footer: "MindMate · Counseling Management System",
      }),
    });
  } catch (error) {
    const correlationId = randomUUID();
    logError("Staff verification email delivery failed", {correlationId,
      error: error instanceof Error ? error.message : String(error)});
    throw new HttpsError("unavailable", "The verification email could not be delivered. Please try again shortly.", {correlationId});
  }
  return {accepted: true};
}

async function requestAdminPasswordResetHandler(request: CallableRequest) {
  const email = normalizeRecoveryEmail(request.data?.email);
  await enforcePasswordResetRateLimit(email, requestIp(request));

  let firebaseLink: string;
  try {
    firebaseLink = await getAuth().generatePasswordResetLink(email, {
      url: `${adminWebUrl.value().replace(/\/$/, "")}/`,
    });
  } catch (error: unknown) {
    if ((error as {code?: string})?.code === "auth/user-not-found") {
      return {accepted: true};
    }
    throw error;
  }

  const resetLink = directPasswordResetLink(firebaseLink, adminWebUrl.value());
  const sender = smtpSender.value().trim();
  const safeEmail = escapeHtml(email);
  try {
    await accountEmailTransporter().sendMail({
      from: `MindMate <${sender}>`,
      to: email,
      subject: "Reset your MindMate Admin password",
      text: [
        "A password reset was requested for your MindMate Admin account.",
        "",
        `Reset your password: ${resetLink}`,
        "",
        "This secure link expires automatically. If you did not request this, ignore this email.",
      ].join("\n"),
      html: brandedEmailShell({
        heading: "Reset your MindMate password",
        body: `<p>A password reset was requested for <strong>${safeEmail}</strong>.</p><p>This secure link expires automatically. If you did not request this, you can safely ignore this email.</p>`,
        actionLabel: "Choose a new password",
        actionUrl: resetLink,
        footer: "MindMate · Counseling Management System",
      }),
    });
  } catch (error) {
    const correlationId = randomUUID();
    logError("Admin password reset email delivery failed", {
      correlationId,
      error: error instanceof Error ? error.message : String(error),
    });
    throw new HttpsError(
      "unavailable",
      "The reset email could not be delivered. Please try again shortly.",
      {correlationId},
    );
  }

  return {accepted: true};
}

export const resolveSchoolIdAuthEmail = onCall(
  {enforceAppCheck: true},
  resolveSchoolIdAuthEmailHandler,
);

export const resolveSchoolIdAuthEmailDev = onCall(
  {enforceAppCheck: false},
  resolveSchoolIdAuthEmailHandler,
);

export const requestAdminPasswordReset = onCall(
  {enforceAppCheck: true, secrets: [smtpAppPassword]},
  requestAdminPasswordResetHandler,
);

export const requestAdminPasswordResetDev = onCall(
  {enforceAppCheck: false, secrets: [smtpAppPassword]},
  requestAdminPasswordResetHandler,
);

export const requestStaffEmailVerification = onCall(
  {enforceAppCheck: true, secrets: [smtpAppPassword]},
  requestStaffEmailVerificationHandler,
);

export const requestStaffEmailVerificationDev = onCall(
  {enforceAppCheck: false, secrets: [smtpAppPassword]},
  requestStaffEmailVerificationHandler,
);

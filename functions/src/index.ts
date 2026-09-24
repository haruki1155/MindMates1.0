import {getApps, initializeApp} from "firebase-admin/app";
import {FieldPath, FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {getAuth} from "firebase-admin/auth";
import {getDownloadURL, getStorage} from "firebase-admin/storage";
import {onDocumentCreated, onDocumentDeleted, onDocumentUpdated, onDocumentWritten} from "firebase-functions/v2/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
export {
  submitQuickAssessment,
  submitQuickAssessmentDev,
  submitFullAssessment,
  submitFullAssessmentDev,
} from "./assessment/submissions";
export {
  provisionAppUserProfile,
  provisionAppUserProfileDev,
  getAssessmentStatus,
  getAssessmentStatusDev,
} from "./account_integrity";
export {
  resolveSchoolIdAuthEmail,
  resolveSchoolIdAuthEmailDev,
  requestAdminPasswordReset,
  requestAdminPasswordResetDev,
  requestStaffEmailVerification,
  requestStaffEmailVerificationDev,
} from "./account_recovery";
import {defineString} from "firebase-functions/params";
import {randomBytes} from "node:crypto";
import {AUDIT_ACTIONS, AUDIT_CATEGORIES, actorName, writeAudit} from "./audit";
import {
  AppointmentSchedulingValidationError,
  formatAppointmentTime,
  validateAppointmentTimestamp,
} from "./appointment_scheduling";
import {
  AppointmentAvailabilityValidationError,
  canManagePaccAvailability,
  validatePaccAppointmentAvailability,
  validatePaccAvailabilityPayload,
} from "./appointment_availability";
import {
  APPOINTMENT_ACTIVE_STATUSES,
  canTransitionAppointment,
  canonicalAppointmentStatus,
} from "./appointment_lifecycle";
import {appointmentBookingPolicy, bookingPolicyViolation} from "./appointment_policy";
import {appointmentEmail, appointmentPhone, boundedText} from "./appointment_intake";
export {
  aggregateMindAidFeedback,
  sendMindAidMessage,
  sendMindAidMessageDev,
} from "./mind_aid";
export {getReportAnalytics} from "./report_generation";
export {
  importWalkInAppointments,
  listWalkInImports,
  deleteWalkInImport,
  archiveWalkInImport,
} from "./walk_in_import";
export {
  getCounselingPopulation,
  saveCounselingPopulation,
  getAcademicYears,
  createAcademicYear,
  closeAcademicYear,
} from "./counseling_population";

if (!getApps().length) initializeApp();

const db = getFirestore();
const superAdminUid = defineString("SUPER_ADMIN_UID");
const posts = db.collection("secret_chats");
const stats = db.collection("secret_chat_profile_stats");
const events = db.collection("_secret_chat_events");
const analyticsEvents = db.collection("_analytics_events");
const secretChatProfiles = db.collection("secret_chat_profiles");
const secretChatAliases = db.collection("secret_chat_aliases");
const publicUserIds = db.collection("user_public_ids");
const publicUserIdReservations = db.collection("public_user_id_reservations");
const portalAppointmentQueue = db.collection("appointment_queue");

const SECRET_CHAT_ALIAS_PATTERN = /^[A-Za-z0-9]+(?: [A-Za-z0-9]+)*$/;
const SECRET_CHAT_PHOTO_PATTERN = /^secret_chat_profiles\/([^/]+)\/avatar_[0-9]+\.(jpg|png)$/;
const MAX_SECRET_CHAT_PHOTO_BYTES = 5 * 1024 * 1024;

function requireAuthenticatedUser(request: {auth?: {uid: string}}): string {
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Sign in is required.");
  return userId;
}

export function normalizeSecretChatAlias(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "A public name is required.");
  }
  const alias = value.trim().replace(/\s+/g, " ");
  if (alias.length < 1 || alias.length > 30 || !SECRET_CHAT_ALIAS_PATTERN.test(alias)) {
    throw new HttpsError(
      "invalid-argument",
      "Use 1 to 30 letters, numbers, and single spaces only.",
    );
  }
  return alias;
}

export function isValidSecretChatPhotoPath(userId: string, photoPath: string): boolean {
  const match = SECRET_CHAT_PHOTO_PATTERN.exec(photoPath);
  return match !== null && match[1] === userId;
}

function callableProfile(
  snapshot: FirebaseFirestore.DocumentSnapshot,
): Record<string, unknown> {
  const profile = snapshot.data() ?? {};
  const timestamp = profile.updatedAt;
  return {
    userId: snapshot.id,
    alias: String(profile.alias ?? "Anonymous"),
    aliasKey: String(profile.aliasKey ?? ""),
    ...(typeof profile.photoUrl === "string" ? {photoUrl: profile.photoUrl} : {}),
    ...(typeof profile.photoPath === "string" ? {photoPath: profile.photoPath} : {}),
    ...(timestamp instanceof Timestamp ? {updatedAt: timestamp.toDate().toISOString()} : {}),
  };
}

export const saveSecretChatProfile = onCall(async (request) => {
  const userId = requireAuthenticatedUser(request);
  const alias = normalizeSecretChatAlias(request.data?.alias);
  const aliasKey = alias.toLowerCase();
  const profileRef = secretChatProfiles.doc(userId);
  const aliasRef = secretChatAliases.doc(aliasKey);

  await db.runTransaction(async (transaction) => {
    const profileSnapshot = await transaction.get(profileRef);
    const aliasSnapshot = await transaction.get(aliasRef);
    const previousKey = String(profileSnapshot.data()?.aliasKey ?? "");
    const previousAliasRef = previousKey && previousKey !== aliasKey ?
      secretChatAliases.doc(previousKey) : null;
    const previousAliasSnapshot = previousAliasRef ?
      await transaction.get(previousAliasRef) : null;

    if (aliasSnapshot.exists && aliasSnapshot.data()?.userId !== userId) {
      throw new HttpsError("already-exists", "That Secret Chat name is already taken.");
    }

    transaction.set(aliasRef, {
      userId,
      alias,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(profileRef, {
      userId,
      alias,
      aliasKey,
      createdAt: profileSnapshot.data()?.createdAt instanceof Timestamp ?
        profileSnapshot.data()?.createdAt : FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    if (previousAliasRef && previousAliasSnapshot?.data()?.userId === userId) {
      transaction.delete(previousAliasRef);
    }
  });

  return {profile: callableProfile(await profileRef.get())};
});

export const finalizeSecretChatProfilePhoto = onCall(async (request) => {
  const userId = requireAuthenticatedUser(request);
  const photoPath = typeof request.data?.photoPath === "string" ?
    request.data.photoPath : "";
  if (!isValidSecretChatPhotoPath(userId, photoPath)) {
    throw new HttpsError("invalid-argument", "The profile photo path is invalid.");
  }

  const file = getStorage().bucket().file(photoPath);
  const [exists] = await file.exists();
  if (!exists) throw new HttpsError("not-found", "The uploaded photo was not found.");
  const [metadata] = await file.getMetadata();
  const size = Number(metadata.size ?? 0);
  if (size < 1 || size > MAX_SECRET_CHAT_PHOTO_BYTES ||
      (metadata.contentType !== "image/jpeg" && metadata.contentType !== "image/png")) {
    throw new HttpsError("invalid-argument", "The uploaded photo is not a valid JPEG or PNG.");
  }

  const profileRef = secretChatProfiles.doc(userId);
  const before = await profileRef.get();
  if (!before.exists || typeof before.data()?.alias !== "string") {
    throw new HttpsError("failed-precondition", "Save a public name before adding a photo.");
  }
  const photoUrl = await getDownloadURL(file);
  await profileRef.set({
    photoUrl,
    photoPath,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  const previousPath = before.data()?.photoPath;
  if (typeof previousPath === "string" && previousPath !== photoPath) {
    await getStorage().bucket().file(previousPath).delete({ignoreNotFound: true}).catch(() => undefined);
  }
  return {profile: callableProfile(await profileRef.get())};
});

export const removeSecretChatProfilePhoto = onCall(async (request) => {
  const userId = requireAuthenticatedUser(request);
  const profileRef = secretChatProfiles.doc(userId);
  const before = await profileRef.get();
  if (!before.exists) {
    throw new HttpsError("not-found", "The Secret Chat profile was not found.");
  }
  await profileRef.set({
    photoUrl: FieldValue.delete(),
    photoPath: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  const previousPath = before.data()?.photoPath;
  if (typeof previousPath === "string") {
    await getStorage().bucket().file(previousPath).delete({ignoreNotFound: true}).catch(() => undefined);
  }
  return {profile: callableProfile(await profileRef.get())};
});

export const deleteSecretChatPost = onCall(async (request) => {
  const userId = requireAuthenticatedUser(request);
  const postId = typeof request.data?.postId === "string" ? request.data.postId.trim() : "";
  if (!postId || postId.length > 150 || postId.includes("/")) {
    throw new HttpsError("invalid-argument", "The Secret Chat post ID is invalid.");
  }

  const postRef = posts.doc(postId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(postRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "This Secret Chat post no longer exists.");
    }
    if (snapshot.data()?.authorId !== userId) {
      throw new HttpsError("permission-denied", "Only the post owner can delete it.");
    }
    transaction.update(postRef, {
      moderationStatus: "deleting",
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  const [commentsSnapshot, interactionsSnapshot] = await Promise.all([
    db.collection("secret_chat_comments").where("postId", "==", postId).get(),
    db.collection("secret_chat_interactions").where("postId", "==", postId).get(),
  ]);
  await postRef.delete();
  const writer = db.bulkWriter();
  for (const document of commentsSnapshot.docs) writer.delete(document.ref);
  for (const document of interactionsSnapshot.docs) writer.delete(document.ref);
  await writer.close();
  return {deleted: true, postId};
});

function manilaDateKey(date: Date): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Manila",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

async function requireStaff(uid: string): Promise<FirebaseFirestore.DocumentData> {
  const user = await db.collection("users").doc(uid).get();
  const profile = user.data() ?? {};
  const legacyRole = String(profile.role ?? "").toLowerCase();
  const accessRole = String(profile.accessRole ??
    (legacyRole === "admin" || legacyRole === "counselor" ? legacyRole : "appUser"));
  if (!["portalStaff", "counselor", "admin"].includes(accessRole)) {
    throw new HttpsError("permission-denied", "Staff access is required.");
  }
  // New PAACC access requests must pass all three gates.  Older privileged
  // records remain readable while they are migrated, but no newly registered
  // staff account can reach protected functions until verification is synced.
  if (accessRole !== "admin" && profile.staffAccountStatus != null) {
    const authUser = await getAuth().getUser(uid);
    if (profile.staffAccountStatus !== "approved" ||
        profile.accountStatus !== "active" ||
        !authUser.emailVerified) {
      throw new HttpsError("permission-denied", "Your PAACC portal access is not active.");
    }
  }
  return {...profile, accessRole};
}

function configuredSuperAdminUid(): string {
  const value = superAdminUid.value().trim();
  if (!value) throw new HttpsError("failed-precondition", "SUPER_ADMIN_UID is not configured.");
  return value;
}

async function requireSuperAdmin(uid: string): Promise<FirebaseFirestore.DocumentData> {
  if (uid !== configuredSuperAdminUid()) {
    throw new HttpsError("permission-denied", "Super-administrator access is required.");
  }
  const actor = await requireStaff(uid);
  if (actor.accessRole !== "admin") {
    throw new HttpsError("permission-denied", "The configured account is not an administrator.");
  }
  await db.collection("system_config").doc("security").set(
    {superAdminUid: uid, updatedAt: FieldValue.serverTimestamp()}, {merge: true},
  );
  return actor;
}

function normalizedEmployeeId(value: unknown): string {
  const employeeId = requiredText(value, "Employee ID", 3, 40).toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (employeeId.length < 3) throw new HttpsError("invalid-argument", "Enter a valid employee ID.");
  return employeeId;
}

const STAFF_ACCESS_ROLES = ["portalStaff", "counselor"] as const;
const STAFF_ACCOUNT_STATUSES = ["pending", "approved", "rejected", "disabled"] as const;

export const registerStaffAccount = onCall(async (request) => {
  const userId = requireAuthenticatedUser(request);
  const authUser = await getAuth().getUser(userId);
  const email = String(authUser.email ?? "").trim().toLowerCase();
  if (!email) throw new HttpsError("failed-precondition", "An email address is required.");
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    throw new HttpsError("invalid-argument", "Enter a valid email address.");
  }
  const employeeId = requiredText(request.data?.employeeId, "Employee ID", 3, 40);
  const employeeIdKey = normalizedEmployeeId(employeeId);
  const firstName = requiredText(request.data?.firstName, "First name", 1, 80);
  const lastName = requiredText(request.data?.lastName, "Last name", 1, 80);
  const position = requiredText(request.data?.position, "Position", 2, 100);
  const requestedRole = String(request.data?.requestedRole ?? "").trim();
  if (!STAFF_ACCESS_ROLES.includes(requestedRole as typeof STAFF_ACCESS_ROLES[number])) {
    throw new HttpsError("invalid-argument", "Choose PAACC Staff or Counselor.");
  }
  const userRef = db.collection("users").doc(userId);
  const reservationRef = db.collection("employee_id_reservations").doc(employeeIdKey);
  const requestRef = db.collection("staffAccessRequests").doc();

  await db.runTransaction(async (transaction) => {
    const [existing, reservation] = await Promise.all([
      transaction.get(userRef), transaction.get(reservationRef),
    ]);
    if (existing.exists) throw new HttpsError("already-exists", "An account profile already exists.");
    if (reservation.exists && reservation.data()?.userId !== userId) {
      throw new HttpsError("already-exists", "That employee ID is already registered.");
    }
    transaction.create(reservationRef, {userId, employeeId, createdAt: FieldValue.serverTimestamp()});
    transaction.create(userRef, {
      id: userId, email, firstName, lastName, name: `${firstName} ${lastName}`,
      employeeId, employeeIdKey, position, office: "PAACC / Guidance Office",
      populationRole: "nonTeaching", declaredRole: "nonTeaching", role: "staff",
      accessRole: "appUser", staffAccountStatus: "pending", verificationStatus: "pending",
      requestedRole, requestedAccessRole: requestedRole, approvedRole: null,
      accessRequestId: requestRef.id,
      registrationStatus: "email_verification_required", accountStatus: "pending",
      profileVersion: 3, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(requestRef, {
      requestId: requestRef.id, applicantUserId: userId, firstName, lastName,
      employeeId, email, position, office: "PAACC / Guidance Office", requestedRole,
      registrationStatus: "email_verification_required", submittedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    writeAudit(transaction, db, {actorId: userId, actorNameSnapshot: `${firstName} ${lastName}`,
      actorRoleSnapshot: "appUser", action: "STAFF_ACCESS_REQUEST_SUBMITTED",
      category: AUDIT_CATEGORIES.userManagement, targetType: "staff", targetId: userId,
      metadata: {after: {registrationStatus: "email_verification_required", requestedRole}, targetLabel: email}});
  });
  return {ok: true, requestId: requestRef.id, reference: `REQ-${requestRef.id.slice(0, 8).toUpperCase()}`};
});

// Firebase Auth is the authority for email ownership.  The browser calls this
// after a verification link is opened (and again on sign-in), allowing the
// portal profile to advance to admin review without trusting client data.
export const syncStaffEmailVerification = onCall(async (request) => {
  const userId = requireAuthenticatedUser(request);
  const authUser = await getAuth().getUser(userId);
  const target = db.collection("users").doc(userId);
  const profile = await target.get();
  if (!profile.exists || profile.data()?.staffAccountStatus == null) {
    throw new HttpsError("not-found", "PAACC access request not found.");
  }
  if (!authUser.emailVerified) {
    return {emailVerified: false, registrationStatus: "email_verification_required"};
  }
  let notify = false;
  let requestId = "";
  let applicantName = "";
  let requestedRole = "portalStaff";
  await db.runTransaction(async (transaction) => {
    const before = await transaction.get(target);
    const data = before.data() ?? {};
    requestId = String(data.accessRequestId ?? "");
    applicantName = String(data.name ?? `${data.firstName ?? ""} ${data.lastName ?? ""}`).trim();
    requestedRole = String(data.requestedRole ?? "portalStaff");
    const status = String(data.registrationStatus ?? "");
    if (status === "email_verification_required") {
      notify = true;
      transaction.update(target, {
        verificationStatus: "verified",
        emailVerifiedAt: FieldValue.serverTimestamp(),
        registrationStatus: "pending_admin_review",
        accountStatus: "pending",
        updatedAt: FieldValue.serverTimestamp(),
      });
      if (requestId) {
        transaction.set(db.collection("staffAccessRequests").doc(requestId), {
          emailVerifiedAt: FieldValue.serverTimestamp(),
          registrationStatus: "pending_admin_review",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }
      writeAudit(transaction, db, {actorId: userId, actorNameSnapshot: applicantName || "PAACC applicant",
        actorRoleSnapshot: "appUser", action: "STAFF_EMAIL_VERIFIED",
        category: AUDIT_CATEGORIES.userManagement, targetType: "staff", targetId: userId,
        metadata: {after: {registrationStatus: "pending_admin_review"}}});
    }
  });
  if (notify && requestId) {
    try {
      await notifyAccessRequestAdmins(requestId, applicantName || "A PAACC applicant", requestedRole);
    } catch (error) {
      console.warn("Email verification was saved but administrator notification delivery failed.", error);
    }
  }
  return {emailVerified: true, registrationStatus: notify ? "pending_admin_review" : String(profile.data()?.registrationStatus ?? "pending_admin_review")};
});

export const reviewStaffRegistration = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  const actor = await requireSuperAdmin(actorId);
  const targetUserId = requiredText(request.data?.userId, "User ID", 1, 128);
  const decision = String(request.data?.decision ?? (request.data?.approve === true ? "approve" : "reject"));
  const approve = decision === "approve";
  const moreInfo = decision === "more_information";
  const accessRole = String(request.data?.accessRole ?? "portalStaff");
  const reason = requiredText(request.data?.reason, "Reason", 3, 500);
  if (targetUserId === actorId) throw new HttpsError("permission-denied", "You cannot review yourself.");
  if ((approve || moreInfo) && !STAFF_ACCESS_ROLES.includes(accessRole as typeof STAFF_ACCESS_ROLES[number])) {
    throw new HttpsError("invalid-argument", "Choose Portal Staff or Counselor.");
  }
  const target = db.collection("users").doc(targetUserId);
  await db.runTransaction(async (transaction) => {
    const before = await transaction.get(target);
    if (!before.exists || !["pending_admin_review", "more_information_required"].includes(String(before.data()?.registrationStatus ?? "email_verification_required"))) {
      throw new HttpsError("failed-precondition", "This registration is no longer pending.");
    }
    if (approve) {
      const authUser = await getAuth().getUser(targetUserId);
      if (!authUser.emailVerified || before.data()?.emailVerifiedAt == null) {
        throw new HttpsError("failed-precondition", "The applicant must verify their email before approval.");
      }
    }
    const status = approve ? "approved" : moreInfo ? "more_information_required" : "rejected";
    transaction.update(target, {
      staffAccountStatus: approve ? "approved" : moreInfo ? "pending" : "rejected",
      accessRole: approve ? accessRole : "appUser", approvedRole: approve ? accessRole : null,
      registrationStatus: status, accountStatus: approve ? "active" : moreInfo ? "pending" : "disabled",
      verificationStatus: before.data()?.verificationStatus ?? "pending",
      approvedBy: approve ? actorId : null,
      approvedAt: approve ? FieldValue.serverTimestamp() : null,
      moreInformationReason: moreInfo ? reason : null, reviewReason: reason,
      updatedAt: FieldValue.serverTimestamp()});
    const requestId = String(before.data()?.accessRequestId ?? "");
    if (requestId) {
      transaction.set(db.collection("staffAccessRequests").doc(requestId), {
        registrationStatus: status, reviewedAt: FieldValue.serverTimestamp(), reviewedBy: actorId,
        approvedRole: approve ? accessRole : null, moreInformationReason: moreInfo ? reason : null,
        reviewReason: reason, updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    writeAudit(transaction, db, {actorId, actorNameSnapshot: actorName(actor), actorRoleSnapshot: actor.accessRole,
      action: approve ? "STAFF_ACCESS_REQUEST_APPROVED" : moreInfo ? "STAFF_ACCESS_REQUEST_MORE_INFO_REQUIRED" : "STAFF_REGISTRATION_REJECTED",
      category: AUDIT_CATEGORIES.userManagement, targetType: "staff", targetId: targetUserId,
      metadata: {before: {registrationStatus: before.data()?.registrationStatus ?? "pending_review", accessRole: "appUser"}, after: {registrationStatus: status, approvedRole: approve ? accessRole : null}, reason}});
    if (approve) {
      writeAudit(transaction, db, {actorId, actorNameSnapshot: actorName(actor), actorRoleSnapshot: actor.accessRole,
        action: "STAFF_ROLE_ASSIGNED", category: AUDIT_CATEGORIES.userManagement, targetType: "staff", targetId: targetUserId,
        metadata: {requestedRole: before.data()?.requestedRole ?? "", approvedRole: accessRole, reason}});
      writeAudit(transaction, db, {actorId, actorNameSnapshot: actorName(actor), actorRoleSnapshot: actor.accessRole,
        action: "STAFF_ACCOUNT_ACTIVATED", category: AUDIT_CATEGORIES.userManagement, targetType: "staff", targetId: targetUserId,
        metadata: {approvedRole: accessRole, reason}});
    }
  });
  if (!approve) await getAuth().revokeRefreshTokens(targetUserId);
  if (approve || moreInfo) {
    const targetProfile = await target.get();
    const targetData = targetProfile.data() ?? {};
    try {
      await notifyAccessRequestApplicant(targetUserId, targetData, approve, moreInfo, accessRole, reason);
    } catch (error) {
      console.warn('Access decision was saved but applicant notification delivery failed.', error);
    }
  }
  return {ok: true};
});

export const setStaffAccountEnabled = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  const actor = await requireSuperAdmin(actorId);
  const targetUserId = requiredText(request.data?.userId, "User ID", 1, 128);
  const enabled = request.data?.enabled === true;
  const reason = requiredText(request.data?.reason, "Reason", 3, 500);
  if (targetUserId === actorId || targetUserId === configuredSuperAdminUid()) {
    throw new HttpsError("permission-denied", "The super-administrator cannot be modified.");
  }
  const target = db.collection("users").doc(targetUserId);
  await db.runTransaction(async (transaction) => {
    const before = await transaction.get(target);
    if (!before.exists) throw new HttpsError("not-found", "Staff profile not found.");
    const previous = String(before.data()?.staffAccountStatus ?? "pending");
    if (!STAFF_ACCOUNT_STATUSES.includes(previous as typeof STAFF_ACCOUNT_STATUSES[number])) {
      throw new HttpsError("failed-precondition", "This is not a staff account.");
    }
    const status = enabled ? "approved" : "disabled";
    transaction.update(target, {staffAccountStatus: status, accessRole: enabled ? before.data()?.previousAccessRole ?? "portalStaff" : "appUser",
      previousAccessRole: enabled ? FieldValue.delete() : before.data()?.accessRole ?? "portalStaff", updatedAt: FieldValue.serverTimestamp()});
    writeAudit(transaction, db, {actorId, actorNameSnapshot: actorName(actor), actorRoleSnapshot: actor.accessRole,
      action: enabled ? "STAFF_ACCOUNT_REACTIVATED" : "STAFF_ACCOUNT_SUSPENDED",
      category: AUDIT_CATEGORIES.userManagement, targetType: "staff", targetId: targetUserId,
      metadata: {before: {staffAccountStatus: previous, accessRole: before.data()?.accessRole}, after: {staffAccountStatus: status}, reason}});
  });
  await getAuth().updateUser(targetUserId, {disabled: !enabled});
  if (!enabled) await getAuth().revokeRefreshTokens(targetUserId);
  return {ok: true};
});

export const bulkManageStaffAccounts = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  const actor = await requireSuperAdmin(actorId);
  const rawIds = Array.isArray(request.data?.userIds) ? request.data.userIds : [];
  const userIds: string[] = Array.from(new Set<string>(rawIds.filter((value: unknown): value is string => typeof value === "string" && value.trim().length > 0)));
  const action = String(request.data?.action ?? "");
  const reason = requiredText(request.data?.reason, "Reason", 3, 500);
  if (userIds.length < 1 || userIds.length > 200) throw new HttpsError("invalid-argument", "Select between 1 and 200 staff accounts.");
  if (!["suspend", "reactivate"].includes(action)) throw new HttpsError("invalid-argument", "Choose a valid account action.");
  if (userIds.includes(actorId) || userIds.includes(configuredSuperAdminUid())) throw new HttpsError("permission-denied", "The super-administrator cannot be modified.");
  const refs = userIds.map((id) => db.collection("users").doc(id));
  await db.runTransaction(async (transaction) => {
    const snapshots = await Promise.all(refs.map((ref) => transaction.get(ref)));
    for (let index = 0; index < snapshots.length; index++) {
      const before = snapshots[index];
      if (!before.exists) throw new HttpsError("not-found", "One or more staff accounts could not be found.");
      const data = (before.data() ?? {}) as Record<string, unknown>;
      const previous = String(data.staffAccountStatus ?? "pending");
      if (!STAFF_ACCOUNT_STATUSES.includes(previous as typeof STAFF_ACCOUNT_STATUSES[number])) throw new HttpsError("failed-precondition", "Only staff accounts can be changed.");
      if (action === "suspend" && previous !== "approved") throw new HttpsError("failed-precondition", "Only active staff accounts can be suspended.");
      if (action === "reactivate" && previous !== "disabled") throw new HttpsError("failed-precondition", "Only suspended staff accounts can be reactivated.");
      const enabled = action === "reactivate";
      transaction.update(before.ref, {
        staffAccountStatus: enabled ? "approved" : "disabled",
        accessRole: enabled ? String(data.previousAccessRole ?? "portalStaff") : "appUser",
        previousAccessRole: enabled ? FieldValue.delete() : String(data.accessRole ?? "portalStaff"),
        accountStatus: enabled ? "active" : "suspended",
        updatedAt: FieldValue.serverTimestamp(),
      });
      writeAudit(transaction, db, {
        actorId, actorNameSnapshot: actorName(actor), actorRoleSnapshot: actor.accessRole,
        action: enabled ? "STAFF_ACCOUNT_REACTIVATED" : "STAFF_ACCOUNT_SUSPENDED",
        category: AUDIT_CATEGORIES.userManagement, targetType: "staff", targetId: before.id,
        metadata: {bulk: true, before: {staffAccountStatus: previous}, after: {staffAccountStatus: enabled ? "approved" : "disabled"}, reason},
      });
    }
  });
  await Promise.all(userIds.map((id) => action === "reactivate"
    ? getAuth().updateUser(id, {disabled: false})
    : getAuth().updateUser(id, {disabled: true}).then(() => getAuth().revokeRefreshTokens(id))));
  return {ok: true, affected: userIds.length};
});

function authMetadataTimestamp(value: string | undefined): Timestamp | null {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : Timestamp.fromDate(date);
}

// The Admin SDK is the source of truth for sign-in metadata. This deliberately
// writes into the existing user profile, so the real-time User Management
// stream remains the single data source for the UI.
export const recordPortalSessionActivity = onCall(async (request) => {
  const userId = requireAuthenticatedUser(request);
  await requireStaff(userId);
  const authUser = await getAuth().getUser(userId);
  const lastSignInAt = authMetadataTimestamp(authUser.metadata.lastSignInTime);
  const profileRef = db.collection("users").doc(userId);
  await db.runTransaction(async (transaction) => {
    const profile = await transaction.get(profileRef);
    if (!profile.exists) return;
    const currentActive = profile.data()?.lastActiveAt;
    const activeMillis = currentActive instanceof Timestamp ? currentActive.toMillis() : 0;
    const values: Record<string, FirebaseFirestore.FieldValue | Timestamp> = {
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (lastSignInAt) values.lastSignInAt = lastSignInAt;
    // Refresh application activity at most once per fifteen minutes. This
    // represents portal use, not merely Firebase credential authentication.
    if (Date.now() - activeMillis >= 15 * 60 * 1000) {
      values.lastActiveAt = FieldValue.serverTimestamp();
    }
    transaction.update(profileRef, values);
  });
  return {ok: true};
});

// One safe, idempotent migration for accounts created before portal activity
// tracking existed. It imports only Firebase Auth metadata and never invents a
// "last active" time for older accounts.
export const backfillStaffAccountAuthMetadata = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  await requireSuperAdmin(actorId);
  const profiles = await db.collection("users").get();
  const staff = profiles.docs.filter((profile) => {
    const data = profile.data();
    return data.staffAccountStatus != null || ["portalStaff", "counselor", "admin"].includes(String(data.accessRole ?? ""));
  });
  let updated = 0;
  for (let start = 0; start < staff.length; start += 100) {
    const slice = staff.slice(start, start + 100);
    const result = await getAuth().getUsers(slice.map((profile) => ({uid: profile.id})));
    const authByUid = new Map(result.users.map((user) => [user.uid, user]));
    const batch = db.batch();
    let batchUpdates = 0;
    for (const profile of slice) {
      const authUser = authByUid.get(profile.id);
      const lastSignInAt = authMetadataTimestamp(authUser?.metadata.lastSignInTime);
      if (!lastSignInAt) continue;
      const current = profile.data().lastSignInAt;
      const currentMillis = current instanceof Timestamp ? current.toMillis() : 0;
      if (currentMillis === lastSignInAt.toMillis()) continue;
      batch.update(profile.ref, {lastSignInAt, updatedAt: FieldValue.serverTimestamp()});
      updated++;
      batchUpdates++;
    }
    if (batchUpdates > 0) await batch.commit();
  }
  return {ok: true, updated, scanned: staff.length};
});

const POPULATION_ROLES = ["student", "teaching", "nonTeaching"] as const;
const ACCESS_ROLES = ["appUser", "portalStaff", "counselor", "admin"] as const;
export type AccessRoleValue = typeof ACCESS_ROLES[number];
export const canReviewVerification = (role: string): boolean =>
  ["portalStaff", "counselor", "admin"].includes(role);
export const canAccessClinicalData = (role: string): boolean =>
  role === "counselor" || role === "admin";
export const canManageAccess = (role: string): boolean => role === "admin";

function requiredText(value: unknown, label: string, min: number, max: number): string {
  const text = typeof value === "string" ? value.trim() : "";
  if (text.length < min || text.length > max) {
    throw new HttpsError("invalid-argument", `${label} must be ${min}-${max} characters.`);
  }
  return text;
}

export function newPublicUserId(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = randomBytes(6);
  return `USR-${Array.from(bytes, (byte) => alphabet[byte % alphabet.length]).join("")}`;
}

async function ensurePublicUserId(userId: string): Promise<string> {
  const mappingRef = publicUserIds.doc(userId);
  const existing = await mappingRef.get();
  if (existing.exists) return String(existing.data()?.publicUserId ?? "");
  for (let attempt = 0; attempt < 12; attempt++) {
    const publicUserId = newPublicUserId();
    const reservationRef = publicUserIdReservations.doc(publicUserId);
    try {
      await db.runTransaction(async (transaction) => {
        const [mapping, reservation] = await Promise.all([
          transaction.get(mappingRef), transaction.get(reservationRef),
        ]);
        if (mapping.exists) return;
        if (reservation.exists) throw new Error("PUBLIC_ID_COLLISION");
        transaction.create(reservationRef, {userId, createdAt: FieldValue.serverTimestamp()});
        transaction.create(mappingRef, {publicUserId, createdAt: FieldValue.serverTimestamp()});
      });
      const saved = await mappingRef.get();
      if (saved.exists) return String(saved.data()?.publicUserId ?? publicUserId);
    } catch (error) {
      if (!(error instanceof Error) || error.message !== "PUBLIC_ID_COLLISION") throw error;
    }
  }
  throw new HttpsError("resource-exhausted", "Unable to allocate a public user ID.");
}

export const assignPublicIdOnUserCreate = onDocumentCreated("users/{userId}", async (event) => {
  const data = event.data?.data();
  if (!data || data.staffAccountStatus != null || data.accessRole === "admin") return;
  await ensurePublicUserId(event.params.userId);
});

export const listPublicAppUsers = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  await requireSuperAdmin(actorId);
  const snapshots = await db.collection("users").get();
  const appUsers = snapshots.docs.filter((doc) => {
    const data = doc.data();
    return data.staffAccountStatus == null && data.accessRole !== "admin";
  });
  return {users: await Promise.all(appUsers.map(async (doc) => {
    const data = doc.data();
    const createdAt = data.createdAt instanceof Timestamp
      ? data.createdAt.toDate().toISOString()
      : typeof data.createdAt === "string" ? data.createdAt : null;
    return {
      userId: doc.id,
      publicUserId: await ensurePublicUserId(doc.id),
      populationRole: String(data.populationRole ?? data.declaredRole ?? data.role ?? ""),
      department: String(data.department ?? data.sector ?? ""),
      createdAt,
    };
  }))};
});

export const backfillPublicAppUserIds = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  await requireSuperAdmin(actorId);
  const snapshots = await db.collection("users").get();
  const appUsers = snapshots.docs.filter((doc) => {
    const data = doc.data();
    return data.staffAccountStatus == null && data.accessRole !== "admin";
  });
  await Promise.all(appUsers.map((doc) => ensurePublicUserId(doc.id)));
  return {ok: true, processed: appUsers.length};
});

export const confirmSuperAdmin = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  await requireSuperAdmin(actorId);
  return {isSuperAdmin: true};
});

export const completeAdminPasswordChange = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  const actor = await requireSuperAdmin(actorId);
  const target = db.collection("users").doc(actorId);
  const audit = db.collection("admin_audit_logs").doc();
  await db.runTransaction(async (transaction) => {
    const profile = await transaction.get(target);
    if (!profile.exists) throw new HttpsError("not-found", "Administrator profile not found.");
    transaction.update(target, {mustChangePassword: false, passwordChangedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
    transaction.create(audit, {actorId, actorAccessRole: actor.accessRole, targetUserId: actorId,
      action: "initialAdminPasswordChanged", reason: "Mandatory initial password change completed",
      before: {mustChangePassword: profile.data()?.mustChangePassword === true},
      after: {mustChangePassword: false}, createdAt: FieldValue.serverTimestamp()});
  });
  return {ok: true};
});

export const requestRoleCorrection = onCall(async (request) => {
  const userId = requireAuthenticatedUser(request);
  const requestedRole = String(request.data?.requestedRole ?? "");
  if (!POPULATION_ROLES.includes(requestedRole as typeof POPULATION_ROLES[number])) {
    throw new HttpsError("invalid-argument", "Choose a valid population role.");
  }
  const reason = requiredText(request.data?.reason, "Reason", 10, 500);
  const userRef = db.collection("users").doc(userId);
  const requestRef = db.collection("role_correction_requests").doc();
  await db.runTransaction(async (transaction) => {
    const user = await transaction.get(userRef);
    if (!user.exists) throw new HttpsError("not-found", "User profile not found.");
    const currentRole = String(user.data()?.populationRole ?? user.data()?.declaredRole ?? "");
    if (currentRole === requestedRole) {
      throw new HttpsError("failed-precondition", "This is already your current role.");
    }
    transaction.create(requestRef, {
      userId,
      currentRole,
      requestedRole,
      reason,
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return {ok: true, requestId: requestRef.id};
});

export const reviewProfileVerification = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  const actor = await requireStaff(actorId);
  const targetUserId = requiredText(request.data?.userId, "User ID", 1, 128);
  const decision = String(request.data?.decision ?? "");
  const reason = requiredText(request.data?.reason, "Reason", 3, 500);
  if (!["verified", "rejected", "needsReview"].includes(decision)) {
    throw new HttpsError("invalid-argument", "Choose a valid verification decision.");
  }
  if (actorId === targetUserId) {
    throw new HttpsError("permission-denied", "You cannot verify your own profile.");
  }
  const target = db.collection("users").doc(targetUserId);
  const audit = db.collection("role_audit_logs").doc();
  await db.runTransaction(async (transaction) => {
    const before = await transaction.get(target);
    if (!before.exists) throw new HttpsError("not-found", "User profile not found.");
    transaction.update(target, {
      verificationStatus: decision,
      verifiedAt: decision === "verified" ? FieldValue.serverTimestamp() : null,
      verifiedBy: decision === "verified" ? actorId : "",
      profileVersion: 2,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(audit, {
      targetUserId,
      actorId,
      actorAccessRole: actor.accessRole,
      action: "verificationReviewed",
      reason,
      before: {verificationStatus: before.data()?.verificationStatus ?? "needsReview"},
      after: {verificationStatus: decision},
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return {ok: true};
});

export const reviewRoleCorrection = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  const actor = await requireStaff(actorId);
  if (actor.accessRole !== "admin") {
    throw new HttpsError("permission-denied", "Administrator access is required.");
  }
  const requestId = requiredText(request.data?.requestId, "Request ID", 1, 128);
  const approve = request.data?.approve === true;
  const reason = requiredText(request.data?.reason, "Reason", 3, 500);
  const requestRef = db.collection("role_correction_requests").doc(requestId);
  const audit = db.collection("role_audit_logs").doc();
  await db.runTransaction(async (transaction) => {
    const correction = await transaction.get(requestRef);
    if (!correction.exists || correction.data()?.status !== "pending") {
      throw new HttpsError("failed-precondition", "This request is no longer pending.");
    }
    const targetUserId = String(correction.data()?.userId ?? "");
    if (targetUserId === actorId) {
      throw new HttpsError("permission-denied", "You cannot approve your own role change.");
    }
    const target = db.collection("users").doc(targetUserId);
    const before = await transaction.get(target);
    if (!before.exists) throw new HttpsError("not-found", "User profile not found.");
    const requestedRole = String(correction.data()?.requestedRole ?? "");
    transaction.update(requestRef, {
      status: approve ? "approved" : "rejected",
      reviewReason: reason,
      reviewedBy: actorId,
      reviewedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (approve) {
      transaction.update(target, {
        populationRole: requestedRole,
        declaredRole: requestedRole,
        verificationStatus: "verified",
        verifiedAt: FieldValue.serverTimestamp(),
        verifiedBy: actorId,
        profileVersion: 2,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    transaction.create(audit, {
      targetUserId,
      actorId,
      actorAccessRole: actor.accessRole,
      action: approve ? "roleCorrectionApproved" : "roleCorrectionRejected",
      reason,
      requestId,
      before: {populationRole: before.data()?.populationRole ?? before.data()?.role ?? ""},
      after: {populationRole: approve ? requestedRole : before.data()?.populationRole ?? ""},
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return {ok: true};
});

export const assignAccessRole = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  const actor = await requireSuperAdmin(actorId);
  const targetUserId = requiredText(request.data?.userId, "User ID", 1, 128);
  const accessRole = String(request.data?.accessRole ?? "");
  const reason = requiredText(request.data?.reason, "Reason", 3, 500);
  if (![...STAFF_ACCESS_ROLES, "appUser"].includes(accessRole as "portalStaff" | "counselor" | "appUser")) {
    throw new HttpsError("invalid-argument", "Choose Portal Staff, Counselor, or revoke access.");
  }
  if (targetUserId === actorId || targetUserId === configuredSuperAdminUid()) {
    throw new HttpsError("permission-denied", "The super-administrator cannot be modified.");
  }
  const target = db.collection("users").doc(targetUserId);
  await db.runTransaction(async (transaction) => {
    const before = await transaction.get(target);
    if (!before.exists) throw new HttpsError("not-found", "User profile not found.");
    transaction.update(target, {accessRole, profileVersion: 2, updatedAt: FieldValue.serverTimestamp()});
    writeAudit(transaction, db, {actorId, actorNameSnapshot: actorName(actor), actorRoleSnapshot: actor.accessRole,
      action: accessRole === "appUser" ? "STAFF_ACCESS_REVOKED" : "STAFF_ROLE_CHANGED",
      category: AUDIT_CATEGORIES.userManagement, targetType: "staff", targetId: targetUserId,
      metadata: {before: {accessRole: before.data()?.accessRole ?? "appUser"}, after: {accessRole}, reason}});
  });
  return {ok: true};
});

const AUDIT_CATEGORY_VALUES = Object.values(AUDIT_CATEGORIES);
const AUDIT_METADATA_KEYS = new Set([
  "before", "after", "reason", "format", "reportType", "academicYearId",
  "selectedDepartment", "dateRange", "targetLabel", "status",
]);

function safeAuditMetadata(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const result: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
    if (!AUDIT_METADATA_KEYS.has(key)) continue;
    if (typeof item === "string" || typeof item === "number" || typeof item === "boolean") {
      result[key] = item;
    } else if (item && typeof item === "object" && !Array.isArray(item)) {
      const values: Record<string, unknown> = {};
      for (const [nestedKey, nestedValue] of Object.entries(item as Record<string, unknown>)) {
        if ((typeof nestedValue === "string" || typeof nestedValue === "number" || typeof nestedValue === "boolean") && nestedKey.length <= 50) values[nestedKey] = nestedValue;
      }
      result[key] = values;
    }
  }
  return result;
}

export const recordAuditEvent = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  const actor = await requireStaff(actorId);
  const action = String(request.data?.action ?? "") as typeof AUDIT_ACTIONS[number];
  const category = String(request.data?.category ?? "");
  if (!AUDIT_ACTIONS.includes(action)) throw new HttpsError("invalid-argument", "Choose a valid audit action.");
  if (!AUDIT_CATEGORY_VALUES.includes(category as typeof AUDIT_CATEGORY_VALUES[number])) throw new HttpsError("invalid-argument", "Choose a valid audit category.");
  const targetType = typeof request.data?.targetType === "string" ? request.data.targetType.trim().slice(0, 60) : undefined;
  const targetId = typeof request.data?.targetId === "string" ? request.data.targetId.trim().slice(0, 160) : undefined;
  const audit = db.collection("admin_audit_logs").doc();
  await audit.create({actorId, actorNameSnapshot: actorName(actor), actorRoleSnapshot: actor.accessRole,
    action, category, targetType: targetType || null, targetId: targetId || null,
    metadata: safeAuditMetadata(request.data?.metadata), sessionId: null,
    timestamp: FieldValue.serverTimestamp(), createdAt: FieldValue.serverTimestamp(),
    targetUserId: targetType === "staff" ? targetId : null});
  return {ok: true};
});

export const getAuditLogPage = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  await requireSuperAdmin(actorId);
  const targetUserId = requiredText(request.data?.targetUserId, "Target user", 1, 128);
  const category = typeof request.data?.category === "string" ? request.data.category.trim() : "";
  const action = typeof request.data?.action === "string" ? request.data.action.trim() : "";
  const afterMillis = typeof request.data?.afterMillis === "number" ? request.data.afterMillis : null;
  const pageSize = Math.min(Math.max(Number(request.data?.pageSize ?? 25), 1), 50);
  let query: FirebaseFirestore.Query = db.collection("admin_audit_logs")
    .where("targetUserId", "==", targetUserId).orderBy("createdAt", "desc").limit(pageSize);
  if (category) query = query.where("category", "==", category);
  if (action) query = query.where("action", "==", action);
  if (afterMillis != null) query = query.where("createdAt", ">=", Timestamp.fromMillis(afterMillis));
  if (typeof request.data?.beforeMillis === "number") query = query.startAfter(Timestamp.fromMillis(request.data.beforeMillis));
  const snapshot = await query.get();
  return {events: snapshot.docs.map((doc) => {
    const data = doc.data();
    const timestamp = data.timestamp instanceof Timestamp ? data.timestamp.toDate().toISOString() : data.createdAt instanceof Timestamp ? data.createdAt.toDate().toISOString() : null;
    return {id: doc.id, ...data, timestamp, createdAt: timestamp};
  }), hasMore: snapshot.size === pageSize};
});

const DEFAULT_ACADEMIC_STRUCTURE: Record<string, string[]> = {
  "College of Accountancy and Business Administration": ["BS Accountancy", "BS Business Administration", "BS Management"],
  "College of Arts and Sciences / College of Arts and Languages": ["BA Communication / Mass Communication", "BA English", "BA Filipino", "BA Political Science", "BA Psychology"],
  "College of Information and Technology Education / College of Computer Studies": ["BS Information Technology", "Bachelor of Library and Information Science", "Associate in Computer Technology"],
  "College of Criminology": ["BS Criminology"],
  "College of Education / College of Teacher Education": ["Bachelor of Elementary Education - Preschool Ed, Primary Ed", "Bachelor of Secondary Education - English, Filipino, Mathematics, Science, Social Studies", "Bachelor in Physical Education", "Bachelor in Music", "Bachelor in Fine Arts"],
  "College of Engineering and Architecture": ["BS Architecture", "BS Civil Engineering", "BS Computer Engineering", "BS Electrical Engineering / Electronic Engineering", "BS Mechanical Engineering"],
  "College of Law": ["Juris Doctor"],
  "College of Nursing": ["BS Nursing"],
  "College of Pharmacy": ["BS Pharmacy"],
  "College of Science and Mathematics": ["BS Mathematics", "BS Biology / Natural Sciences"],
  "College of Social Work": ["BS Social Work"],
  "Graduate School / Institute of Graduate and Advanced Studies": ["Doctor of Education", "Master of Arts in Education - all major fields", "Master in Business Administration", "Master of Arts in Nursing"],
  "School of Hotel and Restaurant Services and Tourism Management": ["BS Hotel and Restaurant Management", "BS Tourism Management"],
  "School of Midwifery": ["Midwifery Program"],
};

export const initializeAcademicStructure = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  await requireSuperAdmin(actorId);
  const colleges = await db.collection("colleges").limit(1).get();
  if (!colleges.empty) return {created: false, message: "Academic structure is already configured."};
  const batch = db.batch();
  for (const [collegeName, courseNames] of Object.entries(DEFAULT_ACADEMIC_STRUCTURE)) {
    const collegeId = `college-${collegeName.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")}`;
    const departmentId = `${collegeId}-programs`;
    const collegeRef = db.collection("colleges").doc(collegeId);
    const departmentRef = db.collection("departments").doc(departmentId);
    batch.set(collegeRef, {name: collegeName, code: collegeId.replace("college-", "").slice(0, 12).toUpperCase(), normalizedName: collegeName.toLowerCase(), normalizedCode: collegeId, active: true, status: "ACTIVE", createdBy: actorId, updatedBy: actorId, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
    batch.set(departmentRef, {name: "Academic Programs", code: "PROGRAMS", collegeId, normalizedName: `${collegeName.toLowerCase()} academic programs`, normalizedCode: `${collegeId}-programs`, active: true, status: "ACTIVE", createdBy: actorId, updatedBy: actorId, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
    for (const courseName of courseNames) {
      const courseId = `${departmentId}-${courseName.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")}`;
      batch.set(db.collection("courses").doc(courseId), {name: courseName, code: courseName.replace(/[^A-Za-z0-9]/g, "").slice(0, 12).toUpperCase(), normalizedName: courseName.toLowerCase(), normalizedCode: courseId, collegeId, departmentId, active: true, status: "ACTIVE", createdBy: actorId, updatedBy: actorId, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
    }
  }
  await batch.commit();
  return {created: true, colleges: Object.keys(DEFAULT_ACADEMIC_STRUCTURE).length};
});

export const saveOrganizationRecord = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  await requireSuperAdmin(actorId);
  const kind = String(request.data?.kind ?? "");
  const collection = ({college: "colleges", department: "departments", course: "courses"} as const)[kind as "college" | "department" | "course"];
  if (!collection) throw new HttpsError("invalid-argument", "Choose a valid directory type.");
  const recordId = typeof request.data?.id === "string" && request.data.id.trim() ? request.data.id.trim() : db.collection(collection).doc().id;
  const name = requiredText(request.data?.name, "Name", 2, 120);
  const code = requiredText(request.data?.code, "Code", 1, 30).toUpperCase();
  const active = request.data?.active !== false;
  const collegeId = kind !== "college" ? requiredText(request.data?.collegeId, "College", 1, 128) : "";
  const departmentId = kind === "course" ? requiredText(request.data?.departmentId, "Department", 1, 128) : "";
  if (kind !== "college") {
    const college = await db.collection("colleges").doc(collegeId).get();
    if (!college.exists || college.data()?.active !== true) {
      throw new HttpsError("failed-precondition", "Choose an active college.");
    }
  }
  if (kind === "course") {
    const department = await db.collection("departments").doc(departmentId).get();
    if (!department.exists || department.data()?.active !== true || department.data()?.collegeId !== collegeId) {
      throw new HttpsError("failed-precondition", "Choose a department under the selected college.");
    }
  }
  const duplicate = await db.collection(collection).where("normalizedName", "==", name.toLowerCase()).limit(10).get();
  const duplicateCode = await db.collection(collection).where("normalizedCode", "==", code.toLowerCase()).limit(10).get();
  if (duplicate.docs.some((doc) => doc.id !== recordId) || duplicateCode.docs.some((doc) => doc.id !== recordId)) {
    throw new HttpsError("already-exists", `A ${kind} with that name already exists.`);
  }
  await db.collection(collection).doc(recordId).set({name, code, normalizedName: name.toLowerCase(), normalizedCode: code.toLowerCase(), active, status: active ? "ACTIVE" : "INACTIVE",
    ...(kind !== "college" ? {collegeId} : {}), ...(kind === "course" ? {departmentId} : {}), updatedBy: actorId, updatedAt: FieldValue.serverTimestamp(),
    ...(typeof request.data?.id === "string" && request.data.id.trim() ? {} : {createdBy: actorId, createdAt: FieldValue.serverTimestamp()})}, {merge: true});
  return {ok: true, id: recordId};
});

export const archiveOrganizationRecord = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  await requireSuperAdmin(actorId);
  const kind = String(request.data?.kind ?? "");
  const collection = ({college: "colleges", department: "departments", course: "courses"} as const)[kind as "college" | "department" | "course"];
  const id = requiredText(request.data?.id, "Record", 1, 128);
  const archived = request.data?.archived === true;
  if (!collection) throw new HttpsError("invalid-argument", "Choose a valid academic structure type.");
  const ref = db.collection(collection).doc(id);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new HttpsError("not-found", "Academic structure record not found.");
  const data = snapshot.data() ?? {};
  if (archived && collection === "colleges") {
    const [departments, courses] = await Promise.all([
      db.collection("departments").where("collegeId", "==", id).where("active", "==", true).limit(1).get(),
      db.collection("courses").where("collegeId", "==", id).where("active", "==", true).limit(1).get(),
    ]);
    if (!departments.empty || !courses.empty) throw new HttpsError("failed-precondition", "Archive its active departments and courses first.");
  }
  if (archived && collection === "departments") {
    const courses = await db.collection("courses").where("departmentId", "==", id).where("active", "==", true).limit(1).get();
    if (!courses.empty) throw new HttpsError("failed-precondition", "Archive its active courses first.");
  }
  await ref.update({active: !archived, status: archived ? "ARCHIVED" : "ACTIVE", updatedBy: actorId, updatedAt: FieldValue.serverTimestamp()});
  await db.collection("admin_audit_logs").add({actorId, action: `${kind.toUpperCase()}_${archived ? "ARCHIVED" : "RESTORED"}`, category: AUDIT_CATEGORIES.userManagement, targetType: collection, targetId: id, metadata: {before: {active: data.active === true}, after: {active: !archived}}, createdAt: FieldValue.serverTimestamp()});
  return {ok: true};
});

export const updateStaffOrganization = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  const actor = await requireSuperAdmin(actorId);
  const targetUserId = requiredText(request.data?.userId, "User ID", 1, 128);
  const departmentId = requiredText(request.data?.departmentId, "Department", 1, 128);
  const collegeId = typeof request.data?.collegeId === "string" ? request.data.collegeId.trim() : "";
  const courseId = typeof request.data?.courseId === "string" ? request.data.courseId.trim() : "";
  const reason = requiredText(request.data?.reason, "Reason", 3, 500);
  const [department, course, target] = await Promise.all([
    db.collection("departments").doc(departmentId).get(),
    courseId ? db.collection("courses").doc(courseId).get() : Promise.resolve(null),
    db.collection("users").doc(targetUserId).get(),
  ]);
  if (!target.exists || !("staffAccountStatus" in (target.data() ?? {}))) throw new HttpsError("failed-precondition", "Only staff accounts can be updated.");
  if (!department.exists || department.data()?.active !== true) throw new HttpsError("failed-precondition", "Choose an active department.");
  if (course && (!course.exists || course.data()?.active !== true || course.data()?.collegeId !== collegeId)) {
    throw new HttpsError("failed-precondition", "Choose a course belonging to the selected college.");
  }
  await db.runTransaction(async (transaction) => {
    transaction.update(target.ref, {departmentId, collegeId, courseId, updatedAt: FieldValue.serverTimestamp()});
    transaction.create(db.collection("admin_audit_logs").doc(), {actorId, actorAccessRole: actor.accessRole,
      targetUserId, action: "staffOrganizationUpdated", reason,
      before: {departmentId: target.data()?.departmentId ?? "", collegeId: target.data()?.collegeId ?? "", courseId: target.data()?.courseId ?? ""},
      after: {departmentId, collegeId, courseId}, createdAt: FieldValue.serverTimestamp()});
  });
  return {ok: true};
});

export function reactionDelta(before: unknown, after: unknown): number {
  return Number(after === true) - Number(before === true);
}

export function activeCommentDelta(before: unknown, after: unknown): number {
  return Number(after === "active") - Number(before === "active");
}

export const rebuildMySecretChatStats = onCall(async (request) => {
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Sign in is required.");
  const statsRef = stats.doc(userId);
  if ((await statsRef.get()).exists) return {rebuilt: false};
  const snapshot = await posts.where("authorId", "==", userId).get();
  const totals = snapshot.docs.reduce((value, document) => {
    const post = document.data();
    value.reads += Number(post.readCount ?? 0);
    value.reactions += Number(post.likeCount ?? 0);
    value.comments += Number(post.commentCount ?? 0);
    return value;
  }, {reads: 0, reactions: 0, comments: 0});
  await db.runTransaction(async (transaction) => {
    if ((await transaction.get(statsRef)).exists) return;
    transaction.create(statsRef, {
      userId,
      ...totals,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return {rebuilt: true};
});

async function once(eventId: string, apply: (
  transaction: FirebaseFirestore.Transaction,
  marker: FirebaseFirestore.DocumentReference,
) => Promise<void>): Promise<void> {
  const marker = events.doc(eventId);
  await db.runTransaction(async (transaction) => {
    if ((await transaction.get(marker)).exists) return;
    await apply(transaction, marker);
    transaction.create(marker, {processedAt: FieldValue.serverTimestamp()});
  });
}

export const syncSecretChatInteraction = onDocumentWritten(
  {document: "secret_chat_interactions/{interactionId}", retry: true},
  async (event) => {
    if (!event.data) return;
    const before = event.data.before.data();
    const after = event.data.after.data();
    const postId = String(after?.postId ?? before?.postId ?? "");
    if (!postId) return;
    const reactionChange = reactionDelta(before?.liked, after?.liked);
    const firstRead = !(before?.readAt instanceof Timestamp) && after?.readAt instanceof Timestamp;
    if (reactionChange === 0 && !firstRead) return;

    await once(`interaction_${event.id}`, async (transaction, marker) => {
      const postRef = posts.doc(postId);
      const postSnapshot = await transaction.get(postRef);
      if (!postSnapshot.exists) return;
      const post = postSnapshot.data()!;
      const authorId = String(post.authorId ?? "");
      if (!authorId) return;
      const statsRef = stats.doc(authorId);
      await transaction.get(statsRef);
      const readerId = String(after?.userId ?? "");
      const readDelta = firstRead && readerId !== authorId ? 1 : 0;
      transaction.set(postRef, {
        likeCount: FieldValue.increment(reactionChange),
        readCount: FieldValue.increment(readDelta),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.set(statsRef, {
        userId: authorId,
        reactions: FieldValue.increment(reactionChange),
        reads: FieldValue.increment(readDelta),
        comments: FieldValue.increment(0),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    });
  },
);

export const syncSecretChatComment = onDocumentWritten(
  {document: "secret_chat_comments/{commentId}", retry: true},
  async (event) => {
    if (!event.data) return;
    const before = event.data.before.data();
    const after = event.data.after.data();
    const wasActive = before?.moderationStatus === "active";
    const isActive = after?.moderationStatus === "active";
    const delta = activeCommentDelta(
      wasActive ? "active" : undefined,
      isActive ? "active" : undefined,
    );
    const postId = String(after?.postId ?? before?.postId ?? "");
    if (!postId || delta === 0) return;

    await once(`comment_${event.id}`, async (transaction, marker) => {
      const postRef = posts.doc(postId);
      const postSnapshot = await transaction.get(postRef);
      if (!postSnapshot.exists) return;
      const authorId = String(postSnapshot.data()?.authorId ?? "");
      if (!authorId) return;
      const statsRef = stats.doc(authorId);
      await transaction.get(statsRef);
      transaction.set(postRef, {
        commentCount: FieldValue.increment(delta),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.set(statsRef, {
        userId: authorId,
        comments: FieldValue.increment(delta),
        reactions: FieldValue.increment(0),
        reads: FieldValue.increment(0),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    });
  },
);

export const removeDeletedPostStats = onDocumentDeleted(
  {document: "secret_chats/{postId}", retry: true},
  async (event) => {
    const post = event.data?.data();
    const authorId = String(post?.authorId ?? "");
    if (!authorId) return;
    await once(`post_delete_${event.id}`, async (transaction, marker) => {
      const statsRef = stats.doc(authorId);
      await transaction.get(statsRef);
      transaction.set(statsRef, {
        userId: authorId,
        reactions: FieldValue.increment(-Number(post?.likeCount ?? 0)),
        comments: FieldValue.increment(-Number(post?.commentCount ?? 0)),
        reads: FieldValue.increment(-Number(post?.readCount ?? 0)),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    });
  },
);

export const aggregateUserActivity = onDocumentCreated(
  {document: "user_activities/{activityId}", retry: true},
  async (event) => {
    const activity = event.data?.data();
    const userId = String(activity?.userId ?? "");
    const type = String(activity?.type ?? "unknown").replace(/[^A-Za-z0-9_]/g, "_");
    if (!userId) return;
    const occurred = activity?.createdAt instanceof Timestamp ? activity.createdAt.toDate() : new Date();
    const dateKey = manilaDateKey(occurred);
    const marker = analyticsEvents.doc(event.params.activityId);
    const day = db.collection("analytics_daily").doc(dateKey);
    const dailyUser = day.collection("users").doc(userId);

    await db.runTransaction(async (transaction) => {
      if ((await transaction.get(marker)).exists) return;
      const isNewDailyUser = !(await transaction.get(dailyUser)).exists;
      transaction.set(day, {
        dateKey,
        eventCount: FieldValue.increment(1),
        activeUserCount: FieldValue.increment(isNewDailyUser ? 1 : 0),
        [`activityCounts.${type}`]: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.set(dailyUser, {
        userId,
        lastActivityType: type,
        lastActiveAt: activity?.createdAt ?? FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.create(marker, {
        activityId: event.params.activityId,
        userId,
        dateKey,
        processedAt: FieldValue.serverTimestamp(),
      });
    });
  },
);

type PortalNotificationKind = "appointment" | "inquiry";

const NOTIFICATION_ARCHIVE_AFTER_DAYS = 30;
const NOTIFICATION_DELETE_AFTER_DAYS = 90;
const DAY_MILLIS = 24 * 60 * 60 * 1000;

export function notificationArchiveAtMillis(readAtMillis: number): number {
  return readAtMillis + NOTIFICATION_ARCHIVE_AFTER_DAYS * DAY_MILLIS;
}

export function notificationDeleteAtMillis(archivedAtMillis: number): number {
  return archivedAtMillis + NOTIFICATION_DELETE_AFTER_DAYS * DAY_MILLIS;
}

export function isNormalNotificationType(type: unknown): boolean {
  return type === "appointment" || type === "inquiry";
}

export const managePortalNotification = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  const rawIds = Array.isArray(request.data?.notificationIds)
    ? request.data.notificationIds
    : [request.data?.notificationId];
  const notificationIds: string[] = Array.from(
    new Set<string>(rawIds.map((id: unknown) => String(id ?? "").trim())),
  );
  const action = String(request.data?.action ?? "");
  if (notificationIds.length < 1 || notificationIds.length > 200 || notificationIds.some((id) => id.length > 180 || id.includes("/"))) {
    throw new HttpsError("invalid-argument", "Choose a valid notification.");
  }
  if (!["archive", "restore", "delete"].includes(action)) {
    throw new HttpsError("invalid-argument", "Choose a valid notification action.");
  }
  const refs = notificationIds.map((id) => db.collection("notifications").doc(id));
  await db.runTransaction(async (transaction) => {
    const snapshots = await Promise.all(refs.map((ref) => transaction.get(ref)));
    snapshots.forEach((snapshot, index) => {
      if (!snapshot.exists) throw new HttpsError("not-found", "A notification no longer exists.");
      const data = snapshot.data() ?? {};
      if (data.userId !== uid || data.audience !== "portal") {
        throw new HttpsError("permission-denied", "You cannot manage this notification.");
      }
      const ref = refs[index];
      if (action === "restore") {
        if (data.archivedAt) transaction.update(ref, {
          archivedAt: null,
          expiresAt: null,
          archiveEligibleAt: null,
        });
      } else {
        if (!data.readAt && !data.resolvedAt) {
          throw new HttpsError("failed-precondition", "Open notifications before clearing them.");
        }
        if (action === "delete") {
          transaction.delete(ref);
        } else if (!data.archivedAt) {
          const archivedAt = Timestamp.now();
          transaction.update(ref, {
            archivedAt,
            archiveEligibleAt: null,
            expiresAt: Timestamp.fromMillis(notificationDeleteAtMillis(archivedAt.toMillis())),
          });
        }
      }
    });
  });
  return {success: true, affected: notificationIds.length};
});

export function portalNotificationPayload(
  kind: PortalNotificationKind,
  recipientId: string,
  recordId: string,
): Record<string, unknown> {
  const isAppointment = kind === "appointment";
  return {
    userId: recipientId,
    type: kind,
    audience: "portal",
    title: isAppointment ? "New counseling appointment" : "New inquiry",
    body: isAppointment ?
      "A new counseling appointment is ready for review." :
      "A new inquiry is ready for review.",
    ...(isAppointment ? {appointmentId: recordId} : {inquiryId: recordId}),
    createdAt: FieldValue.serverTimestamp(),
    readAt: null,
    resolvedAt: null,
    archiveEligibleAt: null,
    archivedAt: null,
    expiresAt: null,
  };
}

async function notifyClinicalStaff(
  kind: PortalNotificationKind,
  recordId: string,
): Promise<void> {
  const staff = await db.collection("users")
    .where("accessRole", "in", ["portalStaff", "counselor", "admin"])
    .get();
  await Promise.all(staff.docs.map(async (recipient) => {
    const notificationId = `portal_${kind}_${recordId}_${recipient.id}`;
    try {
      await db.collection("notifications").doc(notificationId).create(
        portalNotificationPayload(kind, recipient.id, recordId),
      );
    } catch (error: unknown) {
      const code = typeof error === "object" && error !== null && "code" in error ?
        String((error as {code?: unknown}).code) : "";
      if (code !== "6" && code !== "already-exists") throw error;
    }
  }));
}

async function notifyAccessRequestAdmins(
  requestId: string,
  applicantName: string,
  requestedRole: string,
): Promise<void> {
  const admins = await db.collection("users").where("accessRole", "==", "admin").get();
  await Promise.all(admins.docs.map(async (admin) => {
    const notificationId = `access_request_${requestId}_${admin.id}`;
    try {
      await db.collection("notifications").doc(notificationId).create({
        userId: admin.id,
        audience: "portal",
        type: "access_request",
        title: "New PAACC access request",
        body: `${applicantName} requested ${requestedRole === "counselor" ? "Counselor" : "PAACC Staff"} access.`,
        accessRequestId: requestId,
        createdAt: FieldValue.serverTimestamp(),
        readAt: null,
        resolvedAt: null,
        archiveEligibleAt: null,
        archivedAt: null,
        expiresAt: null,
      });
    } catch (error: unknown) {
      const code = typeof error === "object" && error !== null && "code" in error ?
        String((error as {code?: unknown}).code) : "";
      if (code !== "6" && code !== "already-exists") throw error;
    }
  }));
}

async function notifyAccessRequestApplicant(
  userId: string,
  profile: FirebaseFirestore.DocumentData,
  approved: boolean,
  moreInfo: boolean,
  approvedRole: string,
  reason: string,
): Promise<void> {
  const requestId = String(profile.accessRequestId ?? userId);
  const roleLabel = approvedRole === "counselor" ? "Counselor" : "PAACC Staff";
  await db.collection("notifications").doc(`access_request_status_${requestId}_${profile.registrationStatus ?? "updated"}`).set({
    userId,
    audience: "portal",
    type: "access_request",
    title: approved ? "PAACC portal access approved" : "More information is required",
    body: approved
      ? `Your PAACC portal access is active. Approved role: ${roleLabel}.`
      : `Please review your PAACC access request. ${reason}`,
    accessRequestId: requestId,
    createdAt: FieldValue.serverTimestamp(),
    readAt: null,
    resolvedAt: null,
    archiveEligibleAt: null,
    archivedAt: null,
    expiresAt: null,
    status: approved ? "approved" : moreInfo ? "more_information_required" : "pending_review",
  });
}

export const notifyPortalOfAppointment = onDocumentCreated(
  {document: "appointments/{appointmentId}", retry: true},
  async (event) => notifyClinicalStaff("appointment", event.params.appointmentId),
);

// Keep the non-clinical PAACC queue current without granting portal staff a
// direct read of sensitive appointment documents.
export const syncPortalAppointmentQueue = onDocumentWritten(
  {document: "appointments/{appointmentId}", retry: true},
  async (event) => {
    const queueDocument = portalAppointmentQueue.doc(event.params.appointmentId);
    if (!event.data?.after.exists) {
      await queueDocument.delete();
      return;
    }
    await queueDocument.set(
      portalAppointmentQueueProjection(
        event.params.appointmentId,
        event.data.after.data() ?? {},
      ),
    );
  },
);

export const notifyPortalOfStudentAppointmentAction = onDocumentUpdated(
  {document: "appointments/{appointmentId}", retry: true},
  async (event) => {
    const before = event.data?.before.data() ?? {};
    const after = event.data?.after.data() ?? {};
    const beforeStatus = canonicalAppointmentStatus(before.status);
    const afterStatus = canonicalAppointmentStatus(after.status);
    const isStudentProposal = afterStatus === "reschedule_proposed" && after.proposedBy === "student";
    const isStudentCancellation = afterStatus === "cancelled" && after.cancelledBy === after.userId;
    const acceptedCounselorProposal = beforeStatus === "reschedule_proposed" && before.proposedBy === "counselor" && afterStatus === "confirmed";
    if (!isStudentProposal && !isStudentCancellation && !acceptedCounselorProposal) return;
    const label = isStudentProposal ? "Schedule change requested" : isStudentCancellation ? "Appointment cancelled by student" : "Schedule change accepted";
    await notifyClinicalStaff("appointment", event.params.appointmentId);
    // Keep a durable, action-specific staff record alongside the existing
    // new-appointment notification, without exposing the student's concern.
    const staff = await db.collection("users").where("accessRole", "in", ["portalStaff", "counselor", "admin"]).get();
    await Promise.all(staff.docs.map((recipient) => db.collection("notifications").doc(`portal_appointment_action_${event.params.appointmentId}_${afterStatus}_${recipient.id}`).set({
      userId: recipient.id, audience: "portal", type: "appointment", appointmentId: event.params.appointmentId,
      title: label, body: "An appointment needs your review.", createdAt: FieldValue.serverTimestamp(), readAt: null,
    }, {merge: true})));
  },
);

export const notifyPortalOfInquiry = onDocumentCreated(
  {document: "inquiries/{inquiryId}", retry: true},
  async (event) => notifyClinicalStaff("inquiry", event.params.inquiryId),
);

export const scheduleReadNotificationArchive = onDocumentUpdated(
  {document: "notifications/{notificationId}", retry: true},
  async (event) => {
    const change = event.data;
    if (!change) return;
    const before = change.before.data();
    const after = change.after.data();
    if (!after || !isNormalNotificationType(after.type) || after.archivedAt) return;
    if (before?.readAt || !(after.readAt instanceof Timestamp) || after.archiveEligibleAt) return;
    await event.data?.after.ref.update({
      archiveEligibleAt: Timestamp.fromMillis(notificationArchiveAtMillis(after.readAt.toMillis())),
    });
  },
);

async function archiveResolvedPortalNotifications(
  kind: PortalNotificationKind,
  recordId: string,
): Promise<void> {
  const idField = kind === "appointment" ? "appointmentId" : "inquiryId";
  const notifications = await db.collection("notifications").where(idField, "==", recordId).get();
  if (notifications.empty) return;
  const archivedAt = Timestamp.now();
  const expiresAt = Timestamp.fromMillis(notificationDeleteAtMillis(archivedAt.toMillis()));
  const batch = db.batch();
  let updates = 0;
  for (const notification of notifications.docs) {
    const data = notification.data();
    if (data.audience !== "portal" || data.archivedAt) continue;
    batch.update(notification.ref, {
      resolvedAt: archivedAt,
      archivedAt,
      expiresAt,
      archiveEligibleAt: null,
    });
    updates += 1;
  }
  if (updates > 0) await batch.commit();
}

export const resolvePortalAppointmentNotifications = onDocumentUpdated(
  {document: "appointments/{appointmentId}", retry: true},
  async (event) => {
    const before = String(event.data?.before.data()?.status ?? "").toLowerCase();
    const after = String(event.data?.after.data()?.status ?? "").toLowerCase();
    const terminal = new Set(["completed", "complete", "declined", "cancelled", "canceled", "no_show", "noshow", "expired"]);
    if (terminal.has(after) && !terminal.has(before)) {
      await archiveResolvedPortalNotifications("appointment", event.params.appointmentId);
    }
  },
);

export const resolvePortalInquiryNotifications = onDocumentUpdated(
  {document: "inquiries/{inquiryId}", retry: true},
  async (event) => {
    const before = String(event.data?.before.data()?.status ?? "").toLowerCase();
    const after = String(event.data?.after.data()?.status ?? "").toLowerCase();
    if (after === "resolved" && before !== "resolved") {
      await archiveResolvedPortalNotifications("inquiry", event.params.inquiryId);
    }
  },
);

export const archiveReadNotifications = onSchedule(
  {
    schedule: "every day 02:00",
    timeZone: "Asia/Manila",
    region: "asia-east1",
    timeoutSeconds: 300,
  },
  async () => {
    const now = Timestamp.now();
    const expiresAt = Timestamp.fromMillis(notificationDeleteAtMillis(now.toMillis()));
    for (let page = 0; page < 10; page += 1) {
      const eligible = await db.collection("notifications")
        .where("archiveEligibleAt", "<=", now)
        .limit(400)
        .get();
      if (eligible.empty) break;
      const batch = db.batch();
      for (const notification of eligible.docs) {
        batch.update(notification.ref, {
          archivedAt: now,
          expiresAt,
          archiveEligibleAt: null,
        });
      }
      await batch.commit();
      if (eligible.size < 400) break;
    }

    // Cursor through notifications read before lifecycle tracking existed.
    // The cursor prevents archived records from being rescanned every day.
    const stateRef = db.collection("_notification_lifecycle").doc("read_backfill");
    for (let page = 0; page < 10; page += 1) {
      const state = await stateRef.get();
      const cursorReadAt = state.data()?.cursorReadAt;
      const cursorId = String(state.data()?.cursorId ?? "");
      const readCutoff = Timestamp.fromMillis(
        now.toMillis() - NOTIFICATION_ARCHIVE_AFTER_DAYS * DAY_MILLIS,
      );
      let query = db.collection("notifications")
        .where("readAt", "<=", readCutoff)
        .orderBy("readAt")
        .orderBy(FieldPath.documentId())
        .limit(400);
      if (cursorReadAt instanceof Timestamp && cursorId) {
        query = query.startAfter(cursorReadAt, cursorId);
      }
      const legacy = await query.get();
      if (legacy.empty) break;
      const batch = db.batch();
      for (const notification of legacy.docs) {
        const data = notification.data();
        if (isNormalNotificationType(data.type) && !data.archivedAt) {
          batch.update(notification.ref, {
            archivedAt: now,
            expiresAt,
            archiveEligibleAt: null,
          });
        }
      }
      const last = legacy.docs.at(-1)!;
      batch.set(stateRef, {
        cursorReadAt: last.data().readAt,
        cursorId: last.id,
        updatedAt: now,
      }, {merge: true});
      await batch.commit();
      if (legacy.size < 400) break;
    }
  },
);

export function appointmentSlotId(timestamp: Pick<Timestamp, "toMillis">, staffId = "pacc"): string {
  return `${staffId}_${timestamp.toMillis()}`;
}

function createAppointmentEvent(transaction: FirebaseFirestore.Transaction, appointment: FirebaseFirestore.DocumentReference, type: string, actorId: string, previousStatus: string, newStatus: string, metadata: Record<string, unknown> = {}) {
  transaction.create(appointment.collection("history").doc(), {
    type, performedBy: actorId, performedByRole: "system", previousStatus,
    newStatus, metadata, timestamp: FieldValue.serverTimestamp(), createdAt: FieldValue.serverTimestamp(),
  });
}

/**
 * Fields intentionally safe for the general PAACC scheduling queue. Keep this
 * separate from the clinical appointment record: portal staff must never need
 * a concern, contact information, demographics, or counseling history to run
 * the front-desk schedule.
 */
export function portalAppointmentQueueProjection(
  appointmentId: string,
  appointment: FirebaseFirestore.DocumentData,
): FirebaseFirestore.DocumentData {
  return {
    appointmentId,
    studentDisplayName: String(appointment.fullName ?? "").trim(),
    scheduledAt: appointment.scheduledAt ?? Timestamp.now(),
    scheduledTime: String(appointment.scheduledTime ?? "").trim(),
    status: String(appointment.status ?? "requested").trim().toLowerCase(),
    assignedCounselor: String(appointment.counselorName ?? "").trim(),
    isArchived: appointment.archivedAt != null,
    sourceUpdatedAt: appointment.updatedAt ?? appointment.createdAt ?? Timestamp.now(),
    projectedAt: FieldValue.serverTimestamp(),
  };
}

export const refreshPortalAppointmentQueue = onCall(async (request) => {
  const staffId = requireAuthenticatedUser(request);
  const staff = await requireStaff(staffId);
  if (staff.accessRole !== "portalStaff") {
    throw new HttpsError("permission-denied", "PAACC staff access is required.");
  }

  const appointments = await db.collection("appointments").get();
  const writer = db.bulkWriter();
  for (const appointment of appointments.docs) {
    writer.set(
      portalAppointmentQueue.doc(appointment.id),
      portalAppointmentQueueProjection(appointment.id, appointment.data()),
    );
  }
  await writer.close();
  return {refreshed: appointments.size};
});

export const savePaccAvailability = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  const actor = await requireStaff(actorId);
  if (!canManagePaccAvailability(actor.accessRole)) {
    throw new HttpsError("permission-denied", "Counselor or administrator access is required.");
  }
  let availability;
  try {
    availability = validatePaccAvailabilityPayload(request.data);
  } catch (error: unknown) {
    if (error instanceof AppointmentAvailabilityValidationError) {
      throw new HttpsError("invalid-argument", error.message);
    }
    throw error;
  }
  const current = db.collection("pacc_availability").doc("current");
  await db.runTransaction(async (transaction) => {
    const before = await transaction.get(current);
    transaction.set(current, {
      ...availability,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    writeAudit(transaction, db, {
      actorId,
      actorNameSnapshot: actorName(actor),
      actorRoleSnapshot: actor.accessRole,
      action: "SCHEDULE_UPDATED",
      category: AUDIT_CATEGORIES.schedule,
      targetType: "pacc_availability",
      targetId: "current",
      metadata: {
        before: before.exists ? before.data() ?? null : null,
        after: availability,
      },
    });
  });
  return {ok: true};
});

function manilaSlotMillis(date: string, minutes: number): number {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
  if (!match) throw new HttpsError("invalid-argument", "Choose a valid appointment date.");
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const local = new Date(Date.UTC(year, month - 1, day, 0, minutes));
  if (local.getUTCFullYear() !== year || local.getUTCMonth() !== month - 1 || local.getUTCDate() !== day) {
    throw new HttpsError("invalid-argument", "Choose a valid appointment date.");
  }
  // Asia/Manila is UTC+08:00; scheduling already uses this canonical zone.
  return local.getTime() - 8 * 60 * 60 * 1000;
}

export const getAvailableAppointmentSlots = onCall(async (request) => {
  requireAuthenticatedUser(request);
  const input = (request.data ?? {}) as Record<string, unknown>;
  const date = String(input.date ?? "").trim();
  const availabilitySnapshot = await db.collection("pacc_availability").doc("current").get();
  const policySnapshot = await db.collection("appointment_policy").doc("current").get();
  const policy = appointmentBookingPolicy(policySnapshot.exists ? policySnapshot.data() : null);
  const slots: Array<{start: number; label: string}> = [];
  for (let minutes = 0; minutes < 24 * 60; minutes += 60) {
    const start = manilaSlotMillis(date, minutes);
    try {
      validateAppointmentTimestamp(start);
      validatePaccAppointmentAvailability(start, availabilitySnapshot.exists ? availabilitySnapshot.data() : null);
      if (bookingPolicyViolation(policy, start)) continue;
    } catch (error) {
      if (error instanceof AppointmentSchedulingValidationError || error instanceof AppointmentAvailabilityValidationError) continue;
      throw error;
    }
    const occupied = await db.collection("appointment_slots").doc(appointmentSlotId(Timestamp.fromMillis(start))).get();
    if (!occupied.exists) slots.push({start, label: formatAppointmentTime(start)});
  }
  return {date, slots};
});

export const createAppointmentRequest = onCall(async (request) => {
  const userId = requireAuthenticatedUser(request);
  const input = (request.data ?? {}) as Record<string, unknown>;
  const concern = boundedText(input.concern, "Concern", 2_000, {required: true});
  let schedule: {millis: number; scheduledTime: string};
  try {
    schedule = validateAppointmentTimestamp(input.scheduledAt);
  } catch (error: unknown) {
    if (error instanceof AppointmentSchedulingValidationError) {
      throw new HttpsError("invalid-argument", error.message);
    }
    throw error;
  }
  const scheduledAt = Timestamp.fromMillis(schedule.millis);
  const appointment = db.collection("appointments").doc();
  const parentAppointmentId = boundedText(input.parentAppointmentId, "Parent appointment", 128);
  const slot = db.collection("appointment_slots").doc(appointmentSlotId(scheduledAt));
  const availability = db.collection("pacc_availability").doc("current");
  const policyDocument = db.collection("appointment_policy").doc("current");
  const rateLimit = db.collection("_appointment_rate_limits").doc(userId);
  const profile = await db.collection("users").doc(userId).get();
  await db.runTransaction(async (transaction) => {
    const parent = parentAppointmentId ? db.collection("appointments").doc(parentAppointmentId) : null;
    const [occupied, availabilitySnapshot, policySnapshot, existingAppointments, rateLimitSnapshot, parentSnapshot] = await Promise.all([
      transaction.get(slot),
      transaction.get(availability),
      transaction.get(policyDocument),
      transaction.get(db.collection("appointments").where("userId", "==", userId)),
      transaction.get(rateLimit),
      parent ? transaction.get(parent) : Promise.resolve(null),
    ]);
    if (parentSnapshot) {
      const parentData = parentSnapshot.data();
      if (!parentData || String(parentData.userId ?? "") !== userId ||
          !["completed", "no_show", "cancelled", "declined", "expired"].includes(canonicalAppointmentStatus(parentData.status))) {
        throw new HttpsError("permission-denied", "This follow-up appointment is unavailable.");
      }
    }
    const policy = appointmentBookingPolicy(policySnapshot.exists ? policySnapshot.data() : null);
    const policyError = bookingPolicyViolation(policy, schedule.millis);
    if (policyError) throw new HttpsError("failed-precondition", policyError);
    const statuses = existingAppointments.docs.map((item) => canonicalAppointmentStatus(item.data().status));
    if (policy.maxActiveAppointments !== null && statuses.filter((status) => APPOINTMENT_ACTIVE_STATUSES.has(status)).length >= policy.maxActiveAppointments) {
      throw new HttpsError("resource-exhausted", "You have reached the active appointment limit.");
    }
    if (policy.maxPendingAppointments !== null && statuses.filter((status) => status === "requested").length >= policy.maxPendingAppointments) {
      throw new HttpsError("resource-exhausted", "You have reached the pending appointment limit.");
    }
    if (policy.rateLimitWindowMinutes !== null && policy.rateLimitCount !== null) {
      const now = Timestamp.now();
      const started = rateLimitSnapshot.data()?.windowStartedAt as Timestamp | undefined;
      const withinWindow = started && now.toMillis() - started.toMillis() < policy.rateLimitWindowMinutes * 60_000;
      const count = withinWindow ? Number(rateLimitSnapshot.data()?.count ?? 0) : 0;
      if (count >= policy.rateLimitCount) throw new HttpsError("resource-exhausted", "Too many appointment requests. Please try again later.");
      transaction.set(rateLimit, {windowStartedAt: withinWindow ? started : now, count: count + 1, updatedAt: FieldValue.serverTimestamp()});
    }
    if (occupied.exists) throw new HttpsError("already-exists", "This time is no longer available. Please choose another schedule.");
    try {
      validatePaccAppointmentAvailability(
        schedule.millis,
        availabilitySnapshot.exists ? availabilitySnapshot.data() : null,
      );
    } catch (error: unknown) {
      if (error instanceof AppointmentAvailabilityValidationError) {
        throw new HttpsError("failed-precondition", error.message);
      }
      throw error;
    }
    const source = profile.data() ?? {};
    const profileName = String(
      source.name ??
          [source.firstName, source.middleName, source.lastName]
            .filter((part) => typeof part === "string" && part.trim())
            .join(" "),
    ).trim();
    transaction.create(slot, {appointmentId: appointment.id, scheduledAt, createdAt: FieldValue.serverTimestamp()});
    transaction.create(appointment, {
      // Profile-derived identity wins over client payloads. Contact fields stay
      // editable by design, with a profile value only as the initial fallback.
      userId, fullName: boundedText(profileName || input.fullName, "Full name", 160),
      contactNumber: appointmentPhone(input.contactNumber ?? source.phone), email: appointmentEmail(source.email ?? input.email),
      preferredContactMethod: boundedText(input.preferredContactMethod, "Preferred contact method", 64), concern,
      bestTime: boundedText(input.bestTime, "Preferred time", 120), location: boundedText(input.location ?? "PACC Office, 2nd Floor, Main Building", "Location", 200),
      scheduledAt, scheduledTime: schedule.scheduledTime, status: "requested", createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      department: boundedText(source.department ?? input.department, "Department", 160), academicYearId: boundedText(input.academicYearId, "Academic year", 80),
      ...(parentAppointmentId ? {parentAppointmentId} : {}),
      age: input.age ?? null, address: boundedText(input.address, "Address", 300), facebook: boundedText(input.facebook, "Social contact", 120), sex: boundedText(input.sex, "Sex", 32), course: boundedText(source.course ?? input.course, "Course", 160), yearLevel: boundedText(input.yearLevel, "Year level", 64), therapyBefore: boundedText(input.therapyBefore, "Counseling history", 500),
    });
    createAppointmentEvent(transaction, appointment, "appointment_requested", userId, "", "requested");
  });
  return {ok: true, appointmentId: appointment.id};
});

export const respondToAppointment = onCall(async (request) => {
  const userId = requireAuthenticatedUser(request);
  const input = (request.data ?? {}) as Record<string, unknown>;
  const appointmentId = String(input.appointmentId ?? "").trim();
  const action = String(input.action ?? "").trim();
  if (!appointmentId || !["cancel", "accept_reschedule", "propose_reschedule"].includes(action)) throw new HttpsError("invalid-argument", "A valid appointment action is required.");
  const appointment = db.collection("appointments").doc(appointmentId);
  const policyDocument = db.collection("appointment_policy").doc("current");
  const availabilityDocument = db.collection("pacc_availability").doc("current");
  await db.runTransaction(async (transaction) => {
    const [snapshot, policySnapshot, availabilitySnapshot] = await Promise.all([
      transaction.get(appointment),
      transaction.get(policyDocument),
      transaction.get(availabilityDocument),
    ]);
    if (!snapshot.exists || String(snapshot.data()?.userId ?? "") !== userId) throw new HttpsError("permission-denied", "This appointment is unavailable.");
    const data = snapshot.data()!;
    const before = canonicalAppointmentStatus(data.status);
    if (!APPOINTMENT_ACTIVE_STATUSES.has(before)) throw new HttpsError("failed-precondition", "This appointment can no longer be changed.");
    const notification = db.collection("notifications").doc();
    if (action === "cancel") {
      if (!canTransitionAppointment(before, "student", "cancelled")) {
        throw new HttpsError("failed-precondition", "This appointment cannot be cancelled in its current state.");
      }
      const cutoff = appointmentBookingPolicy(
        policySnapshot.exists ? policySnapshot.data() : null,
      );
      const cancellationReason = boundedText(input.reason, "Cancellation reason", 500);
      if (cutoff.requireCancellationReason && !cancellationReason) {
        throw new HttpsError("invalid-argument", "Provide a cancellation reason.");
      }
      const scheduledAt = data.scheduledAt as Timestamp;
      if (cutoff.cancellationCutoffMinutes !== null && scheduledAt.toMillis() - Date.now() < cutoff.cancellationCutoffMinutes * 60_000) {
        throw new HttpsError("failed-precondition", "This appointment is inside the cancellation cutoff window.");
      }
      transaction.update(appointment, {status: "cancelled", cancelledBy: userId, cancelledAt: FieldValue.serverTimestamp(), cancellationReason, updatedAt: FieldValue.serverTimestamp()});
      transaction.delete(db.collection("appointment_slots").doc(appointmentSlotId(data.scheduledAt as Timestamp)));
      createAppointmentEvent(transaction, appointment, "appointment_cancelled", userId, before, "cancelled");
      if (data.assignedStaffId) transaction.create(notification, {userId: data.assignedStaffId, appointmentId, type: "appointment", title: "Appointment cancelled", body: "A student cancelled an appointment.", createdAt: FieldValue.serverTimestamp(), readAt: null});
      return;
    }
    if (action === "accept_reschedule") {
      if (!canTransitionAppointment(before, "student", "confirmed") || !data.proposedScheduledAt) throw new HttpsError("failed-precondition", "There is no active schedule proposal.");
      const proposedAt = data.proposedScheduledAt as Timestamp;
      try {
        validatePaccAppointmentAvailability(
          proposedAt.toMillis(),
          availabilitySnapshot.exists ? availabilitySnapshot.data() : null,
        );
      } catch (error: unknown) {
        if (error instanceof AppointmentAvailabilityValidationError) {
          throw new HttpsError("failed-precondition", error.message);
        }
        throw error;
      }
      const oldSlot = db.collection("appointment_slots").doc(appointmentSlotId(data.scheduledAt as Timestamp));
      // Existing bookings reserve the shared PACC slot. Keep every lifecycle
      // transition on that same key until counselor-specific availability is
      // introduced as a compatible, server-side migration.
      const newSlot = db.collection("appointment_slots").doc(appointmentSlotId(proposedAt));
      const claimed = await transaction.get(newSlot);
      if (claimed.exists) throw new HttpsError("already-exists", "This time is no longer available. Please choose another schedule.");
      transaction.delete(oldSlot); transaction.create(newSlot, {appointmentId, scheduledAt: proposedAt, createdAt: FieldValue.serverTimestamp()});
      transaction.update(appointment, {status: "confirmed", scheduledAt: proposedAt, scheduledTime: data.proposedScheduledTime ?? "", proposedScheduledAt: FieldValue.delete(), proposedScheduledTime: FieldValue.delete(), proposedBy: FieldValue.delete(), proposalStatus: FieldValue.delete(), reminders: {}, updatedAt: FieldValue.serverTimestamp()});
      createAppointmentEvent(transaction, appointment, "reschedule_accepted", userId, before, "confirmed");
      return;
    }
    if (!canTransitionAppointment(before, "student", "reschedule_proposed")) throw new HttpsError("failed-precondition", "Only confirmed appointments can be rescheduled.");
    let proposal: {millis: number; scheduledTime: string};
    try {
      proposal = validateAppointmentTimestamp(input.proposedScheduledAt);
    } catch (error: unknown) {
      if (error instanceof AppointmentSchedulingValidationError) throw new HttpsError("invalid-argument", error.message);
      throw error;
    }
    transaction.update(appointment, {status: "reschedule_proposed", proposedScheduledAt: Timestamp.fromMillis(proposal.millis), proposedScheduledTime: proposal.scheduledTime, proposedBy: "student", proposalStatus: "awaiting_counselor", updatedAt: FieldValue.serverTimestamp()});
    createAppointmentEvent(transaction, appointment, "reschedule_proposed", userId, before, "reschedule_proposed");
  });
  return {ok: true};
});

export const reviewAppointment = onCall(async (request) => {
  const staffId = request.auth?.uid;
  if (!staffId) throw new HttpsError("unauthenticated", "Sign in is required.");
  const staff = await requireStaff(staffId);
  const input = request.data as Record<string, unknown>;
  const appointmentId = String(input.appointmentId ?? "").trim();
  const action = String(input.action ?? "").trim();
  const reply = boundedText(input.reply, "Reply", 1_000, {required: true});
  let proposal: {millis: number; scheduledTime: string} | null = null;
  if (!appointmentId || !["confirmed", "declined", "reschedule_proposed", "completed", "no_show", "cancelled"].includes(action)) {
    throw new HttpsError("invalid-argument", "A valid appointment decision is required.");
  }
  if (action === "reschedule_proposed") {
    try {
      proposal = validateAppointmentTimestamp(input.proposedScheduledAt);
    } catch (error: unknown) {
      if (error instanceof AppointmentSchedulingValidationError) throw new HttpsError("invalid-argument", error.message);
      throw error;
    }
  }

  const appointment = db.collection("appointments").doc(appointmentId);
  const notification = db.collection("notifications").doc();
  const history = appointment.collection("history").doc();
  const availabilityDocument = db.collection("pacc_availability").doc("current");
  await db.runTransaction(async (transaction) => {
    const [current, availabilitySnapshot] = await Promise.all([
      transaction.get(appointment),
      transaction.get(availabilityDocument),
    ]);
    if (!current.exists) throw new HttpsError("not-found", "Appointment not found.");
    const data = current.data()!;
    // A counselor may claim an unassigned request while reviewing it. Once
    // assigned, only that counselor (or an administrator) may transition it.
    if (staff.accessRole === "counselor" && data.assignedStaffId && String(data.assignedStaffId) !== staffId) {
      throw new HttpsError("permission-denied", "This appointment is not assigned to your caseload.");
    }
    const before = canonicalAppointmentStatus(data.status);
    if (!APPOINTMENT_ACTIVE_STATUSES.has(before) || !canTransitionAppointment(before, "staff", action)) {
      throw new HttpsError("failed-precondition", "This appointment has already been finalized.");
    }
    const userId = String(data.userId ?? "");
    if (!userId) throw new HttpsError("failed-precondition", "Appointment has no student.");
    const staffName = String(staff.name ?? staff.email ?? "Counseling staff");
    const acceptingProposal = before === "reschedule_proposed" && action === "confirmed" && data.proposedScheduledAt instanceof Timestamp;
    if (acceptingProposal) {
      try {
        validatePaccAppointmentAvailability(
          (data.proposedScheduledAt as Timestamp).toMillis(),
          availabilitySnapshot.exists ? availabilitySnapshot.data() : null,
        );
      } catch (error: unknown) {
        if (error instanceof AppointmentAvailabilityValidationError) {
          throw new HttpsError("failed-precondition", error.message);
        }
        throw error;
      }
      const proposedSlot = db.collection("appointment_slots").doc(appointmentSlotId(data.proposedScheduledAt as Timestamp));
      const occupied = await transaction.get(proposedSlot);
      if (occupied.exists) throw new HttpsError("already-exists", "This time is no longer available. Please choose another schedule.");
      transaction.delete(db.collection("appointment_slots").doc(appointmentSlotId(data.scheduledAt as Timestamp)));
      transaction.create(proposedSlot, {appointmentId, scheduledAt: data.proposedScheduledAt, createdAt: FieldValue.serverTimestamp()});
    }
    const patch: Record<string, unknown> = {
      status: action,
      assignedStaffId: staffId,
      counselorName: staffName,
      staffReply: reply,
      reviewedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      proposedScheduledAt: action === "reschedule_proposed" ? Timestamp.fromMillis(proposal!.millis) : null,
      proposedScheduledTime: action === "reschedule_proposed" ? proposal!.scheduledTime : "",
      proposedBy: action === "reschedule_proposed" ? "counselor" : FieldValue.delete(),
      proposalStatus: action === "reschedule_proposed" ? "awaiting_student" : FieldValue.delete(),
      ...(acceptingProposal ? {scheduledAt: data.proposedScheduledAt, scheduledTime: data.proposedScheduledTime ?? "", reminders: {}} : {}),
      completedAt: action === "completed" ? FieldValue.serverTimestamp() : null,
      noShowAt: action === "no_show" ? FieldValue.serverTimestamp() : null,
      cancelledAt: action === "cancelled" ? FieldValue.serverTimestamp() : null,
      cancellationReason: action === "cancelled" ? reply : null,
    };
    transaction.update(appointment, patch);
    transaction.create(history, {
      previousStatus: before,
      status: action,
      reply,
      proposedScheduledAt: patch.proposedScheduledAt ?? null,
      proposedScheduledTime: patch.proposedScheduledTime,
      staffId,
      staffName,
      createdAt: FieldValue.serverTimestamp(),
    });
    const title = action === "confirmed" ? "PACC Appointment Confirmed" : action === "declined" ? "Appointment request declined" : action === "completed" ? "Appointment completed" : action === "no_show" ? "Appointment marked no-show" : action === "cancelled" ? "Appointment cancelled" : "Schedule Change Proposed";
    transaction.create(notification, {
      userId,
      appointmentId,
      type: action === "confirmed" ? "appointment_confirmed" : action === "declined" ? "appointment_declined" : action === "completed" ? "appointment_completed" : action === "cancelled" ? "appointment_cancelled" : action === "reschedule_proposed" ? "reschedule_proposed" : "appointment_update",
      title,
      body: reply,
      createdAt: FieldValue.serverTimestamp(),
      readAt: null,
    });
    const auditAction = action === "confirmed" ? "APPOINTMENT_CONFIRMED"
      : action === "completed" ? "APPOINTMENT_COMPLETED"
        : action === "no_show" ? "APPOINTMENT_MARKED_NO_SHOW"
          : action === "cancelled" ? "APPOINTMENT_CANCELLED"
      : action === "reschedule_proposed" ? "APPOINTMENT_RESCHEDULED" : "APPOINTMENT_DECLINED";
    writeAudit(transaction, db, {
      actorId: staffId,
      actorNameSnapshot: actorName(staff),
      actorRoleSnapshot: staff.accessRole,
      action: auditAction,
      category: AUDIT_CATEGORIES.appointments,
      targetType: "appointment",
      targetId: appointmentId,
      metadata: {
        before: {status: before},
        after: {status: action, ...(action === "reschedule_proposed" ? {date: new Date(proposal!.millis).toISOString().slice(0, 10), time: proposal!.scheduledTime} : {})},
      },
    });
  });
  return {ok: true};
});

export const archiveAppointments = onCall(async (request) => {
  const actorId = requireAuthenticatedUser(request);
  const actor = await requireStaff(actorId);
  const rawIds = Array.isArray(request.data?.appointmentIds) ? request.data.appointmentIds : [];
  const appointmentIds: string[] = Array.from(new Set<string>(rawIds.filter((value: unknown): value is string => typeof value === "string" && value.trim().length > 0)));
  const archived = request.data?.archived === true;
  if (appointmentIds.length < 1 || appointmentIds.length > 200) throw new HttpsError("invalid-argument", "Select between 1 and 200 appointments.");
  const refs = appointmentIds.map((id) => db.collection("appointments").doc(id));
  await db.runTransaction(async (transaction) => {
    const snapshots = await Promise.all(refs.map((ref) => transaction.get(ref)));
    for (const snapshot of snapshots) {
      if (!snapshot.exists) throw new HttpsError("not-found", "One or more appointments could not be found.");
      const data = snapshot.data() ?? {};
      const status = String(data.status ?? "").toLowerCase().trim();
      const terminal = ["completed", "complete", "declined", "cancelled", "canceled", "no_show", "noshow"].includes(status);
      if (!archived && !data.archivedAt) throw new HttpsError("failed-precondition", "Only archived appointments can be restored.");
      if (archived && !terminal) throw new HttpsError("failed-precondition", "Only finished appointments can be moved to history.");
      if (actor.accessRole === "counselor" && String(data.assignedStaffId ?? "") !== actorId) throw new HttpsError("permission-denied", "You can only manage your assigned appointments.");
      transaction.update(snapshot.ref, {archivedAt: archived ? FieldValue.serverTimestamp() : FieldValue.delete(), archivedBy: archived ? actorId : FieldValue.delete(), updatedAt: FieldValue.serverTimestamp()});
      writeAudit(transaction, db, {actorId, actorNameSnapshot: actorName(actor), actorRoleSnapshot: actor.accessRole, action: archived ? "APPOINTMENT_MOVED_TO_HISTORY" : "APPOINTMENT_RESTORED_FROM_HISTORY", category: AUDIT_CATEGORIES.appointments, targetType: "appointment", targetId: snapshot.id, metadata: {status, bulk: appointmentIds.length > 1}});
    }
  });
  return {ok: true, affected: appointmentIds.length};
});

// Keep the active queue operational: once an appointment reaches a terminal
// outcome, preserve it in History automatically.
export const archiveTerminalAppointment = onDocumentUpdated(
  {document: "appointments/{appointmentId}", retry: true},
  async (event) => {
    const change = event.data;
    if (!change) return;
    const before = change.before.data();
    const after = change.after.data();
    if (!after || after.archivedAt) return;
    const status = String(after.status ?? "").toLowerCase().trim();
    const terminal = ["completed", "complete", "declined", "cancelled", "canceled", "no_show", "noshow"].includes(status);
    if (!terminal || String(before?.status ?? "").toLowerCase().trim() === status) return;
    await change.after.ref.update({archivedAt: FieldValue.serverTimestamp(), archivedBy: "system", updatedAt: FieldValue.serverTimestamp()});
  },
);

export const sendAppointmentNotification = onDocumentCreated(
  {
    document: "notifications/{notificationId}",
    retry: true,
    // This trigger is already deployed in asia-east1. Keep its source
    // definition explicit so a targeted deploy updates it in place.
    region: "asia-east1",
  },
  async (event) => {
    const notification = event.data?.data();
    if (!notification || !(String(notification.type ?? "") === "inquiry" || String(notification.type ?? "").startsWith("appointment") || String(notification.type ?? "").startsWith("reschedule"))) return;
    const userId = String(notification.userId ?? "");
    if (!userId) return;
    const tokens = await db.collection("user_devices").doc(userId).collection("tokens").get();
    const values = tokens.docs.map((document) => String(document.data().token ?? "")).filter(Boolean);
    if (!values.length) return;
    const result = await getMessaging().sendEachForMulticast({
      tokens: values,
      notification: {title: String(notification.title ?? "MindMate"), body: String(notification.body ?? "")},
      data: {
        type: String(notification.type),
        appointmentId: String(notification.appointmentId ?? ""),
        inquiryId: String(notification.inquiryId ?? ""),
      },
    });
    const invalid = result.responses
      .map((response, index) => !response.success ? values[index] : "")
      .filter(Boolean);
    await Promise.all(invalid.map((token) => db.collection("user_devices").doc(userId).collection("tokens").doc(token).delete()));
  },
);

export const acknowledgeInquiry = onCall(async (request) => {
  const staffId = request.auth?.uid;
  if (!staffId) throw new HttpsError("unauthenticated", "Sign in is required.");
  const staff = await requireStaff(staffId);
  const inquiryId = String(request.data?.inquiryId ?? "").trim();
  if (!inquiryId) throw new HttpsError("invalid-argument", "Inquiry ID is required.");
  const inquiry = db.collection("inquiries").doc(inquiryId);
  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(inquiry);
    if (!current.exists) throw new HttpsError("not-found", "Inquiry not found.");
    const data = current.data()!;
    if (data.acknowledgedAt) {
      throw new HttpsError("failed-precondition", "A receipt notification was already sent.");
    }
    const userId = String(data.userId ?? "");
    if (!userId) throw new HttpsError("failed-precondition", "Inquiry has no sender.");
    transaction.update(inquiry, {
      status: "in_progress",
      acknowledgedAt: FieldValue.serverTimestamp(),
      acknowledgedBy: staffId,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(db.collection("notifications").doc(), {
      userId,
      inquiryId,
      type: "inquiry",
      title: "Form received",
      body: `PAACC received your ${String(data.subject ?? "form")}. Our staff will review it.`,
      staffName: String(staff.name ?? staff.email ?? "PAACC staff"),
      createdAt: FieldValue.serverTimestamp(),
      readAt: null,
    });
  });
  return {ok: true};
});

const REMINDER_WINDOWS: Array<{key: "twentyFourHour" | "oneHour"; minutes: number}> = [
  {key: "twentyFourHour", minutes: 24 * 60},
  {key: "oneHour", minutes: 60},
];

/** Runs independently of Flutter so reminders are durable across devices. */
export const sendAppointmentReminders = onSchedule(
  {schedule: "every 10 minutes", timeZone: "Asia/Manila", retryCount: 3},
  async () => {
    const now = Timestamp.now();
    const lower = Timestamp.fromMillis(now.toMillis() + 45 * 60 * 1000);
    const upper = Timestamp.fromMillis(now.toMillis() + (24 * 60 + 15) * 60 * 1000);
    const candidates = await db.collection("appointments")
      .where("status", "==", "confirmed")
      .where("scheduledAt", ">=", lower)
      .where("scheduledAt", "<=", upper)
      .get();
    await Promise.all(candidates.docs.flatMap((appointment) => REMINDER_WINDOWS.map(async ({key, minutes}) => {
      const data = appointment.data();
      const scheduledAt = data.scheduledAt;
      if (!(scheduledAt instanceof Timestamp)) return;
      const target = scheduledAt.toMillis() - minutes * 60 * 1000;
      // The scheduler may run late; only deliver within a bounded window.
      if (now.toMillis() < target || now.toMillis() > target + 15 * 60 * 1000) return;
      const notification = db.collection("notifications").doc(`appointment_reminder_${key}_${appointment.id}`);
      try {
        await db.runTransaction(async (transaction) => {
          const fresh = await transaction.get(appointment.ref);
          const current = fresh.data() ?? {};
          if (canonicalAppointmentStatus(current.status) !== "confirmed" || current.reminders?.[key]) return;
          transaction.create(notification, {
            userId: String(current.userId ?? ""), appointmentId: appointment.id,
            type: "appointment_reminder", title: "PACC Appointment Reminder",
            body: minutes === 60 ? "You have a PACC appointment in about an hour." : "You have a PACC appointment tomorrow.",
            reminderStage: key, createdAt: FieldValue.serverTimestamp(), readAt: null,
          });
          transaction.update(appointment.ref, {[`reminders.${key}`]: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
        });
      } catch (error: unknown) {
        const code = typeof error === "object" && error !== null && "code" in error ? String((error as {code?: unknown}).code) : "";
        if (code !== "6" && code !== "already-exists") throw error;
      }
    })));
  },
);

/** Expires only configured, still-unreviewed requests and releases their slot. */
export const expireStaleAppointmentRequests = onSchedule(
  {schedule: "every 60 minutes", timeZone: "Asia/Manila", retryCount: 3},
  async () => {
    const policySnapshot = await db.collection("appointment_policy").doc("current").get();
    const hours = appointmentBookingPolicy(policySnapshot.exists ? policySnapshot.data() : null).staleRequestExpiryHours;
    if (hours === null) return;
    const cutoff = Timestamp.fromMillis(Date.now() - hours * 60 * 60 * 1000);
    const candidates = await db.collection("appointments")
      .where("status", "==", "requested")
      .where("createdAt", "<=", cutoff)
      .limit(400)
      .get();
    await Promise.all(candidates.docs.map(async (appointment) => {
      await db.runTransaction(async (transaction) => {
        const current = await transaction.get(appointment.ref);
        const data = current.data();
        if (!data || canonicalAppointmentStatus(data.status) !== "requested" ||
            !(data.createdAt instanceof Timestamp) || data.createdAt.toMillis() > cutoff.toMillis()) return;
        const userId = String(data.userId ?? "");
        transaction.update(appointment.ref, {
          status: "expired", expiredAt: FieldValue.serverTimestamp(),
          expiryReason: "Request expired before PAACC review", updatedAt: FieldValue.serverTimestamp(),
        });
        if (data.scheduledAt instanceof Timestamp) {
          transaction.delete(db.collection("appointment_slots").doc(appointmentSlotId(data.scheduledAt)));
        }
        createAppointmentEvent(transaction, appointment.ref, "appointment_expired", "system", "requested", "expired");
        if (userId) transaction.create(db.collection("notifications").doc(), {
          userId, appointmentId: appointment.id, type: "appointment_expired",
          title: "Appointment request expired", body: "Your PACC appointment request was not reviewed in time. Please book a new appointment.",
          createdAt: FieldValue.serverTimestamp(), readAt: null,
        });
      });
    }));
  },
);

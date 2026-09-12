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
} from "./account_recovery";
import {defineString} from "firebase-functions/params";
import {randomBytes} from "node:crypto";
import {AUDIT_ACTIONS, AUDIT_CATEGORIES, actorName, writeAudit} from "./audit";
export {
  aggregateMindAidFeedback,
  sendMindAidMessage,
  sendMindAidMessageDev,
} from "./mind_aid";
export {getReportAnalytics} from "./report_generation";
export {importWalkInAppointments} from "./walk_in_import";
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
  const legacyRole = String(user.data()?.role ?? "").toLowerCase();
  const accessRole = String(user.data()?.accessRole ??
    (legacyRole === "admin" || legacyRole === "counselor" ? legacyRole : "appUser"));
  if (!["portalStaff", "counselor", "admin"].includes(accessRole)) {
    throw new HttpsError("permission-denied", "Staff access is required.");
  }
  return {...(user.data() ?? {}), accessRole};
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
      registrationStatus: "pending_review", accountStatus: "disabled",
      profileVersion: 3, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(requestRef, {
      requestId: requestRef.id, applicantUserId: userId, firstName, lastName,
      employeeId, email, position, office: "PAACC / Guidance Office", requestedRole,
      registrationStatus: "pending_review", submittedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    writeAudit(transaction, db, {actorId: userId, actorNameSnapshot: `${firstName} ${lastName}`,
      actorRoleSnapshot: "appUser", action: "STAFF_ACCESS_REQUEST_SUBMITTED",
      category: AUDIT_CATEGORIES.userManagement, targetType: "staff", targetId: userId,
      metadata: {after: {registrationStatus: "pending_review", requestedRole}, targetLabel: email}});
  });
  return {ok: true, requestId: requestRef.id, reference: `REQ-${requestRef.id.slice(0, 8).toUpperCase()}`};
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
    if (!before.exists || !["pending", "pending_review", "more_information_required"].includes(String(before.data()?.registrationStatus ?? "pending_review"))) {
      throw new HttpsError("failed-precondition", "This registration is no longer pending.");
    }
    const status = approve ? "approved" : moreInfo ? "more_information_required" : "rejected";
    transaction.update(target, {
      staffAccountStatus: approve ? "approved" : moreInfo ? "pending" : "rejected",
      accessRole: approve ? accessRole : "appUser", approvedRole: approve ? accessRole : null,
      registrationStatus: status, accountStatus: approve ? "active" : "disabled",
      verificationStatus: approve ? "verified" : moreInfo ? "pending" : "rejected",
      verifiedBy: approve ? actorId : null,
      verifiedAt: approve ? FieldValue.serverTimestamp() : null,
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
  });
  if (!approve) await getAuth().revokeRefreshTokens(targetUserId);
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
  const collegeId = kind === "course" ? requiredText(request.data?.collegeId, "College", 1, 128) : "";
  if (kind === "course") {
    const college = await db.collection("colleges").doc(collegeId).get();
    if (!college.exists || college.data()?.active !== true) {
      throw new HttpsError("failed-precondition", "Choose an active college.");
    }
  }
  const duplicate = await db.collection(collection).where("normalizedName", "==", name.toLowerCase()).limit(1).get();
  if (duplicate.docs.some((doc) => doc.id !== recordId)) {
    throw new HttpsError("already-exists", `A ${kind} with that name already exists.`);
  }
  await db.collection(collection).doc(recordId).set({name, code, normalizedName: name.toLowerCase(), active,
    ...(kind === "course" ? {collegeId} : {}), updatedBy: actorId, updatedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp()}, {merge: true});
  return {ok: true, id: recordId};
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
    const before = event.data?.before.data();
    const after = event.data?.after.data();
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
    const before = event.data?.before.data();
    const after = event.data?.after.data();
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

export const notifyPortalOfAppointment = onDocumentCreated(
  {document: "appointments/{appointmentId}", retry: true},
  async (event) => notifyClinicalStaff("appointment", event.params.appointmentId),
);

export const notifyPortalOfInquiry = onDocumentCreated(
  {document: "inquiries/{inquiryId}", retry: true},
  async (event) => notifyClinicalStaff("inquiry", event.params.inquiryId),
);

export const scheduleReadNotificationArchive = onDocumentUpdated(
  {document: "notifications/{notificationId}", retry: true},
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
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
    const terminal = new Set(["completed", "complete", "declined", "cancelled", "canceled"]);
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

export const reviewAppointment = onCall(async (request) => {
  const staffId = request.auth?.uid;
  if (!staffId) throw new HttpsError("unauthenticated", "Sign in is required.");
  const staff = await requireStaff(staffId);
  const input = request.data as Record<string, unknown>;
  const appointmentId = String(input.appointmentId ?? "").trim();
  const action = String(input.action ?? "").trim();
  const reply = String(input.reply ?? "").trim();
  const proposedMillis = Number(input.proposedScheduledAt ?? 0);
  const proposedTime = String(input.proposedScheduledTime ?? "").trim();
  // Declined remains readable for legacy records, but is intentionally not a
  // valid action for new appointment decisions.
  if (!appointmentId || !["confirmed", "reschedule_required", "reschedule_proposed", "completed"].includes(action)) {
    throw new HttpsError("invalid-argument", "A valid appointment decision is required.");
  }
  if (!reply) throw new HttpsError("invalid-argument", "A reply to the student is required.");
  if (action === "reschedule_proposed" && (!Number.isFinite(proposedMillis) || proposedMillis <= 0 || !proposedTime)) {
    throw new HttpsError("invalid-argument", "A proposed date and time are required.");
  }

  const appointment = db.collection("appointments").doc(appointmentId);
  const notification = db.collection("notifications").doc();
  const history = appointment.collection("history").doc();
  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(appointment);
    if (!current.exists) throw new HttpsError("not-found", "Appointment not found.");
    const data = current.data()!;
    if (staff.accessRole === "counselor" && String(data.assignedStaffId ?? "") !== staffId) {
      throw new HttpsError("permission-denied", "This appointment is not assigned to your caseload.");
    }
    const before = String(data.status ?? "pending").toLowerCase();
    const allowed = before === "confirmed"
      ? ["completed"]
      : before === "reschedule_required"
        ? ["reschedule_proposed"]
        : ["confirmed", "reschedule_required", "reschedule_proposed"];
    if (!["pending", "upcoming", "reschedule_required", "confirmed"].includes(before) || !allowed.includes(action)) {
      throw new HttpsError("failed-precondition", "This appointment has already been finalized.");
    }
    const userId = String(data.userId ?? "");
    if (!userId) throw new HttpsError("failed-precondition", "Appointment has no student.");
    const staffName = String(staff.name ?? staff.email ?? "Counseling staff");
    const patch: Record<string, unknown> = {
      status: action,
      assignedStaffId: staffId,
      counselorName: staffName,
      staffReply: reply,
      reviewedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      proposedScheduledAt: action === "reschedule_proposed" ? Timestamp.fromMillis(proposedMillis) : null,
      proposedScheduledTime: action === "reschedule_proposed" ? proposedTime : "",
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
    const title = action === "confirmed" ? "Appointment confirmed" : action === "completed" ? "Appointment completed" : action === "reschedule_required" ? "Schedule adjustment needed" : "New appointment time proposed";
    transaction.create(notification, {
      userId,
      appointmentId,
      type: "appointment",
      title,
      body: reply,
      createdAt: FieldValue.serverTimestamp(),
      readAt: null,
    });
    const auditAction = action === "confirmed" ? "APPOINTMENT_CONFIRMED"
      : action === "completed" ? "APPOINTMENT_COMPLETED"
        : action === "reschedule_proposed" ? "APPOINTMENT_RESCHEDULED" : "APPOINTMENT_ADJUSTMENT_REQUESTED";
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
        after: {status: action, ...(action === "reschedule_proposed" ? {date: new Date(proposedMillis).toISOString().slice(0, 10), time: proposedTime} : {})},
      },
    });
  });
  return {ok: true};
});

export const sendAppointmentNotification = onDocumentCreated(
  {document: "notifications/{notificationId}", retry: true},
  async (event) => {
    const notification = event.data?.data();
    if (!notification || !["appointment", "inquiry"].includes(String(notification.type ?? ""))) return;
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

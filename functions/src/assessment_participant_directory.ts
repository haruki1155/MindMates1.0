import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

if (!getApps().length) initializeApp();
const db = getFirestore();

/** Minimal participant display metadata for authorized clinical review screens.
 * Never permits general account lookup: each requested ID must own an assessment.
 */
export const getAssessmentParticipantDirectory = onCall(async (request) => {
  const callerId = request.auth?.uid;
  if (!callerId || request.auth?.token.email_verified !== true) {
    throw new HttpsError("unauthenticated", "Sign in with a verified account.");
  }
  const caller = await db.collection("users").doc(callerId).get();
  const role = String(caller.data()?.accessRole ?? "");
  const status = String(caller.data()?.staffAccountStatus ?? "");
  if (!["admin", "counselor"].includes(role) ||
      (status && status !== "approved") ||
      (caller.data()?.accountStatus && caller.data()?.accountStatus !== "active")) {
    throw new HttpsError("permission-denied", "Clinical access is required.");
  }

  const requested = request.data?.userIds;
  if (!Array.isArray(requested) || requested.length < 1 || requested.length > 80 ||
      requested.some((id: unknown) => typeof id !== "string" || !id.trim() || id.length > 160)) {
    throw new HttpsError("invalid-argument", "Provide between 1 and 80 participant IDs.");
  }
  const ids = [...new Set<string>(requested.map((id: string) => id.trim()))];
  // Verify actual assessment membership before reading restricted user profiles.
  const assessments = await Promise.all(ids.map((id) =>
    db.collection("assessments").where("userId", "==", id).limit(1).get()));
  const verifiedIds = ids.filter((_, i) => !assessments[i].empty);
  if (verifiedIds.length === 0) return {participants: []};
  const profiles = await db.getAll(...verifiedIds.map((id) => db.collection("users").doc(id)));
  const collegeIds = [...new Set(profiles
    .map((snapshot) => String(snapshot.data()?.collegeId ?? "").trim())
    .filter(Boolean))];
  const colleges = collegeIds.length > 0
    ? await db.getAll(...collegeIds.map((id) => db.collection("colleges").doc(id)))
    : [];
  const collegeNames = new Map<string, string>(colleges.map((snapshot): [string, string] => [
    snapshot.id, String(snapshot.data()?.name ?? snapshot.data()?.collegeName ?? "").trim(),
  ]));
  const participants = profiles.map((snapshot) => {
    const profile = snapshot.data() ?? {};
    const parts = [profile.firstName, profile.middleName, profile.lastName]
      .map((value) => String(value ?? "").trim()).filter(Boolean);
    const name = parts.join(" ") || String(profile.name ?? "").trim() || "Name unavailable";
    const collegeId = String(profile.collegeId ?? "").trim();
    const college = (collegeId ? collegeNames.get(collegeId) : "") ||
      String(profile.department ?? "").trim() || "Unassigned";
    return {
      userId: snapshot.id,
      name,
      role: String(profile.populationRole ?? profile.declaredRole ?? profile.role ?? "Unknown"),
      college,
    };
  });
  return {participants};
});

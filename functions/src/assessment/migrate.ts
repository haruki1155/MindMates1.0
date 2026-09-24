import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {getApps, initializeApp} from "firebase-admin/app";
import {calculateFull, calculateQuick, FullAnswer, QuickAnswer, validateFullAnswers, validateQuickAnswers} from "./calculator";
import {roleFromPopulation} from "./catalog";

if (!getApps().length) initializeApp();
const db = getFirestore();

type Counts = {
  verified: number;
  skipped: number;
  malformed: number;
  alreadyProcessed: number;
  profileRoleBackfills: number;
  profileRoleConflicts: number;
  missingProfiles: number;
};

function legacyRole(role: string): string {
  if (role === "teaching") return "faculty";
  if (role === "nonTeaching") return "staff";
  return "student";
}

function answersFrom(data: Record<string, unknown>): {kind: "quick" | "full"; value: unknown[]} {
  const raw = data.responses ?? data.answers;
  if (!Array.isArray(raw)) throw new Error("missing response array");
  const quick = raw.some((item) => item && typeof item === "object" && "optionId" in item);
  return {kind: quick ? "quick" : "full", value: raw};
}

export function migrateAssessmentData(data: Record<string, unknown>): Record<string, unknown> {
  if (data.schemaVersion === "assessment_record_v4") {
    // V4 records carry the catalog snapshot and server-derived result that
    // reproduce the original submission. Never recalculate them as legacy.
    return {...data};
  }
  const role = roleFromPopulation(data.populationRole ?? data.role);
  if (!role) throw new Error("unsupported role");
  const source = answersFrom(data);
  if (source.kind === "quick") {
    const answers: QuickAnswer[] = source.value.map((item) => {
      const value = item as Record<string, unknown>;
      return {questionId: String(value.questionId), optionId: String(value.optionId), value: Number(value.value)};
    });
    validateQuickAnswers(answers);
    return {
      ...calculateQuick(role, String(data.name ?? ""), answers),
      role,
      populationRole: role,
      type: "quick",
      calculationAuthority: "server_migration",
      verificationStatus: "verified_legacy_recomputed",
    };
  }
  const answers: FullAnswer[] = source.value.map((item) => {
    const value = item as Record<string, unknown>;
    return {questionId: String(value.questionId), answer: String(value.answer), isSkipped: value.isSkipped === true};
  });
  const legacyFivePointScale = answers.some((answer) => answer.answer === "sometimes") ||
    String(data.questionSetVersion ?? "").includes("_v1");
  if (legacyFivePointScale) {
    return {
      ...data,
      role,
      populationRole: role,
      calculationAuthority: "client_legacy",
      verificationStatus: "legacy_scale_preserved",
      algorithmVersion: String(data.algorithmVersion ?? "internal_wellness_policy_v1"),
      questionSetVersion: String(data.questionSetVersion ?? "experimental_role_based_v1"),
    };
  }
  validateFullAnswers(role, answers);
  return {
    ...calculateFull(role, answers),
    role,
    populationRole: role,
    calculationAuthority: "server_migration",
    verificationStatus: "verified_legacy_recomputed",
  };
}

async function main(): Promise<void> {
  const apply = process.argv.includes("--apply");
  const snapshot = await db.collection("assessments").get();
  const counts: Counts = {
    verified: 0,
    skipped: 0,
    malformed: 0,
    alreadyProcessed: 0,
    profileRoleBackfills: 0,
    profileRoleConflicts: 0,
    missingProfiles: 0,
  };
  const quickRoles = new Map<string, string>();
  const conflictingUsers = new Set<string>();
  for (const document of snapshot.docs) {
    const data = document.data() as Record<string, unknown>;
    const userId = String(data.userId ?? "").trim();
    const status = String(data.verificationStatus ?? "");
    const authority = String(data.calculationAuthority ?? "");
    const trustedQuick = String(data.type ?? "") === "quick" &&
      ((status === "verified" && authority === "server") ||
        (status === "verified_legacy_recomputed" && authority === "server_migration"));
    const quickRole = trustedQuick ?
      roleFromPopulation(data.populationRole ?? data.role) : null;
    if (userId && quickRole) {
      const previous = quickRoles.get(userId);
      if (previous && previous !== quickRole) conflictingUsers.add(userId);
      else quickRoles.set(userId, quickRole);
    }
    if (status === "verified" || status === "verified_legacy_recomputed" || status === "legacy_scale_preserved") {
      counts.alreadyProcessed++;
      continue;
    }
    try {
      const derived = migrateAssessmentData(data);
      counts.verified++;
      if (apply) {
        const {responses: _responses, ...derivedWithoutResponses} = derived;
        await document.ref.set({
          ...derivedWithoutResponses,
          legacyClientResult: data,
          verifiedAt: FieldValue.serverTimestamp(),
          serverAlgorithmVersion: derived.algorithmVersion,
          serverQuestionSetVersion: derived.questionSetVersion,
        }, {merge: true});
      }
    } catch (error) {
      counts.malformed++;
      if (apply) {
        await document.ref.set({
          verificationStatus: "legacy_unverified",
          calculationAuthority: "client_legacy",
          verificationError: error instanceof Error ? error.message : "Unsupported legacy record",
          verifiedAt: null,
        }, {merge: true});
      }
    }
  }
  for (const [userId, role] of quickRoles) {
    if (conflictingUsers.has(userId)) {
      counts.profileRoleConflicts++;
      continue;
    }
    const profileRef = db.collection("users").doc(userId);
    const profile = await profileRef.get();
    if (!profile.exists) {
      counts.missingProfiles++;
      continue;
    }
    const storedRole = roleFromPopulation(profile.data()?.populationRole) ??
      roleFromPopulation(profile.data()?.declaredRole) ??
      roleFromPopulation(profile.data()?.role);
    if (storedRole) {
      if (storedRole !== role) counts.profileRoleConflicts++;
      continue;
    }
    counts.profileRoleBackfills++;
    if (apply) {
      await profileRef.set({
        role: legacyRole(role),
        populationRole: role,
        declaredRole: role,
        quickAssessmentCompleted: true,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  }
  console.log(JSON.stringify({mode: apply ? "apply" : "dry-run", ...counts}));
}

if (require.main === module) main().catch((error) => { console.error(error); process.exitCode = 1; });

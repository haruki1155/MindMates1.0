import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";

type InsightContentPatch = {
  targetRoles: string[];
  domainIds: string[];
  title?: string;
  subtitle?: string;
  categoryId?: string;
  categoryLabel?: string;
  sectionId?: string;
  contentType?: string;
  tags?: string[];
  source?: string;
  body?: string;
  imageAsset?: string;
  sortOrder?: number;
  isActive?: boolean;
};

// This is intentionally small. Existing IDs receive additive metadata; only
// the four IDs below are created when they do not already exist.
export const ROLE_AWARE_INSIGHT_CONTENT: Record<string, InsightContentPatch> = {
  academic_stress: {
    targetRoles: ["student"], domainIds: ["academicStress"],
  },
  burnout_recovery: {
    targetRoles: ["teaching"], domainIds: ["workplaceStress"],
  },
  emotional_resilience: {
    targetRoles: ["all"], domainIds: ["emotionalWellbeing"],
  },
  sleep_hygiene: {
    targetRoles: ["all"], domainIds: ["sleepRest"],
  },
  student_financial_wellbeing: {
    title: "Financial stress: small steps to regain control",
    subtitle: "Use practical planning and support when money worries affect your studies.",
    categoryId: "stress_burnout", categoryLabel: "Student wellbeing",
    sectionId: "recommended", contentType: "article",
    tags: ["financial wellbeing", "student", "planning"], source: "MindMate",
    body: "Financial concerns can make studying feel harder. Start with a simple weekly plan, identify essential costs, and speak with a trusted campus support person when worries are affecting your wellbeing.",
    imageAsset: "", sortOrder: 25, isActive: true,
    targetRoles: ["student"], domainIds: ["financialWellbeing"],
  },
  student_social_adjustment: {
    title: "Finding support while adjusting to campus life",
    subtitle: "Build connection gradually and use support when changes feel overwhelming.",
    categoryId: "emotional_wellbeing", categoryLabel: "Student wellbeing",
    sectionId: "recommended", contentType: "article",
    tags: ["social adjustment", "student", "connection"], source: "MindMate",
    body: "Adjustment takes time. Try one manageable connection step, such as joining a class activity, talking with a trusted peer, or asking campus support for help navigating change.",
    imageAsset: "", sortOrder: 26, isActive: true,
    targetRoles: ["student"], domainIds: ["socialAdjustment"],
  },
  teaching_professional_support: {
    title: "Using professional support during demanding teaching weeks",
    subtitle: "Create practical support points when teaching responsibilities build up.",
    categoryId: "stress_burnout", categoryLabel: "Teaching wellbeing",
    sectionId: "recommended", contentType: "article",
    tags: ["teaching", "professional support", "workload"], source: "MindMate",
    body: "During demanding weeks, identify one colleague or supervisor you can check in with, clarify urgent priorities, and protect a short recovery period after high-pressure tasks.",
    imageAsset: "", sortOrder: 27, isActive: true,
    targetRoles: ["teaching"], domainIds: ["professionalSupport", "professionalWellbeing"],
  },
  non_teaching_workplace_support: {
    title: "Managing competing workplace responsibilities",
    subtitle: "Use clear priorities and support channels when responsibilities pile up.",
    categoryId: "stress_burnout", categoryLabel: "Workplace wellbeing",
    sectionId: "recommended", contentType: "article",
    tags: ["non-teaching", "workplace responsibilities", "support"], source: "MindMate",
    body: "When responsibilities compete, list the urgent tasks first, clarify deadlines with your supervisor, and use available workplace support before stress builds further.",
    imageAsset: "", sortOrder: 28, isActive: true,
    targetRoles: ["nonTeaching"],
    domainIds: ["workplaceResponsibilities", "workplaceSupport", "workplaceWellbeing"],
  },
};

function stagingProjectId(): string {
  const projectId = process.env.GOOGLE_CLOUD_PROJECT ?? process.env.GCLOUD_PROJECT;
  if (!projectId?.trim()) {
    throw new Error("Set GOOGLE_CLOUD_PROJECT=mindmate-staging before running this staging-only seed.");
  }
  return projectId.trim();
}

export async function seedRoleAwareInsightContent(
  dryRun = true,
  projectId = stagingProjectId(),
): Promise<{projectId: string; changed: number; ids: string[]}> {
  if (projectId !== "mindmate-staging") {
    throw new Error(
      "This seed is staging-only. Set GOOGLE_CLOUD_PROJECT=mindmate-staging; production is never an allowed target.",
    );
  }
  const ids = Object.keys(ROLE_AWARE_INSIGHT_CONTENT);
  if (dryRun) return {projectId, changed: ids.length, ids};

  const writer = getFirestore().bulkWriter();
  for (const [id, patch] of Object.entries(ROLE_AWARE_INSIGHT_CONTENT)) {
    writer.set(getFirestore().collection("insight_content").doc(id), {
      ...patch,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  await writer.close();
  return {projectId, changed: ids.length, ids};
}

if (require.main === module) {
  const apply = process.argv.includes("--apply");
  try {
    const projectId = stagingProjectId();
    if (!getApps().length) initializeApp({projectId});
    seedRoleAwareInsightContent(!apply, projectId)
      .then((result) => console.log(JSON.stringify({mode: apply ? "apply" : "dry-run", ...result})))
      .catch((error) => {
        console.error(error instanceof Error ? error.message : error);
        process.exitCode = 1;
      });
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  }
}

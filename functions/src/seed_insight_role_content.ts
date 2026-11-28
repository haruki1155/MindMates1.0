import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";

type InsightContentPatch = {
  targetRoles?: string[];
  domainIds?: string[];
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
  sourceTitle?: string;
  sourceUrl?: string;
  evidenceType?: string;
  rightsStatus?: string;
  reviewStatus?: string;
  reviewedAt?: string;
  actionRoute?: string;
};

// Original MindMate summaries that link out to the official publisher page.
function curated(sourceTitle: string, sourceUrl: string, actionRoute: string): InsightContentPatch {
  return {
    sourceTitle, sourceUrl, actionRoute,
    evidenceType: "official_guideline", rightsStatus: "original",
    reviewStatus: "approved", reviewedAt: "2026-11-28",
  };
}

// Library links still need an admin to approve them before featuring.
function library(sourceTitle: string, sourceUrl: string): InsightContentPatch {
  return {
    sourceTitle, sourceUrl,
    evidenceType: "official_guideline", rightsStatus: "original",
    reviewStatus: "pending_review",
  };
}

const DWM = "https://www.who.int/publications/i/item/9789240003927";
const NIH_EMO = "https://www.nih.gov/health-information/emotional-wellness-toolkit";

const NIMH_STRESS = "https://www.nimh.nih.gov/health/publications/so-stressed-out-fact-sheet";
const WHO_WORK = "https://www.who.int/news-room/fact-sheets/detail/mental-health-at-work";

// This is intentionally small. Existing IDs receive additive metadata; only
// the four full documents below are created when they do not already exist.
export const ROLE_AWARE_INSIGHT_CONTENT: Record<string, InsightContentPatch> = {
  academic_stress: {
    targetRoles: ["student"], domainIds: ["academicStress"],
    ...curated("NIMH — I'm So Stressed Out! Fact Sheet", NIMH_STRESS, "/insights/mindful-breathing"),
  },
  burnout_recovery: {
    targetRoles: ["teaching"], domainIds: ["workplaceStress"],
    ...curated("WHO — Mental Health at Work", WHO_WORK, "/services"),
  },
  emotional_resilience: {
    targetRoles: ["all"], domainIds: ["emotionalWellbeing"],
    ...curated(
      "NIMH — Caring for Your Mental Health",
      "https://www.nimh.nih.gov/health/topics/caring-for-your-mental-health",
      "/mood/log",
    ),
  },
  sleep_hygiene: {
    targetRoles: ["all"], domainIds: ["sleepRest"],
    ...curated("CDC — About Sleep", "https://www.cdc.gov/sleep/about/index.html", "/sleep-quality"),
  },
  breathing_relaxation: curated(
    "WHO — Doing What Matters in Times of Stress",
    "https://www.who.int/publications/i/item/9789240003927",
    "/insights/mindful-breathing",
  ),
  understanding_anxiety: curated(
    "NIMH — Anxiety Disorders",
    "https://www.nimh.nih.gov/health/topics/anxiety-disorders",
    "/insights/mindful-breathing",
  ),
  healthy_coping_depression: curated(
    "NIMH — Depression", "https://www.nimh.nih.gov/health/topics/depression", "/mood/log",
  ),
  understanding_stress: curated(
    "WHO — Stress: Questions and Answers",
    "https://www.who.int/news-room/questions-and-answers/item/stress",
    "/insights/mindful-breathing",
  ),
  when_to_consult_pacc: curated(
    "CDC — Managing Stress & Mental Health",
    "https://www.cdc.gov/mental-health/living-with/index.html",
    "/services",
  ),
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
    ...library("NIH — Social Wellness Toolkit", "https://www.nih.gov/health-information/social-wellness-toolkit"),
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
    ...library("WHO — Mental Health at Work", WHO_WORK),
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
    ...curated("WHO — Mental Health at Work", WHO_WORK, "/services"),
  },
  healthy_stress_reduction: library("MedlinePlus — Stress", "https://medlineplus.gov/stress.html"),
  normal_worry_vs_anxiety: library("NIMH — I'm So Stressed Out! Fact Sheet", NIMH_STRESS),
  anxiety_triggers: library(
    "WHO — Anxiety disorders", "https://www.who.int/news-room/fact-sheets/detail/anxiety-disorders",
  ),
  understanding_depression: library(
    "WHO — Depressive disorder (depression)", "https://www.who.int/news-room/fact-sheets/detail/depression",
  ),
  depression_warning_signs: library("MedlinePlus — Depression", "https://medlineplus.gov/depression.html"),
  understanding_emotions: library("NIH — Emotional Wellness Toolkit", NIH_EMO),
  anger_frustration: library("WHO — Doing What Matters in Times of Stress", DWM),
  self_compassion: library("WHO — Doing What Matters in Times of Stress", DWM),
  building_self_confidence: library("NIH — Emotional Wellness Toolkit", NIH_EMO),
  negative_self_talk: library("WHO — Doing What Matters in Times of Stress", DWM),
  growth_mindset: library("NIH — Emotional Wellness Toolkit", NIH_EMO),
  why_sleep_matters: library(
    "NHLBI — Why Is Sleep Important?", "https://www.nhlbi.nih.gov/health/sleep/why-sleep-important",
  ),
  sleep_emotional_health: library("MedlinePlus — Healthy Sleep", "https://medlineplus.gov/healthysleep.html"),
  better_sleep_tips: library(
    "NHLBI — Healthy Sleep Habits", "https://www.nhlbi.nih.gov/health/sleep-deprivation/healthy-sleep-habits",
  ),
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

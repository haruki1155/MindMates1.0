import assert from "node:assert/strict";
import test from "node:test";

import {STUDENT_V4_ITEMS} from "./student_v4_catalog";
import {previewAssessmentDomainHandler} from "./preview_assessment_domain";

function academicAnswers() {
  return STUDENT_V4_ITEMS.filter((item) => item.domainId === "academic").map((item) => {
    const responseCode = item.direction === "risk" ? "stronglyAgree" : "stronglyDisagree";
    return {itemId: item.id, responseCode, responseValue: responseCode === "stronglyAgree" ? 4 : 1, skipped: false};
  });
}

test("domain preview returns the policy result after one trusted profile read and no writes", async () => {
  let reads = 0;
  const result = await previewAssessmentDomainHandler(
    {auth: {uid: "student-1"}, data: {instrumentVersion: "student_wellbeing_v4", domainId: "academic", answers: academicAnswers()}} as never,
    {loadProfile: async () => { reads += 1; return {populationRole: "student"}; }},
  );

  assert.equal(reads, 1);
  assert.deepEqual(Object.keys(result).sort(), ["answeredCount", "domainId", "domainLabel", "focusInsight", "interventionEligible", "isScorable", "policyVersion", "presentedCount", "reflectionPrompt", "status", "strengthInsight", "suggestedAction", "summary"]);
  assert.equal(result.status, "supportMayHelp");
  assert.equal(result.interventionEligible, true);
  assert.equal(result.policyVersion, "assessment_intervention_v1");
});

test("domain preview rejects a profile and instrument mismatch", async () => {
  await assert.rejects(
    () => previewAssessmentDomainHandler(
      {auth: {uid: "staff-1"}, data: {instrumentVersion: "student_wellbeing_v4", domainId: "academic", answers: academicAnswers()}} as never,
      {loadProfile: async () => ({populationRole: "teaching"})},
    ),
    (error: {code?: string}) => error.code === "failed-precondition",
  );
});

import assert from "node:assert/strict";
import test from "node:test";

import {STUDENT_V4_ITEMS} from "./student_v4_catalog";
import {calculateStudentV4, StudentV4Answer, validateStudentV4Answers} from "./student_v4_calculator";

const valueFor = (code: StudentV4Answer["responseCode"]): number => ({
  stronglyDisagree: 1,
  disagree: 2,
  agree: 3,
  stronglyAgree: 4,
})[code!];

function answersFor(direction: "low" | "high"): StudentV4Answer[] {
  return STUDENT_V4_ITEMS.map((item) => {
    const responseCode = direction === "low"
      ? item.direction === "risk" ? "stronglyDisagree" : "stronglyAgree"
      : item.direction === "risk" ? "stronglyAgree" : "stronglyDisagree";
    return {itemId: item.id, responseCode, responseValue: valueFor(responseCode), skipped: false};
  });
}

function answersWithDomainConcern(
  concernByDomain: Partial<Record<string, 0 | 33 | 67 | 100>>,
): StudentV4Answer[] {
  return STUDENT_V4_ITEMS.map((item) => {
    const concern = concernByDomain[item.domainId] ?? 0;
    const responseCode = item.direction === "risk"
      ? concern === 0 ? "stronglyDisagree" : concern === 33 ? "disagree" : concern === 67 ? "agree" : "stronglyAgree"
      : concern === 0 ? "stronglyAgree" : concern === 33 ? "agree" : concern === 67 ? "disagree" : "stronglyDisagree";
    return {itemId: item.id, responseCode, responseValue: valueFor(responseCode), skipped: false};
  });
}

test("Student V4 has a fixed 50-item agreement catalog", () => {
  assert.equal(STUDENT_V4_ITEMS.length, 50);
  assert.deepEqual(STUDENT_V4_ITEMS.map((item) => item.id).slice(0, 2), [
    "student_v4_academic_01", "student_v4_academic_02",
  ]);
  assert.equal(STUDENT_V4_ITEMS.at(-1)?.id, "student_v4_emotional_wellbeing_10");
});

test("Student V4 uses agreement codes and creates a generally supported profile", () => {
  const result = calculateStudentV4(answersFor("low"));
  const profile = result.result as Record<string, unknown>;
  assert.equal(result.questionSetVersion, "student_wellbeing_v4");
  assert.equal(profile.profileStatus, "generallySupported");
  assert.equal((profile.responseQuality as Record<string, unknown>).completionPercent, 100);
});

test("Student V4 rejects a response code and value mismatch", () => {
  const answers = answersFor("low");
  answers[0] = {...answers[0], responseValue: answers[0].responseValue === 4 ? 1 : 4};
  assert.throws(() => validateStudentV4Answers(answers));
});

test("Student V4 marks a domain insufficient below seven answers", () => {
  const answers = answersFor("low");
  for (let index = 0; index < 4; index += 1) {
    answers[index] = {itemId: answers[index].itemId, skipped: true};
  }
  const result = calculateStudentV4(answers);
  const profile = result.result as Record<string, unknown>;
  assert.equal(profile.profileStatus, "insufficientResponses");
});

test("Student V4 applies all provisional domain-status boundaries", () => {
  const cases: Array<[0 | 33 | 67 | 100, string]> = [
    [0, "supported"],
    [33, "mostlySupported"],
    [67, "someStrain"],
    [100, "supportMayHelp"],
  ];
  for (const [concern, expectedStatus] of cases) {
    const result = calculateStudentV4(answersWithDomainConcern({academic: concern}));
    const domains = (result.result as Record<string, unknown>).domainResults as Record<string, unknown>[];
    assert.equal(domains.find((domain) => domain.domainId === "academic")?.status, expectedStatus);
  }
});

test("Student V4 profile precedence uses high support need before two strain domains", () => {
  const timely = calculateStudentV4(answersWithDomainConcern({academic: 100, financial: 67, socialAdjustment: 67}));
  assert.equal((timely.result as Record<string, unknown>).profileStatus, "supportMayHelp");
  const attention = calculateStudentV4(answersWithDomainConcern({academic: 67, financial: 67}));
  assert.equal((attention.result as Record<string, unknown>).profileStatus, "someAreasNeedAttention");
});

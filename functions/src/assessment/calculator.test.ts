import assert from "node:assert/strict";
import test from "node:test";

import {QUESTIONS_BY_ROLE, QUICK_QUESTIONS} from "./catalog";
import {
  activeQuestions,
  AssessmentValidationError,
  calculateFull,
  calculateQuick,
  FullAnswer,
  QuickAnswer,
  validateFullAnswers,
} from "./calculator";
import {migrateAssessmentData} from "./migrate";

function lowConcernAnswer(question: {direction: "risk" | "protective"}): string {
  return question.direction === "risk" ? "never" : "always";
}

test("full assessment uses four choices and rejects the removed neutral response", () => {
  const questions = QUESTIONS_BY_ROLE.student.filter((question) => !question.conditional);
  const answers: FullAnswer[] = questions.map((question) => ({
    questionId: question.id,
    answer: lowConcernAnswer(question),
    isSkipped: false,
  }));
  answers[0] = {...answers[0], answer: "sometimes"};

  assert.throws(
    () => validateFullAnswers("student", answers),
    AssessmentValidationError,
  );
});

test("quick assessment emits response-pattern labels for one-item indicators", () => {
  const answers: QuickAnswer[] = QUICK_QUESTIONS.map((question) => ({
    questionId: question.id,
    optionId: question.options[question.options.length - 1].id,
    value: question.options[question.options.length - 1].value,
  }));
  const result = calculateQuick("student", "Test User", answers);
  const interpretation = result.interpretation as Record<string, unknown>;
  const domains = interpretation.domainResults as Record<string, unknown>[];

  assert.equal(result.questionSetVersion, "quick_v3");
  assert.equal(result.responsePatternLabel, "Support may be useful");
  assert.equal(domains[0].presentedCount, 1);
  assert.match(String(domains[0].bandLabel), /Well-being|strain|support|responses/i);
});

test("quick v3 server interpretation matches personal focus copy", () => {
  const answers: QuickAnswer[] = QUICK_QUESTIONS.map((question) => ({
    questionId: question.id,
    optionId: question.options[0].id,
    value: question.options[0].value,
  }));
  answers[1] = {questionId: "overwhelmed", optionId: "sometimes", value: 3};
  const result = calculateQuick("student", "Test User", answers);
  const interpretation = result.interpretation as Record<string, unknown>;
  assert.match(String(interpretation.userSummary), /^Your answers show/);
  assert.deepEqual(interpretation.rationale, ["Areas worth a closer look: stress load."]);
  assert.deepEqual(interpretation.focusInsights, [
    "Stress load: Your tasks have felt overwhelming. Breaking work into smaller steps or talking to someone you trust can lighten the load.",
  ]);
});

test("quick v3 keeps the 30-point stored threshold but uses 40 for focus text", () => {
  const answers: QuickAnswer[] = QUICK_QUESTIONS.map((question) => ({
    questionId: question.id, optionId: question.options[0].id, value: question.options[0].value,
  }));
  answers[3] = {questionId: "little_interest", optionId: "several_days", value: 2};
  const result = calculateQuick("student", "Test User", answers);
  const interpretation = result.interpretation as Record<string, unknown>;
  assert.deepEqual(result.topConcernAreas, ["Motivation and interest"]);
  assert.deepEqual(interpretation.rationale, ["None of your answers stood out as needing attention right now."]);
  assert.deepEqual(interpretation.focusInsights, []);
  assert.equal(interpretation.supportPriority, "routine");
});

test("quick v3 focus ranks tied scores alphabetically and joins three names", () => {
  const answers: QuickAnswer[] = QUICK_QUESTIONS.map((question) => ({
    questionId: question.id, optionId: question.options[0].id, value: question.options[0].value,
  }));
  answers[1] = {questionId: "overwhelmed", optionId: "fairly_often", value: 4};
  answers[2] = {questionId: "connected", optionId: "neutral", value: 3};
  answers[4] = {questionId: "stress_affecting_life", optionId: "often", value: 4};
  const result = calculateQuick("student", "Test User", answers);
  const interpretation = result.interpretation as Record<string, unknown>;
  assert.deepEqual(interpretation.rationale, [
    "Areas worth a closer look: daily coping, stress load, and social connection.",
  ]);
  assert.deepEqual(result.topConcernAreas, ["Daily coping", "Stress load", "Social connection"]);
});

test("quick v3 provides exact summaries for all four response patterns", () => {
  const cases: Array<[number, string, string]> = [
    [0, "wellBeingSupported", "Your answers show healthy patterns in most areas. Keep doing what helps you feel well."],
    [1, "generallySteady", "Your answers show a generally steady balance, with a few areas worth keeping an eye on."],
    [2, "someStrain", "Your answers show some areas that may be adding strain right now. Take a closer look at them below."],
    [4, "supportMayHelp", "Your answers show several areas where things may feel hard right now. Support can help, and you do not have to handle this alone."],
  ];
  for (const [index, pattern, summary] of cases) {
    const answers: QuickAnswer[] = QUICK_QUESTIONS.map((question) => {
      const option = question.options[Math.min(index, question.options.length - 1)];
      return {questionId: question.id, optionId: option.id, value: option.value};
    });
    const result = calculateQuick("student", "Test User", answers);
    assert.equal(result.responsePatternCode, pattern);
    assert.equal(result.summary, summary);
    assert.ok(String((result.interpretation as Record<string, unknown>).userSummary).startsWith(summary));
  }
});

test("full assessment preserves the intended student domain sequence", () => {
  const sections = QUESTIONS_BY_ROLE.student
    .filter((question) => !question.conditional)
    .map((question) => question.section)
    .filter((section, index, values) => values.indexOf(section) === index);

  assert.deepEqual(sections, [
    "academicCore",
    "financialConcern",
    "socialAdjustment",
    "sleepRest",
    "emotionalWellBeing",
  ]);
});

test("full assessment provides ten questions per domain for every role", () => {
  for (const questions of Object.values(QUESTIONS_BY_ROLE)) {
    const counts = new Map<string, number>();
    for (const question of questions) {
      counts.set(question.domain, (counts.get(question.domain) ?? 0) + 1);
    }

    assert.equal(questions.length, 50);
    assert.equal(counts.size, 5);
    assert.deepEqual([...counts.values()], [10, 10, 10, 10, 10]);
  }
});

test("full assessment normalizes four-point responses and equally weights domains", () => {
  const questions = activeQuestions("student", []);
  const answers: FullAnswer[] = questions.map((question) => ({
    questionId: question.id,
    answer: question.section === "academicCore"
      ? "always"
      : lowConcernAnswer(question),
    isSkipped: false,
  }));

  validateFullAnswers("student", answers);
  const result = calculateFull("student", answers);
  const interpretation = result.interpretation as Record<string, unknown>;
  const domains = interpretation.domainResults as Record<string, unknown>[];

  assert.equal(result.overallScore, 20);
  assert.equal(result.status, "Thriving");
  assert.equal(result.wellBeingStatus, "Thriving");
  assert.equal(result.algorithmVersion, "internal_wellness_policy_v2");
  assert.equal(result.questionSetVersion, "experimental_role_based_v3");
  assert.match(String(interpretation.userSummary), /^One or more areas may be placing extra pressure on daily life\./);
  assert.equal(domains.find((domain) => domain.domain === "Academic Stress")?.wellBeingStatus, "At Risk");
  assert.equal(domains.find((domain) => domain.domain === "Financial Well-Being")?.wellBeingStatus, "Thriving");
  assert.ok((interpretation.strengthInsights as string[]).length > 0);
  assert.ok((interpretation.focusInsights as string[]).every((insight) => !insight.startsWith("I ")));
});

test("migration preserves v1 five-point records instead of reinterpreting them", () => {
  const responses = QUESTIONS_BY_ROLE.student
    .filter((question) => !question.conditional)
    .map((question) => ({
      questionId: question.id,
      answer: "sometimes",
      isSkipped: false,
    }));
  const result = migrateAssessmentData({
    populationRole: "student",
    questionSetVersion: "experimental_role_based_v1",
    algorithmVersion: "internal_wellness_policy_v1",
    responses,
    status: "Moderate Concern",
  });

  assert.equal(result.verificationStatus, "legacy_scale_preserved");
  assert.equal(result.questionSetVersion, "experimental_role_based_v1");
  assert.equal(result.status, "Moderate Concern");
});

test("migration leaves immutable V4 records untouched", () => {
  const record = {
    schemaVersion: "assessment_record_v4",
    populationRole: "student",
    verificationStatus: "verified",
    result: {profileStatus: "generallySupported"},
  };
  assert.deepEqual(migrateAssessmentData(record), record);
});

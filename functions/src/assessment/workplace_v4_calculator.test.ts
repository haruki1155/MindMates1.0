import assert from "node:assert/strict";
import test from "node:test";

import {
  NON_TEACHING_V4_CATALOG_HASH, NON_TEACHING_V4_INSTRUMENT_VERSION, NON_TEACHING_V4_ITEMS,
  TEACHING_V4_CATALOG_HASH, TEACHING_V4_INSTRUMENT_VERSION, TEACHING_V4_ITEMS,
} from "./workplace_v4_catalog";
import {calculateNonTeachingV4, calculateTeachingV4, validateTeachingV4Answers, WorkplaceV4Answer} from "./workplace_v4_calculator";

const valueFor = (code: WorkplaceV4Answer["responseCode"]) => ({stronglyDisagree: 1, disagree: 2, agree: 3, stronglyAgree: 4})[code!];
function answersFor(items: readonly {id: string; domainId: string; direction: "risk" | "protective"}[], concerns: Partial<Record<string, 0 | 33 | 67 | 100>> = {}): WorkplaceV4Answer[] {
  return items.map((item) => {
    const concern = concerns[item.domainId] ?? 0;
    const responseCode = item.direction === "risk" ? concern === 0 ? "stronglyDisagree" : concern === 33 ? "disagree" : concern === 67 ? "agree" : "stronglyAgree" : concern === 0 ? "stronglyAgree" : concern === 33 ? "agree" : concern === 67 ? "disagree" : "stronglyDisagree";
    return {itemId: item.id, responseCode, responseValue: valueFor(responseCode), skipped: false};
  });
}

test("workplace V4 catalogs are fixed 50-item, five-domain instruments", () => {
  for (const [items, version, hash] of [[TEACHING_V4_ITEMS, TEACHING_V4_INSTRUMENT_VERSION, TEACHING_V4_CATALOG_HASH], [NON_TEACHING_V4_ITEMS, NON_TEACHING_V4_INSTRUMENT_VERSION, NON_TEACHING_V4_CATALOG_HASH]] as const) {
    assert.equal(items.length, 50);
    assert.equal(new Set(items.map((item) => item.id)).size, 50);
    assert.deepEqual(items.map((item) => item.displayOrder), Array.from({length: 50}, (_, index) => index + 1));
    assert.equal(new Set(items.map((item) => item.domainId)).size, 5);
    assert.ok([...new Set(items.map((item) => item.domainId))].every((domain) => items.filter((item) => item.domainId === domain).length === 10));
    assert.match(version, /_v4$/);
    assert.match(hash, /^[a-f0-9]{64}$/);
  }
});

test("Teaching V4 validates all item IDs and rejects invalid or duplicate responses", () => {
  const answers = answersFor(TEACHING_V4_ITEMS);
  validateTeachingV4Answers(answers);
  assert.throws(() => validateTeachingV4Answers(answers.slice(1)));
  assert.throws(() => validateTeachingV4Answers([...answers.slice(0, 49), answers[0]]));
  const invalid = [...answers];
  invalid[0] = {...invalid[0], responseValue: 1};
  assert.throws(() => validateTeachingV4Answers(invalid));
  const skippedWithValue = [...answers];
  skippedWithValue[0] = {...skippedWithValue[0], skipped: true};
  assert.throws(() => validateTeachingV4Answers(skippedWithValue));
});

test("workplace V4 applies domain boundaries, completion threshold, and immutable output", () => {
  for (const [concern, expected] of [[0, "supported"], [33, "mostlySupported"], [67, "someStrain"], [100, "supportMayHelp"]] as const) {
    const result = calculateTeachingV4(answersFor(TEACHING_V4_ITEMS, {teachingWorkloadDemands: concern}));
    const domains = (result.result as Record<string, unknown>).domainResults as Record<string, unknown>[];
    assert.equal(domains.find((domain) => domain.domainId === "teachingWorkloadDemands")?.status, expected);
  }
  const partial = answersFor(TEACHING_V4_ITEMS);
  for (let index = 0; index < 4; index += 1) partial[index] = {itemId: partial[index].itemId, skipped: true};
  const result = calculateTeachingV4(partial);
  assert.equal((result.result as Record<string, unknown>).profileStatus, "insufficientResponses");
  assert.equal(result.schemaVersion, "assessment_record_v4");
  assert.equal(result.calculationAuthority, "server");
  assert.equal(result.questionSetVersion, TEACHING_V4_INSTRUMENT_VERSION);
  assert.equal((result.itemSnapshot as unknown[]).length, 50);
});

test("workplace V4 profile precedence and non-teaching identity are role-specific", () => {
  assert.equal((calculateTeachingV4(answersFor(TEACHING_V4_ITEMS)).result as Record<string, unknown>).profileStatus, "generallySupported");
  assert.equal((calculateTeachingV4(answersFor(TEACHING_V4_ITEMS, {teachingWorkloadDemands: 67})).result as Record<string, unknown>).profileStatus, "mostlySupported");
  assert.equal((calculateTeachingV4(answersFor(TEACHING_V4_ITEMS, {teachingWorkloadDemands: 67, teachingSupport: 67})).result as Record<string, unknown>).profileStatus, "someAreasNeedAttention");
  assert.equal((calculateTeachingV4(answersFor(TEACHING_V4_ITEMS, {teachingWorkloadDemands: 100})).result as Record<string, unknown>).profileStatus, "supportMayHelp");
  const nonTeaching = calculateNonTeachingV4(answersFor(NON_TEACHING_V4_ITEMS));
  assert.equal(nonTeaching.questionSetVersion, NON_TEACHING_V4_INSTRUMENT_VERSION);
  assert.equal(nonTeaching.algorithmVersion, "non_teaching_profile_v4");
  assert.ok((nonTeaching.interpretation as Record<string, unknown>).userSummary);
});

test("workplace V4 emits deterministic role-specific full-result contracts", () => {
  const cases = [
    [calculateTeachingV4, TEACHING_V4_ITEMS, ["Teaching Workload & Role Demands", "Collegial & Organizational Support", "Professional Engagement & Meaning", "Sleep & Rest", "Emotional Well-Being"]],
    [calculateNonTeachingV4, NON_TEACHING_V4_ITEMS, ["Workload & Role Demands", "Supervisor, Team & Organizational Support", "Work Engagement & Meaning", "Sleep & Rest", "Emotional Well-Being"]],
  ] as const;
  for (const [calculate, items, labels] of cases) {
    const first = calculate(answersFor(items));
    const second = calculate(answersFor(items));
    const instrument = first.instrument as Record<string, unknown>;
    const interpretation = first.interpretation as Record<string, unknown>;
    const domains = interpretation.domainSummaries as Record<string, unknown>[];
    assert.equal(instrument.referenceSetVersion, "mindmate_wellbeing_refs_v1");
    assert.equal(typeof interpretation.userSummary, "string");
    assert.equal(typeof interpretation.overallResponseSummary, "string");
    assert.deepEqual(domains.map((domain) => domain.domainLabel), labels);
    for (const domain of domains) for (const key of ["domainId", "domainLabel", "status", "summary", "focusInsight", "strengthInsight", "suggestedAction"]) assert.ok(key in domain);
    assert.match(interpretation.disclaimer as string, /not an evaluation of your job performance/);
    assert.deepEqual(first.interpretation, second.interpretation);
  }
});

test("Teaching and Non-Teaching V4 preserve all profile statuses and safe explanations", () => {
  const cases = [
    [calculateTeachingV4, TEACHING_V4_ITEMS, ["Teaching Workload & Role Demands", "Collegial & Organizational Support", "Professional Engagement & Meaning", "Sleep & Rest", "Emotional Well-Being"]],
    [calculateNonTeachingV4, NON_TEACHING_V4_ITEMS, ["Workload & Role Demands", "Supervisor, Team & Organizational Support", "Work Engagement & Meaning", "Sleep & Rest", "Emotional Well-Being"]],
  ] as const;
  for (const [calculate, items, labels] of cases) {
    const domainIds = [...new Set(items.map((item) => item.domainId))];
    const incomplete = answersFor(items);
    for (let index = 0; index < 4; index += 1) {
      incomplete[index] = {itemId: incomplete[index].itemId, skipped: true};
    }
    const statuses: Array<[WorkplaceV4Answer[], string]> = [
      [answersFor(items), "generallySupported"],
      [answersFor(items, {[domainIds[0]]: 67}), "mostlySupported"],
      [answersFor(items, {[domainIds[0]]: 67, [domainIds[1]]: 67}), "someAreasNeedAttention"],
      [answersFor(items, {[domainIds[0]]: 100}), "supportMayHelp"],
      [incomplete, "insufficientResponses"],
    ];
    for (const [answers, expectedStatus] of statuses) {
      const first = calculate(answers);
      const second = calculate(answers);
      const result = first.result as Record<string, unknown>;
      const interpretation = first.interpretation as Record<string, unknown>;
      const domainSummaries = interpretation.domainSummaries as Record<string, unknown>[];
      assert.equal(result.profileStatus, expectedStatus);
      assert.equal(domainSummaries.length, 5);
      assert.deepEqual(domainSummaries.map((domain) => domain.domainLabel), labels);
      assert.deepEqual(first.interpretation, second.interpretation);
      const explanationText = [
        interpretation.userSummary,
        interpretation.overallResponseSummary,
        ...domainSummaries.flatMap((domain) => [domain.summary, domain.focusInsight, domain.strengthInsight, domain.suggestedAction]),
      ].filter((value): value is string => typeof value === "string").join(" ");
      assert.doesNotMatch(explanationText, /diagnostic|at risk|\/100/i);
    }
  }
});

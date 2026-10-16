import assert from "node:assert/strict";
import test from "node:test";

import {STUDENT_V4_ITEMS} from "./student_v4_catalog";
import {calculateStudentV4, StudentV4Answer} from "./student_v4_calculator";
import {calculateV4Domain} from "./v4_domain_calculator";

function answersFor(items: readonly {id: string; direction: "risk" | "protective"}[]): StudentV4Answer[] {
  return items.map((item) => {
    const responseCode = item.direction === "risk" ? "stronglyAgree" : "stronglyDisagree";
    return {itemId: item.id, responseCode: responseCode as StudentV4Answer["responseCode"], responseValue: responseCode === "stronglyAgree" ? 4 : 1, skipped: false};
  });
}

test("single-domain calculation matches the canonical Student V4 result", () => {
  const fullAnswers = answersFor(STUDENT_V4_ITEMS);
  const domainAnswers = fullAnswers.filter((answer) => answer.itemId.startsWith("student_v4_academic_"));
  const full = calculateStudentV4(fullAnswers);
  const expected = ((full.result as Record<string, unknown>).domainResults as Array<Record<string, unknown>>)
    .find((domain) => domain.domainId === "academic");
  const actual = calculateV4Domain("student_wellbeing_v4", "academic", domainAnswers);

  assert.equal(actual.status, expected?.status);
  assert.equal(actual.answeredCount, expected?.answeredCount);
  assert.equal(actual.presentedCount, expected?.presentedCount);
  assert.equal(actual.isScorable, expected?.isScorable);
});

test("single-domain calculation rejects a duplicate or foreign item", () => {
  const domainAnswers = answersFor(STUDENT_V4_ITEMS.filter((item) => item.domainId === "academic"));
  assert.throws(() => calculateV4Domain("student_wellbeing_v4", "academic", [...domainAnswers.slice(0, 9), domainAnswers[0]]));
  assert.throws(() => calculateV4Domain("student_wellbeing_v4", "academic", [...domainAnswers.slice(0, 9), answersFor([STUDENT_V4_ITEMS[10]])[0]]));
});

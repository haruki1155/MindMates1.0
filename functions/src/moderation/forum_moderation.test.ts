import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import test from "node:test";

import {FORUM_DICTIONARY_VERSION, isCrisisDisclosure, moderateForumText} from "./forum_moderation";

type Case = {text: string; why: string};
const corpus = JSON.parse(
  readFileSync(resolve(__dirname, "../../src/moderation/forum_moderation_cases.json"), "utf8"),
) as {blocked: Case[]; allowed: Case[]; notBlocked: Case[]};

test("every prohibited expression in the adversarial corpus is blocked", () => {
  const missed = corpus.blocked.filter((item) => moderateForumText(item.text).allowed);
  assert.deepEqual(missed.map((item) => `${item.why}: ${JSON.stringify(item.text)}`), []);
});

test("legitimate words, Taglish and mental-health disclosures stay publishable", () => {
  const wrong = [...corpus.allowed, ...corpus.notBlocked]
    .filter((item) => !moderateForumText(item.text).allowed);
  assert.deepEqual(wrong.map((item) => `${item.why}: ${item.text}`), []);
});

test("a blocked result names categories and a severity, never the matched word", () => {
  const result = moderateForumText("putangina mo");
  assert.equal(result.allowed, false);
  assert.ok(result.categories.length > 0);
  assert.notEqual(result.severity, "none");
  assert.equal(JSON.stringify(result).includes("putangina"), false);
  assert.deepEqual(moderateForumText("Kaya natin to."), {allowed: true, categories: [], severity: "none"});
});

test("distress and crisis disclosures are not profanity", () => {
  for (const text of ["I want to kill myself", "Gusto ko nang mamatay", "I keep cutting myself"]) {
    assert.equal(moderateForumText(text).allowed, true, text);
    assert.equal(isCrisisDisclosure(text), true, text);
  }
  assert.equal(isCrisisDisclosure("Exams are stressful but I am coping."), false);
});

test("long input is bounded and fast", () => {
  const text = `${"Kaya natin to ".repeat(700)}`.slice(0, 10_000);
  const started = Date.now();
  assert.equal(moderateForumText(text).allowed, true);
  assert.ok(Date.now() - started < 200, `took ${Date.now() - started} ms`);
  assert.equal(moderateForumText(`${"a ".repeat(4_000)}gago`).allowed, false);
});

test("the dictionary is versioned", () => {
  assert.match(FORUM_DICTIONARY_VERSION, /^\d{4}-\d{2}-\d{2}\.\d+$/);
});

import assert from "node:assert/strict";
import test from "node:test";

import {authEmailForSchoolId} from "./account_recovery";
import {
  STUDENT_AUTH_ALIAS_DOMAIN, isStudentAuthAlias, studentAuthAliasEmail,
} from "./student_auth_alias";

// These vectors are mirrored in test/repositories/auth_repository_test.dart so the client and server
// can never derive different Firebase Auth emails for the same Student ID.
const VECTORS: Array<[string, string]> = [
  ["QA-2026-0001", "qa20260001@students.mindmate.local"],
  [" qa 2026 0001 ", "qa20260001@students.mindmate.local"],
  ["2020-12345", "202012345@students.mindmate.local"],
  ["abc", "abc@students.mindmate.local"],
  ["ßß", "ssss@students.mindmate.local"],
  ["Ñandú-001", "and001@students.mindmate.local"],
  ["ﬁ-2020", "fi2020@students.mindmate.local"],
  ["Straße1", "strasse1@students.mindmate.local"],
];

test("the alias is derived from the canonical Student ID", () => {
  for (const [input, expected] of VECTORS) assert.equal(studentAuthAliasEmail(input), expected, input);
  assert.equal(STUDENT_AUTH_ALIAS_DOMAIN, "students.mindmate.local");
});

test("formatting differences in the Student ID never change the alias", () => {
  const forms = ["QA-2026-0001", "qa 2026 0001", "QA20260001", "q.a/2026_0001", "  Qa-2026-0001\n"];
  assert.equal(new Set(forms.map(studentAuthAliasEmail)).size, 1);
});

test("an unusable Student ID is rejected", () => {
  for (const bad of ["", "  ", "ab", "-- --", "A".repeat(41), null, undefined, 12345]) {
    assert.throws(() => studentAuthAliasEmail(bad), /valid School ID/, String(bad));
  }
  assert.doesNotThrow(() => studentAuthAliasEmail("A".repeat(40)));
});

test("the alias can never collide with a legacy School-ID alias", () => {
  for (const [input] of VECTORS) {
    let legacy: string | null = null;
    try {
      legacy = authEmailForSchoolId(input);
    } catch {
      legacy = null;
    }
    if (legacy) assert.notEqual(legacy, studentAuthAliasEmail(input));
  }
  assert.ok(studentAuthAliasEmail("QA-2026-0001").endsWith(".mindmate.local"));
  assert.ok(!studentAuthAliasEmail("QA-2026-0001").endsWith("@mindmate.local"));
});

test("the legacy alias helper is unchanged", () => {
  assert.equal(authEmailForSchoolId("QA-2026-0001"), "qa.2026.0001@mindmate.local");
  assert.equal(authEmailForSchoolId("2020-12345"), "2020.12345@mindmate.local");
});

test("isStudentAuthAlias recognizes only the student alias domain", () => {
  assert.equal(isStudentAuthAlias("qa20260001@students.mindmate.local"), true);
  assert.equal(isStudentAuthAlias("QA20260001@Students.MindMate.Local"), true);
  assert.equal(isStudentAuthAlias("qa.2026.0001@mindmate.local"), false);
  assert.equal(isStudentAuthAlias("someone@example.com"), false);
  assert.equal(isStudentAuthAlias(null), false);
  assert.equal(isStudentAuthAlias(undefined), false);
});

import assert from "node:assert/strict";
import test from "node:test";

import {
  claimIdentityMatches, isAllowedPersonalEmail, readSetupPassword, readStudentClaimInput,
} from "./student_claim_domain";

const row = {studentKey: "QA20260001", surname: "Dela Cruz", firstName: "Juan Carlos", middleName: "Santos", dateOfBirthKey: "2005-03-15"};
const base = {studentNo: "QA-2026-0001", firstName: "Juan Carlos", middleName: "Santos", lastName: "Dela Cruz", dateOfBirth: "2005-03-15"};
const code = (fn: () => unknown) => { try { fn(); } catch (e) { return (e as {code?: string}).code; } return "no-error"; };

test("a complete identity is canonicalized", () => {
  const input = readStudentClaimInput(base);
  assert.equal(input.studentKey, "QA20260001");
  assert.equal(input.dateOfBirthKey, "2005-03-15");
});

test("a missing, malformed or non-object identity is rejected", () => {
  for (const bad of [null, [], "x", {...base, firstName: ""}, {...base, lastName: "  "}, {...base, dateOfBirth: "15/03/2005"},
    {...base, dateOfBirth: ""}, {...base, studentNo: "ab"}, {...base, middleName: 7}]) {
    assert.equal(code(() => readStudentClaimInput(bad)), "invalid-argument", JSON.stringify(bad));
  }
  assert.equal(code(() => readStudentClaimInput({...base, middleName: undefined})), "no-error", "middle name is optional");
});

test("matching ignores case, spacing and accents but nothing else", () => {
  const ok = (patch: Record<string, unknown>) => claimIdentityMatches(readStudentClaimInput({...base, ...patch}), row);
  assert.equal(ok({}), true);
  assert.equal(ok({firstName: "  juan   CARLOS ", lastName: "dela cruz"}), true);
  assert.equal(ok({studentNo: "qa 2026 0001"}), true);
  assert.equal(ok({middleName: ""}), true, "an omitted middle name still matches");
  assert.equal(ok({middleName: "Reyes"}), false);
  assert.equal(ok({firstName: "Juan"}), false);
  assert.equal(ok({lastName: "Cruz"}), false);
  assert.equal(ok({dateOfBirth: "2005-03-16"}), false);
  assert.equal(ok({studentNo: "QA-2026-0002"}), false);
});

test("only a personal email is accepted", () => {
  assert.equal(isAllowedPersonalEmail("student@gmail.com"), true);
  for (const bad of ["staff@ucu.edu.ph", "x@UCU.EDU.PH", "a@mindmate.local", "a@students.mindmate.local", "a@revoked.mindmate.local",
    "not-an-email", "", " "]) assert.equal(isAllowedPersonalEmail(bad), false, bad);
});

test("a setup password must be at least eight characters and not absurdly long", () => {
  assert.equal(readSetupPassword("Str0ngPass!"), "Str0ngPass!");
  for (const bad of ["short7!", "", undefined, null, 12345678, "x".repeat(4097)]) {
    assert.equal(code(() => readSetupPassword(bad)), "invalid-argument", String(bad));
  }
});

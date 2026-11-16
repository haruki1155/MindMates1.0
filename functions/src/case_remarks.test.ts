import assert from "node:assert/strict";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";

import {auditLogOwnerField} from "./audit";
import {
  CaseRemarksError,
  MAX_REMARKS_LENGTH,
  decideCaseRemarksAccess,
  expectedRevisionOf,
  normalizeRemarks,
  planRemarksSave,
  remarksView,
} from "./case_remarks";

const student = {accessRole: "appUser", role: "student", collegeId: "cite", verificationStatus: "verified"};
const counselor = (colleges: string[]) => ({accessRole: "counselor", assignedCollegeIds: colleges});

function decide(input: Partial<Parameters<typeof decideCaseRemarksAccess>[0]>) {
  return decideCaseRemarksAccess({
    actorId: "c1", actor: counselor(["cite"]), superAdminUid: "boss", target: student, assignedToActor: false, ...input,
  });
}
function rejects(fn: () => unknown, code: string) {
  assert.throws(fn, (e: unknown) => e instanceof CaseRemarksError && e.code === code);
}

test("remarks are optional: omitted, null and blank all mean no remarks", () => {
  assert.equal(normalizeRemarks(undefined), "");
  assert.equal(normalizeRemarks(null), "");
  assert.equal(normalizeRemarks("   \n\t "), "");
});

test("remarks keep inner line breaks, normalize CRLF and trim the ends", () => {
  assert.equal(normalizeRemarks("  Line one\r\nLine two\n\n\tIndented  "), "Line one\nLine two\n\n\tIndented");
});

test("remarks over the limit, non-text values and control characters are rejected", () => {
  assert.equal(normalizeRemarks("x".repeat(MAX_REMARKS_LENGTH)).length, MAX_REMARKS_LENGTH);
  rejects(() => normalizeRemarks("x".repeat(MAX_REMARKS_LENGTH + 1)), "invalid-argument");
  rejects(() => normalizeRemarks(42), "invalid-argument");
  rejects(() => normalizeRemarks({text: "x"}), "invalid-argument");
  rejects(() => normalizeRemarks("bell\u0007"), "invalid-argument");
  rejects(() => normalizeRemarks("nul\u0000"), "invalid-argument");
});

test("the expected revision must be a non-negative integer", () => {
  assert.equal(expectedRevisionOf(0), 0);
  assert.equal(expectedRevisionOf(7), 7);
  for (const bad of [undefined, null, -1, 1.5, "1", Number.NaN, Number.MAX_SAFE_INTEGER + 1]) {
    rejects(() => expectedRevisionOf(bad), "invalid-argument");
  }
});

test("a counselor for the student's verified college, or assigned to one of the student's cases, may use remarks", () => {
  assert.equal(decide({}), "college");
  assert.equal(decide({actor: counselor([]), assignedToActor: true}), "assigned");
});

test("the super-administrator, other admins, other-college counselors and staff targets are refused", () => {
  rejects(() => decide({actorId: "boss", actor: {accessRole: "admin"}}), "permission-denied");
  rejects(() => decide({actorId: "a2", actor: {accessRole: "admin"}}), "permission-denied");
  rejects(() => decide({actor: counselor(["cas"])}), "permission-denied");
  rejects(() => decide({target: {...student, verificationStatus: "pending"}}), "permission-denied");
  rejects(() => decide({target: {accessRole: "counselor"}}), "permission-denied");
  rejects(() => decide({target: null}), "permission-denied");
  rejects(() => decide({actor: {accessRole: "portalStaff", assignedCollegeIds: ["cite"]}}), "permission-denied");
});

test("the first save writes revision 1; identical text is a no-op", () => {
  assert.deepEqual(planRemarksSave({current: null, text: "Note", expectedRevision: 0}), {kind: "write", revision: 1});
  assert.deepEqual(planRemarksSave({current: null, text: "", expectedRevision: 0}), {kind: "unchanged", revision: 0});
  assert.deepEqual(planRemarksSave({current: {text: "Note", revision: 3}, text: "Note", expectedRevision: 3}), {kind: "unchanged", revision: 3});
  assert.deepEqual(planRemarksSave({current: {text: "Note", revision: 3}, text: "", expectedRevision: 3}), {kind: "write", revision: 4});
});

test("a stale expected revision conflicts and writes nothing", () => {
  rejects(() => planRemarksSave({current: {text: "Newer", revision: 2}, text: "Mine", expectedRevision: 1}), "aborted");
  rejects(() => planRemarksSave({current: null, text: "Mine", expectedRevision: 1}), "aborted");
  // A stale revision conflicts even when the text happens to match.
  rejects(() => planRemarksSave({current: {text: "Mine", revision: 2}, text: "Mine", expectedRevision: 1}), "aborted");
});

test("the view carries text, revision, author and versions newest first, and nothing else", () => {
  const at = Timestamp.fromDate(new Date("2026-11-16T01:00:00Z"));
  const view = remarksView("appt-1", {
    text: "Current", revision: 2, authorNameSnapshot: "Coach Cite", updatedAt: at, authorId: "c1", studentId: "s1",
  }, [
    {revision: 1, text: "First", authorNameSnapshot: "Coach Cite", createdAt: at, authorId: "c1"},
    {revision: 2, text: "Current", authorNameSnapshot: "Coach Cite", createdAt: at, authorId: "c1"},
  ]);
  assert.deepEqual(view, {
    appointmentId: "appt-1",
    text: "Current",
    revision: 2,
    updatedAt: "2026-11-16T01:00:00.000Z",
    authorName: "Coach Cite",
    versions: [
      {revision: 2, text: "Current", authorName: "Coach Cite", savedAt: "2026-11-16T01:00:00.000Z"},
      {revision: 1, text: "First", authorName: "Coach Cite", savedAt: "2026-11-16T01:00:00.000Z"},
    ],
  });
  assert.deepEqual(remarksView("appt-2", null, []), {appointmentId: "appt-2", text: "", revision: 0, updatedAt: null, authorName: "", versions: []});
});

test("remark audit events are listed under the counselor who performed them", () => {
  assert.equal(auditLogOwnerField("CASE_REMARKS_VIEWED"), "actorId");
  assert.equal(auditLogOwnerField("CASE_REMARKS_UPDATED"), "actorId");
});

import assert from "node:assert/strict";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";

import {
  CaseHistoryError,
  caseHistoryEntry,
  decideCaseHistoryAccess,
  decodeCursor,
  encodeCursor,
  pageCaseHistory,
  pageSizeOf,
  sortCaseHistory,
} from "./student_case_history";

const student = {accessRole: "appUser", role: "student", collegeId: "cite", verificationStatus: "verified"};
const counselor = (colleges: string[]) => ({accessRole: "counselor", assignedCollegeIds: colleges});
const ts = (iso: string) => Timestamp.fromDate(new Date(iso));

function decide(input: Partial<Parameters<typeof decideCaseHistoryAccess>[0]>) {
  return decideCaseHistoryAccess({
    actorId: "c1", actor: counselor(["cite"]), superAdminUid: "boss", target: student, assignedToActor: false, ...input,
  });
}
function denied(fn: () => unknown, code: string) {
  assert.throws(fn, (e: unknown) => e instanceof CaseHistoryError && e.code === code);
}

test("a counselor serving the student's verified college may view the history", () => {
  assert.equal(decide({}), "college");
});

test("a counselor for another college, or a student with an unverified college, is refused", () => {
  denied(() => decide({actor: counselor(["cas"])}), "permission-denied");
  denied(() => decide({target: {...student, verificationStatus: "pending"}}), "permission-denied");
  denied(() => decide({target: {...student, collegeId: undefined}}), "permission-denied");
  denied(() => decide({actor: {accessRole: "counselor"}}), "permission-denied");
});

test("a counselor assigned to one of the student's cases may view it without the college", () => {
  assert.equal(decide({actor: counselor([]), assignedToActor: true}), "assigned");
});

test("only the configured super-administrator among admins is allowed", () => {
  assert.equal(decide({actorId: "boss", actor: {accessRole: "admin"}}), "super_admin");
  denied(() => decide({actorId: "a2", actor: {accessRole: "admin", assignedCollegeIds: ["cite"]}}), "permission-denied");
});

test("staff or missing target accounts are refused without revealing which (counselor) or explained (super-admin)", () => {
  for (const target of [null, {accessRole: "counselor"}, {role: "admin"}, {accessRole: "portalStaff"}]) {
    denied(() => decide({target, assignedToActor: true}), "permission-denied");
  }
  denied(() => decide({actorId: "boss", actor: {accessRole: "admin"}, target: null}), "not-found");
  denied(() => decide({actorId: "boss", actor: {accessRole: "admin"}, target: {accessRole: "counselor"}}), "failed-precondition");
});

const docs = [
  {id: "b", data: {scheduledAt: ts("2026-03-01T09:00:00Z")}},
  {id: "nots", data: {}},
  {id: "c", data: {scheduledAt: ts("2026-05-01T09:00:00Z")}},
  {id: "created-only", data: {createdAt: ts("2026-04-01T09:00:00Z")}},
  {id: "a", data: {scheduledAt: ts("2026-03-01T09:00:00Z")}},
  {id: "nots2", data: {scheduledAt: "not a timestamp"}},
];

test("history is newest first, falls back to createdAt, ties by id, timestamp-less records last", () => {
  assert.deepEqual(sortCaseHistory(docs).map((d) => d.id), ["c", "created-only", "a", "b", "nots", "nots2"]);
});

test("cursor paging returns every record exactly once in order", () => {
  const sorted = sortCaseHistory(docs);
  const seen: string[] = [];
  let cursor: string | null = null;
  let pages = 0;
  do {
    const page: {items: typeof sorted; nextCursor: string | null} = pageCaseHistory(sorted, cursor, 2);
    seen.push(...page.items.map((d) => d.id));
    cursor = page.nextCursor;
    pages++;
  } while (cursor && pages < 10);
  assert.deepEqual(seen, sorted.map((d) => d.id));
  assert.equal(pages, 3);
});

test("a record inserted before the cursor is not repeated on the next page", () => {
  const first = pageCaseHistory(sortCaseHistory(docs), null, 2);
  const grown = sortCaseHistory([...docs, {id: "new", data: {scheduledAt: ts("2026-06-01T09:00:00Z")}}]);
  const next = pageCaseHistory(grown, first.nextCursor, 2);
  assert.deepEqual(next.items.map((d) => d.id), ["a", "b"]);
});

test("cursors round-trip and malformed cursors are rejected", () => {
  assert.deepEqual(decodeCursor(encodeCursor(123, "x|y")), {millis: 123, id: "x|y"});
  assert.deepEqual(decodeCursor(encodeCursor(null, "z")), {millis: null, id: "z"});
  for (const bad of ["", "abc", "12", "1.5|x", "|x", "none|", 42, {}]) {
    assert.throws(() => decodeCursor(bad), (e: unknown) => e instanceof CaseHistoryError && e.code === "invalid-argument");
  }
});

test("page size defaults to 20 and is bounded to 1..50", () => {
  assert.equal(pageSizeOf(undefined), 20);
  assert.equal(pageSizeOf(5), 5);
  assert.equal(pageSizeOf(500), 50);
  assert.equal(pageSizeOf(0), 1);
  assert.equal(pageSizeOf("7"), 20);
});

test("entries carry case details only: no contact details or clinical notes", () => {
  const entry = caseHistoryEntry("ap1", {
    userId: "s1", fullName: "Ana", status: "Pending", scheduledAt: ts("2026-05-01T09:00:00Z"), scheduledTime: "9:00 AM",
    createdAt: ts("2026-04-20T09:00:00Z"), location: "PACC", concern: "Stress", actionByName: "Coach Reyes",
    archivedAt: ts("2026-06-01T00:00:00Z"), contactNumber: "0917", email: "a@b.c", clinicalNotes: "secret",
    staffReply: "x", followUpStatus: "offered",
  });
  assert.deepEqual(entry, {
    id: "ap1", status: "requested", scheduledAt: "2026-05-01T09:00:00.000Z", scheduledTime: "9:00 AM",
    createdAt: "2026-04-20T09:00:00.000Z", completedAt: null, archived: true, archivedAt: "2026-06-01T00:00:00.000Z",
    counselorName: "Coach Reyes", location: "PACC", concern: "Stress", followUpStatus: "offered", hasSchedule: true,
  });
  assert.equal(caseHistoryEntry("x", {counselorName: "Legacy", actionByName: "Other"}).counselorName, "Legacy");
  assert.equal(caseHistoryEntry("x", {}).hasSchedule, false);
});

import assert from "node:assert/strict";
import {test} from "node:test";

import {
  CollegeAssignmentError,
  planCollegeAssignmentChange,
  planCollegeCounselorTransfer,
} from "./college_assignments";

const colleges = new Map([
  ["cite", {active: true}],
  ["cas", {active: true}],
  ["cba", {active: true}],
  ["archived", {active: false}],
]);
const counselor = {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active"};
const code = (expected: string) => (e: unknown) => e instanceof CollegeAssignmentError && e.code === expected;

test("assigns multiple colleges to an active counselor, sorted and de-duplicated", () => {
  const plan = planCollegeAssignmentChange({
    target: counselor,
    requested: ["cas", "cite", "cas"],
    colleges,
    expectedRevision: 0,
  });
  assert.deepEqual(plan, {
    changed: true,
    before: [],
    next: ["cas", "cite"],
    added: ["cas", "cite"],
    removed: [],
    revision: 0,
    legacyStaffCleanup: false,
  });
});

test("updates, retains own college, and removes against the stored revision", () => {
  const target = {...counselor, assignedCollegeIds: ["cite", "cas"], collegeAssignmentRevision: 3};
  const owners = new Map([["cite", []], ["cas", []], ["cba", []]]);
  const plan = planCollegeAssignmentChange({target, requested: ["cba", "cite"], colleges, expectedRevision: 3, collegeOwners: owners});
  assert.deepEqual([plan.added, plan.removed, plan.next, plan.revision], [["cba"], ["cas"], ["cba", "cite"], 3]);
  const cleared = planCollegeAssignmentChange({target, requested: [], colleges, expectedRevision: 3, collegeOwners: owners});
  assert.deepEqual([cleared.next, cleared.removed, cleared.changed], [[], ["cas", "cite"], true]);
});

test("an unchanged set is a no-op", () => {
  const target = {...counselor, assignedCollegeIds: ["cite"], collegeAssignmentRevision: 1};
  assert.equal(planCollegeAssignmentChange({target, requested: ["cite"], colleges, expectedRevision: 1}).changed, false);
});

test("only counselors can receive assignments; admins, students, missing and new portalStaff are rejected", () => {
  for (const target of [
    {accessRole: "portalStaff"},
    {accessRole: "admin"},
    {accessRole: "appUser"},
    {role: "student"},
    null,
  ]) {
    assert.throws(
      () => planCollegeAssignmentChange({target, requested: ["cite"], colleges, expectedRevision: 0}),
      code("role-mismatch"),
    );
  }
  assert.throws(
    () => planCollegeAssignmentChange({target: {accessRole: "portalStaff"}, requested: [], colleges, expectedRevision: 0}),
    code("role-mismatch"),
  );
});

test("legacy portal staff assignments can be narrowed or cleared but never added", () => {
  const legacyStaff = {accessRole: "portalStaff", assignedCollegeIds: ["cite", "cas"], collegeAssignmentRevision: 2};
  assert.throws(
    () => planCollegeAssignmentChange({target: legacyStaff, requested: ["cite", "cas", "cba"], colleges, expectedRevision: 2}),
    code("role-mismatch"),
  );
  const partial = planCollegeAssignmentChange({target: legacyStaff, requested: ["cite"], colleges, expectedRevision: 2});
  assert.deepEqual([partial.removed, partial.next, partial.legacyStaffCleanup], [["cas"], ["cite"], true]);
  const cleared = planCollegeAssignmentChange({target: legacyStaff, requested: [], colleges, expectedRevision: 2});
  assert.deepEqual([cleared.removed, cleared.next, cleared.legacyStaffCleanup], [["cas", "cite"], [], true]);
});

test("one counselor per college rejects adding a college owned by another counselor or in conflict", () => {
  assert.throws(
    () => planCollegeAssignmentChange({
      target: counselor,
      requested: ["cite"],
      colleges,
      expectedRevision: 0,
      collegeOwners: new Map([["cite", ["other-counselor"]]]),
    }),
    code("college-already-assigned"),
  );
  assert.throws(
    () => planCollegeAssignmentChange({
      target: counselor,
      requested: ["cite"],
      colleges,
      expectedRevision: 0,
      collegeOwners: new Map([["cite", ["c-a", "c-b"]]]),
    }),
    code("college-conflict"),
  );
  // Retaining already-owned college while adding another unassigned college succeeds.
  const owner = {...counselor, assignedCollegeIds: ["cite"], collegeAssignmentRevision: 1};
  const plan = planCollegeAssignmentChange({
    target: owner,
    requested: ["cite", "cas"],
    colleges,
    expectedRevision: 1,
    collegeOwners: new Map([["cite", []], ["cas", []]]),
  });
  assert.deepEqual(plan.next, ["cas", "cite"]);
});

test("unknown colleges and malformed ids are rejected, never dropped", () => {
  assert.throws(() => planCollegeAssignmentChange({target: counselor, requested: ["cite", "nope"], colleges, expectedRevision: 0}), code("unknown-college"));
  for (const requested of [["bad/id"], [""], [42], "cite", null]) {
    assert.throws(() => planCollegeAssignmentChange({target: counselor, requested, colleges, expectedRevision: 0}), code("invalid-id"));
  }
  const many = Array.from({length: 21}, (_, i) => `c${i}`);
  const big = new Map(many.map((id) => [id, {active: true}]));
  assert.throws(() => planCollegeAssignmentChange({target: counselor, requested: many, colleges: big, expectedRevision: 0}), code("too-many"));
});

test("archived colleges cannot be added but stay removable and retainable", () => {
  assert.throws(() => planCollegeAssignmentChange({target: counselor, requested: ["archived"], colleges, expectedRevision: 0}), code("inactive-college"));
  const target = {...counselor, assignedCollegeIds: ["archived", "cite"], collegeAssignmentRevision: 2};
  assert.deepEqual(planCollegeAssignmentChange({target, requested: ["archived", "cas"], colleges, expectedRevision: 2}).next, ["archived", "cas"]);
  assert.deepEqual(planCollegeAssignmentChange({target, requested: ["cite"], colleges, expectedRevision: 2}).removed, ["archived"]);
});

test("suspended, pending or disabled counselors can be cleared but not extended", () => {
  for (const status of [{staffAccountStatus: "disabled"}, {staffAccountStatus: "pending"}, {accountStatus: "suspended"}]) {
    const target = {...counselor, ...status, assignedCollegeIds: ["cite", "cas"], collegeAssignmentRevision: 1};
    assert.throws(() => planCollegeAssignmentChange({target, requested: ["cite", "cas", "cba"], colleges, expectedRevision: 1}), code("inactive-staff"));
    assert.deepEqual(planCollegeAssignmentChange({target, requested: ["cite"], colleges, expectedRevision: 1}).removed, ["cas"]);
  }
  // Legacy counselor records without lifecycle fields remain active.
  assert.equal(planCollegeAssignmentChange({target: {accessRole: "counselor"}, requested: ["cite"], colleges, expectedRevision: 0}).changed, true);
});

test("a stale or malformed expected revision is refused", () => {
  const target = {...counselor, assignedCollegeIds: ["cite"], collegeAssignmentRevision: 4};
  for (const expectedRevision of [3, 5, "4", -1, null, undefined, 1.5]) {
    assert.throws(() => planCollegeAssignmentChange({target, requested: [], colleges, expectedRevision}), code("stale-revision"));
  }
});

test("transfer planner handles assign, transfer, unassign, conflict resolution, and stale guards", () => {
  const c1 = {uid: "c1", profile: {...counselor, assignedCollegeIds: ["cite"], collegeAssignmentRevision: 1}};
  const c2 = {uid: "c2", profile: {...counselor, assignedCollegeIds: ["cas"], collegeAssignmentRevision: 2}};

  const assigned = planCollegeCounselorTransfer({
    collegeId: "cba",
    college: {active: true},
    currentOwners: [],
    targetCounselor: c2,
    expectedOwnerIds: [],
    expectedRevisions: {c2: 2},
  });
  assert.deepEqual([assigned.changed, assigned.removals.length, assigned.addition?.next], [true, 0, ["cas", "cba"]]);

  const transferred = planCollegeCounselorTransfer({
    collegeId: "cite",
    college: {active: true},
    currentOwners: [c1],
    targetCounselor: c2,
    expectedOwnerIds: ["c1"],
    expectedRevisions: {c1: 1, c2: 2},
  });
  assert.deepEqual([transferred.removals[0].next, transferred.addition?.next, transferred.conflictResolved], [[], ["cas", "cite"], false]);

  const conflictCba1 = {uid: "c1", profile: {...counselor, assignedCollegeIds: ["cba"], collegeAssignmentRevision: 3}};
  const conflictCba2 = {uid: "c2", profile: {...counselor, assignedCollegeIds: ["cba"], collegeAssignmentRevision: 4}};
  const resolved = planCollegeCounselorTransfer({
    collegeId: "cba",
    college: {active: false}, // Retaining an existing owner during conflict resolution works even if archived.
    currentOwners: [conflictCba1, conflictCba2],
    targetCounselor: conflictCba2,
    expectedOwnerIds: ["c1", "c2"],
    expectedRevisions: {c1: 3, c2: 4},
  });
  assert.deepEqual([resolved.removals.map((r) => r.userId), resolved.addition, resolved.conflictResolved], [["c1"], null, true]);

  assert.throws(
    () => planCollegeCounselorTransfer({
      collegeId: "cite",
      college: {active: true},
      currentOwners: [c1],
      targetCounselor: c2,
      expectedOwnerIds: [],
      expectedRevisions: {c1: 1, c2: 2},
    }),
    code("stale-revision"),
  );
  assert.throws(
    () => planCollegeCounselorTransfer({
      collegeId: "cite",
      college: {active: true},
      currentOwners: [c1],
      targetCounselor: {uid: "staff", profile: {accessRole: "portalStaff"}},
      expectedOwnerIds: ["c1"],
      expectedRevisions: {c1: 1, staff: 0},
    }),
    code("role-mismatch"),
  );
});

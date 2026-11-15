import assert from "node:assert/strict";
import {test} from "node:test";

import {CollegeAssignmentError, planCollegeAssignmentChange} from "./college_assignments";

const colleges = new Map([
  ["cite", {active: true}],
  ["cas", {active: true}],
  ["cba", {active: true}],
  ["archived", {active: false}],
]);
const counselor = {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active"};
const code = (expected: string) => (e: unknown) => e instanceof CollegeAssignmentError && e.code === expected;

test("assigns colleges to an active counselor, sorted and de-duplicated", () => {
  const plan = planCollegeAssignmentChange({target: counselor, requested: ["cas", "cite", "cas"], colleges, expectedRevision: 0});
  assert.deepEqual(plan, {changed: true, before: [], next: ["cas", "cite"], added: ["cas", "cite"], removed: [], revision: 0});
});

test("updates and removes against the stored revision", () => {
  const target = {...counselor, assignedCollegeIds: ["cite", "cas"], collegeAssignmentRevision: 3};
  const plan = planCollegeAssignmentChange({target, requested: ["cba", "cite"], colleges, expectedRevision: 3});
  assert.deepEqual([plan.added, plan.removed, plan.next, plan.revision], [["cba"], ["cas"], ["cba", "cite"], 3]);
  const cleared = planCollegeAssignmentChange({target, requested: [], colleges, expectedRevision: 3});
  assert.deepEqual([cleared.next, cleared.removed, cleared.changed], [[], ["cas", "cite"], true]);
});

test("an unchanged set is a no-op", () => {
  const target = {...counselor, assignedCollegeIds: ["cite"], collegeAssignmentRevision: 1};
  assert.equal(planCollegeAssignmentChange({target, requested: ["cite"], colleges, expectedRevision: 1}).changed, false);
});

test("portal staff are eligible; admins, students and missing records are not", () => {
  assert.equal(planCollegeAssignmentChange({target: {accessRole: "portalStaff"}, requested: ["cite"], colleges, expectedRevision: 0}).changed, true);
  for (const target of [{accessRole: "admin"}, {accessRole: "appUser"}, {role: "student"}]) {
    assert.throws(() => planCollegeAssignmentChange({target, requested: ["cite"], colleges, expectedRevision: 0}), code("role-mismatch"));
  }
  assert.throws(() => planCollegeAssignmentChange({target: null, requested: ["cite"], colleges, expectedRevision: 0}), code("role-mismatch"));
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

test("suspended, pending or disabled staff can be cleared but not extended", () => {
  for (const status of [{staffAccountStatus: "disabled"}, {staffAccountStatus: "pending"}, {accountStatus: "suspended"}]) {
    const target = {...counselor, ...status, assignedCollegeIds: ["cite", "cas"], collegeAssignmentRevision: 1};
    assert.throws(() => planCollegeAssignmentChange({target, requested: ["cite", "cas", "cba"], colleges, expectedRevision: 1}), code("inactive-staff"));
    assert.deepEqual(planCollegeAssignmentChange({target, requested: ["cite"], colleges, expectedRevision: 1}).removed, ["cas"]);
  }
  // Legacy records without lifecycle fields are active.
  assert.equal(planCollegeAssignmentChange({target: {accessRole: "counselor"}, requested: ["cite"], colleges, expectedRevision: 0}).changed, true);
});

test("a stale or malformed expected revision is refused", () => {
  const target = {...counselor, assignedCollegeIds: ["cite"], collegeAssignmentRevision: 4};
  for (const expectedRevision of [3, 5, "4", -1, null, undefined, 1.5]) {
    assert.throws(() => planCollegeAssignmentChange({target, requested: [], colleges, expectedRevision}), code("stale-revision"));
  }
});

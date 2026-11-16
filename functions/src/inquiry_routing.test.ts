import assert from "node:assert/strict";
import {test} from "node:test";

import {
  assigneeNotificationId,
  decideRouting,
  escalationNotificationId,
  InquiryRoutingError,
  isEligibleAssignee,
  planReassignment,
  triageNotificationId,
} from "./inquiry_routing";

const verifiedStudent = {verificationStatus: "verified", collegeId: "cite"};
const okAuth = {disabled: false, emailVerified: true};
const counselor = (over: Record<string, unknown> = {}) => ({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: ["cite"], ...over});
const code = (expected: string) => (e: unknown) => e instanceof InquiryRoutingError && e.code === expected;

test("routes a verified student's inquiry to every eligible assignee of the college, sorted", () => {
  const decision = decideRouting({
    student: verifiedStudent,
    collegeExists: true,
    candidates: [
      {uid: "s2", label: "Staff Two", profile: {accessRole: "portalStaff", assignedCollegeIds: ["cite"]}, auth: okAuth},
      {uid: "c1", label: "Counselor One", profile: counselor(), auth: okAuth},
    ],
  });
  assert.deepEqual(decision, {
    routingStatus: "routed",
    routingReason: null,
    collegeId: "cite",
    assigneeIds: ["c1", "s2"],
    assigneeLabels: {c1: "Counselor One", s2: "Staff Two"},
  });
});

test("missing, unverified and unknown colleges go to triage with a reason", () => {
  const triage = (student: Record<string, unknown> | null, collegeExists = true) =>
    decideRouting({student, collegeExists, candidates: []});
  assert.equal(triage(null).routingReason, "missing_college");
  assert.equal(triage({verificationStatus: "verified"}).routingReason, "missing_college");
  assert.equal(triage({verificationStatus: "verified", collegeId: "bad/id"}).routingReason, "missing_college");
  assert.equal(triage({verificationStatus: "needsReview", collegeId: "cite"}).routingReason, "unverified_profile");
  assert.equal(triage({collegeId: "cite"}).routingReason, "unverified_profile");
  assert.equal(triage(verifiedStudent, false).routingReason, "unknown_college");
  for (const reason of ["missing_college", "unverified_profile"]) {
    const d = triage(reason === "missing_college" ? null : {collegeId: "cite"});
    assert.equal(d.routingStatus, "needs_triage");
    assert.deepEqual(d.assigneeIds, []);
  }
  // The college is recorded only once it is verified and known.
  assert.equal(triage({verificationStatus: "needsReview", collegeId: "cite"}).collegeId, "");
  assert.equal(triage(verifiedStudent, false).collegeId, "");
});

test("a college with no eligible staff goes to triage but keeps the college", () => {
  const d = decideRouting({
    student: verifiedStudent,
    collegeExists: true,
    candidates: [
      {uid: "x", label: "Suspended", profile: counselor({accountStatus: "suspended"}), auth: okAuth},
      {uid: "y", label: "Unverified", profile: counselor(), auth: {disabled: false, emailVerified: false}},
      {uid: "z", label: "Elsewhere", profile: counselor({assignedCollegeIds: ["cas"]}), auth: okAuth},
    ],
  });
  assert.deepEqual([d.routingStatus, d.routingReason, d.collegeId, d.assigneeIds], ["needs_triage", "no_eligible_staff", "cite", []]);
});

test("eligibility mirrors the portal lifecycle gates", () => {
  assert.equal(isEligibleAssignee(counselor(), okAuth), true);
  assert.equal(isEligibleAssignee({accessRole: "portalStaff"}, okAuth), true, "legacy record without lifecycle fields");
  assert.equal(isEligibleAssignee({accessRole: "admin"}, okAuth), false);
  assert.equal(isEligibleAssignee({accessRole: "appUser"}, okAuth), false);
  assert.equal(isEligibleAssignee(counselor({staffAccountStatus: "pending"}), okAuth), false);
  assert.equal(isEligibleAssignee(counselor({staffAccountStatus: "disabled"}), okAuth), false);
  assert.equal(isEligibleAssignee(counselor({accountStatus: "suspended"}), okAuth), false);
  assert.equal(isEligibleAssignee(counselor(), {disabled: true, emailVerified: true}), false);
  assert.equal(isEligibleAssignee(counselor(), {disabled: false, emailVerified: false}), false);
  assert.equal(isEligibleAssignee(counselor(), null), false);
});

test("reassignment requires eligible accounts, a fresh revision and records out-of-college assignees", () => {
  const candidates = new Map([
    ["c1", {label: "Counselor One", profile: counselor(), auth: okAuth}],
    ["c2", {label: "Counselor Two", profile: counselor({assignedCollegeIds: ["cas"]}), auth: okAuth}],
    ["bad", {label: "Suspended", profile: counselor({accountStatus: "suspended"}), auth: okAuth}],
  ]);
  const inquiry = {collegeId: "cite", assigneeIds: ["old"], routingRevision: 2, ownerId: "old"};
  const plan = planReassignment({inquiry, requested: ["c2", "c1", "c1"], candidates, expectedRevision: 2});
  assert.deepEqual(plan, {
    assigneeIds: ["c1", "c2"],
    assigneeLabels: {c1: "Counselor One", c2: "Counselor Two"},
    added: ["c1", "c2"],
    removed: ["old"],
    outOfCollege: ["c2"],
    ownerId: null,
    revision: 3,
  });
  assert.throws(() => planReassignment({inquiry, requested: ["c1"], candidates, expectedRevision: 1}), code("stale-revision"));
  assert.throws(() => planReassignment({inquiry, requested: ["bad"], candidates, expectedRevision: 2}), code("ineligible-assignee"));
  assert.throws(() => planReassignment({inquiry, requested: ["ghost"], candidates, expectedRevision: 2}), code("ineligible-assignee"));
  assert.throws(() => planReassignment({inquiry, requested: [], candidates, expectedRevision: 2}), code("invalid-assignees"));
  assert.throws(() => planReassignment({inquiry, requested: Array.from({length: 11}, (_, i) => `u${i}`), candidates, expectedRevision: 2}), code("invalid-assignees"));
  assert.throws(() => planReassignment({inquiry, requested: ["bad/id"], candidates, expectedRevision: 2}), code("invalid-assignees"));
  // An owner who stays assigned keeps ownership; legacy inquiries start at revision 0.
  const kept = planReassignment({inquiry: {collegeId: "cite", assigneeIds: ["c1"], ownerId: "c1"}, requested: ["c1", "c2"], candidates, expectedRevision: 0});
  assert.deepEqual([kept.ownerId, kept.revision, kept.added, kept.removed], ["c1", 1, ["c2"], []]);
});

test("notification ids are deterministic and path-safe", () => {
  assert.equal(assigneeNotificationId("inq1", "uid1"), "portal_inquiry_inq1_uid1");
  assert.equal(triageNotificationId("inq1"), "portal_inquiry_triage_inq1");
  assert.equal(escalationNotificationId("inq1", 3), "portal_inquiry_escalation_inq1_3");
});

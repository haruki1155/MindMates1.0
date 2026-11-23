import assert from "node:assert/strict";
import {test} from "node:test";

import {
  ApprovalError,
  AuthState,
  decideApprovalAuthority,
  decideApprovalScope,
  isEligibleCounselor,
} from "./appointment_approval";

const okAuth = {disabled: false, emailVerified: true};
const counselor = (over: Record<string, unknown> = {}) =>
  ({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: ["cite"], ...over});
const student = {verificationStatus: "verified", collegeId: "cite"};
const code = (expected: string) => (e: unknown) => e instanceof ApprovalError && e.code === expected;

test("an appointment is college-scoped when a verified student's college has an eligible counselor", () => {
  assert.deepEqual(
    decideApprovalScope({student, collegeExists: true, counselors: [{profile: counselor(), auth: okAuth}]}),
    {scope: "college", collegeId: "cite", reason: null},
  );
});

test("unverifiable or unstaffed appointments are exceptions with a reason", () => {
  const scope = (s: Record<string, unknown> | null, collegeExists = true, counselors: Array<{profile: Record<string, unknown>; auth: AuthState}> = [{profile: counselor(), auth: okAuth}]) =>
    decideApprovalScope({student: s, collegeExists, counselors});
  assert.deepEqual(scope(null), {scope: "exception", collegeId: "", reason: "missing_college"});
  assert.equal(scope({verificationStatus: "verified"}).reason, "missing_college");
  assert.equal(scope({verificationStatus: "verified", collegeId: "bad/id"}).reason, "missing_college");
  assert.equal(scope({verificationStatus: "needsReview", collegeId: "cite"}).reason, "unverified_profile");
  assert.equal(scope({collegeId: "cite"}).reason, "unverified_profile");
  assert.equal(scope(student, false).reason, "unknown_college");
  assert.deepEqual(scope(student, true, []), {scope: "exception", collegeId: "cite", reason: "no_eligible_counselor"});
  // Portal staff, suspended or unverified counselors and other colleges do not make a college approvable.
  const ineligible = [
    {profile: {accessRole: "portalStaff", assignedCollegeIds: ["cite"]}, auth: okAuth},
    {profile: counselor({accountStatus: "suspended"}), auth: okAuth},
    {profile: counselor(), auth: {disabled: false, emailVerified: false}},
    {profile: counselor({assignedCollegeIds: ["cas"]}), auth: okAuth},
  ];
  assert.equal(scope(student, true, ineligible).reason, "no_eligible_counselor");
});

test("counselor eligibility mirrors the portal lifecycle gates and requires the counselor role", () => {
  assert.equal(isEligibleCounselor(counselor(), okAuth), true);
  assert.equal(isEligibleCounselor({accessRole: "counselor"}, okAuth), true, "legacy record without lifecycle fields");
  for (const profile of [{accessRole: "portalStaff"}, {accessRole: "admin"}, counselor({staffAccountStatus: "pending"}), counselor({staffAccountStatus: "disabled"}), counselor({accountStatus: "suspended"})]) {
    assert.equal(isEligibleCounselor(profile, okAuth), false, JSON.stringify(profile));
  }
  assert.equal(isEligibleCounselor(counselor(), {disabled: true, emailVerified: true}), false);
  assert.equal(isEligibleCounselor(counselor(), null), false);
});

const college = {scope: "college" as const, collegeId: "cite", reason: null};
const exception = {scope: "exception" as const, collegeId: "", reason: "missing_college" as const};

test("the assigned counselor approves college-scoped appointments; others are refused", () => {
  assert.deepEqual(
    decideApprovalAuthority({actor: {role: "counselor", isSuperAdmin: false, assignedCollegeIds: ["cas", "cite"]}, scope: college}),
    {mode: "college", collegeId: "cite", scopeReason: null, exceptionReason: null},
  );
  assert.throws(() => decideApprovalAuthority({actor: {role: "counselor", isSuperAdmin: false, assignedCollegeIds: ["cas"]}, scope: college}), code("wrong_college"));
  assert.throws(() => decideApprovalAuthority({actor: {role: "counselor", isSuperAdmin: false, assignedCollegeIds: ["cite"]}, scope: exception}), code("needs_triage"));
  for (const role of ["portalStaff", "appUser", ""]) {
    assert.throws(() => decideApprovalAuthority({actor: {role, isSuperAdmin: false, assignedCollegeIds: ["cite"]}, scope: college}), code("operational_staff"));
  }
});

test("administrators are read-only for appointments and cannot approve or override", () => {
  const admin = {role: "admin", isSuperAdmin: true, assignedCollegeIds: ["cite"]};
  assert.throws(() => decideApprovalAuthority({actor: admin, scope: exception}), code("admin_read_only"));
  assert.throws(() => decideApprovalAuthority({actor: admin, scope: college}), code("admin_read_only"));
  assert.throws(
    () => decideApprovalAuthority({actor: admin, scope: college, exceptionReason: "Counselor on leave this week"}),
    code("admin_read_only"),
  );
  const otherAdmin = {role: "admin", isSuperAdmin: false, assignedCollegeIds: ["cite"]};
  assert.throws(() => decideApprovalAuthority({actor: otherAdmin, scope: exception}), code("admin_read_only"));
  assert.throws(
    () => decideApprovalAuthority({actor: otherAdmin, scope: college, exceptionReason: "Counselor on leave"}),
    code("admin_read_only"),
  );
});

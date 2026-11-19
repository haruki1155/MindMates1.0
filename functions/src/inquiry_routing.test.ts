import assert from "node:assert/strict";
import {test} from "node:test";

import {
  assigneeNotificationId,
  buildInquiryStatusProjection,
  decideRouting,
  escalationNotificationId,
  InquiryRoutingError,
  isEligibleAssignee,
  isEligibleCounselorAssignee,
  isEligibleMonitoringStaff,
  planReassignment,
  shouldWriteInquiryProjection,
  triageNotificationId,
} from "./inquiry_routing";

const verifiedStudent = {verificationStatus: "verified", collegeId: "cite"};
const okAuth = {disabled: false, emailVerified: true};
const counselor = (over: Record<string, unknown> = {}) => ({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: ["cite"], ...over});
const portalStaff = (over: Record<string, unknown> = {}) => ({accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active", ...over});
const code = (expected: string) => (e: unknown) => e instanceof InquiryRoutingError && e.code === expected;

test("routes a verified student's inquiry to eligible counselors only, ignoring legacy portalStaff college assignments", () => {
  const decision = decideRouting({
    student: verifiedStudent,
    collegeExists: true,
    candidates: [
      {uid: "s2", label: "Staff Two", profile: {accessRole: "portalStaff", assignedCollegeIds: ["cite"]}, auth: okAuth},
      {uid: "c1", label: "Counselor One", profile: counselor(), auth: okAuth},
      {uid: "c3", label: "Counselor Three", profile: counselor(), auth: okAuth},
    ],
  });
  assert.deepEqual(decision, {
    routingStatus: "routed",
    routingReason: null,
    collegeId: "cite",
    assigneeIds: ["c1", "c3"],
    assigneeLabels: {c1: "Counselor One", c3: "Counselor Three"},
    monitoringStaffIds: [],
    monitoringStaffLabels: {},
  });
});

test("college with only legacy portalStaff and no eligible counselor goes to triage", () => {
  const d = decideRouting({
    student: verifiedStudent,
    collegeExists: true,
    candidates: [
      {uid: "s1", label: "Legacy Staff", profile: portalStaff({assignedCollegeIds: ["cite"]}), auth: okAuth},
    ],
  });
  assert.deepEqual([d.routingStatus, d.routingReason, d.collegeId, d.assigneeIds, d.monitoringStaffIds],
    ["needs_triage", "no_eligible_staff", "cite", [], []]);
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

test("eligibility enforces counselor clinical vs portalStaff monitoring separation and lifecycle gates", () => {
  assert.equal(isEligibleCounselorAssignee(counselor(), okAuth), true);
  assert.equal(isEligibleAssignee(counselor(), okAuth), true);
  assert.equal(isEligibleCounselorAssignee(portalStaff(), okAuth), false);
  assert.equal(isEligibleMonitoringStaff(portalStaff(), okAuth), true);
  assert.equal(isEligibleMonitoringStaff({accessRole: "portalStaff"}, okAuth), true, "legacy record without lifecycle fields");
  assert.equal(isEligibleMonitoringStaff(counselor(), okAuth), false);
  assert.equal(isEligibleCounselorAssignee({accessRole: "admin"}, okAuth), false);
  assert.equal(isEligibleCounselorAssignee({accessRole: "appUser"}, okAuth), false);
  assert.equal(isEligibleCounselorAssignee(counselor({staffAccountStatus: "pending"}), okAuth), false);
  assert.equal(isEligibleCounselorAssignee(counselor({staffAccountStatus: "disabled"}), okAuth), false);
  assert.equal(isEligibleCounselorAssignee(counselor({accountStatus: "suspended"}), okAuth), false);
  assert.equal(isEligibleMonitoringStaff(portalStaff({accountStatus: "suspended"}), okAuth), false);
  assert.equal(isEligibleCounselorAssignee(counselor(), {disabled: true, emailVerified: true}), false);
  assert.equal(isEligibleCounselorAssignee(counselor(), {disabled: false, emailVerified: false}), false);
  assert.equal(isEligibleCounselorAssignee(counselor(), null), false);
});

test("reassignment separates clinical counselors and operational monitoring staff cleanly", () => {
  const candidates = new Map([
    ["c1", {label: "Counselor One", profile: counselor(), auth: okAuth}],
    ["c2", {label: "Counselor Two", profile: counselor({assignedCollegeIds: ["cas"]}), auth: okAuth}],
    ["s1", {label: "Staff One", profile: portalStaff(), auth: okAuth}],
    ["bad", {label: "Suspended", profile: counselor({accountStatus: "suspended"}), auth: okAuth}],
  ]);
  const inquiry = {collegeId: "cite", assigneeIds: ["old"], monitoringStaffIds: ["old-staff"], routingRevision: 2, ownerId: "old"};
  const plan = planReassignment({
    inquiry,
    requested: ["c2", "c1", "c1"],
    requestedMonitoring: ["s1", "s1"],
    candidates,
    expectedRevision: 2,
  });
  assert.deepEqual(plan, {
    assigneeIds: ["c1", "c2"],
    assigneeLabels: {c1: "Counselor One", c2: "Counselor Two"},
    monitoringStaffIds: ["s1"],
    monitoringStaffLabels: {s1: "Staff One"},
    added: ["c1", "c2", "s1"],
    removed: ["old", "old-staff"],
    outOfCollege: ["c2"],
    ownerId: null,
    revision: 3,
  });
  assert.throws(() => planReassignment({inquiry, requested: ["s1"], candidates, expectedRevision: 2}), code("ineligible-assignee"));
  assert.throws(() => planReassignment({inquiry, requested: ["c1"], requestedMonitoring: ["c2"], candidates, expectedRevision: 2}), code("ineligible-assignee"));
  assert.throws(() => planReassignment({inquiry, requested: ["c1"], candidates, expectedRevision: 1}), code("stale-revision"));
  assert.throws(() => planReassignment({inquiry, requested: ["bad"], candidates, expectedRevision: 2}), code("ineligible-assignee"));
  assert.throws(() => planReassignment({inquiry, requested: ["ghost"], candidates, expectedRevision: 2}), code("ineligible-assignee"));
  assert.throws(() => planReassignment({inquiry, requested: [], candidates, expectedRevision: 2}), code("invalid-assignees"));
  assert.throws(() => planReassignment({inquiry, requested: [], requestedMonitoring: ["s1"], candidates, expectedRevision: 2}), code("invalid-assignees"));
  assert.throws(() => planReassignment({inquiry, requested: [], requestedMonitoring: [], candidates, expectedRevision: 2}), code("invalid-assignees"));
  assert.throws(() => planReassignment({inquiry, requested: Array.from({length: 11}, (_, i) => `u${i}`), candidates, expectedRevision: 2}), code("invalid-assignees"));
  assert.throws(() => planReassignment({inquiry, requested: ["bad/id"], candidates, expectedRevision: 2}), code("invalid-assignees"));
  // An owner who stays assigned keeps ownership; legacy inquiries start at revision 0.
  const kept = planReassignment({inquiry: {collegeId: "cite", assigneeIds: ["c1"], ownerId: "c1"}, requested: ["c1", "c2"], candidates, expectedRevision: 0});
  assert.deepEqual([kept.ownerId, kept.revision, kept.added, kept.removed], ["c1", 1, ["c2"], []]);
});

test("buildInquiryStatusProjection strips all PII, user-authored text and escalation reasons, and prevents stale overwrites", () => {
  const projection = buildInquiryStatusProjection("inq-1", {
    userId: "student-secret-uid",
    subject: "User-authored sensitive subject",
    message: "Private student distress narrative",
    email: "student@example.edu",
    name: "Private Student Name",
    role: "student",
    category: "Service Form",
    formType: "client_feedback",
    formData: {q1: "Private clinical response"},
    clinicalNotes: "Confidential notes",
    transcript: "Confidential transcript",
    status: "in_progress",
    collegeId: "cite",
    routingStatus: "routed",
    routingMode: "manual",
    routingRevision: 3,
    assigneeIds: ["c1"],
    assigneeLabels: {c1: "Counselor One"},
    monitoringStaffIds: ["s1"],
    monitoringStaffLabels: {s1: "Staff One"},
    ownerId: "c1",
    escalation: {status: "requested", reason: "Student disclosed sensitive personal details"},
    responseCount: 2,
    firstResponseAt: "ts1",
    lastResponseAt: "ts2",
    lastResponseBy: "c1",
    lastResponseByName: "Secret Responder Name",
    lastResponseRole: "counselor",
    takeover: {by: "admin", byName: "Super Admin", reason: "Confidential takeover note"},
  });
  const json = JSON.stringify(projection);
  for (const forbidden of [
    "student-secret-uid",
    "User-authored sensitive subject",
    "Private student distress narrative",
    "student@example.edu",
    "Private Student Name",
    "Private clinical response",
    "Confidential notes",
    "Confidential transcript",
    "Student disclosed sensitive personal details",
    "Confidential takeover note",
    "Super Admin",
    "Secret Responder Name",
  ]) {
    assert.ok(!json.includes(forbidden), `projection leaked: ${forbidden}`);
  }
  for (const key of ["userId", "subject", "message", "formData", "email", "name", "role", "escalationReason", "escalation", "clinicalNotes", "transcript", "takeover", "takeoverReason", "takeoverByName", "lastResponseByName", "lastResponseBy", "lastResponseRole"]) {
    assert.equal(Object.prototype.hasOwnProperty.call(projection, key), false, `unexpected key: ${key}`);
  }
  assert.equal(projection.operationalLabel, "Client Feedback Form");
  assert.equal(projection.escalationStatus, "requested");
  assert.equal(projection.responseCount, 2);
  assert.equal(projection.isTakenOver, true);
  assert.deepEqual(projection.monitoringStaffIds, ["s1"]);

  // Unknown client-supplied category or formType cannot smuggle user text.
  const sanitized = buildInquiryStatusProjection("inq-2", {
    category: "Private crafted category text",
    formType: "crafted_secret_slug",
  });
  assert.equal(sanitized.category, "General");
  assert.equal(sanitized.formType, null);
  assert.equal(sanitized.operationalLabel, "General Inquiry");

  // Delayed triggers with older routingRevision must not overwrite newer projections.
  assert.equal(shouldWriteInquiryProjection({...projection, routingRevision: 3}, {...projection, routingRevision: 2}), false);
  assert.equal(shouldWriteInquiryProjection({...projection, routingRevision: 3}, {...projection, routingRevision: 3}), false);
  assert.equal(shouldWriteInquiryProjection({...projection, routingRevision: 3}, {...projection, routingRevision: 4}), true);
});

test("notification ids are deterministic and path-safe", () => {
  assert.equal(assigneeNotificationId("inq1", "uid1"), "portal_inquiry_inq1_uid1");
  assert.equal(triageNotificationId("inq1"), "portal_inquiry_triage_inq1");
  assert.equal(escalationNotificationId("inq1", 3), "portal_inquiry_escalation_inq1_3");
});

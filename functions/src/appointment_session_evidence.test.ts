import assert from "node:assert/strict";
import {test} from "node:test";
import {validateSessionEvidence, sessionEvidencePathFor} from "./appointment_session_evidence";

const appointmentId = "ap-123";
const counselorId = "counselor-55";
const path = `counseling_session_files/${appointmentId}/${counselorId}/0123456789abcdef0123456789abcdef.pdf`;
const valid = {path, name: "Interview checklist.pdf", contentType: "application/pdf", size: 2456};

test("bounded private interview documentation normalizes valid text and file manifest", () => {
  const result = validateSessionEvidence({
    interviewQuestions: "  What support helps you?  ",
    requirementsChecked: "  Consent explained  ",
    materialsUsed: "  Counseling worksheet  ",
    attachments: [valid],
  }, appointmentId, counselorId);
  assert.equal(result.interviewQuestions, "What support helps you?");
  assert.equal(result.requirementsChecked, "Consent explained");
  assert.equal(result.materialsUsed, "Counseling worksheet");
  assert.deepEqual(result.attachments, [valid]);
});

test("non-completed session cannot introduce private documentation", () => {
  assert.deepEqual(validateSessionEvidence({}, appointmentId, counselorId), {
    interviewQuestions: "", requirementsChecked: "", materialsUsed: "", attachments: [],
  });
  assert.throws(() => validateSessionEvidence({
    interviewQuestions: "x".repeat(4001),
  }, appointmentId, counselorId), /too long/);
});

test("rejects mismatched owner, path traversal, MIME mismatch and oversized attachments", () => {
  for (const invalid of [
    {...valid, path: path.replace(counselorId, "another-staff")},
    {...valid, path: `counseling_session_files/${appointmentId}/${counselorId}/../private.pdf`},
    {...valid, path: path.replace(".pdf", ".png")},
    {...valid, size: 5 * 1024 * 1024 + 1},
    {...valid, name: "../patient.txt"},
    {...valid, contentType: "text/html"},
  ]) {
    assert.throws(
      () => validateSessionEvidence({attachments: [invalid]}, appointmentId, counselorId),
      {code: "invalid-argument"},
    );
  }
});

test("rejects duplicate files and unbounded number of attachments", () => {
  assert.throws(() => validateSessionEvidence({attachments: [valid, valid]}, appointmentId, counselorId), /Duplicate/);
  assert.throws(() => validateSessionEvidence({attachments: Array(6).fill(valid)}, appointmentId, counselorId), /at most five/);
});

test("object path helper excludes original filename and validates IDs", () => {
  assert.equal(sessionEvidencePathFor(appointmentId, counselorId, "0123456789abcdef0123456789abcdef", "png"),
    `counseling_session_files/${appointmentId}/${counselorId}/0123456789abcdef0123456789abcdef.png`);
  assert.throws(() => sessionEvidencePathFor("../other", counselorId, "0123456789abcdef0123456789abcdef", "png"));
});

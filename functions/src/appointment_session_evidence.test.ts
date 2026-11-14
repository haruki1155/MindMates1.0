import assert from "node:assert/strict";
import {test} from "node:test";
import {validateSessionEvidence, sessionEvidencePathFor} from "./appointment_session_evidence";

const appointmentId = "ap-123";
const counselorId = "counselor-55";
const path = `counseling_session_files/${appointmentId}/${counselorId}/0123456789abcdef0123456789abcdef.pdf`;
const valid = {path, name: "Interview checklist.pdf", contentType: "application/pdf", size: 2456};

test("private session evidence validates a file manifest without new text fields", () => {
  const result = validateSessionEvidence({attachments: [valid]}, appointmentId, counselorId);
  assert.deepEqual(result, {attachments: [valid]});
});

test("empty file manifests work and removed text fields are rejected", () => {
  assert.deepEqual(
    validateSessionEvidence({}, appointmentId, counselorId),
    {attachments: []},
  );
  for (const field of ["interviewQuestions", "requirementsChecked", "materialsUsed"]) {
    assert.throws(
      () => validateSessionEvidence({[field]: "unsupported"}, appointmentId, counselorId),
      {code: "invalid-argument"},
    );
  }
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

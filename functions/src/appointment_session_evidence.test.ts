import assert from "node:assert/strict";
import {test} from "node:test";
import {
  downloadSessionEvidenceFile,
  sessionEvidencePathFor,
  validateSessionEvidence,
  validateSessionEvidenceDownloadRequest,
} from "./appointment_session_evidence";

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

test("download request validation accepts valid appointmentId and clinical attachment path", () => {
  const result = validateSessionEvidenceDownloadRequest({appointmentId, path});
  assert.deepEqual(result, {appointmentId, path});
});

test("download request validation rejects invalid appointmentIds, path traversal, non-clinical prefixes, mismatches, and bad extensions", () => {
  const validHex = "0123456789abcdef0123456789abcdef";
  const badInputs: Array<Record<string, unknown>> = [
    {},
    {appointmentId: "", path},
    {appointmentId: "../bad", path},
    {appointmentId: "a/b", path},
    {appointmentId: "a".repeat(121), path},
    {appointmentId, path: ""},
    {appointmentId, path: `profile_images/${counselorId}/${validHex}.pdf`},
    {appointmentId, path: `backups/2026/${validHex}.pdf`},
    {appointmentId, path: `counseling_session_files/${appointmentId}/${counselorId}/../${validHex}.pdf`},
    {appointmentId, path: `counseling_session_files/${appointmentId}/${counselorId}/%2e%2e/${validHex}.pdf`},
    {appointmentId, path: `counseling_session_files/${appointmentId}/${counselorId}\\${validHex}.pdf`},
    {appointmentId, path: `counseling_session_files/${appointmentId}/${counselorId}/sub/${validHex}.pdf`},
    {appointmentId, path: `counseling_session_files/other-appt/${counselorId}/${validHex}.pdf`},
    {appointmentId, path: `counseling_session_files/${appointmentId}/${counselorId}/0123456789ABCDEF0123456789ABCDEF.pdf`},
    {appointmentId, path: `counseling_session_files/${appointmentId}/${counselorId}/shorthex.pdf`},
    {appointmentId, path: `counseling_session_files/${appointmentId}/${counselorId}/${validHex}.txt`},
    {appointmentId, path: `counseling_session_files/${appointmentId}/${counselorId}/${validHex}.exe`},
    {appointmentId, path: `counseling_session_files/${appointmentId}/${counselorId}/${validHex}.svg`},
  ];
  for (const input of badInputs) {
    assert.throws(
      () => validateSessionEvidenceDownloadRequest(input),
      (err: {code?: string; message?: string}) =>
        err?.code === "invalid-argument" && !String(err.message ?? "").includes("counseling_session_files/"),
    );
  }
});

test("downloadSessionEvidenceFile enforces metadata/size/MIME integrity and safe not-found errors", async () => {
  const fileBytes = Buffer.from("%PDF-1.4\nhello", "utf8");
  const baseDeps = () => ({
    requireClinical: async () => ({accessRole: "counselor", assignedCollegeIds: ["cite"], name: "Counselor One"}),
    superAdminUid: () => "super-admin",
    readAppointment: async () => ({userId: "student-1"}),
    readStudentUser: async () => ({verificationStatus: "verified", collegeId: "cite"}),
    readSessionNote: async () => ({
      attachments: [{path, name: "Worksheet.pdf", contentType: "application/pdf", size: fileBytes.length}],
    }),
    readObjectMetadata: async () => ({
      size: fileBytes.length,
      contentType: "application/pdf",
      metadata: {uploadedBy: counselorId, appointmentId},
    }),
    downloadObjectBytes: async () => fileBytes,
    writeAudit: async (_event: unknown) => undefined,
  });

  // Success returns exact bytes, filename, contentType, and audits without raw path/filename/bytes
  let capturedAudit: Record<string, unknown> | null = null;
  const okDeps = baseDeps();
  okDeps.writeAudit = async (event: unknown) => {
    capturedAudit = event as Record<string, unknown>;
  };
  const downloaded = await downloadSessionEvidenceFile({actorId: counselorId, appointmentId, path}, okDeps);
  assert.equal(downloaded.name, "Worksheet.pdf");
  assert.equal(downloaded.contentType, "application/pdf");
  assert.equal(downloaded.size, fileBytes.length);
  assert.deepEqual(Buffer.from(downloaded.dataBase64, "base64"), fileBytes);
  assert.equal(capturedAudit?.["action"], "CLINICAL_ATTACHMENT_DOWNLOADED");
  assert.equal(JSON.stringify(capturedAudit).includes("Worksheet.pdf"), false);
  assert.equal(JSON.stringify(capturedAudit).includes("counseling_session_files/"), false);

  // Oversized object rejected before downloadObjectBytes
  let downloadCalled = false;
  await assert.rejects(
    downloadSessionEvidenceFile(
      {actorId: counselorId, appointmentId, path},
      {
        ...baseDeps(),
        readObjectMetadata: async () => ({
          size: 5 * 1024 * 1024 + 1,
          contentType: "application/pdf",
          metadata: {uploadedBy: counselorId, appointmentId},
        }),
        downloadObjectBytes: async () => {
          downloadCalled = true;
          return fileBytes;
        },
      },
    ),
    {code: "failed-precondition"},
  );
  assert.equal(downloadCalled, false);

  // Empty (0 B) object rejected
  await assert.rejects(
    downloadSessionEvidenceFile(
      {actorId: counselorId, appointmentId, path},
      {
        ...baseDeps(),
        readObjectMetadata: async () => ({
          size: 0,
          contentType: "application/pdf",
          metadata: {uploadedBy: counselorId, appointmentId},
        }),
      },
    ),
    {code: "failed-precondition"},
  );

  // MIME mismatch rejected
  await assert.rejects(
    downloadSessionEvidenceFile(
      {actorId: counselorId, appointmentId, path},
      {
        ...baseDeps(),
        readObjectMetadata: async () => ({
          size: fileBytes.length,
          contentType: "image/png",
          metadata: {uploadedBy: counselorId, appointmentId},
        }),
      },
    ),
    {code: "failed-precondition"},
  );

  // Metadata mismatch (uploadedBy / appointmentId) rejected
  for (const badMeta of [
    {uploadedBy: "someone-else", appointmentId},
    {uploadedBy: counselorId, appointmentId: "other-appt"},
  ]) {
    await assert.rejects(
      downloadSessionEvidenceFile(
        {actorId: counselorId, appointmentId, path},
        {
          ...baseDeps(),
          readObjectMetadata: async () => ({
            size: fileBytes.length,
            contentType: "application/pdf",
            metadata: badMeta,
          }),
        },
      ),
      {code: "failed-precondition"},
    );
  }

  // Missing Storage file throws not-found without leaking bucket or path
  await assert.rejects(
    downloadSessionEvidenceFile(
      {actorId: counselorId, appointmentId, path},
      {
        ...baseDeps(),
        readObjectMetadata: async () => null,
      },
    ),
    (err: {code?: string; message?: string}) => {
      const msg = String(err?.message ?? "");
      return err?.code === "not-found" &&
        !msg.includes("counseling_session_files/") &&
        !msg.includes("gs://") &&
        !msg.includes("firebasestorage");
    },
  );
});

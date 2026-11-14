# MindMate: Counselor interview documentation and protected evidence (Task #10)
Date: 2026-11-14 | Status: Implementation candidate; local and emulator verification required

## Goal
A verified Guidance Counselor performing **Web → Appointments → Review** can record what was checked and used during a real session: private session summary, questions asked, student requirements reviewed, materials used, plus reference files (images and PDF/DOCX/documents). The completed appointment's Review/Details dialog must show the saved record to clinical staff, including authenticated file downloads. No counseling note or file link may appear in client-facing appointment/notification records.

## Alternatives considered
1. **Single session-summary string only**: no structured fields or attachments; doesn't meet the request.
2. **Base64 blobs in the appointment document**: breaches Firestore size and confidentiality boundaries. Rejected.
3. **Private clinical note subdocument + Firebase Storage**: selected. Reuses the existing callable-only session completion transaction and private clinical_notes rules, with strictly typed bounded attachments; explicit storage rules.

## Data contract
Private document: `appointments/{appointmentId}/clinical_notes/session`, callable-created on completion only. Existing `summary` preserved. Additional strings `interviewQuestions` (max 4000), `requirementsChecked` (max 2000), `materialsUsed` (max 2000), and `attachments`: at most five {path, name, contentType, size} records.
Private objects: `counseling_session_files/{appointmentId}/{uploaderUid}/{uniqueFileName}`. Allowed PNG, JPEG, PDF, DOC, DOCX; max 5 MiB each. Unique immutable objects, no public `getDownloadURL` references. The web reads downloads via Storage authenticated `getData`.

## Flow
- The Review Appointment dialog shows additional fields when `action == completed`, alongside the existing required summary and optional follow-up offer.
- Counselor selects up to five supported files via browser file picker; client checks size and types; files stay in memory until Send Decision.
- After the appointment revision guard (initialization path) and UI validation, upload selected files to private Storage using a per-appointment path; then pass metadata and text to existing reviewAppointment callable.
- Server validates text and metadata, confirms each Storage object matches path/staff/allowed type/size, and commits only verified references in the clinical_notes/session transaction. Failures preserve draft in UI; best-effort delete uploaded files only for an unsuccessful request; don't delete after successful completion.
- Opening an already-completed appointment loads the clinical session note via an authenticated Firestore read and renders the summary, questions, requirements, materials and file list; file bytes fetched on explicit action and downloaded locally; never store public download tokens.
- General staff, students, and unrelated accounts cannot access clinical notes/files. Clinical access follows current counselor/admin privacy model, not looser permissions.

## Guardrails
- Do not alter booking or follow-up agreement state machine, general appointment fields, notifications, or audit metadata with clinical content.
- Reject path traversal, spoofed references, MIME mismatches, oversized files, extra fields and non-completed-action payloads on backend; storage rules are defense in depth. Do not broaden old existing profile-image rules.
- If storage/firestore rules are not deployed to staging, upload will not work; no production rule changes/deploy until approval.
- Orphan upload risks and stale appointments must be handled and surfaced. Require staged emulator validation and device/browser acceptance before PR.
- Never use clinic material in public hosting downloads, analytics or logs.

## Acceptance
1. Counselor sees text fields and Add files only when Mark session as completed is selected.
2. Selected image/PDF/DOC/DOCX appears in private attachments list; invalid types/sizes rejected.
3. Completion without summary remains denied; text & verified references saved only to `clinical_notes/session` and reviewable on completed appointment.
4. Student/portalStaff cannot read private files or clinical notes; direct writing denied.
5. Existing appointment review/reschedule/follow-up flows and regression suites stay green.
6. Staging web preview and screenshot before PR; PR only after user approval.

# MindMate — Counselor Session Attachments (Task #10)
Date: 2026-11-14 | Status: User-approved scope revision; tests and preview pending after revision.

## User-approved scope
On Web → Appointments → Review Appointment → Mark session as completed:
- **Retain** the preexisting required **Session summary (internal)** and Follow-up controls.
- **Add only file attachments**: images and documents (PNG, JPG, PDF, DOC, DOCX; up to 5 files, 5 MiB each).
- **Remove** the three proposed new text areas: Interview questions asked, Student requirements checked, and Materials used.
- In completed appointment details, display the private session summary and authenticated downloadable attachment list; do not show the three removed text areas.

## Architecture
- Reuse the existing callable-only session completion transaction and the private `appointments/{appointmentId}/clinical_notes/session` document.
- Persist existing `summary` plus new `attachments` (up to five {path, name, contentType, size} manifests) **only in the clinical note**. Do not add to student-facing appointment data or notifications.
- Store bytes in private Firebase Storage at `counseling_session_files/{appointmentId}/{uploaderUid}/{randomNonce}.{jpg|jpeg|png|pdf|doc|docx}`; original filenames are metadata only, not path components.
- UI selects supported files, checks size/type, uploads before the session-completion callable, and passes verified object references. The callable validates the manifest and checks actual Storage metadata before committing; existing completion/appointment revision guards remain.
- Existing counseling/booking/follow-up behavior must remain intact. Rejected old text-field payloads prevent stale API usage.

## Security and operational constraints
- Authenticated, email-verified, appropriately approved clinical users can read private files; general staff/students cannot. Creation is restricted to the uploader while the appointment is confirmed. No public download URLs.
- Objects are immutable after completed session (writes/updates denied). Existing profile-image Storage rules unchanged.
- A failed or ambiguous completion request can leave uploaded draft objects; safe cleanup and retry behavior require review before live deployment. Avoid deleting evidence after an ambiguous success.
- Firebase Functions and Storage rules must be validated against emulators and then deployed to **staging** for staging end-to-end upload tests; do not deploy to production without explicit approval.
- All tests use mock or synthetic counseling data only.

## Acceptance checklist
1. In Review Appointment → Mark session as completed, Session summary still appears and only a Session attachments picker is added.
2. No Interview questions asked, Student requirements checked, or Materials used text inputs, persistence, or saved-detail fields.
3. Allowed file types/size/count enforced; file list and removal controls functional.
4. On completion, metadata stored only inside private clinical notes; access denied to student/general Staff.
5. Completed appointments can read and download private attachments via authenticated SDK.
6. Flutter/widget tests, Dart analyze, Functions tests, Storage rules emulator tests, and web preview pass; create a PR only after review and approval.

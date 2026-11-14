# Task #10 — Counselor interview documentation implementation plan
Date: 2026-11-14 | Base: `f07eb59`

1. Baseline & tests: read session review code, clinical note rules, storage rules; add tests for validator, file manifest and UI visibility. RED requires local test runner.
2. Backend validation: extend existing completion payload with bounded `interviewQuestions`, `requirementsChecked`, `materialsUsed`, `attachments`. Server-only manifest verifier confirms Storage object existence/type/size/ownership before Firestore transaction.
3. Security rules: private `counseling_session_files/{appointmentId}/{staffId}/{fileName}` with verified counselor/admin access, strict path/type/size, immutable objects; test emulator denies student/staff.
4. Client repository: upload selected document bytes only on confirmed completion, use Storage authenticated getData for downloads, read clinical_notes/session on completed appointments.
5. Flutter UI: add interview documentation fields/file picker to completed action, retain required summary; show private previous note and attachments on completed record.
6. Verification: `flutter pub get`, targeted Flutter test and analyze, Functions npm test and rules emulator, full admin regression, browser staging preview, then PR (not before).
7. Deployment gating: storage.rules / Functions must be deployed to staging for live upload tests; use staging only, no production deploy.

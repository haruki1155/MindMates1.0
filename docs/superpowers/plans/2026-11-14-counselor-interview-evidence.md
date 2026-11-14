# Task #10 — Upload-only counselor session attachments implementation plan
Date: 2026-11-14 | Base commit: `f07eb59` | Scope revised per user screenshot

1. **Simplify UI**: retain existing Session summary and Follow-up controls; replace the three added text fields with Session attachments and Add images / documents. Remove them from the completed-details viewer.
2. **Simplify contracts**: drop unused controllers, repository arguments, Dart model properties, and backend clinical-note text fields. Keep `summary` and bounded `attachments`; reject retired fields in completion payloads.
3. **TDD regression coverage**: assert upload control remains actionable; removed fields absent in both Review Appointment and read-only details; file manifest and private path verification remain tested.
4. **Private upload/security**: preserve existing Storage rules and object metadata verification; verify students/general Staff are denied; test immutability on completed sessions in Firebase Emulator.
5. **Static RepoCheck**: scan files for stale references; review branch status/merge divergence and lockfile/SDK compatibility; ensure no production or other worktree modifications.
6. **Local checks**: run targeted Flutter tests, Dart analyze, Functions TypeScript compile/unit tests, Firestore+Storage emulator tests, and web build/preview on staging-flavored local code. Do not upload real student counseling materials.
7. **PR gate**: after successful tests and user acceptance, create a PR. Staging deployment is separately gated for live upload end-to-end testing; **never deploy production from this branch**.

## Current known risks
- The private Storage rules and callable need to be deployed to a controlled staging environment before a real upload end-to-end test; no deployment has been performed.
- Orphan drafts can remain if upload succeeds but completion fails. Review cleanup only after proving a safe distinction between failed and ambiguously successful commits.
- Existing `functions/package-lock.json` vulnerabilities predate this branch; handle separately with a tested security-remediation PR, not a blind forced upgrade.

## Continued workstream — integrate Counselor Messaging into Inquiries (same branch)
8. Record a failing widget test for two Inquiries sections: Messages (default) and Other services, plus permission and no-standalone-navigation assertions.
9. Reuse `CounselorMessagesPage` in embedded presentation mode; do not change conversations, send controller, Firestore collections or read receipts.
10. Update the portal sidebar: remove the independent Counselor Messages destination; keep the Inquiries link and move the existing Counselor unread badge onto it. Introduce one role policy: counselor only.
11. Wrap the existing submitted-inquiry queue as the Other services section for Counselor. Admin retains the existing inquiry queue; other roles receive no broadened permissions.
12. RepoCheck the branch diff and stale navigation references, run targeted Flutter tests and analysis, test mobile messaging regression, Functions and Storage security regressions, then stage-flavored web preview. Update only the same branch; do not create another branch or PR until user accepts.

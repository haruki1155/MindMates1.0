# Optional Transcript / Remarks in My Cases — Design

**Date:** 2026-11-16 · **Requirement:** evaluator #10 (PR 8)

> [!IMPORTANT]
> **Stacked PR.** Base is `feat/pr7-student-case-history` (0f71035, PR 7 / requirement #9, pushed, not merged), not `main`. PR 8 reuses PR 7's case-history page and its entitlement rule (`decideCaseHistoryAccess`). Merge PR 7 first, then rebase this branch onto the updated `origin/main` and re-run the tests.

## Findings
- `appointments/{id}/clinical_notes/session` is written once, by `reviewAppointment` at completion, with `transaction.set` (a full overwrite). Rules let **every** active counselor or admin read `clinical_notes/*` directly (`hasClinicalAccess`).
- Storing remarks there would (a) be readable by counselors and admins with no entitlement for the student, and (b) be wiped by the completion `set` if remarks were saved before completion. So remarks get their own document.
- `firestore.rules` has no `{document=**}` wildcard, so any subcollection without a `match` is denied to every client by default.
- `recordAuditEvent` lets any staff account write any action in `AUDIT_ACTIONS`. Server-only events must therefore stay out of that list.

## Decisions (confirmed with the user)
1. **Storage:** server-only `appointments/{id}/case_remarks/current`, with immutable versions at `appointments/{id}/case_remarks/current/versions/{revision}`. No rules change; default deny covers both paths, and a rules emulator test proves it.
2. **Access:** only a counselor with a `college` or `assigned` basis (the PR 7 rule) may read or write. The super-administrator, other admins, portal staff and students are refused. The super-administrator still sees the PR 7 history, without remarks.

## Data contract
`case_remarks/current`: `appointmentId, studentId, text, revision, authorId, authorNameSnapshot, authorRoleSnapshot, createdAt, updatedAt`.
`versions/{revision}`: `revision, text, authorId, authorNameSnapshot, authorRoleSnapshot, createdAt` (never updated).

- Text is optional. Omitted, `null` and blank all mean "no remarks" when no remarks exist yet. Once non-empty remarks exist, omitting `text` (or passing `null`) is rejected (`invalid-argument`) so a missing field can never silently delete saved remarks. Explicit clearing (`""`) requires confirmation in the UI and records a new version while preserving all prior versions in `versions/{revision}`. CRLF becomes LF, the ends are trimmed, the limit is 10,000 characters, and control characters other than newline/tab are rejected.
- **Optimistic concurrency:** `expectedRevision` must equal the current revision (0 when none exists), or the call fails with `aborted` and nothing is written. Saving identical text is a no-op (no new revision, no audit).
- **Audit:** `CASE_REMARKS_VIEWED` on every successful read; `CASE_REMARKS_UPDATED` in the same transaction as each write. Metadata is `appointmentId, studentId, basis, revision, length, cleared`. The note text is never audited. Both are actor-scoped and not client-recordable.

## Callables (`functions/src/case_remarks_callable.ts`)
| Callable | Input | Output |
|---|---|---|
| `getCaseRemarks` | `appointmentId` | `{appointmentId, text, revision, updatedAt, authorName, versions[≤20, newest first]}` |
| `saveCaseRemarks` | `appointmentId, text?, expectedRevision` | same shape after save |

The order is: `requireClinical` → load appointment → `userId` → profile and assigned-case query → `decideCaseRemarksAccess`. A missing appointment and an out-of-scope appointment both return `permission-denied`, so the callable can't be used to discover records. Inside the save transaction, the appointment's `userId` is re-checked.

## Web
`CaseRemarksEditor` (`lib/features/admin/widgets/case_remarks_editor.dart`): a labeled multi-line field **Transcript / Remarks (optional)**, Save, a "Last saved by … · revision n" line, and previous versions.
- **Conflict:** the draft is kept, with a Reload option.
- **Save error:** the draft is kept, with a truthful error message.
- **Refused:** a "not authorized" message.

On the case-history page, each case card has a "Transcript / Remarks" toggle for counselors only. Remarks load only when the toggle is opened, so nothing is read or audited until a counselor asks. The editor never caches across instances, so switching accounts cannot show a previous user's text.

## Not changed / non-goals
- Session evidence upload and `clinical_notes/session` are unchanged.
- No automatic transcription.
- Nothing is added to `appointment_queue`, reports or the PR 7 history projection.
- Firestore rules are unchanged.
- Populating `assignedStaffId` is out of scope.

## Deploy
Deploy `getCaseRemarks` and `saveCaseRemarks` by name together with the web app. There is no migration and no index (the `versions` query on `revision` uses the automatic single-field index). Rollback: redeploy the previous web app; remark documents are inert without the callables.

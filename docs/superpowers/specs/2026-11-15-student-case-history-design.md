# Student Case History — Design

**Date:** 2026-11-15 · **Requirement:** evaluator #9 (PR 7) · **Base:** `origin/main` 0560e13 (PR #3 merged; PRs #48, #50, #51, #52 not needed and not included)

## Findings
- **My Cases** (`counselor_workflow_page.dart`) streams `watchMyAssignedAppointments()` (`appointments` where `assignedStaffId == uid`). Nothing has written `assignedStaffId` since 2dfa8e4, so the list is empty in practice; each card shows only the latest appointment per student.
- There is no per-student history anywhere. Firestore rules let every counselor/admin read every appointment (`hasClinicalAccess`), so a client-side query could not enforce a narrower entitlement.
- Student identity: `appointments.userId` is the student's Auth UID, set server-side at booking. `fullName` is free text and not unique. The verified college is `users/{uid}.collegeId` with `verificationStatus: "verified"`. Counselor service area is `users/{uid}.assignedCollegeIds` (PR #3).
- `COUNSELING_HISTORY_VIEWED` already exists in `AUDIT_ACTIONS` but nothing writes it. `getStudentPersonalInfo` is the precedent: callable + `requireClinical` + audit row.
- Archived appointments keep their data with `archivedAt` set. Some legacy records may lack `scheduledAt`.

## Goals
1. A student-specific, newest-first history of all of that student's appointments (current and archived), matched by `userId` only.
2. Only authorized staff see it, checked on the server; every first-page view is audited.
3. Paginated, with empty, error and access-denied states, and back navigation; usable at narrow widths.
4. Existing appointment history, clinical notes, rules and My Cases behaviour unchanged.

## Non-goals
Narrowing direct Firestore read rules (PACC policy, same note as PR #6); clinical notes in the history; populating `assignedStaffId`; approvals (PR #6).

## Approaches
| | Approach | Trade-offs |
|---|---|---|
| **A (chosen)** | `getStudentCaseHistory` callable: entitlement + `userId` query + server sort/cursor + audit; returns a non-clinical-note projection | Server-enforced, auditable, no new index or rule change. One callable per page. |
| B | Client query `where userId ==` orderBy `scheduledAt` | Cannot enforce an entitlement narrower than the rules, drops records without `scheduledAt`, needs a composite index, no audit. Rejected. |
| C | Rule change to scope reads by college | Breaks the existing org-wide appointments page; a policy change outside this requirement. Rejected. |

## Entitlement (pure: `functions/src/student_case_history.ts`)
Actor must first pass `requireClinical` (approved, active, email-verified counselor/admin).
| Actor | Allowed when | Basis |
|---|---|---|
| configured super-administrator | always (target must be a non-staff account) | `super_admin` |
| counselor | student `verificationStatus == "verified"` and `collegeId` in actor's `assignedCollegeIds` | `college` |
| counselor | otherwise, any of the student's appointments has `assignedStaffId == actor` | `assigned` |
| any other counselor / admin | — | `permission-denied` |

Unknown or staff target accounts: `permission-denied` for counselors (no account enumeration), `not-found`/`failed-precondition` for the super-administrator.

## Ordering and pagination
Sort key = `scheduledAt`, else `createdAt`, else none. Newest first; records with no timestamp last; ties by document ID. Opaque cursor `"<millis|none>|<id>"`: next page starts strictly after it, so records added during paging never repeat. Page size default 20, max 50. All of a student's appointments are read (cap 500, then `truncated: true`).

## Returned entry (no contact details, no clinical notes, no history subcollection)
`id, status, scheduledAt, scheduledTime, createdAt, completedAt, archived, archivedAt, counselorName (counselorName ?? actionByName), location, concern, followUpStatus, hasSchedule`. Header: student display name, college ID. The concern is the same text counselors see on the appointments page today.

## Web
`StudentCaseHistoryPage` (pushed route, AppBar back): student header, entries grouped by year, status and "Archived" chips, counselor, schedule, concern; "Load more"; empty / error-with-retry / not-authorized states. Entry points: "Case history" on My Cases cards and on appointment cards (counselor/admin only).

## Calls for review
1. Counselor entitlement = verified-college assignment or assigned case; other admins refused (consistent with PRs #3, #4, #6).
2. Concern included; contact details and clinical notes excluded.
3. Only the first page is audited, so paging does not flood the audit log.

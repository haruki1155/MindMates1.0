# College Inquiry Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Checkbox steps.

**Goal:** Server-routed, assignee-scoped inquiries with audited transitions. **Spec:** `docs/superpowers/specs/2026-11-15-college-inquiry-routing-design.md`

## Global Constraints
- No new dependencies or collections; appointment code untouched; `users.collegeId` never written.
- Audit actions: `INQUIRY_ROUTED`, `INQUIRY_ACKNOWLEDGED`, `INQUIRY_REASSIGNED`, `INQUIRY_ESCALATED` (new) + existing `INQUIRY_STATUS_CHANGED`, `INQUIRY_RESOLVED`.
- Notification IDs as in the spec; bodies generic.

## Review Focus
1. Trigger retried after routing committed but before notifications → no duplicate notifications, no re-routing. (Task 2)
2. Assignee suspended after routing → loses read (rules) and callable access. (Tasks 2, 3)
3. Two super-admin reassignments racing → second `failed-precondition`. (Task 2)
4. Staff list query without `array-contains` → denied, not silently empty. (Task 3)
5. Legacy inquiry without routing fields → invisible to staff, visible to super-admin, routable by backfill. (Tasks 2, 3)

### Task 1 — `functions/src/inquiry_routing.ts` (pure) + tests
`decideRouting({student, collegeExists, candidates})`, `isEligibleAssignee(profile, auth)`, `planReassignment(...)`, notification id helpers.

### Task 2 — `functions/src/inquiry_routing_service.ts` + callables + trigger + audit + tests (Auth/Firestore emulators)
`routeInquiry`, `acknowledgeInquiry` (tightened), `setInquiryStatus`, `escalateInquiry`, `reassignInquiry`, `routeExistingInquiries`; `notifyPortalOfInquiry` delegates to the router.

### Task 3 — Rules + rules tests
Assignee-scoped read, `update: false`, list-query shape.

### Task 4 — Flutter model/repository
`AdminInquiryModel` routing fields; `FirestoreService.watchDocuments(whereArrayContains:)` (additive); repository stream by role; callables; scope helper.

### Task 5 — Web UI
Nav for portalStaff; list badge; routing panel with Escalate / Reassign / Route existing.

### Task 6 — Verification + PR readiness

# Inquiry SLA Oversight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans.

**Spec:** `docs/superpowers/specs/2026-11-15-inquiry-sla-oversight-design.md` · **Base:** `feat/pr4-college-inquiry-routing`

## Review Focus
1. Reply retried after commit → same reply, one notification set, one audit row.
2. Assignee replies after takeover → refused; admin reply after an assignee's stale view → revision conflict.
3. Deadline exactly reached → overdue; replied or resolved → never overdue.
4. Target unset → nothing flagged, view says so.
5. Other-college staff cannot read replies.

### Task 1 — Pure validation (`functions/src/inquiry_sla.ts`) + Dart overdue projection (`lib/features/admin/domain/inquiry_sla.dart`) with simulated clock tests
### Task 2 — Callables `setInquirySla`, `replyToInquiry`, `takeOverInquiry`; revision on `setInquirySla`/status; reassign clears takeover; audit; emulator tests
### Task 3 — Rules for replies and `system_config/inquiry_sla`; rules tests
### Task 4 — Flutter model/repository
### Task 5 — Web: target selector, Overdue panel, reply timeline/composer, Take over
### Task 6 — Verification and PR readiness

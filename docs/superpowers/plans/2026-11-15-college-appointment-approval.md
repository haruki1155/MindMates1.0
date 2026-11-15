# College-Scoped Appointment Approval Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans.

**Spec:** `docs/superpowers/specs/2026-11-15-college-appointment-approval-design.md` · **Base:** `origin/main`

## Review Focus
1. Counselor assignment removed between list and action → action refused (authority is re-evaluated per action).
2. Student changes/loses verified college → appointment moves to triage.
3. Two approvers race on one appointment → exactly one transition; slot never double-claimed.
4. Super-admin acting on a college-scoped appointment without a reason → refused, nothing written.
5. Approvals list never returns concern/clinical text.

### Task 0 — Fixture fix for pre-existing Auth failures (done: f40bfd7)
### Task 1 — Pure scope/decision module + unit tests
### Task 2 — Authority service, wiring into review/agreement/initialise, list callable; emulator tests; update suites that asserted "any counselor"
### Task 3 — Flutter repository (`listAppointmentApprovals`, `exceptionReason` pass-through) + approvals panel + dialog field; widget tests
### Task 4 — Verification and PR readiness

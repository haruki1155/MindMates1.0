# PAACC Schedule V2 Design

**Source contract:** `C:\Users\Mj\Downloads\MINDMATE_PAACC_SCHEDULE_EVOLUTION_PLAN.md`

## Objective

Evolve PAACC availability from one global V1 configuration to a server-authoritative V2 weekly schedule with date overrides, while preserving existing appointments and V1 document readability during rollout.

## Non-negotiable rules

- `Asia/Manila` is the sole timezone used for schedule resolution.
- A V2 document has `schemaVersion: 2`, `timezone: "Asia/Manila"`, seven weekday entries keyed `1` through `7`, optional date overrides, a notice, a revision, and audit metadata.
- Each day has `enabled`, `opensAt`, `closesAt`, `presence`, `appointmentsEnabled`, and `acceptsWalkIns`. A disabled day is closed and cannot enable appointments or walk-ins.
- Date overrides supersede the relevant weekly day. They either close the full day or contain a complete V2 day schedule.
- Backend validation is final authority for slot generation, appointment creation, confirmation, staff proposals, and student acceptance of a proposal. Direct Firestore writes remain denied.
- Existing V1 `openDays`, `opensAt`, `closesAt`, `presence`, `acceptsWalkIns`, `notice`, and `blackoutDates` documents normalize into an effective V2 schedule; stored documents are not migrated automatically.
- Changing a schedule must not cancel or mutate existing appointments. A preview lists future requested, confirmed, and proposed appointments that the candidate schedule would invalidate.
- Saves use an expected revision and a transaction. Accepted writes record the acting user, previous revision, new revision, and a bounded change summary.
- Only Admin and Counselor may mutate the schedule. Staff is read-only; unauthenticated and student clients cannot mutate it.

## Architecture

`appointment_availability.ts` owns parsing, V1 normalization, V2 validation, and the canonical effective-schedule resolver. Every backend entry point reads a document snapshot and invokes that resolver in its transaction before accepting a slot or status mutation. The callable that saves availability validates the candidate schedule, previews conflicts, enforces the expected revision, writes the V2 document, and appends an audit event atomically.

Flutter owns a lossless V2 model with V1 read compatibility. Its repository invokes callable operations rather than writing Firestore. The Admin/Counselor editor uses a separate mutable draft, presents seven independent day cards, bulk updates, special-date editing, an effective student preview, conflict warnings, and unsaved-change protection. Read-only consumers show resolver-derived status rather than reconstructing V1 global availability.

## Failure handling

Malformed stored data, unsupported fields, invalid timezone, invalid times, duplicate override dates, closed-day contradictions, stale revisions, and schedule-invalid appointment mutations fail with explicit callable errors. UI retains its draft on save errors and presents a refresh/review path for revision conflicts. A stale proposal is revalidated transactionally at acceptance.

## Verification requirements

Tests cover V2 parsing/serialization, V1 normalization, resolver precedence and timezone boundaries, payload validation, permissions, slot filtering, appointment create/confirm/reschedule rejection, occupied-slot safety, conflict preview, revision conflicts, rules, Flutter model mapping, responsive UI behavior, and accessibility labels. Full appointment lifecycle regression runs after implementation.

## Verified rollout limits

Automated verification establishes the source, callable, rules, and Flutter test contracts only. Deployment, authenticated staging validation, and any intentional V1-to-V2 document migration remain separate follow-up operations. V1 documents must continue to be read through normalization until a separately approved migration is planned and executed; this rollout does not migrate stored schedules or alter existing appointments.

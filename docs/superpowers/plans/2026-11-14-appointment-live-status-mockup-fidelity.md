# Appointment live status and mockup fidelity implementation plan

> Execute inline with Superpowers TDD, progressive validation, and an independent final review. Preserve the existing dirty checkout and leave all changes uncommitted.

Goal: Align the student appointment experience with the user's November14 twelve-screen gallery, with priority on live Upcoming status, the summary/activity details page and correct alignment. The supplied gallery is the approved visual direction; this continues the November13 plan.

Constraints: Existing Provider stream/repository/callable contracts and authorization remain authoritative. No backend, schema, Rules, dependency or hosted changes. Retain the latest native contact/appointment pickers (not illustrative slot chips), all required fields, saved personal draft, request identity, conflict/revision protections, unchanged-schedule approval, and exact Review request / Send appointment request / Request received wording. Never add simulation controls or fabricated history. Reuse global navigation; no app-wide redesign.

- [x] RED: widget tests for amber/green live status badges, aligned upcoming card, live details stream updates, actual activity, narrow/large-text layouts and current permissions.
- [x] GREEN: feature presentation tokens/status badge; overview hero, segmented tabs and aligned summary/actions. Full-height details presentation with labeled date/time/location/counselor, truthful activity, existing private information and pinned eligible edit action. Use provider state without extra server queries.
- [x] RED/GREEN: align edit/current/review/result presentation with gallery while preserving existing date/availability calls and conflict recovery; review sends only once. Do not add unsupported status operations.
- [x] Align existing intake/review/success/calendar/notification presentation with shared palette, consistent padding, readable sections and button alignment; preserve selected values and profile autofill.
- [x] Run complete focused106-test baseline plus new tests, targeted analysis and git diff --check. Independently review relevant diff; fix findings and rerun affected checks.
- [ ] Capture rendered representative screens, inspect actual layout at phone width and large text; build/install authorized staging preview and record results/limitations in existing ledger. Do not claim100% pixel equivalence without comprehensive rendered comparison.

Checkpoint November14:115 focused tests pass(exit0), targeted analysis0 and diff check0. Representative widget renders inspected for overview/details/edit/review/result/personal information. Independent review P2 stale follow-up callback and misleading schedule-update timestamp fixed and re-reviewed. Physical-device acceptance and comprehensive twelve-screen visual comparison remain pending; no100percent equivalence claimed.

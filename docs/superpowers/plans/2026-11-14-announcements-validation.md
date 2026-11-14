# Announcement implementation validation

Branch: `feat/pacc-announcements`, isolated workspace `.worktrees/announcements`.
Base: `453b3ff96cade389e9fd6243b196a01cf8b927dd`.

## Implemented

Staff/admin publishing, drafts, explicit published edits, archiving, revision conflict protection, atomic audits, role-protected callables and Rules, bounded public link previews, shared Flutter repository, mobile card feed and full-screen vertical viewer, external source actions, and a distinct Home announcement entry. Office availability remains separately available.

## Verified evidence

- `npm.cmd run build` in functions: passed on local Node v24.18.0. Deployment manifest still targets Node 22; exact Node22 acceptance is unverified.
- `node --test lib/announcements.test.js lib/announcement_link_preview.test.js lib/announcement_indexes.test.js`: 10 passed. Covers policy, validation, revisions/transitions, metadata, address restrictions, pinned real local transport, body limits/abort, rate limits and index JSON structure.
- Local `demo-announcements` Firestore v1.22.0 plus Auth emulator, `node --test --test-concurrency=1 functions/lib/announcements_rules.test.js functions/lib/announcements_callable.test.js`: 3 passed after resume. Covers persisted transaction/audit, real HTTP onCall wrapper with synthetic local Auth users, and Rules get/query/write boundaries. This is not a deployed Functions or hosted Firebase acceptance claim.
- `flutter test test/features/announcements test/features/home/pacc_schedule_status_test.dart test/repositories/pacc_availability_repository_test.dart`: 23 passed after final fixes.
- Scoped analysis of announcements, admin_portal.dart, home_screen.dart and home_dashboard_widgets.dart: no issues before final fixes; final run recorded in progress ledger.
- Wider Home regression: 16 passed, one pre-existing failure: `home uses the authenticated Teaching profile instead of a stale Student assessment selection`, expected `Teaching Work Well-Being Reflection`, actual `Teaching Assessment`. Same failure reproduced in original checkout, which has no announcement code. Left unrelated code/test unchanged.
- Actual Flutter screen render test passed for feed, viewer and editor; widget-test Ahem font prevents typography acceptance. No physical-device/browser acceptance is claimed.
- Independent whole-change review completed. Three Important findings addressed with regressions: malformed index JSON; long-post viewer navigation; refresh retry mode. Each regression was observed failing, then passing. No critical findings. Reviewer initially interrupted by usage limit, then resumed and supplied consolidated verdict.
- `git diff --check`: clean apart from Git line-ending notices.

## Deferred minor

The editor's destination hostname may remain stale until a parent rebuild after editing the source URL. The submitted source URL and backend validation use current controller text. Reviewer classified this display-only issue Minor; deferred under the requested execution workflow.

## Rulings made

1. Native PowerShell ledger/verification replaces Bash workspace/task helpers after the helper repeatedly failed on sandboxed `/c` paths. Cost: manual bookkeeping instead of automatic task records.
2. Transaction persistence alone is not HTTP evidence; authored and ran a real local onCall HTTP wrapper test with Auth emulator. Cost: small Express development-only harness and local integration runtime. No transport claim is based on `.run()`.
3. Flutter dependency resolution adjusted four SDK-constrained test packages in the isolated lock. Cost: isolated dependency-lock changes; original dirty lock preserved.
4. A small feature-local ChangeNotifier controller shares feed/viewer ordering, refresh, and pagination. Cost: one additional file; no new state framework.
5. Integration wrappers moved into `announcements_callable.ts` to test real exported onCall handlers without loading unrelated global function exports. Cost: one small backend module, unchanged callable names.
6. Keep the pre-existing assessment-title test failure outside announcement scope. Cost: wider Home suite is not wholly green and integration readiness must retain that limitation.

## Boundaries and status

No push, merge, deployment, hosted Firebase read/write, migration, APK build/install or production change occurred. No real external website was fetched by preview tests. Original checkout changes were preserved. Feature implementation and focused local validation are complete; device/browser behavior, Node22 runtime, deployed indexes/Rules/callables, and full-app acceptance remain unverified. Branch/worktree retained for user review and separate integration authorization.

# Announcement UI Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. User selected inline execution; no per-task agents.

**Goal:** Polish mobile announcement reading and web publishing using each platform's established palette, and verify staff/admin workspace navigation excludes counselor-only accounts.

**Architecture:** Keep existing announcement screens, repository, controller, backend contracts and role boundaries. Apply scoped presentation changes using HomePalette and AdminColors/AdminTheme, Flutter built-in transitions, and existing navigation. No global theme redesign.

**Tech Stack:** Existing Flutter/Material widgets, Firebase repositories unchanged, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-14-announcements-ui-refresh-design.md`, approved through the user's instruction to proceed.

## Global Constraints

- Work in the existing `.worktrees/announcements` checkout on `feat/pacc-announcements`; preserve all pre-existing changes, local test services and synthetic test posts.
- No new dependencies, state framework, backend/schema/permission changes or unrelated formatting.
- No commits, pushes, merges, deployments or new APK installs in this UI pass. Leave changes reviewable locally.
- Staff/admin can manage posts; counselor-only accounts cannot. Preserve existing counseling navigation.
- Keep current source-link vs full-screen actions, explicit publishing, conflict handling, refresh/pagination, and readable uncropped poster images.
- Use 150–220 ms transitions and zero-duration transitions when MediaQuery.disableAnimations is true. Avoid looping decoration and motion that delays input.
- Support 320px widths, enlarged text, keyboard focus, screen-reader labels and minimum 48 logical-pixel action targets.

## Review Focus

- Long image-free posts at enlarged text must retain reachable source and viewer navigation controls (Task 1).
- A failed image must not collapse its surrounding content or prevent opening its source (Task 1).
- Switching category or refreshing during an animation must retain current request-generation protections (Task 1).
- Editing a source URL while preview retrieval is pending must show the current hostname and reject stale preview results (Task 2).
- Collapsed and compact portal navigation must expose Announcements for staff/admin without exposing it to counselors (Task 3).

### Task 1: Mobile presentation and feedback

**Files:** Modify `lib/features/announcements/screens/announcements_screen.dart`, `lib/features/announcements/screens/announcement_viewer_screen.dart`, `lib/features/announcements/widgets/announcement_card.dart`; extend `test/features/announcements/announcements_screen_test.dart`. Create `lib/features/announcements/widgets/announcement_presentation.dart` only if theme and motion behavior are shared by more than one widget.

**Interfaces:** Preserve AnnouncementsScreen, AnnouncementViewerScreen and AnnouncementCard constructor contracts and AnnouncementFeedController behavior. If shared presentation is needed, expose `ThemeData announcementMobileTheme(ThemeData base)` and `Duration announcementTransitionDuration(BuildContext context)`; base tokens come from HomePalette, duration is 180 ms or zero with reduced motion. Scope the mobile theme to the announcement routes only.

- [ ] Add widget regressions asserting usable source/viewer actions with long content, 320px/large text, failed image fallback, selected category semantics and reduced-motion completion. Preserve existing external-source, refresh retry and long-post navigation tests.
- [ ] Run `flutter test test/features/announcements/announcements_screen_test.dart`; expected RED for newly required presentation/feedback behavior before implementing it. Fix test setup issues separately.
- [ ] Apply warm cream canvas, light cards, gold emphasis, dark headings, consistent spacing/borders and restrained shadows. Keep compact header, wrapping filters, clear attribution/date/category, image, excerpt and hostname hierarchy. Use semantic loading/error/empty feedback and built-in animated state/selection transitions. Do not animate entire lists in a way that resets scroll or keys.
- [ ] Keep viewer paging controls visible outside long post scroll content; keep actions accessible by keyboard and touch. Preserve feed position and query state.
- [ ] Run the same test command; expected PASS. Run `flutter analyze lib/features/announcements`; expected no new diagnostics. Record evidence in this plan's progress ledger; do not commit.

### Task 2: Web publisher layout and interaction states

**Files:** Modify `lib/features/announcements/screens/manage_announcements_page.dart` and `lib/features/announcements/widgets/announcement_editor.dart`; extend `test/features/announcements/manage_announcements_test.dart`. Reuse Task 1 motion helper if created; do not apply mobile colors to admin widgets.

**Interfaces:** Keep ManageAnnouncementsPage/AnnouncementEditor repository injection and navigation results unchanged. Keep saveDraft/publish/archive payloads and revision values unchanged. Source hostname derives reactively from the existing source controller, not from the last preview result.

- [ ] Add tests for immediate source-hostname updates without fetching a preview, pending-preview URL changes, explicit publish/busy indicators with a delayed callable, and narrow/large-text action reachability. Assert no write before an explicit publish/save action and form contents retained after errors.
- [ ] Run `flutter test test/features/announcements/manage_announcements_test.dart`; expected RED for missing immediate destination/feedback behavior.
- [ ] Apply existing admin neutral surface and pale-yellow active state styling. Group list header/action, filters, post status/category metadata and edit/archive actions. Use a responsive readable editor with sections for type/category, source/preview, content/image and final actions. Keep archive confirmation and existing failure behavior; no extra workflow gates.
- [ ] Use short built-in transitions for preview/result states and status filters, respecting reduced motion. Rebuild destination display on source changes and preserve stale-response protection. Do not replace manual text with remote preview text without the existing empty-field checks.
- [ ] Run the same tests and `flutter analyze lib/features/announcements`; expected PASS/no issues. Record evidence; do not commit.

### Task 3: Workspace navigation, integrated checks and local preview

**Files:** Modify `lib/features/admin/screens/admin_portal.dart` only where necessary for announcement destination placement/accessibility; add `test/features/admin/announcement_navigation_test.dart` using existing portal test injection patterns discovered by a narrow symbol search. Add `docs/superpowers/plans/2026-11-14-announcements-ui-refresh-validation.md`.

**Interfaces:** Preserve AdminPortalPage.announcements, its content guard, and existing backend authorization. Retain Publishing grouping unless actual surrounding navigation requires a minimal placement adjustment. Do not expose a test-only navigation API or change unrelated page roles.

- [ ] Test actual staff/admin workspace rendering in expanded and compact/collapsed forms: announcement destination is reachable, selecting it opens the publisher, counselor-only workspace lacks it, and unrelated counseling destinations remain intact. If current behavior already passes, retain it and record validation rather than changing working navigation.
- [ ] Run `flutter test test/features/admin/announcement_navigation_test.dart`; expected PASS for preserved working behavior, or RED followed by minimal required navigation fix and PASS.
- [ ] Run `flutter test test/features/announcements test/features/admin/announcement_navigation_test.dart test/features/home/pacc_schedule_status_test.dart test/repositories/pacc_availability_repository_test.dart`; expected all executed checks PASS. Run affected existing portal tests found by targeted search. Do not silently fix the previously documented unrelated Home assessment-title mismatch.
- [ ] Run scoped analysis on announcements and touched portal/Home integration files plus `git diff --check`; expected no new diagnostics/whitespace errors. No backend build is needed for presentation-only changes.
- [ ] Restart/hot-restart the existing local web preview against demo-announcements emulators, preserving synthetic posts. Inspect staff publishing and reader feed at desktop and mobile widths, including new/edit form, empty/error/loading feedback, filters and full-screen controls. Do not claim signed-in production portal or physical-phone acceptance from this isolated harness.
- [ ] Request one fresh-context whole-change review against this spec/plan, UI diff and ledger. Fix Critical/Important findings in one pass with regressions observed RED then GREEN; record deferred minors. Retain working tree and local preview for user review; no commit or publication.

## Execution bookkeeping

Use `.superpowers/sdd/2026-11-14-announcements-ui-refresh/progress.md` for task evidence and rulings; do not overwrite the original announcement implementation ledger. Use native PowerShell bookkeeping if the previously failing Bash helpers cannot operate correctly. Preserve the workspace at handoff because this scope explicitly leaves changes uncommitted for local review.

## Plan self-review

Coverage: mobile feed/viewer, publisher/editor, role-specific navigation, motion/accessibility and local visual verification are assigned above. Repository, backend, data and permission semantics remain unchanged. Shared motion/theme helpers, if necessary, are consumed only by presentation widgets; no cross-task data interface changes exist. Existing navigation will be validated before being changed. No implementation has begun.

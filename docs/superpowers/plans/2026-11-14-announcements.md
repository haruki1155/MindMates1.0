# PACC Announcements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking. User selected inline execution.

**Goal:** Staff/admin announcement publishing with editable link previews, a mobile card feed and vertical full-screen viewer, and links to original posts.

**Architecture:** Add an announcements feature to the existing Flutter/Firebase application. Use trusted callables for mutations and metadata, Firestore for paginated reads, and the existing portal authorization/audit patterns. Share one repository and model between publisher and mobile views.

**Tech Stack:** Flutter/Dart, Firebase Functions TypeScript on Node 22, Firestore. Add url_launcher for supported external navigation and a maintained HTML parser for metadata only if not already available; use Node HTTPS/HTTP and DNS primitives for bounded, pinned-address retrieval.

**Spec:** `docs/superpowers/specs/2026-11-14-announcements-design.md`

## Global Constraints

- Only eligible portalStaff/admin accounts manage posts and request previews; counselor-only access is excluded.
- Mobile audience is all existing eligible signed-in app users; unpublished data stays private.
- No direct client writes; no hard deletion; no production actions, deployment, push, migration, APK build/install, or notifications.
- Preserve unrelated dirty files, especially the pre-existing pubspec.lock change. Make additive, scoped edits only.
- Published edits require Publish changes; no background autosave to the live record. First publishedAt remains stable on edits.
- Reuse existing component themes, callable router, Firestore infrastructure, and audit schema; no new state framework.
- Do not implement on main/master. Current checkout is feat/appointment-two-way-agreement, with unrelated changes and a remote tracking gap. Do not synchronize it as part of this feature.
- Commit only task-owned files when allowed; never stage unrelated changes. Preserve scratch ledger until completion evidence is safely retained.

## Review Focus

- DNS rebinding and multi-hop redirects: every actual connection must target the validated public address, including IPv6 and mapped forms (Task 2).
- User leaves editor while metadata is pending or changes the URL: old results must not overwrite the new form (Task 4).
- Archive/edit occurs while a viewer is open: it must not retain an archived post as actionable current content after refresh, or leak drafts (Task 5).
- Equal publication times and filter changes: cursor pagination must avoid duplicates and stale responses (Task 3).
- Small screens and large text: actions and long titles must remain reachable without clipping (Tasks 4/5).

### Task 1: Trusted announcement contract, storage, and permissions

**Files:** Create `functions/src/announcements.ts`, `functions/src/announcements.test.ts`, `functions/src/announcements_callable.test.ts`, `functions/src/announcements_rules.test.ts`; modify `functions/src/index.ts`, `functions/src/audit.ts` if its category/action contract requires it, `firestore.rules`, `firestore.indexes.json`.

**Interfaces:** Produce `validateAnnouncementPayload(value): AnnouncementInput`, `canManageAnnouncements(actor): boolean`, and trusted transaction handler `saveAnnouncement(db, actorUid, input)`. Export callable `saveAnnouncement` from index through the existing auth/eligibility guard plus a specific portalStaff/admin check. Callable payload: `{id?: string, expectedRevision: number, action: 'saveDraft'|'publish'|'archive', post?: {kind, category, title, body, imageUrl?, sourceUrl?}}`; return `{id: string, revision: number}`. Creation revision is 0; stored revision starts at 1. Read model uses kind original/link, category careerGuidance/placements, status draft/published/archived, authorId and server timestamps. Archived records are terminal for this scope.

- [ ] Write failing Node tests: portalStaff/admin allowed, counselor/appUser/rejected/inactive/unverified denied; new draft invisible to public; publish sets timestamp; edit preserves timestamp; stale revision rejected; archive hides without deleting; audit and mutation commit atomically. Limits: title 160, body 10000, URLs 2048, required nonempty title/body, linked source required, original source absent; no unsafe schemes/credentials/unknown enum values. Reject draft-save against published and invalid transitions.
- [ ] Run `npm.cmd --prefix functions run build`, then `node --test functions/lib/announcements.test.js`. Expected: RED from missing implementation, then GREEN after implementation.
- [ ] Implement pure validation/policy and transaction handler. Read actor eligibility in the transaction for mutations, using existing guard semantics; never trust payload author/status/timestamps. Audit stores identifiers/status changes, not pasted body or URL.
- [ ] Add callable wrapper using existing verified-identity conventions. Add Firestore rules allowing eligible staff/admin list/get of all statuses, eligible app readers only published status, no client writes. Match current account eligibility semantics without weakening other collections. Add query indexes for status/category and publishedAt/id plus admin updatedAt/id ordering.
- [ ] Add emulator tests for raw callable persistence and Rules get/query/write boundaries, including unauthenticated and counselor draft denial. Use explicit local emulator env; never default to hosted resources. Run the named Node tests against already authorized local tooling; otherwise record emulator tests BLOCKED, not passed. Pure tests/build must pass.
- [ ] Review scoped diff and commit task-owned files: `feat: add trusted announcement publishing and permissions`.

### Task 2: Safe editable link previews

**Files:** Create `functions/src/announcement_link_preview.ts`, `functions/src/announcement_link_preview.test.ts`; modify `functions/src/index.ts`, `functions/package.json` and its lock only if a parser dependency is necessary.

**Interfaces:** Produce `getAnnouncementLinkPreview(url: string): Promise<{sourceUrl: string, title: string, description: string, imageUrl?: string, available: boolean}>`; export callable `previewAnnouncementLink` accepting `{url}` and returning that shape. Staff/admin authorization is identical to Task 1. Link preview never creates a post.

- [ ] Write failing tests with injected resolver/transport for localhost, private/reserved IPv4/IPv6, mapped IPs, credentials, unsupported scheme/port, redirects to private hosts, loop/too many redirects, rebinding, oversized/slow response, non-HTML, script content, metadata escaping and relative image URLs. Assert network connections use validated pinned addresses with original hostname TLS verification; blocked destinations are never connected to. Do not contact real websites in tests.
- [ ] Run build and `node --test functions/lib/announcement_link_preview.test.js`. Expected: RED before implementation.
- [ ] Implement max 3 redirects, 8-second total deadline, 512 KiB response limit, public HTTP(S) standard ports only, no cookies/auth, TLS verification and address pinning. Revalidate every redirect and image URL syntax; no remote image fetch is required. Parse Open Graph then standard title/description, normalize plain text, clamp to Task 1 limits. Unsafe input is rejected; unavailable/blocked-site metadata becomes available:false with manual-form fallback, without leaking remote content or internal addresses in errors. Bound callable concurrency/instances and per-user preview usage using a small transactional rate-limit record denied to clients.
- [ ] Test timeout/size abort, redirect response-body cleanup, and rate-limit rejection. Run build and the preview tests. Expected: GREEN.
- [ ] Review and commit only task-owned files: `feat: add safe announcement link previews`.

### Task 3: Shared Flutter model, repository, and source navigation

**Files:** Create `lib/features/announcements/models/announcement.dart`, `lib/features/announcements/data/announcement_repository.dart`, `lib/features/announcements/services/announcement_link_launcher.dart`, `test/features/announcements/announcement_repository_test.dart`; modify `lib/database/firestore_collections.dart`, `pubspec.yaml`, dependency lock/platform registration only as required.

**Interfaces:** `Announcement` mirrors Task 1 with safe parsing and nullable source/image. Repository: `Future<AnnouncementPage> loadPublished({AnnouncementCategory? category, AnnouncementCursor? after})`, `loadManaged({AnnouncementStatus? status, AnnouncementCursor? after})`, `save({String? id, required int expectedRevision, required AnnouncementAction action, AnnouncementInput? post})`, `previewLink(String url)`. Page contains items and next cursor. Query page size 20, newest-first publishedAt then document ID; admin updatedAt then ID. Inject data/callable adapters for focused tests; production adapter uses existing router/service. Launcher: `Future<bool> openAnnouncementSource(Uri url)` using external application mode; inject into UI.

- [ ] Write failing tests for malformed/missing optional metadata, timestamp mapping, exact callable payloads, pagination equal timestamps, empty/end cursor, and category/status query boundaries. Assert queries always constrain published status for mobile.
- [ ] Run `flutter test test/features/announcements/announcement_repository_test.dart`. Expected: RED.
- [ ] Implement model/repository/launcher; add url_launcher with dependency resolution preserving unrelated lock changes. Check current official package documentation before API selection. Do not implement external navigation with arbitrary WebView HTML or platform-specific ad hoc browser code.
- [ ] Run focused tests and Dart analysis on changed feature files. Expected: GREEN, no new diagnostics.
- [ ] Commit task-owned changes only: `feat: add announcement repository and external navigation`.

### Task 4: Staff/admin publisher

**Files:** Create `lib/features/announcements/screens/manage_announcements_page.dart`, `lib/features/announcements/widgets/announcement_editor.dart`, `test/features/announcements/manage_announcements_test.dart`; modify `lib/features/admin/screens/admin_portal.dart` only for imports/page enum/label/icon/content/access/navigation entries.

**Interfaces:** `ManageAnnouncementsPage({AnnouncementRepository? repository})`; editor takes an optional existing Announcement and repository, returns a saved result for list refresh. Consume Task 3 repository. UI must use existing AdminTheme and portal page conventions.

- [ ] Write failing widget tests for new original/link form, editable preview population, missing-preview fallback, publish payload, draft save, published Publish changes, cancellation without writes, revision conflict, archive confirmation, role-based navigation, URL edits while preview pending, disposed editor, and 320px/large-text reachability.
- [ ] Run `flutter test test/features/announcements/manage_announcements_test.dart`. Expected: RED.
- [ ] Implement status-filtered paginated list and editor. Show explicit Load preview action after pasting; preserve user text on retries unless they accept replacing it. Disable duplicate submissions; retain entered data on errors; display image failure placeholder and source hostname. Publishing happens only through explicit action. Expose page only to staff/admin; backend remains authoritative.
- [ ] Run widget tests plus existing relevant portal navigation tests selected by symbol search, and scoped analyze. Expected: GREEN.
- [ ] Commit task-owned files: `feat: add staff and admin announcement publisher`.

### Task 5: Mobile feed, full-screen viewer, and home entry

**Files:** Create `lib/features/announcements/screens/announcements_screen.dart`, `lib/features/announcements/screens/announcement_viewer_screen.dart`, `lib/features/announcements/widgets/announcement_card.dart`, `test/features/announcements/announcements_screen_test.dart`; modify `lib/features/home/screens/home_screen.dart`, `lib/features/home/widgets/home_dashboard_widgets.dart` minimally. Add route constants/generator only if current navigation needs named routes.

**Interfaces:** `AnnouncementsScreen({AnnouncementRepository? repository, AnnouncementSourceLauncher? launcher})`; viewer receives current ordered items, selected index, repository/page continuation, and launcher. Shared card takes Announcement, onOpenSource/onOpenViewer. Linked content opens source; separate clearly labeled full-screen control opens viewer. Original content opens viewer. Source launcher failures show a retryable message.

- [ ] Write failing widget tests for loading/empty/error/retry, category switching with in-flight requests, pagination/retry without duplicates, linked-card redirect, distinct full-screen control, original post content, vertical swipe/source action, return position, archive removal on refresh, image error, large font/long title, and retained PACC availability detail behavior.
- [ ] Run `flutter test test/features/announcements/announcements_screen_test.dart`. Expected: RED.
- [ ] Implement feed using built-in list/navigation and a vertical PageView with scrollable text inside each page. Guard stale requests and mounted state. Keep loaded feed position; reload fresh data on explicit refresh and when returning from an external source. Viewer can load subsequent pages; reconcile refreshed status without treating missing drafts as public records. Avoid personalization, social actions, or autoplay.
- [ ] Add a dedicated home announcement entry that opens the feed. Label the existing availability section PACC Office Status and keep its schedule/detail behavior separate from announcements. Do not redirect office-status taps to career posts.
- [ ] Run widget tests, affected home tests selected by symbol search, and feature-scoped analyze. Expected: GREEN.
- [ ] Commit task-owned files: `feat: add mobile announcement feed and swipe viewer`.

### Task 6: Integration verification and whole-change review

**Files:** Update this plan's progress checkboxes and add `docs/superpowers/plans/2026-11-14-announcements-validation.md` with exact commands/results and any blocked acceptance.

**Interfaces:** Verify callables/export names, field enums, cursor/index order, authorization, portal navigation, and mobile launch behavior agree across Tasks 1–5.

- [ ] Run all `test/features/announcements` tests, affected home/portal tests, scoped Dart analysis, Functions build, pure announcement/preview tests, and local Rules/callable tests where authorized infrastructure exists. Expected: all executed checks GREEN; infrastructure gaps explicitly BLOCKED with no hosted fallback.
- [ ] Verify source actions on supported Android/web targets if a runnable local target exists; otherwise mark device/browser acceptance unverified. No build/install/deploy is implied.
- [ ] Review the whole diff with a fresh reviewer as required by executing-plans, including the five Review Focus cases, plan/spec, and ledger rulings. Fix material findings with RED-to-GREEN tests; record deferred minors.
- [ ] Confirm unrelated dirty changes were preserved, no secrets entered the diff, and no production resources changed. Report implementation, actual validation, and remaining acceptance gaps concisely. Stop when scope is satisfied.

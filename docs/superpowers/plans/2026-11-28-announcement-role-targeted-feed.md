# Role-targeted Announcement Feed and News-style Publishing

Status: Proposed implementation plan. This is a plan-only change; no application code, data, or hosted resources have been changed.

## Goal

Extend the existing Announcements feature so Portal Staff and Admins can publish `Announcement` or `Information` posts targeted to selected `Student`, `Teaching`, and `Non-Teaching` audiences. Each app user can read only published posts addressed to their own population role, enforced server-side in Firestore Security Rules. Present those posts in a chronological, news-feed-style layout with safe debounced link metadata previews and optional linked video posts.

Use familiar feed-card hierarchy as a visual reference while preserving the existing Firestore collection, Cloud Function callables, SSRF-hardened preview backend, audit logging, and navigation architecture.

## Confirmed decisions

- **Audiences:** `Student` (`student`), `Teaching` (`teaching`), and `Non-Teaching` (`nonTeaching`). Publishers can target one, two, or all three roles. Default new posts to all three roles to preserve current all-user reach unless narrowed.
- **Post types:** `Announcement` (`announcement`) or `Information` (`information`). Video is a media option (`mediaType`), not a third post type.
- **Link preview:** Reuse the existing safe, editable `previewAnnouncementLink` callable. When a valid HTTP(S) URL is pasted or entered, fetch available title, description, and image metadata automatically after a short debounce. Keep manual retry and manual-entry fallback. Never publish automatically or overwrite publisher-edited fields.
- **Video posts:** External HTTP(S) video URL only. Render an available thumbnail (or styled video placeholder when absent/failed) with a play treatment and a clear `Watch Video` action opening the source via the existing external-link launcher. No video upload, in-app playback, autoplay, or social interactions.
- **Layout reference only:** Treat Facebook as a card-layout reference. Do not scrape authenticated pages or add a Meta Page API integration in this increment.

## Existing implementation verified in codebase

- `lib/features/announcements/screens/announcements_screen.dart` loads a paginated published feed via `AnnouncementFeedController` / `AnnouncementRepository` and opens `AnnouncementViewerScreen`.
- `lib/features/announcements/screens/manage_announcements_page.dart` and `widgets/announcement_editor.dart` provide the Admin Portal publisher flow, wired in `lib/features/admin/screens/admin_portal.dart` for `portalStaff` and `admin`.
- `functions/src/announcements.ts` uses revision-checked transactions (`tx.set(ref, next)`) and atomic `writeAudit` entries via `functions/src/announcements_callable.ts`.
- `functions/src/announcement_link_preview.ts` validates public destinations and redirects, pins DNS resolution, caps bytes/time (`512 KB` / `8s`), rate-limits to `10` requests/minute per user (`admitAnnouncementPreview`), and returns a manual fallback when metadata is unavailable.
- `firestore.rules` currently allows any active, email-verified user to read any `status == 'published'` announcement regardless of population role.
- `lib/features/home/screens/home_screen.dart` launches `const AnnouncementsScreen()` without passing the signed-in user's population role (`UserModel.effectivePopulationRole`, derived from `populationRole ?? declaredRole ?? PopulationRole.parse(role)`).
- Minor existing UI rough edges to fix while touching these files: encoding artifacts (`'PACC ? Official update'` in `announcement_card.dart`, `'Loading announcements?'` in `announcements_screen.dart` and `manage_announcements_page.dart`), duplicate category text in `manage_announcements_page.dart`, and career-guidance-only copy across publisher and feed screens.

## Data contract and invariants

### Announcement document fields

Each new or updated post persists:

- `postType`: `'announcement'` | `'information'` (required).
- `audienceRoles`: non-empty array of unique canonical values from `['student', 'teaching', 'nonTeaching']`, stored in canonical order `['student', 'teaching', 'nonTeaching']` (required).
- `mediaType`: `'standard'` | `'video'` (required).
- `kind`: `'original'` | `'link'` (existing, required).
- Existing fields: `title`, `body`, `imageUrl`, `sourceUrl`, `status`, `authorId`, `revision`, `createdAt`, `publishedAt`, `updatedAt`.
- Historical `category` (`'careerGuidance'` | `'placements'`): optional on input (validated if present), omitted on brand-new posts, and **explicitly preserved from `before.category`** inside `announcementMutation` when editing or archiving an existing legacy post (since `saveAnnouncement` writes with full-document `tx.set(ref, next)`).

### Cross-field validation matrix (`functions/src/announcements.ts` and editor)

| `kind` | `mediaType` | `sourceUrl` | Allowed? |
| --- | --- | --- | --- |
| `original` | `standard` | Must be empty (`""`) | Yes |
| `original` | `video` | Any | **No — reject** |
| `link` | `standard` | Required valid HTTP(S) URL without credentials | Yes |
| `link` | `video` | Required valid HTTP(S) URL without credentials (`imageUrl` optional thumbnail) | Yes |

Additional backend validation requirements:
- Reject non-array, empty, duplicate, non-string, or unsupported `audienceRoles` entries; reject unknown keys and privileged fields (`status`, `authorId`, `revision`, `publishedAt`, `createdAt`).
- Preserve `authorId`, `createdAt`, `publishedAt` (once published), and `before.category` on edits, and preserve all content/audience/type/media fields on `archive`.
- Add `postType`, `audienceRoles`, and `mediaType` to `writeAudit` metadata so audit logs capture targeting and type changes.

### Firestore queries and composite indexes

Mobile feed queries must:
- Require `status == 'published'` and `audienceRoles array-contains <effectivePopulationRole>`.
- Optionally filter `postType == <'announcement' | 'information'>`.
- Order by `publishedAt DESC`, `__name__ DESC` with cursor pagination (`startAfter([Timestamp, id])`, page size `20`, `Source.server`).

Add two composite indexes to `firestore.indexes.json` using `"arrayConfig": "CONTAINS"` (not `"order": "ASCENDING"`) on `audienceRoles`:
1. `status` ASC, `audienceRoles` CONTAINS, `publishedAt` DESC, `__name__` DESC
2. `status` ASC, `postType` ASC, `audienceRoles` CONTAINS, `publishedAt` DESC, `__name__` DESC

**Retain** all three existing `announcements` indexes (`status + updatedAt + __name__` is still required by `ManageAnnouncementsPage`, and the two legacy published/category indexes keep older clients working until rules tighten). Total `announcements` indexes become `5`.

### Firestore Security Rules (`firestore.rules`)

Server-side authorization must never trust client query hints or route parameters:
- Keep `allow write: if false;` on `/announcements/{postId}`.
- Keep `announcementPublisher()` access for active, approved, email-verified `portalStaff` and `admin` accounts.
- Derive `effectiveAnnouncementAudienceRole()` from `/users/$(request.auth.uid)` (requiring `announcementReader()`: `isVerifiedEmail()`—which includes `signedIn()` and blocks `firstLoginPending == true`—plus existing profile doc and `accountStatus == 'active'`), matching `UserModel.effectivePopulationRole` and `functions/src/student_personal_info.ts`:
  1. Use `populationRole` if it is in `['student', 'teaching', 'nonTeaching']` (treating `null` or `""` as absent, since legacy/backfilled profiles store `""`).
  2. Otherwise use `declaredRole` if it is in `['student', 'teaching', 'nonTeaching']`.
  3. Otherwise, when `currentAccessRole() == 'appUser'`, map legacy `role`: `'student'` → `'student'`, `'teaching'` / `'faculty'` → `'teaching'`, `'nonTeaching'` / `'staff'` → `'nonTeaching'`.
  4. Otherwise return `null` (ineligible).
- Enforce published app-user read rule using the direct membership check that Firestore's static query analyzer proves for `array-contains` list queries:
  `announcementReader() && resource.data.status == 'published' && effectiveAnnouncementAudienceRole() != null && effectiveAnnouncementAudienceRole() in resource.data.audienceRoles`
  - Avoid adding non-provable predicates like `resource.data.audienceRoles is list` inside the `list` path; missing or non-list `audienceRoles` on an un-backfilled document already fails closed.
  - Counselor-only profiles (no population role) are not a target audience and will be denied reading published announcements; update the counselor assertion in `announcements_rules.test.ts` accordingly.

## Existing-record compatibility and backfill

Before enforcing role-filtered reads in Firestore Rules, add an idempotent backfill (`functions/src/backfill_announcements.ts`):
- Scans all documents in `announcements` (`published`, `draft`, and `archived`) and patches **only missing/null fields**:
  - missing `audienceRoles` → `['student', 'teaching', 'nonTeaching']`
  - missing `postType` → `'announcement'`
  - missing `mediaType` → `'standard'`
- **Never** modifies `category`, `kind`, `title`, `body`, `imageUrl`, `sourceUrl`, `status`, `authorId`, `revision`, `createdAt`, `publishedAt`, or `updatedAt` (crucially, preserving `updatedAt` keeps `ManageAnnouncementsPage`'s `updatedAt DESC` ordering intact).
- Exports `backfillAnnouncements(db, {dryRun})` with an injectable `Firestore` instance, guards `initializeApp()` and CLI execution behind `if (require.main === module)`, reuses the `resolveProjectId()` + `bulkWriter()` pattern from `backfill_profiles.ts`, and reports structured counts (`mode`, `scanned`, `changed`, `skipped`, `anomalies`) without printing post contents.
- Exposes `announcements:backfill:dry-run` and `announcements:backfill:apply` in `functions/package.json`.
- Flutter model parsing (`Announcement.fromJson`) also tolerates legacy records while backfill is pending (defaulting missing `postType` → `announcement`, missing `mediaType` → `standard`, missing `audienceRoles` → all three roles).

## UI behavior

### Publisher (`ManageAnnouncementsPage` & `AnnouncementEditor`)

- **Post type & audience controls:** Add `Announcement` / `Information` selector and multi-select audience filter chips (`Student`, `Teaching`, `Non-Teaching`, defaulting to all three for new posts). Show inline validation (`Select at least one audience.`) if all are deselected.
- **Media option:** Support `Standard` vs `Video` media selection. Selecting `Video` requires a linked post with a valid HTTP(S) `sourceUrl` (selecting `Original post` resets `mediaType` to `standard`; selecting `Video` switches to or requires the link input with clear video-link helper copy). Optional `imageUrl` serves as the video thumbnail.
- **Debounced auto-preview (rate-limit and edit safe):**
  - Because `admitAnnouncementPreview` enforces a `10/min` server rate limit, debounce URL changes by ~`650ms`, trigger only for valid HTTP(S) URLs (`announcementHttpUri`), skip duplicate fetches for an unchanged URL, and seed `_lastFetchedUrl` from the existing post in `initState` so opening an existing post for editing does not auto-fetch.
  - Guard responses with a monotonically increasing request ID plus current URL/kind check so stale responses never mutate a newer URL or original post.
  - Distinguish user-edited fields from untouched/auto-filled fields so preview responses never overwrite publisher edits.
  - Cancel pending debounce timers in `dispose()` and before saving; never block manual entry or manual Draft/Publish if preview fails, returns unavailable, or hits `resource-exhausted` (show clear inline status + manual retry button).
- **Managed list:** Display post status, `postType` badge, optional `Video` indicator, and target audience chips cleanly (removing the duplicate category label), and replace career-only headings/copy.
- **Publishing safety:** Keep explicit `Save draft`, `Publish`, `Publish changes`, and `Archive` actions. Never execute or render fetched HTML.

### App feed (`HomeScreen`, `AnnouncementsScreen`, `AnnouncementCard`, `AnnouncementViewerScreen`)

- **Role propagation & fail-closed guard:**
  - `HomeScreen` passes `UserProvider.user?.effectivePopulationRole` to `AnnouncementsScreen(populationRole: ...)`.
  - `AnnouncementRepository.loadPublished` requires a non-nullable `PopulationRole audienceRole` so an unscoped published query is impossible at compile time.
  - `AnnouncementFeedController` accepts nullable `PopulationRole? audienceRole` (and updates via `didUpdateWidget` if the role changes). When `audienceRole == null`, `load()`, `retry()`, and `selectPostType()` clear state and return without querying Firestore; `AnnouncementsScreen` shows a calm `AnnouncementStatusPanel` indicating that role-targeted updates are unavailable for this account rather than spinning or querying unscoped.
- **Filters & feed copy:** Replace `Career Guidance` / `Placements` chips with `All`, `Announcement`, and `Information`. Update career-only hero copy and viewer heading (`AnnouncementViewerScreen`) to fit general PACC updates, and fix the existing `'Loading announcements?'` and `'PACC ? Official update'` encoding glitches.
- **News-feed card hierarchy (`AnnouncementCard`):**
  - Top header row: PACC avatar, `PACC · Official update`, post type label (`Announcement` / `Information`), publication date, and full-screen button (when not already in full-screen viewer).
  - Readable title and body text above media/link preview attachment.
  - Media/link attachment:
    - Standard link/image: show image (with graceful `Image unavailable` fallback) and source host with `Open original post` action.
    - Video post: show thumbnail with a centered play treatment when `imageUrl` loads, or a clean styled video placeholder with play icon + host when `imageUrl` is empty or fails to load, plus a clear `Watch Video` action (minimum `48dp` touch target) opening `post.sourceUri` via the existing external launcher in both feed and full-screen viewer.
- **Preserved states:** Keep loading, empty, calm error + retry (preserving the tested `No announcements yet` / `You will be notified when there is an announcement.` / `Retry` state unless explicitly changed with tests), image-failure, source-launch retry snackbar, reduced-motion transitions, pagination, viewer swipe/arrow anchoring, and the separate `PaccHomeScheduleStatus` card on Home unchanged.

## Exact implementation file scope

### App source

- `lib/features/announcements/models/announcement.dart` — add `AnnouncementPostType`, `AnnouncementMediaType`, `audienceRoles` (`List<PopulationRole>`), cross-field serialization, and legacy-safe `fromJson` defaults; keep `AnnouncementCategory?` optional for legacy parsing.
- `lib/features/announcements/data/announcement_repository.dart` — require `PopulationRole audienceRole` and optional `AnnouncementPostType? postType` in `loadPublished` (`audienceRoles array-contains` + optional `postType ==`); keep `loadManaged`, cursor pagination, and callables intact.
- `lib/features/announcements/data/announcement_feed_controller.dart` — store `PopulationRole? audienceRole` and `AnnouncementPostType? postType`; fail closed without querying when `audienceRole == null`; reset/reload on role or type change with generation-based stale-response protection.
- `lib/features/announcements/screens/announcements_screen.dart` — accept `PopulationRole? populationRole`, render missing-role state when null, replace category chips with `All` / `Announcement` / `Information`, update copy/encoding glitch, and keep refresh/scroll/viewer behavior.
- `lib/features/announcements/screens/announcement_viewer_screen.dart` — work with the type-aware feed, support video `Watch Video` action, and update the generic viewer heading.
- `lib/features/announcements/screens/manage_announcements_page.dart` — show `postType`, optional `Video` indicator, and audience chips in the managed list; remove duplicate category label and update copy/encoding glitch.
- `lib/features/announcements/widgets/announcement_editor.dart` — add post type, multi-select audience, and standard/video media controls; implement rate-limit-safe debounced auto-preview with stale-response and manual-edit protection; retain manual retry/fallback and explicit save actions.
- `lib/features/announcements/widgets/announcement_card.dart` — update to news-feed hierarchy, display `postType` and fixed attribution header, and render linked video thumbnail/placeholder + play treatment + `Watch Video` action.
- `lib/features/home/screens/home_screen.dart` — pass the signed-in user's `effectivePopulationRole` to `AnnouncementsScreen` without altering `PaccHomeScheduleStatus`.

### Trusted backend and access control

- `functions/src/announcements.ts` — validate `postType`, canonical non-empty unique `audienceRoles`, `mediaType`, and `kind × mediaType × sourceUrl` invariants; make `category` optional while preserving `before.category` on edits/archives; include targeting/type/media fields in audit metadata.
- `functions/src/backfill_announcements.ts` — add dry-run/apply idempotent backfill for missing `audienceRoles`, `postType`, and `mediaType` without mutating `updatedAt` or other historical fields.
- `functions/package.json` — add `announcements:backfill:dry-run` and `announcements:backfill:apply` scripts.
- `firestore.rules` — derive `effectiveAnnouncementAudienceRole()` from `/users/$(request.auth.uid)` and enforce `effectiveAnnouncementAudienceRole() in resource.data.audienceRoles` on published app-user reads; preserve publisher access and deny direct client writes. (Use the `firestore-rules-author` specialist subagent when editing `firestore.rules`.)
- `firestore.indexes.json` — add the two `arrayConfig: "CONTAINS"` audience-scoped published composite indexes while retaining the existing three `announcements` indexes.

Unchanged files reused as-is: `functions/src/announcements_callable.ts`, `functions/src/announcement_link_preview.ts`, `lib/features/announcements/services/announcement_link_launcher.dart`, `lib/features/announcements/widgets/announcement_presentation.dart`, and `lib/features/admin/screens/admin_portal.dart`.

### Focused tests

- `test/features/announcements/announcement_repository_test.dart` — required role + optional `postType` query constraints, cursor stability, new payload serialization, and legacy parsing defaults.
- `test/features/announcements/manage_announcements_test.dart` — audience/type/video controls, empty-audience validation, debounced auto-preview + deduplication + stale-response rejection + manual-edit preservation + unavailable/rate-limit fallback, no auto-fetch on editing existing post, and audience/type labels in managed list.
- `test/features/announcements/announcements_screen_test.dart` — role-scoped feed, missing-role fail-closed state (zero queries), `All`/`Announcement`/`Information` filters, video `Watch Video` source action in feed and viewer, error/retry/empty states, and pagination.
- `test/features/announcements/announcement_presentation_test.dart` — news-feed card hierarchy, `Announcement`/`Information` labels, video thumbnail + placeholder fallback + play treatment, narrow large-text fit, and reduced motion.
- `test/features/home/home_screen_test.dart` — `Student`, `Teaching`, and `Non-Teaching` profiles pass the matching `PopulationRole` to `AnnouncementsScreen`; missing role passes `null` and triggers no unscoped query.
- `functions/src/announcements.test.ts` — valid/invalid `postType`, `audienceRoles` (empty, duplicate, unknown, ordering), `mediaType`, `original + video` rejection, `before.category` preservation, and immutable `authorId`/`publishedAt`/revision checks.
- `functions/src/announcements_callable.test.ts` — new fields persist through callable and audit metadata.
- `functions/src/announcements_rules.test.ts` — matching audience direct `get` and `array-contains` `list` reads succeed (covering `populationRole`, `declaredRole`, and legacy `role` `faculty`/`staff`/`student`, plus empty-string fallback); non-matching direct/query reads, unscoped queries, counselor-only profiles, missing-role profiles, unverified/suspended/`firstLoginPending` users, and all client writes fail; `portalStaff`/`admin` publisher access remains intact.
- `functions/src/announcement_indexes.test.ts` — assert the exact field paths, `arrayConfig: "CONTAINS"`, sort directions, and retention of managed/legacy indexes (5 `announcements` indexes total).
- `functions/src/backfill_announcements.test.ts` — dry-run vs apply, idempotence (second run changes 0), missing-only patching across published/draft/archived docs, anomaly counting, and strict preservation of `category`, `updatedAt`, `publishedAt`, `authorId`, and `revision`.

Keep `functions/src/announcement_link_preview.test.ts` untouched as a regression check for SSRF, redirect, size, timeout, rate-limit, and metadata-fallback protections.

## Implementation sequence

1. **Backend tests & schema (`functions/src/announcements.ts`, `functions/src/backfill_announcements.ts`, `functions/package.json`):** Add failing unit/emulator tests for payload validation, `before.category` preservation, audit metadata, and backfill idempotence; implement backend validation and backfill; verify unit tests pass.
2. **Firestore Rules & indexes (`firestore.rules`, `firestore.indexes.json`):** Add failing index-shape and Rules emulator tests (including legacy role fallback, non-matching direct/list denials, and counselor-only denial); update `firestore.rules` (via `firestore-rules-author`) and `firestore.indexes.json`; verify under the Firebase Emulator so emulator-gated tests actually execute rather than skip.
3. **Flutter model, repository & controller:** Update `announcement.dart`, `announcement_repository.dart`, and `announcement_feed_controller.dart` with failing-first repository tests verifying compile-time role scoping, `postType` filtering, cursors, and legacy parsing.
4. **Publisher UI (`announcement_editor.dart`, `manage_announcements_page.dart`):** Add failing widget tests for audience/type/video controls and debounced auto-preview edge cases (including timer disposal, deduplication, edit preservation, and no auto-fetch on existing posts); implement publisher updates.
5. **Feed, card, viewer & Home wiring (`announcement_card.dart`, `announcements_screen.dart`, `announcement_viewer_screen.dart`, `home_screen.dart`):** Add failing widget tests for role propagation, missing-role fail-closed UI, `All`/`Announcement`/`Information` filters, and video card/viewer actions; implement UI updates without changing `PaccHomeScheduleStatus`.
6. **Scoped verification:**
   - Functions unit & index tests: `cd functions && npm run build && node --test lib/announcements.test.js lib/announcement_indexes.test.js lib/announcement_link_preview.test.js`
   - Functions emulator tests (must run with `FIRESTORE_EMULATOR_HOST` / Auth emulator so tests do not skip): `firebase emulators:exec --only firestore,auth "cd functions && node --test --test-concurrency=1 lib/announcements_callable.test.js lib/announcements_rules.test.js lib/backfill_announcements.test.js"`
   - Flutter focused tests: `flutter test test/features/announcements/ test/features/home/home_screen_test.dart`
   - Static checks on touched files: `dart analyze` and `dart format --output=none --set-exit-if-changed` on modified Dart files, plus `git diff --check` and allowlist review (preserving unrelated dirty working-tree changes).

## Safe rollout and cutover order (outside this code-only plan)

When separately authorized for staging, and later for production, apply changes in this exact order to avoid downtime or index/rules errors:
1. Deploy updated **Cloud Functions** (`saveAnnouncement`) and additive **Firestore indexes** (`firestore.indexes.json`) and wait for composite indexes to finish building.
2. Run **`announcements:backfill:dry-run`**, review counts/anomalies, run **`announcements:backfill:apply`**, then re-run **`announcements:backfill:dry-run`** to confirm `changed: 0`.
3. Roll out / verify the updated **Admin Portal** and **Mobile App** builds using role-scoped queries.
4. Deploy the tightened **`firestore.rules`** only after backfill verification succeeds. Note: once tightened rules deploy, older un-updated mobile APKs issuing unscoped published queries will intentionally receive `PERMISSION_DENIED` until updated.

Production migration, deployment, APK build/install, and publishing changes remain outside this implementation plan and require separate authorization.

## Explicit exclusions

- Likes, comments, shares, direct messages, algorithmic ranking, and push notifications.
- Video upload/storage, transcoding, autoplay, or in-app video playback.
- Authenticated-page scraping or Facebook/Meta Page API integration.
- Changes to counseling/appointment features, `PaccHomeScheduleStatus`, or other announcement consumers.
- Changes to Admin Portal navigation or creating a new announcements collection/service.

## Acceptance criteria

- A `Student` receives only published posts whose `audienceRoles` contains `student`; `Teaching` and `Non-Teaching` users receive only posts matching their effective population role.
- Direct document `get` and collection `list` queries cannot expose another audience's post, an unscoped feed, or any post to counselor-only/missing-role/unverified/suspended/`firstLoginPending` accounts by altering client route or query parameters.
- Portal Staff and Admins retain draft, publish, edit, and archive workflows with revision checks and audit logging; invalid/empty/duplicate audiences, unsupported post/media types, and `original + video` combinations are rejected by the backend.
- Editing or archiving a legacy post preserves its historical `category`, `authorId`, and `publishedAt`.
- New posts default to all three audiences, can target any non-empty subset, and are labeled `Announcement` or `Information`.
- A valid pasted URL triggers one debounced, rate-limit-safe preview request when settled; opening an existing post does not auto-fetch; publisher edits are never overwritten; stale responses are ignored; unavailable or rate-limited previews leave manual entry and retry working; publication remains explicit.
- A video post displays a thumbnail (or styled video placeholder) with play treatment and a `Watch Video` action opening the external source URL in both feed and full-screen viewer.
- Existing posts remain visible to all three app-user roles after the idempotent backfill, with `category`, `updatedAt`, `publishedAt`, `authorId`, and `revision` preserved.
- Feed ordering, `All`/`Announcement`/`Information` filters, pagination, retry, and full-screen viewing continue to work under role filtering.

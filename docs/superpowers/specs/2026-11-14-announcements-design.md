# PACC announcements design

Status: approved by user on 2026-11-14, including staff/admin publishing and the audience and publication defaults below.

## Intent
Give the PACC head a publishing area for career guidance and placement announcements, and give mobile users a dedicated announcement feed with scrolling cards and a full-screen swipe view. Linked announcements open the original platform when tapped.

## Existing project
Flutter/Firebase already provides a role-based admin portal, callable routing, Firestore services, and audit logging. AccessRole.admin is the existing administrative role; no separate PACC-head role was found in the inspected role model. The home Announcement card currently presents office availability. Preserve that behavior as office status and add a distinct announcement entry point. No dedicated announcement collection or publisher was found in the targeted searches.

## Approaches
1. **Selected: one stored announcement collection, two mobile views.** Cards and full-screen paging share content, ordering, and selection. Reuses existing Flutter/Firebase patterns and gives both requested experiences.
2. Separate card and full-screen feeds. Adds synchronization and maintenance with no identified benefit.
3. Embed external platform feeds. Cannot reliably cover arbitrary pasted links or original PACC posts; platform restrictions would control the experience.

## Admin experience
Add Announcements to the existing admin portal. List drafts, published posts, and archived posts. Create an original announcement or paste a source link. Choose Career Guidance or Placements, enter/edit title and body, review an optional preview image, and explicitly publish. Support editing and archiving; do not hard-delete historical posts. Saving a draft must not publish it. Edits to a published post go live only when the author selects Publish changes; closing the editor discards unsaved changes and does not modify the published record. Saving drafts applies to unpublished records only; separate server-side draft versions of published posts are outside this scope.

Pasting a link requests available page metadata from a trusted backend. Populate editable title, description, and preview image; preserve the source URL. Missing or blocked metadata leaves a usable manual form and never auto-publishes. Display the destination hostname before publication and on mobile. A source link is required only for linked posts.

## Mobile experience
A dedicated Announcements screen shows newest published posts first, with category filters and paginated loading. Cards show PACC attribution, category, date, title, text excerpt, optional image, and source hostname for linked posts. Use the app's existing visual language.

To avoid conflicting tap behavior, a linked card's content opens its external source; a separate visible full-screen control opens the swipe viewer at that announcement. Original posts open their complete content in the viewer. The viewer pages vertically between the same ordered announcements and has an explicit source action; tapping linked content also opens its source. Closing returns to the feed without losing position. This interaction detail is a proposed builder decision for review.

Provide loading, empty, retry, image-failure, preview-unavailable, and link-opening-failure states. Text must remain readable with larger font sizes. Full-screen means a focused post page, not a requirement for video, autoplay, or edge-to-edge cropped posters.

## Data and services
Add an additive announcements collection and model: id, kind (original/link), category, title, body, optional image URL, optional source URL, status (draft/published/archived), author UID, createdAt, updatedAt, publishedAt, and revision. Store timestamps on the server. Keep publication time stable on ordinary edits. Preserve compatibility with all existing data.

Use a thin repository over existing Firestore/callable infrastructure. Backend mutations validate payloads and current authorization, and record administrative audit events. Revision checks prevent silent overwrites. Published queries use stable publishedAt/id ordering with cursors and required indexes. Drafts and archived posts remain admin-only. Mobile reads only published records under the existing authenticated-app access policy.

## Permissions and link handling
Confirmed: currently authorized AccessRole.portalStaff and AccessRole.admin accounts can create, edit, publish, and archive announcements and request metadata. Counselor-only accounts do not gain posting rights. Reuse the existing account eligibility checks; no new role is required.

Do not allow direct client writes. Validate authorization in backend handlers and enforce read boundaries in Firestore rules. Preview retrieval accepts only public HTTP(S) destinations, blocks private/local/reserved addresses and credentials, validates every redirect and resolved address, and uses connection-time destination enforcement, bounded timeouts, redirect counts, response sizes, and HTML parsing. Never execute fetched scripts or forward user credentials. A tested safe fetch implementation is required; unsafe generic fetching is not an acceptable fallback.

Treat remote metadata as untrusted plain text. Reject unsafe URL schemes, including image URLs. Never render fetched HTML. External links launch through the supported operating-system/browser mechanism; do not promise opening a native social app or bypassing login/private-post restrictions. Metadata preview failure does not prevent manually authored linked announcements. Do not download or rehost source media in this scope.

## Scope and non-goals
Includes publisher, metadata preview, trusted mutations, storage, read permissions, indexes, audit effects, mobile entry point, both viewing modes, and external source navigation. Confirmed audience is all existing eligible signed-in mobile users. No personalized ranking, likes, comments, scraping authenticated pages, video hosting, scheduled publishing, push notifications, or production changes. No migration or existing-data rewrite is needed.

## Validation
Use focused tests for authorization, payload validation, draft/public visibility, revision conflicts, audit events, stable pagination, metadata redirects/private-address rejection/limits/fallback, and malformed metadata. Widget tests cover admin preview/publish errors and mobile feed, filters, full-screen navigation, source actions, and empty/error states. Run scoped Dart analysis and Functions build/tests; use approved local emulator checks where available. Report any infrastructure-blocked checks separately. Builds, installs, hosted reads, deployments, and pushes require their existing separate authorization.

## Remaining builder decisions
Reuse nearby portal navigation, Firebase authorization helpers, audit schema, and component styling after narrow inspection. Choose exact field limits and pagination size and document them in the implementation plan. Inspect current dependencies before selecting a safe metadata parser/fetch implementation or link launcher; add a dependency only where needed. Visual mockups are a separate next design step after the user accepts a visual preview.

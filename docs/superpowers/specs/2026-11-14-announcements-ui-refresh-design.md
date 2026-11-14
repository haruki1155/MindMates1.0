# Announcement UI refresh

Status: approved by user; implementation plan subsequently approved for inline execution. UI refresh implemented uncommitted for local review.

## Intent and scope
Make existing announcement publishing and reading feel polished, clear, and interactive on mobile and web. Change only announcement UI and its staff/admin workspace navigation. Preserve backend contracts, permissions, storage, publishing actions, link previews, source navigation, and office availability.

## Approaches
1. **Selected by user: match each platform.** Reuse HomePalette for mobile cream/gold/dark-text surfaces and AdminColors/AdminTheme for web neutral surfaces with pale-yellow emphasis. Shared hierarchy and interaction patterns create continuity without restyling the whole portal.
2. Identical mobile cream/gold styling everywhere. More uniform announcement appearance, but competes with the existing admin workspace design. Not selected.

## Mobile feed and viewer
- Use warm cream background, light cards, dark readable headings, gold primary emphasis, subtle borders and restrained shadows from existing tokens. Avoid introducing unrelated accent colors.
- Keep a compact header, short introduction, category filters with unmistakable selection, and newest-first cards. Each card clearly separates PACC attribution/date, category, optional image, title, excerpt, and destination hostname.
- Preserve full image visibility rather than cropping informational posters. Missing or failed images have a calm fallback without blocking text.
- Linked content opens its original platform; the separate full-screen control opens the vertical viewer. Original announcements open their full content. Keep visible previous/next viewer controls so long scrolling content never traps navigation.
- Give loading, refreshing, empty, failed-load/retry, pagination, and external-link failure distinct states. Do not substitute sample posts for unavailable real data.
- Preserve feed scroll position and selected category when returning from the viewer. Keep existing refresh and pagination behavior.

## Staff/admin publisher
- Use the existing neutral admin canvas and white surfaces with pale-yellow active filters and restrained gold emphasis. Keep clear page title, brief explanation, New announcement action, and Drafts/Published/Archived filters.
- Center the editing form within its existing readable width. Group post type/category, source link and preview action, editable content/image, then publication actions. Show source hostname immediately when its field changes.
- Clearly distinguish preview loading/unavailable, saving, saved return, validation errors, revision conflicts, and archive confirmation. Disable duplicate actions during work; retain form values after failures.
- Existing published posts use Publish changes; unpublished posts can Save draft or Publish. No automatic publication or change to publishing semantics.

## Workspace navigation
Keep Announcements as a visible workspace navigation destination for AccessRole.portalStaff and AccessRole.admin in expanded and compact layouts. Preserve its existing Publishing grouping unless the surrounding workspace uses a stronger established grouping. Exclude AccessRole.counselor and appUser from publishing navigation and page access; do not remove existing counseling features from their workspaces. Backend authorization remains authoritative and unchanged.

## Motion, feedback, and accessibility
Use Flutter built-in implicit animations only: brief fades/content transitions, selected-filter transitions, button hover/press/focus feedback, and restrained loading indicators. Aim for 150–220 ms; honor MediaQuery.disableAnimations with immediate transitions. Avoid looping decoration, parallax, heavy blur, and motion that delays actions.

Use adequate contrast, descriptive tooltips/semantics, visible keyboard focus and at least 48 logical-pixel touch targets. Layouts must wrap rather than clip at 320px and large text scales. Keep source and publication actions reachable without relying on hover. Do not add dependencies or a new state-management layer.

## Validation and boundaries
Run focused announcement widget/repository tests, affected portal navigation/Home tests, and scoped analysis. Add tests for role navigation visibility, source-label updates, selected/loading/error states, large-text/narrow layouts, and reduced motion where behavior changes. Inspect actual web rendering locally; distinguish synthetic emulator data from staging/production. Preserve the documented pre-existing Home assessment-title failure.

No backend changes, full-portal redesign, commit, push, merge, deployment, APK replacement, or hosted-resource modifications are included in this UI planning approval. Existing user changes and the announcement worktree remain intact. Implementation planning follows approval of this design.

## Builder decisions
Reuse existing card, spacing, typography, navigation, and theme conventions before adding feature-local styling. Set exact token application and widget boundaries in the implementation plan after targeted reads. Prefer a few shared announcement presentation helpers over a new design system. All defaults in this document beyond the selected platform approach are proposed design decisions for user review.

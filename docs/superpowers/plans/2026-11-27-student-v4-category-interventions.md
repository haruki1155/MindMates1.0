# Student Well-Being V4 Category Intervention Plan

> **For agentic workers:** Use `superpowers:executing-plans` to implement this plan task by task. Keep source and test edits within the exact file allowlist below.

**Goal:** Replace the random activity offered after an eligible Student Well-Being V4 category review with one short activity that matches that category, while keeping participation optional and assessment progress easy to resume. Retain the existing Breathing and Walking activities in the Student V4 category set.

**Architecture:** Continue using the trusted V4 domain preview as the sole eligibility source. Add a deterministic Student V4 domain-to-activity mapping. Reuse the existing Walking, Breathing, and Grounding screens for Social Adjustment, Sleep and Rest, and Emotional Well-Being; add a small screen for the new Academic and Financial activities. Leave the existing random activity rotation and default activity behavior in place for Teaching, Non-Teaching, and legacy assessment flows.

**Tech stack:** Flutter/Dart, Provider, current Full Assessment flow and `AssessmentPresentation` components.

**Confirmed decisions:** Student Well-Being V4 only; one optional tap starts an activity; use the five category mappings below, including the existing Breathing and Walking activities; keep feedback skippable. The existing feedback screen already has a `Skip feedback` action and keeps feedback in memory for the current session, so retain it and add regression coverage rather than changing that screen.

## Planning Snapshot

- Relevant source was reviewed in `.worktrees/device-build` at commit `5e80441a` on `main`, tracking `origin/main`.
- That worktree already has unrelated modified and untracked files. Reconfirm the implementation base before coding and preserve all existing edits. Do not use this plan as authorization to clean or replace that worktree.
- This document is the only file created by the planning task. No application source or test files have been changed.

## Scope and Safety Constraints

- Apply the new mapping only when `AssessmentProvider.isStudentAssessmentV4` is true. Keep the current generic rotation and existing activity routes for Teaching, Non-Teaching, and legacy assessments.
- Keep `preview['interventionEligible']` from the trusted V4 preview as the gate. Do not compute eligibility from answers or scores in the client.
- Show an activity only on an eligible Student V4 category review. Do not auto-start it, require completion, or let it affect the assessment result.
- Keep activity choices and reflection local to the screen/session. Do not persist answers, add analytics, collect financial details, or add services, backend endpoints, database fields, permissions, or dependencies.
- Do not change assessment scoring, question sets, submission, safety screening, appointments/PACC, workplace assessment content, or the server preview contract.
- Use supportive, non-diagnostic language. These brief exercises are self-help options; do not claim that the category mapping diagnoses, treats, or is clinically validated for a condition.

## Student V4 Category Mapping

| V4 domain ID | Category | Activity | Interaction |
| --- | --- | --- | --- |
| `academic` | Academic | **Start with five minutes** | New planning activity: choose one small first step and pair it with a practical time or cue. Any text stays on screen and is not saved. |
| `financial` | Financial | **Choose one practical next step** | New planning activity: choose a manageable action such as checking a due date, finding a student support contact, or setting a time to revisit the concern. Do not request balances, income, or account details, and do not give financial advice. |
| `socialAdjustment` | Social Adjustment | **Take a short walk** | Reuse the existing Walking activity in a permission-free, self-reported mode. The student can walk alone or invite someone if comfortable; no contact is required. |
| `sleepRest` | Sleep and Rest | **Try a breathing wind-down** | Reuse the existing Breathing activity. Keep its comfortable, optional hold control; no breath hold is required. |
| `emotionalWellbeing` | Emotional Well-Being | **Ground and notice** | Reuse the existing Grounding activity and add an optional prompt to name or notice a feeling. Do not require disclosure or save a mood entry. |

Keep each activity brief (about one to three minutes), readable, and skippable. The Student V4 Walking route must not request activity-recognition permission; use a self-reported completion option. Avoid treating completion as proof that the user's underlying concern is resolved.

## UX Flow

1. The server preview completes as it does today. Ineligible categories keep the current automatic advance behavior.
2. An eligible Student V4 category opens the existing review screen. Show a compact card with the category-matched activity name and a short description, plus a clear **Try activity** action and the existing **Continue** action. Starting it remains optional and requires one tap.
3. Academic and Financial open the new planning activity screen. Social Adjustment routes to the existing Walking screen in permission-free mode; Sleep and Rest routes to the existing Breathing screen; Emotional Well-Being routes to the existing Grounding screen with an optional name-the-feeling prompt. Keep the current assessment result visible only on the review screen; do not add another result or scoring step.
4. **Skip activity** continues the assessment. Back/cancel returns to the category review, where the student can continue without doing the activity.
5. A completed activity may show the existing feedback screen. Keep **Skip feedback**; choosing it must return to the assessment flow without blocking progress. Feedback remains session-only.

## Exact File Allowlist

Only modify the following production and test files when implementing this plan.

### Production files to modify

- `lib/providers/assessment_provider.dart` — use the category mapping only for Student V4; retain the current selector for every other role/version.
- `lib/features/student_assessment/models/intervention_models.dart` — add identifiers for the new Academic and Financial activities while retaining the existing Walking, Breathing, and Grounding identifiers.
- `lib/features/student_assessment/services/intervention_rotation_policy.dart` — add an explicit mapping for the five Student V4 domain IDs; leave the existing generic rotation behavior intact for non-Student-V4 callers.
- `lib/features/student_assessment/screens/assessment_domain_review_screen.dart` — show the selected Student V4 activity name and concise prompt while retaining the current optional Try and Continue actions.
- `lib/features/student_assessment/screens/student_assessment_screen.dart` — route Academic and Financial to the new screen, Social Adjustment to Walking's permission-free mode, Sleep and Rest to Breathing, and Emotional Well-Being to Grounding; leave other routes intact.
- `lib/features/student_assessment/screens/intervention_walking_screen.dart` — add an opt-in permission-free/self-reported mode for the Student V4 Social Adjustment route; keep existing automatic tracking as the default for other flows.
- `lib/features/student_assessment/screens/intervention_grounding_screen.dart` — add the optional name-the-feeling prompt only when requested by Student V4; keep the existing generic grounding flow unchanged by default.
- Create `lib/features/student_assessment/screens/student_v4_category_intervention_screen.dart` — implement the Academic and Financial planning activities with existing assessment presentation components and no persistence or new permissions.

### Test files to modify

- `test/features/student_assessment/intervention_rotation_policy_test.dart` — verify every Student V4 domain maps to exactly its intended activity and that generic rotation still behaves as before.
- `test/features/student_assessment/assessment_flow_controller_test.dart` — verify only eligible Student V4 previews expose the mapped activity and Teaching/Non-Teaching continue using the legacy behavior.
- `test/features/student_assessment/intervention_activity_widget_test.dart` — verify feedback can be skipped, Student V4 Walking does not request permission, the Grounding prompt is optional, and existing generic activity behavior remains unchanged.
- `test/features/student_assessment/student_v4_completion_test.dart` — cover the category review CTA, eligibility gate, and activity-to-review/continue flow as needed by the current harness.
- Create `test/features/student_assessment/student_v4_category_intervention_screen_test.dart` — cover the Academic and Financial activity content, completion, skip, and absence of data persistence or permission prompts.

No backend, Functions, Firestore rules/schema, localization, Insights, Quick Assessment, workplace assessment, or unrelated UI files are in scope. Do not modify `intervention_breathing_screen.dart` or `intervention_feedback_screen.dart`; the existing breathing exercise and feedback skip behavior are reused as-is.

## Implementation Tasks

### Task 1: Add the Student V4-only category mapping

**Files:** `lib/features/student_assessment/models/intervention_models.dart`, `lib/features/student_assessment/services/intervention_rotation_policy.dart`, `lib/providers/assessment_provider.dart`, `test/features/student_assessment/intervention_rotation_policy_test.dart`, `test/features/student_assessment/assessment_flow_controller_test.dart`

- [ ] Add named activity identifiers for the new Academic and Financial activities without removing existing activity identifiers.
- [ ] Add a deterministic mapping for exactly `academic`, `financial`, `socialAdjustment`, `sleepRest`, and `emotionalWellbeing`, reusing the existing `walking`, `breathing`, and `grounding` identifiers for the last three domains.
- [ ] In the provider, select from that mapping only under `isStudentAssessmentV4`; keep the generic selector for Teaching, Non-Teaching, and legacy flows.
- [ ] Add tests for all five mappings, eligible versus ineligible previews, and unchanged workplace selection.
- [ ] Run the focused policy and flow tests; confirm the mapping and role boundary pass.

### Task 2: Build the Academic and Financial activities and adapt existing category activities

**Files:** `lib/features/student_assessment/screens/student_v4_category_intervention_screen.dart`, `lib/features/student_assessment/screens/student_assessment_screen.dart`, `lib/features/student_assessment/screens/intervention_walking_screen.dart`, `lib/features/student_assessment/screens/intervention_grounding_screen.dart`, `test/features/student_assessment/student_v4_category_intervention_screen_test.dart`, `test/features/student_assessment/intervention_activity_widget_test.dart`, `test/features/student_assessment/student_v4_completion_test.dart`

- [ ] Implement the Academic and Financial planning activities in one screen keyed by the selected Student V4 activity identifier.
- [ ] Keep optional choices ephemeral. Do not send activity content to the repository, Firebase, analytics, or logs.
- [ ] Provide a clear completion action and **Skip activity**. Neither action may change answers, scores, or saved assessment results.
- [ ] Route Social Adjustment to the existing Walking screen without requesting activity-recognition permission; retain the existing sensor behavior for non-Student-V4 routes.
- [ ] Route Sleep and Rest to the existing Breathing screen and Emotional Well-Being to Grounding with a non-persisted optional feeling prompt. Keep both existing generic screens unchanged by default.
- [ ] Add widget/flow coverage for all five category routes, skip, completion, and unchanged generic activity behavior.
- [ ] Run the focused activity and Student V4 completion tests.

### Task 3: Make the category review action more specific

**Files:** `lib/features/student_assessment/screens/assessment_domain_review_screen.dart`, `test/features/student_assessment/student_v4_completion_test.dart`

- [ ] For eligible Student V4 categories, show the matching short title and description with the existing one-tap activity action.
- [ ] Keep **Continue** available without opening the activity; preserve loading, retry, error, and non-eligible review behavior.
- [ ] Verify in tests that the displayed activity matches the category and ineligible previews do not show the activity card.

### Task 4: Preserve optional feedback and assessment continuation

**Files:** `test/features/student_assessment/intervention_activity_widget_test.dart`, `test/features/student_assessment/assessment_flow_controller_test.dart`

- [ ] Add a regression assertion that **Skip feedback** returns no feedback value and the completed activity still advances through the existing assessment flow.
- [ ] Preserve the current session-only feedback behavior. Do not edit `intervention_feedback_screen.dart` unless implementation reveals its current skip action is broken.

### Task 5: Focused verification

- [ ] Run `flutter test test/features/student_assessment/intervention_rotation_policy_test.dart`.
- [ ] Run `flutter test test/features/student_assessment/assessment_flow_controller_test.dart`.
- [ ] Run `flutter test test/features/student_assessment/intervention_activity_widget_test.dart`.
- [ ] Run `flutter test test/features/student_assessment/student_v4_category_intervention_screen_test.dart`.
- [ ] Run `flutter test test/features/student_assessment/student_v4_completion_test.dart`.
- [ ] Run the unchanged `flutter test test/features/student_assessment/workplace_v4_assessment_test.dart` as a boundary regression check.
- [ ] Analyze only the changed Dart files. Do not run a full application build unless a focused failure or release request justifies it.

## Acceptance Criteria

- Each of the five Student V4 domain IDs deterministically selects its matching activity: Academic planning, Financial next step, Walking, Breathing, or Grounding.
- An activity appears only when the trusted preview marks that category eligible; no client-side score threshold is added.
- The student can start with one tap, continue without starting, or skip/cancel without losing assessment progress.
- Feedback remains optional, and skipping it does not block completion or save extra data.
- Teaching and Non-Teaching continue using the existing generic rotation and routes.
- Assessment answers, scores, submission payloads, backend behavior, safety settings, and persistence remain unchanged.

## Evidence and Claims Boundary

The [WHO illustrated stress-management guide](https://tdr.who.int/home/our-work/global-engagement/9789240003927) describes short self-help practices and includes grounding and notice/name exercises. A preregistered university-student trial of implementation intentions found a medium-sized effect on action planning, but no other significant effects; it does not validate this app's five category mappings. Use these sources only to inform brief, low-burden activity design, not to claim clinical efficacy.

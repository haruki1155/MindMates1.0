# Quick Assessment 36–37 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the five Quick Assessment questions and results so students understand each answer, why it matters, and what to do next.

**Architecture:** Keep question and option IDs, values, scoring, thresholds, routes, and action rules intact. Update Flutter catalog and presentation, then mirror stored interpretation copy in the Cloud Function. Use the approved design's exact strings; staging needs a matching Functions deployment before new saved results can show the new server text.

**Tech Stack:** Flutter/Dart, `flutter_test`, Firebase Functions/TypeScript, Node tests.

**Spec:** `docs/superpowers/specs/2026-11-12-quick-assessment-wording-and-result-design.md`

## Global Constraints

- Preserve all question/option IDs and numeric values, scoring thresholds, role selection, action availability, and PACC prompt behavior.
- Set the question-set version to `quick_v3` in both Dart scoring and `functions/src/assessment/catalog.ts`.
- Use the exact copy and layout hierarchy in spec §§5–6; do not claim clinical validation.
- Existing saved results retain their saved wording. Staging uses server-computed result text, so client and Functions must be deployed together for acceptance.
- Prepare a staging Functions revision, but do not deploy it without authorization. The user has already authorized local APK builds and installs on their device for review.

## Review Focus

1. A narrow 360 px phone shows the longest question choice and indicator explanation without truncation or overflow; pin in Tasks 4–5.
2. Every result indicator maps back to its actual selected option, including old saved results whose option label changed in `quick_v3`; pin the version-aware fallback in Task 5.
3. A score of 33.3 remains in “What's going well” and is absent from the >40 focus sentence, while stored `topConcernAreas` keeps its ≥30 rule; pin in Tasks 2–3.
4. Equal indicator scores sort by score descending then name A–Z in app and server text; pin in Tasks 2–3.
5. High and very-high results keep the existing PACC dialog and actions exactly once; pin in Task 5.

---

## File map

- `quick_assessment_models.dart`: question purpose field only.
- `quick_assessment_questions.dart` and `functions/src/assessment/catalog.ts`: matching question/option catalog and version.
- New `quick_indicator_copy.dart`: per-indicator personal meaning and question-to-indicator lookup, consumed by scoring and result UI.
- `quick_assessment_scoring.dart` and `functions/src/assessment/calculator.ts`: matching summary, focus, and insight text; no scoring changes.
- `quick_assessment_question_screen.dart`: “Why we ask” line and two-line options.
- `quick_assessment_category_screen.dart` and new result widgets: visual hierarchy, next steps, answer-linked indicators.
- `docs/quick_assessment_rationale.md`: panel-facing explanation and validation caveat.

### Task 1: Catalog and version contract

**Files:**
- Modify: `lib/features/quick_assessment/models/quick_assessment_models.dart`
- Modify: `lib/features/quick_assessment/data/quick_assessment_questions.dart`
- Modify: `functions/src/assessment/catalog.ts`
- Test: `test/features/quick_assessment/quick_assessment_test.dart`
- Test: `functions/src/assessment/calculator.test.ts`

**Interfaces:** Produces `QuickAssessmentQuestion.purpose: String`; catalog IDs, option IDs/values, and ordering remain unchanged.

- [ ] **Step 1: Write failing catalog tests.** Assert five questions, each exact prompt/choice/purpose from spec §5.1; assert original IDs and values; assert Dart and server versions `quick_v3`.
- [ ] **Step 2: Run red tests.** `flutter test --no-pub test/features/quick_assessment/quick_assessment_test.dart` and `npm test -- --test-name-pattern="quick"` from `functions/`; confirm new-copy/version assertions fail.
- [ ] **Step 3: Add `required this.purpose`/`final String purpose` and apply spec §5.1 in both catalogs; set server `QUICK_QUESTION_SET_VERSION = "quick_v3"`.** Keep role and scoring metadata untouched.
- [ ] **Step 4: Run the same tests green.**
- [ ] **Step 5: Commit the five files** with `feat(quick-assessment): add v3 question catalog and purposes`.

### Task 2: Flutter interpretation copy

**Files:**
- Create: `lib/features/quick_assessment/data/quick_indicator_copy.dart`
- Modify: `lib/features/quick_assessment/services/quick_assessment_scoring.dart`
- Test: `test/features/quick_assessment/quick_assessment_test.dart`

**Interfaces:** Produce `QuickIndicatorCopy.forQuestionId(String questionId)` returning the fixed indicator name, going-well text, closer-look text, and purpose from spec §5; `QuickAssessmentScoring.interpretationFor(List<QuickAssessmentResponse>)` remains callable unchanged.

- [ ] **Step 1: Write failing tests** for all four summary strings, zero/one/multiple focus areas, both insight variants for each of five indicators, `quick_v3`, a 33.3 score, and tied-score ordering. Assert `topConcernAreas` still uses ≥30.
- [ ] **Step 2: Run the targeted Dart test and confirm failures.**
- [ ] **Step 3: Implement fixed copy and update `summaryForScore`, focus sentence, strengths, and focus insights to spec §§5.2–5.3.** Split at >40; sort by score descending then indicator name A–Z; cap insights and focus names at three. Leave scores, levels, priority, and stored concern-area threshold unchanged.
- [ ] **Step 4: Run targeted test green.**
- [ ] **Step 5: Commit** with `feat(quick-assessment): explain v3 results in app`.

### Task 3: Matching server interpretation

**Files:**
- Modify: `functions/src/assessment/calculator.ts` (`calculateQuick` only)
- Test: `functions/src/assessment/calculator.test.ts`

**Interfaces:** Server output keeps the existing result shape; `interpretation.userSummary`, `rationale`, `strengthInsights`, and `focusInsights` match Task 2 for the same answers.

- [ ] **Step 1: Write failing Node tests** for each pattern summary, >40 focus split, empty focus, tied scores, and exact personal insight text; assert `topConcernAreas` and action/priority outputs are unchanged.
- [ ] **Step 2: Run `npm test` in `functions/` and confirm new assertions fail.**
- [ ] **Step 3: Update only `calculateQuick` copy and ordering to spec §5.3.** Use catalog area names and the same fixed copy as Task 2; preserve existing response and policy fields.
- [ ] **Step 4: Run `npm test` and `npm run build` in `functions/`; require both pass.**
- [ ] **Step 5: Commit** with `feat(quick-assessment): align server v3 interpretation`.

### Task 4: Explain questions while answering

**Files:**
- Modify: `lib/features/quick_assessment/screens/quick_assessment_question_screen.dart`
- Test: `test/features/quick_assessment/quick_assessment_test.dart`

**Interfaces:** Consumes `QuickAssessmentQuestion.purpose` from Task 1; selection and Next flow remain unchanged.

- [ ] **Step 1: Write a failing widget test** that checks the exact “Why we ask” text under a question, the full long option label at 360 px without overflow, and selection/Next still work.
- [ ] **Step 2: Run targeted widget test red.**
- [ ] **Step 3: Add the small muted purpose line beneath the prompt; allow `_OptionTile` labels two lines without ellipsis.**
- [ ] **Step 4: Run widget test green.**
- [ ] **Step 5: Commit** with `feat(quick-assessment): explain why each question is asked`.

### Task 5: Reorder and personalize the result

**Files:**
- Modify: `lib/features/quick_assessment/services/quick_assessment_action_policy.dart`
- Modify: `lib/features/quick_assessment/screens/quick_assessment_category_screen.dart`
- Create: `lib/features/quick_assessment/widgets/quick_result_explanations.dart`
- Test: `test/features/quick_assessment/quick_assessment_action_policy_test.dart`
- Test: `test/features/quick_assessment/quick_assessment_category_action_test.dart`
- Test: `test/features/quick_assessment/quick_result_visuals_test.dart`

**Interfaces:** New result widgets consume `QuickAssessmentResult`, `QuickIndicatorCopy`, and the existing `QuickAssessmentActionPolicy`; existing routes and callbacks stay in the screen.

- [ ] **Step 1: Write failing tests** for exact next-step headings/guidance in spec §5.4 and visual order in §6: small role caption, 96 px illustration, prominent pattern, summary, next-step card, grouped indicators, legend, footnote, Home action. Pin “You answered” and “Why it matters” to each selected option; for saved `quick_v2` data, use the saved option ID or a neutral fallback rather than falsely labeling an old answer with new wording. Test 360 px width and high/very-high PACC prompt exactly once.
- [ ] **Step 2: Run the three targeted Dart test files red.**
- [ ] **Step 3: Update action-policy copy; build focused result widgets; replace the current `_DecisionContent` order and old lists.** Keep existing buttons, conditions, and navigation. Match exact support line, Full Assessment note, PACC dialog body, legend title, hero caption, and footnote from spec.
- [ ] **Step 4: Run the three targeted tests green.**
- [ ] **Step 5: Commit** with `feat(quick-assessment): prioritize and explain result`.

### Task 6: Panel rationale and acceptance gate

**Files:**
- Create: `docs/quick_assessment_rationale.md`
- Test: all Quick Assessment Dart tests and Functions tests

**Interfaces:** The rationale is explanatory documentation; no runtime interface.

- [ ] **Step 1: Write the five-question rationale from spec §7**, naming the screening area each is based on and explicitly saying the custom items are not formally validated and need PACC review.
- [ ] **Step 2: Run `flutter analyze`, `flutter test --dart-define=APP_ENV=staging`, `npm test`, and `npm run build` in `functions/`; fix only failures caused by this work and rerun them.**
- [ ] **Step 3: Build staging APK with the agreed Mood V2 flags; install on the connected device and check the five question screens and a fresh result.** A fresh staging result requires the matching Functions revision; if it has not been deployed, use local tests for copy parity and report device result verification as pending.
- [ ] **Step 4: Commit** the rationale and any necessary test updates with `docs(quick-assessment): explain five-question rationale`.

## Execution note

Create a new branch from `feat/assessment-polish-42-46` before Task 1 so the reviewed 38–46 work stays included. The approved 36–37 spec was copied from its design-only branch into this worktree because that branch diverged from the later implementation chain. Do not merge the old design-only branch blindly.

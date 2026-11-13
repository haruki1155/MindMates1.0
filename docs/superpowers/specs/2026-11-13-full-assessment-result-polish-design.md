# Items 42–46: Full Well-being Assessment polish

Status: for approval. Branch `feat/assessment-polish-42-46`, cut from `feat/home-polish-40-41` (PR #18), because item 46 edits the same Home file.

## 1. Intent

Five panel items on the Full Well-being Assessment. The user's framing: *"only cosmetic changes needed to improve UI and layout so that the app looks professional."*

- **42** Result: use visual illustrations, expandable for the explanation.
- **43** Result: remove the "Response completeness" section.
- **44** Start: add the disclaimer from the "How this result was created?" statements.
- **45** Result: add a "Review Responses" button while keeping the appointment button.
- **46** Assessment limit reached: count the days to try again from Monday to Friday.

Four of the five are presentation only. **Item 46 is the one behaviour change**, and only because the panel asked for the counting itself to be fixed.

## 2. How it works today (verified on `feat/home-polish-40-41`)

### The result screen

- The live Full Assessment result is `_StudentV4ProfileView` (`lib/features/student_assessment/screens/student_assessment_complete_screen.dart:464`), reached when `AssessmentProvider.isV4FullAssessment` is true. That flag requires `AppEnvironmentConfig.isStaging`, so **V4 is the screen the panel reviewed and runs on staging**. Production still shows the older view in the same file (`_Hero`, `_SummaryCards`, `_CategoryBars`, `_ResultActions`).
- Its sections, in order: Overall Well-Being Status, Assessment Summary, What Your Responses Suggest Overall, Strengths, Focus Areas, Well-Being Areas, Suggested Next Steps, Assessment Responses, References & Resources, About This Result, then "Book a PACC appointment" and "Continue".
- Each well-being area is a `_V4DomainReflectionCard` (`:685`), already an `ExpansionTile` with a status pill, a two-line summary and up to four details: What to notice, Supportive pattern, A practical next step, Reflection prompt. **There is no illustration.**
- The saved answers render inline through `V4AssessmentResponseReview` (`:601`), which makes the result page very long.

### "Response completeness"

- There is no longer a section with that title; tests already assert it is absent (`test/features/student_assessment/student_v4_completion_test.dart:280`).
- What remains is the **last sentence of the overall summary**, written by the Cloud Functions: `functions/src/assessment/student_v4_calculator.ts:106` and `workplace_v4_calculator.ts:85` end with `You answered X of Y questions, giving this result <confidence> response completeness.`
- That text is stored in the saved record and displayed in two places: the result screen (`:486`, `:532`) and the Mental Health Report (`lib/features/profile/screens/mental_health_report_screen.dart:347`).
- Separately, the older production view has its own **"Response confidence"** card (`student_assessment_complete_screen.dart:1163`).

### Starting the assessment

- `StudentAssessmentScreen` (`lib/features/student_assessment/screens/student_assessment_screen.dart:28`) calls `ensureStudentAssessmentStarted` in `initState` and shows question 1 immediately. There is no intro.
- Six places push `RouteNames.studentAssessment`: Home, MindAid page, the MindAid launcher, three in the Quick Assessment result, and the complete screen's retry.
- "How this result was created" was removed from the result; its statements survive only in `docs/superpowers/specs/2026-09-28-full-assessment-result-v4-design.md` (50 questions, five domains, seven-day recall, four-point scale, server-authoritative deterministic calculation, generative AI not used) and in the saved `interpretation['disclaimer']`.

### The limit

- `AssessmentRepository` constants (`lib/repositories/assessment_repository.dart:36-38`): limit 2, window 7 days, minimum interval 2 days.
- `FullAssessmentEligibility.fromCompletedDates` (`:481`) adds plain `Duration`s, so `nextEligibleAt` can land on a Saturday or Sunday.
- The dialog is `_showAssessmentLimitDialog` (`lib/features/home/screens/home_screen.dart:888`), with `_formatEligibilityDate` (`:943`) naming the weekday.

## 3. Goals

1. The five area cards carry an illustration tinted by status, and still expand to the explanations they already hold.
2. No screen mentions response completeness or confidence, including results saved before this change.
3. Anyone starting the Full Assessment sees the disclaimer first and has to acknowledge it.
4. The result offers **Review Responses** beside the appointment button, and the long answer list moves behind it.
5. The wait between attempts is counted in school days, and the date shown is never a weekend.

## 4. Non-goals and anti-goals

**Non-goals**
- No Cloud Functions, Firestore rules, index or deploy changes.
- No change to questions, scoring, status thresholds, domain names or the meaning of a result.
- No change to the Mood V2 work, Home streak work (items 38–41) or the quick assessment.
- No redesign of the older production result view beyond removing its "Response confidence" card.

**Anti-goals**
- Decorative illustrations that obscure the status: the pill stays, and colour is never the only signal.
- A disclaimer so long that users skip it.
- Any wording that implies clinical validation, diagnosis, or that a result is a performance measure.
- Making the limit stricter than the panel asked: only the wait is recounted, not the number of attempts.

## 5. Approaches

- **A (chosen): all in the app, one PR.** The completeness sentence is removed where it is displayed, so old and new results are both clean with no deploy. The disclaimer lives in the app. Illustrations are Material icons tinted by status. Weekday counting goes in the eligibility rule.
  - Trade-off: the sentence stays inside the stored record, where nothing displays it.
- **B: app plus Cloud Functions.** Also edit the two calculators. Rejected: it needs a Functions deploy that the team's own documents gate tightly, it collides with PR #16 which also touches Functions, and old results would still need the app-side fix.
- **C: two PRs, quick fixes then illustrations.** Rejected: the look is settled before coding, so splitting buys an extra review round for nothing.

## 6. Design

### 6.1 Item 42 — illustrated, expandable areas

`_V4DomainReflectionCard` keeps its `ExpansionTile`, key and content, and gains:

- A **52 px circular tile** at the leading edge: the status colour at 18 % opacity, holding a 26 px Material Rounded icon in the full status colour.
- **Icon per area** (`domainId`), with a fallback so an unknown id still renders:

  | domainId | Icon |
  | --- | --- |
  | `academic` | `menu_book_rounded` |
  | `financial` | `savings_rounded` |
  | `socialAdjustment` | `groups_rounded` |
  | `sleepRest` | `bedtime_rounded` |
  | `emotionalWellbeing` | `favorite_rounded` |
  | `teachingWorkloadDemands`, `nonTeachingWorkloadDemands` | `work_outline_rounded` |
  | `teachingSupport`, `nonTeachingSupport` | `diversity_3_rounded` |
  | `teachingEngagementMeaning`, `nonTeachingEngagementMeaning` | `emoji_objects_rounded` |
  | anything else | `insights_rounded` |

- **Status colour** from `domain['status']`: `supported` `#2F7D6D`, `mostlySupported` `#5E95BC`, `someStrain` `#E09B2D`, `supportMayHelp` `#C0603A`, unknown `#6C665B`. The pill keeps its current label text and gains the matching tint.
- The expanded body gets a **3 px bar in the status colour** down its left edge, so an opened card reads as one block.
- The icon is decorative: it is wrapped so screen readers announce the area name and status, not the icon.

### 6.2 Item 43 — remove response completeness

**Scope, decided by the user: student-facing screens only.** PACC and admin keep the answered count, because it tells a counselor how much of an assessment a student finished before they read the result.

- New pure helper, `String withoutResponseCompleteness(String summary)`, in `lib/features/student_assessment/services/assessment_summary_text.dart`.
  - It removes a trailing sentence that mentions response completeness, matching case-insensitively on "you answered" … "response completeness", and trims the leftover whitespace.
  - A summary without that sentence is returned unchanged.
- The sentence lives in `interpretation['overallResponseSummary']`, not `userSummary`. Apply the helper to that field in both places that render it: the result screen (`student_assessment_complete_screen.dart:486-487`, shown at `:532`) and the Mental Health Report (`mental_health_report_screen.dart:346-348`).
- The Mental Health Report also appends the confidence to a separate metadata line (`:640-645`). Drop the `responseConfidence` part there; keep the rest of the line.
- The older student view's **"Response confidence" card is deleted** from `_SummaryCards` (`:1163`).
- **Unchanged on purpose:** `AssessmentInterpretationEngine` writes "Response confidence: …" into `counselorSummary` (`assessment_interpretation_engine.dart:133-137`), and the admin result view shows its own chip and "X of Y answered" line (`admin_assessment_detail_screen.dart:126-168`, `:410`). Both are counselor-facing and stay.

### 6.3 Item 44 — disclaimer before starting

- `StudentAssessmentScreen` gains a first stage. While it is unacknowledged, the screen shows **Before you start** and does **not** call `ensureStudentAssessmentStarted`, so no session or draft is created until the user agrees. This covers all six entry points without touching any of them.
- Content: a card titled **How this assessment works**, each line with a small amber icon. **Two of the five statements are only true on the V4 build**, because production still runs the legacy instrument (~160 items across the role sets, interpreted on the device by `assessment_interpretation_engine.dart`). The user chose to match the copy to the build, so the list is:

  | Statement | Shown when |
  | --- | --- |
  | "This is a 50-question reflection across five well-being areas." | `isV4FullAssessment` only |
  | "Your result is calculated on our secure server using a fixed, published method." | `isV4FullAssessment` only |
  | "It asks about how things have felt recently, using a simple agreement scale." (V4 wording: "about the past 7 days, using a four-point agreement scale") | always |
  | "Generative AI is not used to decide your result." | always |
  | "This is a non-clinical well-being reflection, not a diagnosis or a mental-health test." | always |

  A statement is never shown on a build where it is untrue. The gate itself appears on both builds.
- Below it, a muted note: "This is a custom university well-being reflection and is not clinically validated. If you are in distress, PACC is here to help." (V4 builds name MindMate V4.)
- Buttons: filled **I understand, start assessment**, and outlined **Not now**.
- *My call:* **Not now** pops when it can, and otherwise returns to Home with `pushNamedAndRemoveUntil(RouteNames.home)`. The result screen's retry uses `pushReplacementNamed` (`student_assessment_complete_screen.dart:68`), so a bare pop there would drop the user onto whatever is underneath. No call site changes.
- *My call:* the gate is skipped when an answering session is already in progress for the same user, because `ensureStudentAssessmentStarted` resumes rather than restarts. Re-entering at question 21 goes straight back to question 21.
- *My call, agreed with the user:* otherwise it appears every time the assessment is started, not once per user. Nothing is persisted.

### 6.4 Item 45 — Review Responses

- New screen `AssessmentSavedResponsesScreen` (`lib/features/student_assessment/screens/assessment_saved_responses_screen.dart`), app bar "Your responses", hosting the existing `V4AssessmentResponseReview` with the same three inputs.
- The result screen drops its inline "Assessment Responses" heading and list, and gains an outlined **Review Responses** button with a checklist icon, placed directly above the existing **Book a PACC appointment**, with **Continue** last.
- The appointment button keeps its current wording. *My call:* the panel's "Schedule Appointment" names the button, and renaming it would diverge from the same button elsewhere in the app.

### 6.5 Item 46 — school-day counting

- New pure helpers in `lib/repositories/assessment_repository.dart`, beside the eligibility class. Both work in local time, like the existing code, which reads `Timestamp.toDate()`:
  - `DateTime addSchoolDays(DateTime from, int days)` — advances day by day, counting only Monday to Friday.
  - `DateTime nextSchoolDay(DateTime date)` — returns the date itself when it is a weekday, otherwise the following Monday.
- *My call: both return the **start of that day**, midnight local.* Today the eligible instant keeps the submission's clock time, so the dialog prints "…at 4:32 PM". "Try again on Tuesday" should mean Tuesday morning, not Tuesday teatime. `_formatEligibilityDate` (`home_screen.dart:943-974`) therefore drops its time portion and prints the date only.
- `FullAssessmentEligibility.fromCompletedDates` uses `addSchoolDays(last, 2)` for the minimum interval instead of adding 2 calendar days, and passes both candidates through `nextSchoolDay`, so the rolling-window date also never lands on a weekend. The attempt count and the 7-day window itself are unchanged.
- The dialog text becomes: "You can take the full assessment up to 2 times in 7 days, with 2 school days between attempts. Try again on {date}." plus a muted line: "School days are Monday to Friday, so weekends are not counted."
- The same wording is used by the Quick Assessment result's limit dialog (`lib/features/quick_assessment/screens/quick_assessment_category_screen.dart:448`) if it states the same rule. *Left to the builder:* check it and keep the two consistent.
- **Known boundary.** The callable still enforces a 2-calendar-day minimum server-side (`functions/src/assessment/submissions.ts:277`). School days are always at least as long as calendar days, so the app blocks before the server ever would and the two can never disagree in practice. Aligning the server is a follow-up for whoever owns Functions, and is named in the pull request.

## 7. Constraints

- Stacked on PR #18; its PR targets `main` once #17 and #18 are merged.
- CI must stay green: `flutter analyze`, `flutter test --dart-define=APP_ENV=staging`, the staging APK build, Functions tests.
- V4 screens need the six Mood V2-independent assessment checks to run on the staging define; existing V4 tests live in `test/features/student_assessment/student_v4_completion_test.dart` and `test/features/profile/profile_screen_test.dart`.
- Never commit regenerated `pubspec.lock`, `linux`, `macos` or `windows` files; format only the touched files.
- Colour contrast: status colours are used on white at 18 % tint behind a full-strength icon, and the pill text stays at full strength.

## 8. Decisions

### Decided by the user
1. **The disclaimer matches the build.** The question-count and server statements appear only where they are true, on V4. The gate itself appears on both builds.
2. **Completeness goes from student screens only.** PACC and admin keep the answered count.

### My calls (for the user to check)
3. The completeness sentence is removed **where it is shown**, not at the source, so old saved results are clean too and nothing needs a deploy. The stored record keeps the sentence.
4. The older student view's "Response confidence" card is removed as well, and so is the confidence on the Mental Health Report's metadata line.
5. The disclaimer is shown every time the assessment is started, but skipped when a part-finished session is being resumed. The session is created only after it is acknowledged.
6. **Not now** pops where it can, and otherwise returns to Home, because one entry point replaces the screen it came from.
7. The appointment button keeps "Book a PACC appointment".
8. The saved answers move off the result page and behind **Review Responses**, which is what makes room for the illustrated areas.
9. School-day counting applies to the 2-day wait, and any resulting weekend date moves to Monday. The limit of 2 in 7 days is unchanged.
10. The eligible moment becomes the **start** of that school day, and the dialog prints a date with no time.
11. The server keeps its own 2-calendar-day rule. The app is always the stricter of the two, so they cannot disagree; aligning the server is a follow-up.

## 9. Files

- `lib/features/student_assessment/screens/student_assessment_complete_screen.dart` — illustrated area cards, summary helper, inline responses removed, Review Responses button, "Response confidence" card deleted.
- New `lib/features/student_assessment/services/assessment_summary_text.dart` — `withoutResponseCompleteness`.
- New `lib/features/student_assessment/widgets/assessment_domain_illustration.dart` — icon and colour per area and status.
- New `lib/features/student_assessment/screens/assessment_saved_responses_screen.dart`.
- `lib/features/student_assessment/screens/student_assessment_screen.dart` — the Before you start stage.
- `lib/features/profile/screens/mental_health_report_screen.dart` — apply the summary helper, and drop the confidence from the metadata line.
- `lib/repositories/assessment_repository.dart` — school-day helpers and eligibility.
- `lib/features/home/screens/home_screen.dart` — limit dialog wording.
- Tests: new unit tests for the summary helper and the school-day helpers; widget tests for the illustrated cards, the Before you start gate, the Review Responses route, and the dialog wording; updates to `student_v4_completion_test.dart` and `profile_screen_test.dart` where they pin the old layout.

# UI Polish Items 31–35 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship five small UI fixes in the user-facing MindMate Flutter app: remove the sign-up rules modal, show "not verified" in red, drop the redundant Quick Assessment name step, replace placeholder role icons with real icons, and add icons, an illustration and a legend to the Quick Assessment result.

**Architecture:** All five changes are presentation-layer edits inside `lib/features/authentication/screens/` and `lib/features/quick_assessment/`. The one non-UI change is a single new `AssessmentProvider.beginQuickAssessment(...)` method. It replaces the name step by taking the name from the signed-in profile. Scoring, Firestore payloads, Cloud Functions, routes other than the name route, and copy outside the listed strings stay unchanged.

**Tech Stack:** Flutter (Material 3 `Icons`), `provider`, `flutter_test`.

**Spec (verbatim from the request):**
```
31. Create account > Before you create account modal > Remove the modal displaying the rule.
32. Verify email > Use color red for the not yet verified label.
33. Quick Assessment > remove redundant fields for name
34. Quick Assessment > Use proper icon for choices
35. Quick Assessment Result > Use icons and illustrations to show indicators & use legends
```

**Scope note:** The request says "admin web", but none of these screens are in `lib/features/admin/`. They are the end-user app screens: `SignupScreen`, `EmailVerificationScreen` and the `quick_assessment` feature. This plan targets those screens.

---

## Agent Prompt (paste this to the executing agent)

> You are implementing `docs/superpowers/plans/2026-11-11-ui-polish-items-31-35.md` in `c:\src\MindMates1.0` (Flutter, Windows, PowerShell + Git Bash available). Read the whole plan first, including Global Constraints and Review Focus. Run the tasks in order (Task 3 must land before Task 5, because Task 5's test uses `beginQuickAssessment`). Use TDD: write the failing test, run it and watch it fail, implement, run it again and watch it pass, then commit. Touch **only** the files listed in each task's **Files** block. The working tree already holds unrelated uncommitted changes (`functions/`, `linux/`, `macos/`, `windows/`, `README.md`, `mind_mates_clean/`, etc.). Never `git add -A`, `git add .`, `git stash` or `git checkout --` them; stage files by explicit path only. Do not change copy, colors, scoring, routes or providers beyond what a step names. If a step is ambiguous or a listed line number has drifted, locate the code by the quoted snippet. If the snippet is missing, stop and report instead of guessing. Finish with `flutter analyze` (no new issues) and the full verification command in "Final Verification", and paste their output.

---

## Global Constraints

- Branch first: `git switch -c fix/ui-polish-31-35` from `main`.
- Stage by explicit path only; leave every pre-existing modified or untracked file untouched and unstaged.
- No new packages, no new image assets, no `pubspec.yaml` edits. Icons come from Flutter's built-in `Icons` set.
- Do not change any user-visible string except where a step explicitly says so.
- Do not modify `functions/`, `firestore.rules`, `lib/features/admin/`, `mind_mates_clean/`, or the quick-assessment scoring and `QuickAssessmentActionPolicy`.
- Red for "not verified" = the existing token `AppColors.error` (`Color(0xFFB3261E)`) from `lib/core/constants/app_colors.dart`.
- The server rejects quick-assessment names that are empty or longer than 100 chars (`functions/src/assessment/submissions.ts:168`). The auto-filled name must satisfy `1 ≤ length ≤ 100` after trim.
- Commit messages use Conventional Commits and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Profile with no first/last name** (e.g. a Google-only account): `UserModel.displayName` falls back to the email address, and the quick assessment must still submit. It must not use an empty name, and it must cap the name at 100 chars. *Pinned in Task 3 tests.*
2. **High-concern result:** with the new visuals, the PACC appointment dialog must still appear exactly once, and the indicator rows must show the "Support may be useful" chip. *Pinned in Task 5 tests.*
3. **Narrow phone width (360 px):** the longest domain ("Motivation and interest") next to the longest chip ("Support may be useful") must not overflow. *Pinned in Task 5 tests.*
4. **Verification-screen tones:** only the "not verified" status turns red. The "Verification email sent" info stays green, and network-error styling stays as it is. *Pinned in Task 2 tests.*
5. **Returning user with a stored role:** the stored-role redirect must go straight to the questions, not to the deleted name route, which would throw "Could not find a generator for route". *Pinned in Task 3 tests.*

---

### Task 1: Remove the "Before you create an account" modal (item 31)

**Files:**
- Modify: `lib/features/authentication/screens/signup_screen.dart` (the `initState` post-frame call at lines 73–75, and `_showRegistrationInstructions()` at lines 82–105)
- Test: `test/features/authentication/signup_screen_test.dart`

**Interfaces:** none produced.

- [ ] **Step 1: Write the failing test.** In `signup_screen_test.dart`, rename the helper `_dismissInstructions` to `_settleSignup` and change its body. Replace every call site (there are ~7; use find/replace on `_dismissInstructions(`):

```dart
Future<void> _settleSignup(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(find.text('Before you create an account'), findsNothing);
  expect(find.byType(AlertDialog), findsNothing);
}
```
Add one explicit test:
```dart
testWidgets('signup opens directly on the form without a rules modal', (tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_SignupHarness(authProvider: _FakeAuthProvider()));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsNothing);
  expect(find.text('Email Address'), findsWidgets);
  expect(find.text('Student account'), findsOneWidget); // inline _AccountTypeNotice still explains the rule
});
```

- [ ] **Step 2: Run it and confirm it fails.** Run `flutter test test/features/authentication/signup_screen_test.dart`. Expected: FAIL, because an `AlertDialog` / "Before you create an account" is found.

- [ ] **Step 3: Implement.** Delete the `WidgetsBinding.instance.addPostFrameCallback(...)` block in `initState` and delete the whole `_showRegistrationInstructions()` method. Keep `_emailController.addListener(_handleEmailChanged);`. Leave `_AccountTypeNotice` and `_confirmRegistrationEmail` ("Confirm your email") unchanged; they are not the rules modal.

- [ ] **Step 4: Run the tests and confirm they pass.** Same command. Expected: all tests PASS.

- [ ] **Step 5: Commit.**
```bash
git add lib/features/authentication/screens/signup_screen.dart test/features/authentication/signup_screen_test.dart
git commit -m "fix(signup): remove pre-registration rules modal"
```

---

### Task 2: Red "not verified yet" status (item 32)

**Files:**
- Modify: `lib/features/authentication/screens/email_verification_screen.dart` (`_messageIsError` state, `_checkVerification`, `_VerificationCard`, `_Status`)
- Create: `test/features/authentication/email_verification_screen_test.dart`

**Interfaces:**
- Produces (file-private): `enum _StatusTone { info, error, notVerified }`. `_Status({required String message, required _StatusTone tone})`. The `_Status` root `Container` gets `key: const Key('email-verification-status')`.

- [ ] **Step 1: Write the failing test** in the new file. The harness is a `ChangeNotifierProvider<AuthProvider>.value` wrapping `MaterialApp(home: EmailVerificationScreen())` with the fake below. Tear down with `await tester.pumpWidget(const SizedBox());` at the end of each test so the 60 s resend `Timer.periodic` is cancelled through `dispose()`.

```dart
class _FakeAuthRepository extends AuthRepository { _FakeAuthRepository() : super(AuthService()); }
class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider() : super(_FakeAuthRepository());
  @override String? get currentUserEmail => 'leo@example.com';
  @override bool get currentUserEmailVerified => false;
  @override Future<void> reloadCurrentUser() async {}
  @override Future<void> sendEmailVerification() async {}
}

testWidgets('not-verified status is shown in red', (tester) async {
  // pump harness, pumpAndSettle
  await tester.tap(find.text('I verified my email'));
  await tester.pumpAndSettle();
  final text = tester.widget<Text>(find.text('Not verified yet. Open the link in your email, then return here.'));
  expect(text.style?.color, AppColors.error);
  final icon = tester.widget<Icon>(find.descendant(of: find.byKey(const Key('email-verification-status')), matching: find.byType(Icon)));
  expect(icon.color, AppColors.error);
  await tester.pumpWidget(const SizedBox());
});

testWidgets('email-sent info status stays non-red', (tester) async {
  // pump harness, pumpAndSettle (initState auto-sends)
  final text = tester.widget<Text>(find.text('Verification email sent. Check your inbox and spam folder.'));
  expect(text.style?.color, AppColors.primary);
  await tester.pumpWidget(const SizedBox());
});
```

- [ ] **Step 2: Run it and confirm it fails.** Run `flutter test test/features/authentication/email_verification_screen_test.dart`. Expected: the first test FAILS (the color is `AppColors.primary`) and the second PASSES.

- [ ] **Step 3: Implement.** Replace `bool _messageIsError` with `_StatusTone _messageTone = _StatusTone.info`. Map the existing assignments one-to-one: every `_messageIsError = true` becomes `_StatusTone.error`, every `_messageIsError = false` becomes `_StatusTone.info`, **except** the not-verified branch in `_checkVerification`, which becomes `_StatusTone.notVerified`. Pass `tone` through `_VerificationCard` (rename its field `messageIsError` to `messageTone`). In `_Status`:

| tone | foreground | background | icon |
|---|---|---|---|
| `info` | `AppColors.primary` (unchanged) | `Color(0xFFEAF6F2)` (unchanged) | `Icons.info_outline_rounded` (unchanged) |
| `error` | `Color(0xFF923B35)` (unchanged) | `Color(0xFFFFEEEC)` (unchanged) | `Icons.error_outline_rounded` (unchanged) |
| `notVerified` | `AppColors.error` | `Color(0xFFFDECEA)` | `Icons.cancel_outlined` |

The message text stays exactly as it is.

- [ ] **Step 4: Run the tests and confirm they pass.** Same command. Expected: both tests PASS.

- [ ] **Step 5: Commit.**
```bash
git add lib/features/authentication/screens/email_verification_screen.dart test/features/authentication/email_verification_screen_test.dart
git commit -m "fix(auth): show not-verified email status in red"
```

---

### Task 3: Remove the redundant Quick Assessment name step (item 33)

The user already entered first, middle and last name at sign-up, so the "Enter Your Name" screen (`/quick-assessment/name`) re-asks for data the app already has. The step is removed and the name is taken from the profile.

**Files:**
- Modify: `lib/providers/assessment_provider.dart` (add `beginQuickAssessment`, remove the unused `nameProgressLabel` getter at lines 168–169)
- Modify: `lib/features/quick_assessment/screens/quick_assessment_role_screen.dart` (`_StoredRoleRedirectState.initState`, `_RoleContent._selectRole`)
- Modify: `lib/features/quick_assessment/widgets/quick_assessment_widgets.dart` (`QuickProgressHeader`)
- Modify: `lib/features/quick_assessment/screens/quick_assessment_question_screen.dart:82-85` (pass `total`)
- Modify: `lib/routes/app_pages.dart` (remove the `quickAssessmentName` entry and its import)
- Modify: `lib/routes/route_names.dart:12` (remove `quickAssessmentName`)
- Delete: `lib/features/quick_assessment/screens/quick_assessment_name_screen.dart`
- Test: `test/features/quick_assessment/quick_assessment_test.dart`

**Interfaces:**
- Produces: `void AssessmentProvider.beginQuickAssessment({required AssessmentRole role, required String name})`. It sets the role and the name (trimmed; `'MindMate User'` if blank; truncated to the first 100 chars), resets the question index, the selected options, `quickResult` and the prompted-appointment ids, then calls `notifyListeners()` once.
- Produces: `QuickProgressHeader({required int step, required String label, required int total})`, with fill = `step.clamp(1, total) / total`.
- Unchanged and still used: `updateName`, `isNameValid`, `name`, `calculateResult` (its name guard stays).

- [ ] **Step 1: Write the failing tests** in `quick_assessment_test.dart`:

```dart
test('beginQuickAssessment uses profile name and starts fresh', () {
  final provider = _readyProvider()..selectAnswer(QuickAssessmentQuestions.questions.first.options.first);
  provider.beginQuickAssessment(role: AssessmentRole.faculty, name: '  Leo Cruz ');
  expect(provider.selectedRole, AssessmentRole.faculty);
  expect(provider.name, 'Leo Cruz');
  expect(provider.currentQuestionIndex, 0);
  expect(provider.hasSelectedAnswer, isFalse);
  expect(provider.quickResult, isNull);
});

test('beginQuickAssessment falls back and caps the name for the server', () {
  final provider = AssessmentProvider(AssessmentRepository());
  provider.beginQuickAssessment(role: AssessmentRole.student, name: '   ');
  expect(provider.name, 'MindMate User');
  provider.beginQuickAssessment(role: AssessmentRole.student, name: 'a' * 150);
  expect(provider.name.length, 100);
});

testWidgets('choosing a role skips the name step and uses the profile name', (tester) async {
  // UserProvider user: UserModel(id: 'u1', email: 'leo@example.com', firstName: 'Leo', lastName: 'Cruz')  (no role)
  // MaterialApp(routes: {RouteNames.quickAssessmentQuestions: (_) => const _RouteMarker('questions target')}, home: QuickAssessmentRoleScreen())
  await tester.tap(find.text('Student'));
  await tester.pumpAndSettle();
  expect(find.text('questions target'), findsOneWidget);
  expect(assessmentProvider.name, 'Leo Cruz');
  expect(assessmentProvider.selectedRole, AssessmentRole.student);
});

testWidgets('stored role redirects straight to questions', (tester) async {
  // same harness; user also has role: 'faculty'
  await tester.pumpAndSettle();
  expect(find.text('questions target'), findsOneWidget);
  expect(assessmentProvider.selectedRole, AssessmentRole.faculty);
  expect(assessmentProvider.name, 'Leo Cruz');
});
```

- [ ] **Step 2: Run them and confirm they fail.** Run `flutter test test/features/quick_assessment/quick_assessment_test.dart`. Expected: compile error, because `beginQuickAssessment` is not defined.

- [ ] **Step 3: Implement.**
  - Add `beginQuickAssessment` to `AssessmentProvider` next to `selectRole`. Delete `nameProgressLabel`.
  - In the role screen, add `String _profileName(BuildContext context)`. It returns `context.read<UserProvider>().user?.displayName ?? ''`, and catches `ProviderNotFoundException` to return `''`. `_selectRole` becomes `provider.beginQuickAssessment(role: role, name: _profileName(context))` followed by `Navigator.of(context).pushNamed(RouteNames.quickAssessmentQuestions)`. `_StoredRoleRedirectState` does the same with `pushReplacementNamed(RouteNames.quickAssessmentQuestions)`.
  - Add `required this.total` to `QuickProgressHeader`. The question screen passes `total: provider.questions.length`.
  - Delete the name screen file, its import and route entry in `app_pages.dart`, and the constant in `route_names.dart`.
  - Run `flutter analyze lib test` and confirm it reports no remaining references to `quickAssessmentName`, `QuickAssessmentNameScreen` or `nameProgressLabel`.

- [ ] **Step 4: Run the tests and confirm they pass.** Run `flutter test test/features/quick_assessment/`. Expected: all tests PASS, including the existing `'requires a non-empty name'` and `'carries selected role and name into pending result data'`.

- [ ] **Step 5: Commit.**
```bash
git add lib/providers/assessment_provider.dart lib/features/quick_assessment/screens/quick_assessment_role_screen.dart lib/features/quick_assessment/screens/quick_assessment_question_screen.dart lib/features/quick_assessment/widgets/quick_assessment_widgets.dart lib/routes/app_pages.dart lib/routes/route_names.dart test/features/quick_assessment/quick_assessment_test.dart
git rm lib/features/quick_assessment/screens/quick_assessment_name_screen.dart
git commit -m "feat(quick-assessment): use profile name instead of a separate name step"
```

---

### Task 4: Real icons for the role choices (item 34)

The role-choice cards render emoji text (`'🎓'`, `'👩‍🏫'`, `'🧑‍🤝‍🧑'`) through a widget literally named `QuickPlaceholderIcon`. The result card uses the letters `'ST'`/`'FC'`/`'SF'`. Both get proper Material icons. The answer options in the questions already use dedicated PNG icons (all asset files exist and are declared in `pubspec.yaml`), so they are **out of scope** (see the open question in the handoff).

**Files:**
- Modify: `lib/features/quick_assessment/widgets/quick_assessment_widgets.dart` (replace `QuickPlaceholderIcon` with `QuickRoleIcon`, add `quickAssessmentRoleIcon`)
- Modify: `lib/features/quick_assessment/screens/quick_assessment_role_screen.dart` (`_RoleContent` cards, `_RoleCard`)
- Modify: `lib/features/quick_assessment/screens/quick_assessment_category_screen.dart` (lines 126–135 `iconFor`, lines 168–171 usage)
- Test: `test/features/quick_assessment/quick_assessment_test.dart`

**Interfaces:**
- Produces: `IconData quickAssessmentRoleIcon(AssessmentRole role)`: `student → Icons.school_rounded`, `faculty → Icons.co_present_rounded`, `staff → Icons.badge_rounded`.
- Produces: `QuickRoleIcon({Key? key, required AssessmentRole role, double size = 28})`. It keeps the old tile (56×56, `Color(0xFFFFD246)`, radius 10) and shows `Icon(quickAssessmentRoleIcon(role), size: size, color: QuickAssessmentPalette.text, semanticLabel: role.label)`.

- [ ] **Step 1: Write the failing test:**
```dart
testWidgets('role choices use Material role icons, not emoji', (tester) async {
  // pump QuickAssessmentRoleScreen with an AssessmentProvider only (no UserProvider, the preview path)
  await tester.pumpAndSettle();
  expect(find.byIcon(Icons.school_rounded), findsOneWidget);
  expect(find.byIcon(Icons.co_present_rounded), findsOneWidget);
  expect(find.byIcon(Icons.badge_rounded), findsOneWidget);
  for (final emoji in ['🎓', '👩‍🏫', '🧑‍🤝‍🧑']) { expect(find.text(emoji), findsNothing); }
});
```
- [ ] **Step 2: Run it and confirm it fails.** Run `flutter test test/features/quick_assessment/quick_assessment_test.dart`. Expected: FAIL, because no `Icons.school_rounded` is found.
- [ ] **Step 3: Implement.** Add the two interfaces to the widgets file (import `../models/quick_assessment_models.dart`) and delete `QuickPlaceholderIcon`. In `_RoleCard`, remove the `String icon` field and render `QuickRoleIcon(role: role)`. Remove the three `icon:` arguments in `_RoleContent`. In the category screen, render `QuickRoleIcon(role: role, size: 30)` and delete the static `iconFor`. Leave the `'🔒'` confidentiality line alone; it is not a choice.
- [ ] **Step 4: Run the tests and confirm they pass.** Run `flutter test test/features/quick_assessment/`. Expected: all PASS.
- [ ] **Step 5: Commit.**
```bash
git add lib/features/quick_assessment/widgets/quick_assessment_widgets.dart lib/features/quick_assessment/screens/quick_assessment_role_screen.dart lib/features/quick_assessment/screens/quick_assessment_category_screen.dart test/features/quick_assessment/quick_assessment_test.dart
git commit -m "feat(quick-assessment): replace placeholder role glyphs with Material icons"
```

---

### Task 5: Result indicators with icons, an illustration and a legend (item 35)

**Files:**
- Create: `lib/features/quick_assessment/widgets/quick_result_visuals.dart`
- Modify: `lib/features/quick_assessment/screens/quick_assessment_category_screen.dart` (the `if (provider.quickResult != null) ...[` block, lines 172–279 only)
- Create: `test/features/quick_assessment/quick_result_visuals_test.dart`

**Interfaces:**
- Consumes: `AssessmentProvider.beginQuickAssessment` (Task 3), `QuickRoleIcon` (Task 4), `AssessmentResponsePattern.labelForCode`, `AssessmentDomainResult.{domain, responsePatternCode, responsePatternLabel}`, `QuickAssessmentResult.responsePatternCode`, `QuickAssessmentScoring.concernAreasByQuestionId`.
- Produces:
  - `class QuickPatternVisual { const QuickPatternVisual({required IconData icon, required Color color, required String label}); static QuickPatternVisual forCode(String code); static const List<String> legendCodes = ['wellBeingSupported', 'generallySteady', 'someStrain', 'supportMayHelp']; }`
  - `IconData quickDomainIcon(String domain)`
  - `QuickResultIllustration({Key? key, required String patternCode})`: a 96 px circle filled with `color.withValues(alpha: 0.12)`, a 2 px `color` border, and a 52 px pattern icon. `Key('quick-result-illustration')`. Semantics label = the pattern label.
  - `QuickIndicatorRow({Key? key, required AssessmentDomainResult indicator})`: a 20 px domain icon, then the `Expanded` domain text (w700), then a rounded pill (`color` at alpha 0.12, 16 px pattern icon plus `responsePatternLabel`, `color`, fontSize 12, w800). The pill sits in `Flexible` so long labels wrap instead of overflowing. Callers key it `ValueKey('quick-indicator-${indicator.domain}')`.
  - `QuickPatternLegend({Key? key})`: the title `'Legend'` (w900) and a `Wrap(spacing: 12, runSpacing: 8)` of the 4 `legendCodes`, each an icon (16) plus a label in its color. `Key('quick-pattern-legend')`.

Fixed values (code → icon, color; label always from `AssessmentResponsePattern.labelForCode(code)`):

| code | icon | color |
|---|---|---|
| `wellBeingSupported` | `Icons.sentiment_very_satisfied_rounded` | `Color(0xFF2E7D32)` |
| `generallySteady` | `Icons.sentiment_satisfied_rounded` | `Color(0xFF00897B)` |
| `someStrain` | `Icons.sentiment_neutral_rounded` | `Color(0xFFB26A00)` |
| `supportMayHelp` | `Icons.volunteer_activism_rounded` | `Color(0xFFC62828)` |
| anything else | `Icons.help_outline_rounded` | `Color(0xFF757575)` |

Domain icons: `'Emotional calm' → Icons.spa_rounded`, `'Stress load' → Icons.monitor_heart_rounded`, `'Social connection' → Icons.groups_rounded`, `'Motivation and interest' → Icons.emoji_objects_rounded`, `'Daily coping' → Icons.self_improvement_rounded`, anything else `→ Icons.insights_rounded`.

- [ ] **Step 1: Write the failing tests** in the new file. Build the result with `AssessmentProvider(AssessmentRepository())..beginQuickAssessment(role: AssessmentRole.student, name: 'Leo')`, then for each question call `selectAnswer(<option>)` and `moveToNextQuestion()`. Pump `ChangeNotifierProvider<AssessmentProvider>.value(value: p, child: MaterialApp(home: QuickAssessmentCategoryScreen()))`; only `AssessmentProvider` is read during build.

```dart
test('QuickPatternVisual maps every code and falls back', () {
  expect(QuickPatternVisual.forCode('wellBeingSupported').icon, Icons.sentiment_very_satisfied_rounded);
  expect(QuickPatternVisual.forCode('supportMayHelp').color, const Color(0xFFC62828));
  expect(QuickPatternVisual.forCode('supportMayHelp').label, 'Support may be useful');
  expect(QuickPatternVisual.forCode('bogus').icon, Icons.help_outline_rounded);
});

testWidgets('low-concern result shows illustration, per-indicator icons and legend', (tester) async {
  // answers: options.first for every question (lowest concern -> 'wellBeingSupported')
  await tester.binding.setSurfaceSize(const Size(900, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // pump, pumpAndSettle
  expect(find.descendant(of: find.byKey(const Key('quick-result-illustration')), matching: find.byIcon(Icons.sentiment_very_satisfied_rounded)), findsOneWidget);
  for (final domain in QuickAssessmentScoring.concernAreasByQuestionId.values) {
    final row = find.byKey(ValueKey('quick-indicator-$domain'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.byIcon(quickDomainIcon(domain))), findsOneWidget);
  }
  final legend = find.byKey(const Key('quick-pattern-legend'));
  for (final code in QuickPatternVisual.legendCodes) {
    expect(find.descendant(of: legend, matching: find.text(AssessmentResponsePattern.labelForCode(code))), findsOneWidget);
  }
  expect(find.byIcon(Icons.school_rounded), findsOneWidget);
  expect(find.text('ST'), findsNothing);
});

testWidgets('high-concern result at 360px: no overflow, prompt still shown once', (tester) async {
  // answers: options.last for every question
  await tester.binding.setSurfaceSize(const Size(360, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // pump, pumpAndSettle
  expect(tester.takeException(), isNull);
  expect(find.text('Would you like to talk with a PACC counselor?'), findsOneWidget);
  await tester.tap(find.text('No, Continue'));
  await tester.pumpAndSettle();
  expect(find.descendant(of: find.byKey(const ValueKey('quick-indicator-Stress load')), matching: find.byIcon(Icons.volunteer_activism_rounded)), findsOneWidget);
});
```

- [ ] **Step 2: Run them and confirm they fail.** Run `flutter test test/features/quick_assessment/quick_result_visuals_test.dart`. Expected: compile error, because `quick_result_visuals.dart` does not exist.

- [ ] **Step 3: Implement.** Create `quick_result_visuals.dart` with the interfaces above. In the category screen's `quickResult != null` block, make only these three changes and keep every existing `Text`, its order and its styling:
  1. Insert `const SizedBox(height: 12), QuickResultIllustration(patternCode: provider.quickResult!.responsePatternCode),` between the `'Your quick well-being profile'` title and the `responsePatternLabel` text.
  2. Replace the per-indicator `Padding(... Row(...))` loop body with `Padding(padding: const EdgeInsets.only(top: 8), child: QuickIndicatorRow(key: ValueKey('quick-indicator-${indicator.domain}'), indicator: indicator))`.
  3. Insert `const SizedBox(height: 14), const QuickPatternLegend(),` immediately before `const Divider(height: 28)`.

- [ ] **Step 4: Run the tests and confirm they pass.** Run `flutter test test/features/quick_assessment/`. Expected: all PASS, including the existing `quick_assessment_category_action_test.dart`.

- [ ] **Step 5: Commit.**
```bash
git add lib/features/quick_assessment/widgets/quick_result_visuals.dart lib/features/quick_assessment/screens/quick_assessment_category_screen.dart test/features/quick_assessment/quick_result_visuals_test.dart
git commit -m "feat(quick-assessment): add indicator icons, result illustration and legend"
```

---

## Final Verification

- [ ] `flutter analyze` → no new issues compared with `main`.
- [ ] `flutter test test/features/authentication test/features/quick_assessment` → all PASS, then `flutter test` (full suite) → all PASS. Paste both summary lines.
- [ ] `git status --short` → the only differences from the pre-existing dirty state are the files named in Tasks 1–5.
- [ ] Manual smoke test (optional, `flutter run`): sign up (no modal), then verify email and tap "I verified my email" before verifying (red status). Then: Quick Assessment role → questions (no name screen, progress bar reaches full on 5/5) → result (illustration, icons, legend).

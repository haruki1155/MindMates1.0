# Items 31 & 32 — Sign-up Rules Modal and Email Verification Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the `mind_mates_clean` app, stop showing the "Before you create an account" rules pop-up on the Create Account screen. Add a red "Not yet verified" status label to the Verify Email screen that turns green once the email is verified.

**Architecture:** Both changes are presentation-only, each inside one existing screen file: `signup_screen.dart` and `email_verification_screen.dart` under `lib/features/authentication/screens/`. No provider, repository, route, Firebase or Cloud Functions code changes. Task 3 is a build prerequisite that is only needed to run the app on an Android phone. It is committed separately so it can be dropped.

**Tech Stack:** Flutter (Material 3), `provider`, `flutter_test`.

**Spec (verbatim from the user):**
```
31. Create account > Before you create account modal > Remove the modal displaying the rule.
32. Verify email > Use color red for the not yet verified label.
    Clarified by the user: "it should be color red and when verified it will turn green."
```

**Project:** `c:\src\MindMates1.0\mind_mates_clean` is the project the user builds and runs. It is its own git repo on `main` at `242b156`. Do **not** touch the outer `c:\src\MindMates1.0` repo.

---

## Agent Prompt (paste this to the executing agent)

> Implement `docs/superpowers/plans/2026-11-11-signup-modal-and-verify-status.md` inside `c:\src\MindMates1.0\mind_mates_clean` (Flutter, Windows; Git Bash and PowerShell are available). This folder is its own git repository. Run every command from inside it, and never modify or commit anything in the parent `c:\src\MindMates1.0` repo. Read the whole plan first, including Global Constraints and Review Focus. Run the tasks in order. Use TDD on every task: write the test, run it and watch it fail for the stated reason, implement, run it and watch it pass, then commit. Touch only the files in each task's **Files** block, and stage by explicit path (never `git add -A` or `git add .`). Use the Edit tool for source changes, not `sed`. The source files use CRLF line endings, so keep them. Do not change any copy, color, route or behavior that a step doesn't name. If a quoted snippet can't be found, stop and report. Finish with "Final Verification" and paste the real command output.

---

## Global Constraints

- Work on a new branch: `git switch -c fix/signup-verify-31-32` from `main` in `mind_mates_clean`.
- First-time setup: run `flutter pub get` in `mind_mates_clean` (it has no `.dart_tool/` yet).
- Red = `AppColors.error` (`Color(0xFFB3261E)`, `lib/core/constants/app_colors.dart`). Green = `Color(0xFF2E7D32)`, added as `_Colors.verified` in `email_verification_screen.dart`. Do **not** edit `app_colors.dart`.
- Exact new copy: `'Not yet verified'` and `'Email verified'`. All other strings stay unchanged.
- No new packages, assets or `pubspec.yaml` edits.
- Commit messages: Conventional Commits, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **The user taps "I verified my email" after verifying:** the label must visibly turn green before the screen moves on to Profile Setup. Navigating instantly would make green impossible to see. *Pinned in Task 2 (hold before navigation).*
2. **A double tap during that green hold:** must not push Profile Setup twice or re-trigger checks. All buttons are disabled once verified. *Pinned in Task 2.*
3. **Network error while checking:** the label stays red ("Not yet verified"), and the error message keeps its existing dark-red error styling. *Pinned in Task 2.*
4. **"Verification email sent" info message:** must stay the existing teal `AppColors.primary`. Only verification *status* uses red or green. *Pinned in Task 2.*
5. **Google sign-up path:** it uses the same `SignupScreen` and `initState`, so the pop-up must not appear there either. Removing the call in `initState` covers both paths. *Pinned in Task 1 (`find.byType(AlertDialog)` on open).*

---

### Task 1: Remove the "Before you create an account" pop-up (item 31)

**Files:**
- Modify: `lib/features/authentication/screens/signup_screen.dart` (the `initState` post-frame callback at lines 73–75, and `_showRegistrationInstructions()` at lines 82–105)
- Test: `test/features/authentication/signup_screen_test.dart`

**Interfaces:** none.

- [ ] **Step 1: Write the failing test.** In `signup_screen_test.dart`, rename the helper `_dismissInstructions` to `_settleSignup` at all 8 call sites and its definition. Replace the helper body with:
```dart
Future<void> _settleSignup(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(find.text('Before you create an account'), findsNothing);
  expect(find.byType(AlertDialog), findsNothing);
}
```
Add this as the first test in `main()`:
```dart
testWidgets('signup opens directly on the form without a rules modal', (tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_SignupHarness(authProvider: _FakeAuthProvider()));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsNothing);
  expect(find.text('Email Address'), findsWidgets);
});
```
- [ ] **Step 2: Run it and confirm it fails.** Run `flutter test test/features/authentication/signup_screen_test.dart`. Expected: FAIL, because an `AlertDialog` / "Before you create an account" is found.
- [ ] **Step 3: Implement.** Delete the `WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _showRegistrationInstructions(); });` block from `initState` (keep `_emailController.addListener(_handleEmailChanged);`), and delete the whole `_showRegistrationInstructions()` method. Do not touch `_AccountTypeNotice` (the inline yellow box), `_confirmRegistrationEmail` ("Confirm your email"), or the Terms dialog.
- [ ] **Step 4: Run the tests and confirm they pass.** Same command. Expected: `All tests passed!` (9 tests).
- [ ] **Step 5: Commit.**
```bash
git add lib/features/authentication/screens/signup_screen.dart test/features/authentication/signup_screen_test.dart
git commit -m "fix(signup): remove pre-registration rules modal"
```

---

### Task 2: Red/green verification status label (item 32)

**Files:**
- Modify: `lib/features/authentication/screens/email_verification_screen.dart`
- Create: `test/features/authentication/email_verification_screen_test.dart`

**Interfaces (all file-private):**
- `enum _StatusTone { info, error, notVerified, verified }` replaces `bool _messageIsError` in the state, in `_VerificationCard` (field `messageTone`) and in `_Status` (field `tone`).
- `bool _verified = false;` lives in the state, and `_busy` becomes `_checking || _sending || _cancelling || _verified`.
- `static const _verifiedHoldDuration = Duration(milliseconds: 1200);` lives in the state.
- `_VerificationBadge({required bool verified})`, keyed `Key('email-verification-badge')`, is rendered in `_VerificationCard` directly under the email `Container` (after its closing, before `SizedBox(height: 20)`), with `SizedBox(height: 12)` above it. `_VerificationCard` gets a new `required bool verified` field.
- The `_Status` root `Container` gets `key: const Key('email-verification-status')`.

Fixed values:

| | text | foreground | background | icon |
|---|---|---|---|---|
| badge, not verified | `'Not yet verified'` | `AppColors.error` | `Color(0xFFFDECEA)` | `Icons.cancel_outlined` |
| badge, verified | `'Email verified'` | `_Colors.verified` (`Color(0xFF2E7D32)`) | `Color(0xFFE8F5E9)` | `Icons.verified_rounded` |
| `_Status` `info` | unchanged | `AppColors.primary` | `Color(0xFFEAF6F2)` | `Icons.info_outline_rounded` |
| `_Status` `error` | unchanged | `Color(0xFF923B35)` | `Color(0xFFFFEEEC)` | `Icons.error_outline_rounded` |
| `_Status` `notVerified` | unchanged | `AppColors.error` | `Color(0xFFFDECEA)` | `Icons.cancel_outlined` |
| `_Status` `verified` | `'Email verified. Continuing to your profile…'` | `_Colors.verified` | `Color(0xFFE8F5E9)` | `Icons.check_circle_outline_rounded` |

Badge style: a pill (`BorderRadius.circular(99)`, padding `h12 v7`) holding a `Row(mainAxisSize: min)` of an Icon (size 16) and Text (fontSize 12.5, `FontWeight.w800`), both in the foreground color. Add `Semantics(label: <text>)`.

The new `_checkVerification` flow:
- **Verified:** `setState(() { _verified = true; _checking = false; _messageTone = _StatusTone.verified; _message = 'Email verified. Continuing to your profile…'; })`. Setting `_checking = false` keeps the button label "I verified my email", and `_verified` keeps it disabled. then `await Future.delayed(_verifiedHoldDuration)`, then `if (!mounted) return;`, then navigate exactly as today (`pushNamedAndRemoveUntil(RouteNames.profileSetup, (route) => false)`).
- **Not verified:** `_messageTone = _StatusTone.notVerified`. The text stays the same.
- **Catch:** `_StatusTone.error`. `_verified` stays `false`.
- **Every other existing assignment:** `_messageIsError = true` becomes `_StatusTone.error`, and `_messageIsError = false` becomes `_StatusTone.info`.
- The `finally` block stays as it is.

- [ ] **Step 1: Write the failing tests** in the new file. Harness: `ChangeNotifierProvider<AuthProvider>.value(value: fake, child: MaterialApp(routes: {RouteNames.profileSetup: (_) => const Scaffold(body: Text('profile setup target'))}, home: const EmailVerificationScreen()))`, at surface size `Size(600, 1400)`. End every test with `await tester.pumpWidget(const SizedBox());` so the 60 s resend `Timer.periodic` is cancelled via `dispose()`.
```dart
class _FakeAuthRepository extends AuthRepository { _FakeAuthRepository() : super(AuthService()); }
class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider() : super(_FakeAuthRepository());
  bool verified = false;
  Object? reloadError;
  @override String? get currentUserEmail => 'leo@example.com';
  @override bool get currentUserEmailVerified => verified;
  @override Future<void> reloadCurrentUser() async { if (reloadError != null) throw reloadError!; }
  @override Future<void> sendEmailVerification() async {}
}
Finder badgeText(String t) => find.descendant(of: find.byKey(const Key('email-verification-badge')), matching: find.text(t));
```
Tests (names and assertions):
1. `'opens with a red Not yet verified badge'`: `badgeText('Not yet verified')` finds one; its `Text.style.color == AppColors.error`; the badge contains `find.byIcon(Icons.cancel_outlined)`; `find.text('Email verified')` finds nothing.
2. `'unverified check keeps badge red and shows red message'`: tap `'I verified my email'`, `pumpAndSettle`. The badge is still `'Not yet verified'` (red). The `Text` for `'Not verified yet. Open the link in your email, then return here.'` has color `AppColors.error`.
3. `'verified check turns the badge green, then opens profile setup'`: set `fake.verified = true`, tap `'I verified my email'`, `await tester.pump()`. `badgeText('Email verified')` has color `const Color(0xFF2E7D32)`, and the badge contains `Icons.verified_rounded`. `find.text('profile setup target')` finds nothing yet. `tester.widget<ButtonStyleButton>(find.ancestor(of: find.text('I verified my email'), matching: find.bySubtype<ButtonStyleButton>())).onPressed` is `null`. Then `await tester.pump(const Duration(milliseconds: 1200)); await tester.pumpAndSettle();` and `find.text('profile setup target')` finds one.
4. `'check error keeps the badge red and uses error styling'`: set `fake.reloadError = Exception('offline')`, tap, `pumpAndSettle`. The badge is still `'Not yet verified'`. The `Icon` inside `find.byKey(const Key('email-verification-status'))` has `icon == Icons.error_outline_rounded` and color `const Color(0xFF923B35)`.
5. `'email-sent info message stays teal'`: right after open, the `Text` `'Verification email sent. Check your inbox and spam folder.'` has color `AppColors.primary`.

Imports: `app_colors.dart`, `email_verification_screen.dart`, `auth_provider.dart`, `auth_repository.dart`, `route_names.dart`, `auth_service.dart`, `provider`.

- [ ] **Step 2: Run them and confirm they fail.** Run `flutter test test/features/authentication/email_verification_screen_test.dart`. Expected: tests 1–4 FAIL (no `email-verification-badge` / `email-verification-status` key; the message is teal). Test 5 PASSES.
- [ ] **Step 3: Implement** the interfaces and the `_checkVerification` flow above.
- [ ] **Step 4: Run the tests and confirm they pass.** Run `flutter test test/features/authentication/` and `flutter analyze lib/features/authentication test/features/authentication`. Expected: all authentication tests PASS, and `No issues found!`.
- [ ] **Step 5: Commit.**
```bash
git add lib/features/authentication/screens/email_verification_screen.dart test/features/authentication/email_verification_screen_test.dart
git commit -m "feat(auth): show red not-verified / green verified email status"
```

---

### Task 3: Unblock the Android build (prerequisite for on-device testing only)

Two files use root-relative imports (`import '/features/...'`). The analyzer and tests accept them, but the Android debug build resolves them against the drive root and fails with `Error when reading '/features/mind_aid/...'`. This was confirmed on the identical code in the outer repo tonight. Using `package:` imports instead causes a duplicate-type error (`MindAidRepository` vs `MindAidRepository`) because `main.dart` uses relative imports. Relative imports are the fix.

**Files:**
- Modify: `lib/providers/mind_aid_provider.dart` (import lines only: `'/` becomes `'../`)
- Modify: `lib/features/page/mind_aid_page.dart` (import lines only: `'/` becomes `'../../`)

- [ ] **Step 1: Confirm the failure.** Run `flutter build apk --debug --flavor staging --dart-define=APP_ENV=staging`. Expected: FAIL with `Error when reading '/features/...'` or `'/providers/...'`. If it **passes**, skip this task and write that in the report.
- [ ] **Step 2: Implement.** Only in lines that start with `import '/`: in `mind_aid_provider.dart` replace the leading `'/` with `'../`, and in `mind_aid_page.dart` replace it with `'../../`. Then `grep -rn "^import '/" lib` must print nothing, and `git diff --stat` must show exactly these 2 files, with insertions equal to deletions.
- [ ] **Step 3: Verify.** Run `flutter analyze lib`, which should report `No issues found!`. Then run the Step 1 build command, which should report `√ Built build\app\outputs\flutter-apk\app-staging-debug.apk`.
- [ ] **Step 4: Commit.**
```bash
git add lib/providers/mind_aid_provider.dart lib/features/page/mind_aid_page.dart
git commit -m "fix(build): use relative imports in MindAid provider and page"
```

---

## Final Verification

- [ ] `flutter analyze` → `No issues found!`
- [ ] `flutter test test/features/authentication/` → `All tests passed!`
- [ ] `flutter test` (full suite) → paste the summary line. For each failure outside `test/features/authentication/`, check whether it also fails on `main` by running the same test in a temporary worktree (`git worktree add <tmp> main`; do **not** use `git stash`). Report each one as pre-existing or new.
- [ ] `git log --oneline main..HEAD` → 3 commits (or 2 if Task 3 was skipped); `git status --short` → clean.
- [ ] On device (user runs, or agent runs with the user's phone connected): `flutter run -d <device-id> --flavor staging --dart-define=APP_ENV=staging`. Tap **Create account**: no pop-up. After signing up, the Verify Email screen shows a red **Not yet verified** badge. Verify the email, tap **I verified my email**, and the badge turns green **Email verified** for about 1 s, then Profile Setup opens.

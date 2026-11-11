# Items 31 & 32 Follow-up — Email Guide and Red/Green Verify Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- On the Create Account form, replace the "Student account / Teaching personnel account detected" box under Email Address with an **Email guide** that says which kind of email was typed.
- On Verify Email, make the **I verified my email** button red until the email is verified, then green.

**Architecture:** Two presentation-only edits, each confined to one existing screen file. Email detection reuses `AuthRepository.isInstitutionalEmployeeEmail`. The automatic switch to Teaching fields and the Employee ID, and all provider, route and Firebase code, stay untouched.

**Tech Stack:** Flutter (Material 3), `provider`, `flutter_test`.

**Spec (verbatim from the user, 2026-11-12, with screenshot circling the Email field + "Student account" box):**
```
31 ... remove the Email guide for creating teaching account it should be email and intutional
   and remove the student account. And label it email guide.
   Clarified: the guide "Changes as you type" — title 'Email guide'; line under it:
   personal email typed → "Personal email detected."; @ucu.edu.ph typed → "Institutional email detected."
32 ... additional the button should be red and when verified will turn to green.
```

**Project / branch:** `c:\src\MindMates1.0\mind_mates_clean`, branch `feat/ui-polish-31-35`. This is a local branch that has never been pushed, and it already holds items 31–35 with one commit per item. Do **not** touch the outer `c:\src\MindMates1.0` repo.

---

## Agent Prompt (paste this to the executing agent)

> Implement `docs/superpowers/plans/2026-11-12-email-guide-and-verify-button.md` in `c:\src\MindMates1.0\mind_mates_clean` on the existing local branch `feat/ui-polish-31-35`. Confirm with `git branch --show-current` and `git status --short` (it must be empty) before starting. Read the whole plan first. Use TDD for each task: write the test, run it and watch it fail for the stated reason, implement, run it and watch it pass, then commit. Edit only the files listed, and use the Edit tool rather than `sed` (the files use CRLF). Stage files by explicit path. **Never push.** After any `flutter` command, run `git checkout -- pubspec.lock linux macos windows` so that tool-regenerated files never get committed: the local Flutter SDK is older than the team's. Do not change any copy, color or behavior a step doesn't name. If a quoted snippet is missing, stop and report. Finish with "Final Verification" and paste the real output.

---

## Global Constraints

- Exact new copy: title `'Email guide'`; lines `'Use your personal email or your institutional email (@ucu.edu.ph).'`, `'Personal email detected.'`, `'Institutional email detected.'`.
- The strings `'Student account'`, `'Teaching personnel account detected'`, `'Use your student details below. Teaching personnel must enter an @ucu.edu.ph email.'` and `'Official UCU email confirmed. Your Employee ID and work details are required.'` must no longer appear on the form.
- Red = `AppColors.error` (`Color(0xFFB3261E)`). Green = `_Colors.verified` (`Color(0xFF2E7D32)`), which already exists in `email_verification_screen.dart`.
- Out of scope, so do not change it: the `_confirmRegistrationEmail` dialog text ("This email identifies your account as a Student account."), the inline field labels (Student ID / Employee ID) and the automatic role switch.
- Commit messages: Conventional Commits, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Empty email field (the form's first state):** shows the neutral line `'Use your personal email or your institutional email (@ucu.edu.ph).'`, not "Personal email detected." *Pinned in Task 1.*
2. **Mixed case or whitespace (`  Juan@UCU.edu.ph `):** detected as institutional, matching the existing helper that trims and lowercases. *Pinned in Task 1.*
3. **Look-alike domains (`juan@ucu.edu.ph.com`, `juan@student.ucu.edu.ph`):** treated as personal, because the helper requires an exact domain match. *Pinned in Task 1.*
4. **The disabled button during the green 1.2 s hold:** Material greys out disabled buttons, so the button must explicitly stay green while disabled. *Pinned in Task 2.*
5. **The button while a check is in progress or after an error:** stays red; it only turns green when verified. *Pinned in Task 2.*

---

### Task 1: Email guide replaces the Student/Teaching account box (item 31 follow-up)

**Files:**
- Modify: `lib/features/authentication/screens/signup_screen.dart` (the `_AccountTypeNotice(isTeaching: !isStudent)` call around line 513, and the `_AccountTypeNotice` class around lines 666–723)
- Test: `test/features/authentication/signup_screen_test.dart` (the first test's `'Student account'` assertion around line 29, the `'Teaching personnel account detected'` assertion around line 171, plus new tests)

**Interfaces (file-private):**
- `enum _EmailKind { empty, personal, institutional }`
- `_EmailKind _emailKindFor(String email)`: trimmed empty → `empty`; `AuthRepository.isInstitutionalEmployeeEmail(email)` → `institutional`; otherwise `personal`.
- `class _EmailGuide extends StatelessWidget { const _EmailGuide({required this.kind}); final _EmailKind kind; }` replaces `_AccountTypeNotice`, which is deleted. Its root `Container` uses `key: const Key('signup-email-guide')`, keeps the existing padding (`EdgeInsets.all(11)`), radius 8 and text styles (title 11/w900, body 10/1.3/w600, `_SignupColors.text`), and uses a single background `Color(0xFFFFF4D6)` and `Icons.info_outline_rounded` (size 18) for every kind.
- In `_SignupFormCard.build`: `_EmailGuide(kind: _emailKindFor(emailController.text))`. The screen already rebuilds on every email change through `_handleEmailChanged`.

| kind | title | line |
|---|---|---|
| `empty` | `Email guide` | `Use your personal email or your institutional email (@ucu.edu.ph).` |
| `personal` | `Email guide` | `Personal email detected.` |
| `institutional` | `Email guide` | `Institutional email detected.` |

- [ ] **Step 1: Write the failing tests.**
  - In the first test (`'signup opens directly on the form without a rules modal'`), replace `expect(find.text('Student account'), findsOneWidget);` with:
    ```dart
    expect(_guideText('Email guide'), findsOneWidget);
    expect(_guideText('Use your personal email or your institutional email (@ucu.edu.ph).'), findsOneWidget);
    expect(find.text('Student account'), findsNothing);
    ```
  - In `'official UCU email automatically switches to teaching fields'`, replace `expect(find.text('Teaching personnel account detected'), findsOneWidget);` with `expect(_guideText('Institutional email detected.'), findsOneWidget);`. Keep its Employee ID assertions, since the role switch must still happen.
  - Add the helper `Finder _guideText(String t) => find.descendant(of: find.byKey(const Key('signup-email-guide')), matching: find.text(t));`.
  - Add the test `'email guide follows the typed email'`. Use the standard harness (surface `Size(900, 1400)`, `_SignupHarness`, `_settleSignup`). For each pair below, call `await tester.enterText(find.byType(TextFormField).first, input); await tester.pump();` (Email is the first field. Don't find it by its hint text, which disappears once text is entered.) and then `expect(_guideText(expected), findsOneWidget)`:
    | input | expected |
    |---|---|
    | `'leo@gmail.com'` | `'Personal email detected.'` |
    | `'  Juan@UCU.edu.ph '` | `'Institutional email detected.'` |
    | `'juan@ucu.edu.ph.com'` | `'Personal email detected.'` |
    | `'juan@student.ucu.edu.ph'` | `'Personal email detected.'` |
    | `''` | `'Use your personal email or your institutional email (@ucu.edu.ph).'` |

    After the loop: `expect(find.text('Student account'), findsNothing); expect(find.text('Teaching personnel account detected'), findsNothing);`.
- [ ] **Step 2: Run them and confirm they fail.** Run `flutter test test/features/authentication/signup_screen_test.dart`. Expected: the 3 edited/new tests FAIL (no `signup-email-guide` key); the others PASS.
- [ ] **Step 3: Implement** the interfaces above. Delete `_AccountTypeNotice`. Remove the `isStudent` local only if the analyzer reports it unused. It is still used elsewhere in `build`, so it most likely stays.
- [ ] **Step 4: Run the tests and confirm they pass.** Run `flutter test test/features/authentication/signup_screen_test.dart` and `flutter analyze lib/features/authentication test/features/authentication`. Expected: `All tests passed!` and `No issues found!`.
- [ ] **Step 5: Commit.** Clean up first (`git checkout -- pubspec.lock linux macos windows`), then:
```bash
git add lib/features/authentication/screens/signup_screen.dart test/features/authentication/signup_screen_test.dart
git commit -m "fix(signup): replace account-type notice with an Email guide"
```

---

### Task 2: "I verified my email" button red → green (item 32 follow-up)

**Files:**
- Modify: `lib/features/authentication/screens/email_verification_screen.dart` (the check button `style: _primaryButtonStyle` around line 446; the top-level `_primaryButtonStyle` around line 698)
- Test: `test/features/authentication/email_verification_screen_test.dart`

**Interfaces (file-private):**
- Replace the top-level `final _primaryButtonStyle` with `ButtonStyle _checkButtonStyle({required bool verified})`, built with `FilledButton.styleFrom`. `_primaryButtonStyle` has no other users; confirm with grep before deleting. Values:
  - `backgroundColor`: `verified ? _Colors.verified : AppColors.error`
  - `disabledBackgroundColor`: `verified ? _Colors.verified : AppColors.error.withAlpha(110)`
  - `foregroundColor` and `disabledForegroundColor`: `Colors.white`
  - Shape (radius 16) and text style (15 / w900) are unchanged.
- The button uses `style: _checkButtonStyle(verified: verified)`, where `verified` is the existing `_VerificationCard.verified` field. The label, icon and `onPressed` logic stay as they are.

- [ ] **Step 1: Write the failing tests.** Add a helper:
```dart
ButtonStyle _checkStyle(WidgetTester tester) => tester.widget<ButtonStyleButton>(
  find.ancestor(of: find.text('I verified my email'), matching: find.bySubtype<ButtonStyleButton>()),
).style!;
```
Tests:
1. `'verify button is red before verification'`: right after open, `_checkStyle(tester).backgroundColor!.resolve(<WidgetState>{})` equals `AppColors.error`.
2. `'verify button stays red after an unverified check and after an error'`: tap and `pumpAndSettle`; the resolved background (no states) is still `AppColors.error`. Repeat on a fresh pump with `reloadError = Exception('offline')`: still `AppColors.error`.
3. `'verify button turns green when verified, even while disabled'`: set `verified = true`, tap, `pump()`. Both `backgroundColor.resolve({})` and `backgroundColor.resolve({WidgetState.disabled})` equal `const Color(0xFF2E7D32)`, and `onPressed` is null. Then `pump(1200 ms)` + `pumpAndSettle` and confirm `'profile setup target'` is shown.

End every test with `await tester.pumpWidget(const SizedBox());`.
- [ ] **Step 2: Run them and confirm they fail.** Run `flutter test test/features/authentication/email_verification_screen_test.dart`. Expected: the 3 new tests FAIL (the background is `AppColors.primary`); the 5 existing tests PASS.
- [ ] **Step 3: Implement** the interfaces above.
- [ ] **Step 4: Run the tests and confirm they pass.** Run `flutter test test/features/authentication/` and `flutter analyze lib/features/authentication test/features/authentication`. Expected: `All tests passed!` and `No issues found!`.
- [ ] **Step 5: Commit.** Clean up first, then:
```bash
git add lib/features/authentication/screens/email_verification_screen.dart test/features/authentication/email_verification_screen_test.dart
git commit -m "feat(auth): red/green 'I verified my email' button"
```

---

### Task 3: Keep one commit per item (tidy the unpushed branch)

The user wants the branch "clean and tidy", one commit per item. Fold Task 1's commit into the item-31 commit and Task 2's commit into the item-32 commit. The branch has never been pushed (`git ls-remote --heads origin feat/ui-polish-31-35` prints nothing), so rewriting it is safe. Run that check first and **stop** if it prints anything.

- [ ] **Step 1: Commit this plan, then back up.** Run `git add docs/superpowers/plans/2026-11-12-email-guide-and-verify-button.md && git commit -m "docs(plan): add email guide and verify button follow-up plan"`, then `git branch -f backup/ui-polish-pre-fold HEAD`.
- [ ] **Step 2: Rebuild the branch.** Recreate the same commit order on top of `main`: plan doc → item 31 (+ Task 1 changes) → item 32 (+ Task 2 changes) → 33 → 34 → 35 → 31–32 plan doc → this plan doc. Use `git switch --detach <item-31 commit>`. Then fold each follow-up with `git cherry-pick --no-commit <task commit> && git commit --amend --no-edit`. Re-apply the rest with plain `git cherry-pick <sha>...` (no `-q`: `cherry-pick` rejects it). Move the branch with `git branch -f feat/ui-polish-31-35 HEAD && git switch feat/ui-polish-31-35`.
- [ ] **Step 3: Verify.** `git diff backup/ui-polish-pre-fold HEAD` must print **nothing** (identical tree). `git log --oneline main..HEAD` must show exactly 8 commits: plan, 31, 32, 33, 34, 35, 31–32 plan, this plan. If either check fails, run `git branch -f feat/ui-polish-31-35 backup/ui-polish-pre-fold`, switch to it, and report.
- [ ] **Step 4: Remove the backup.** `git branch -D backup/ui-polish-pre-fold`.

---

## Final Verification

- [ ] `flutter analyze` → `No issues found!`
- [ ] `flutter test test/features/authentication/` → `All tests passed!`
- [ ] `flutter test` (full suite): expect `+611 -31` or similar. Compare the failing set with `origin/main`'s known 31 (home_screen 1, quick_assessment Firebase no-app 3, student_assessment 27); there must be **no new** failures. Use a temporary `git worktree add <tmp> origin/main` if a comparison is needed, and never `git stash`.
- [ ] `git status --short` → empty; `git log origin/main..HEAD --oneline` → 8 commits; nothing pushed.
- [ ] On the device: run with the `fix/mindaid-relative-imports` files restored into the working tree only (`git restore --source=fix/mindaid-relative-imports -- lib/providers/mind_aid_provider.dart lib/features/page/mind_aid_page.dart`), then `flutter run -d 13195704C5003842 --flavor staging --dart-define=APP_ENV=staging`. After launch, restore with `git checkout -- lib/providers/mind_aid_provider.dart lib/features/page/mind_aid_page.dart`. Check: Create account shows **Email guide** and the line updates as you type; on Verify Email the button is red, then turns green once verified.

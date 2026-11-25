# Student Roster Email Login V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Students request a temporary login by Student ID, receive it at the roster email, sign in, are forced to set a permanent password, then complete Student Information.

**Architecture:** One new callable `requestStudentLogin` creates/reissues the alias Auth user (existing `<id>@students.mindmate.local`) and emails Student ID + temporary password. A custom claim `firstLoginPending` gates Rules, callables and the app until `completeStudentPasswordChange` (server-side `updateUser`) succeeds. Reuses alias, reservation, roster link, SMTP mailer, `consumeWindow`, Forgot Password and the Student Information gate.

**Tech Stack:** Firebase Functions v2 (TypeScript, node:test + emulators), Firestore Rules, Flutter (Provider, FirebaseFunctions).

**Spec:** `docs/superpowers/specs/2026-11-24-student-roster-email-login-design.md` (incl. "V2 security revisions").

## Audit (Step 1, read-only) - reuse map
- Alias + create: `student_auth_alias.ts` (`studentAuthAliasEmail`), `student_activation.ts` (`createAliasUser`, `authEmailTaken`).
- Roster link writes: `student_account_setup.ts:approveAccountClaim` (profile via `student_profile.ts:rosterStudentProfile`, `student_id_reservations/{key}`, roster `activated/userId/claimMethod`, audit `writeAudit`).
- Mail / limits / dev guard: `student_account_recovery.ts` (`defaultRecoveryDeps.sendMail`, `consumeWindow`, `callerIp`, `assertDevEndpointAllowed`, `currentProjectId`, `smtpAppPassword` secret). Forgot Password `resetPasswordForStudentId` needs a verified `student_recovery_contacts/{uid}` and an `emailVerified` Auth user.
- Gates: app `auth_flow_routes.dart:gateRouteForUser` (client only today); rules `signedIn()`/`isOwner()` are central (`firestore.rules:5-11`); callable `access.ts:requireUid` is central, plus direct `request.auth` readers in `account_integrity, account_recovery, announcements_callable, assessment/*, assessment_participant_directory, index, mind_aid, mood_entries, report_generation, student_*`.
- Admin pattern `completeAdminPasswordChange` (index.ts) trusts the client: NOT reused.
- Staging dependencies: aliased callables in `firebase_callable_router.dart`; deployed activation/setup Functions stay. Hosted changes needed later: new `requestStudentLogin`(+Dev), `completeStudentPasswordChange`, Functions touched by the `requireUid` gate, Firestore Rules.

## Global Constraints
- Local work only: no hosted Firebase writes, deploys, GitHub push/merge, Production changes, account migration, real roster edits, employee-auth changes. Do not remove deployed activation/setup Functions.
- Neutral response `{accepted: true}` for every `requestStudentLogin` outcome; minimum response time via `deps.minResponseMs`.
- Temp password: 12 chars from `ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789`, crypto-random, TTL 24 h; reissue only when expired or (>=60 min since last send and <3 issues in 24 h). Limits: 10 per 15 min per IP (`consumeWindow`), 3 per 15 min per Student ID (suppressed, never an error).
- Permanent password policy: >=10 chars, upper, lower, digit, not the temporary password, not the Student ID.
- Passwords never in logs, audit metadata, Firestore (only a scrypt hash in server-only `student_login_issuance`), or analytics.
- Claim name `firstLoginPending`; collection `student_login_issuance/{studentKey}`; roster `claimMethod: "roster-email-login"`.

## Review Focus
- Student ID typed with spaces/lowercase/hyphens gives the same canonical key and the same neutral response (Task 2 test).
- Roster email in mixed case/whitespace: mail goes to the normalized roster address only (Task 2).
- Double-tap / concurrent requests: one Auth user, one email (Task 2).
- App killed mid-change, or Auth updated but the Firestore write failed: reopening is still gated and a retry completes (Task 3).
- Already-activated (old flow) student: no email, password untouched (Task 2).

---

### Task 1: Domain helpers
**Files:** Create `functions/src/student_login_domain.ts`, `functions/src/student_login_domain.test.ts`
**Interfaces:** Produces `FIRST_LOGIN_CLAIM = "firstLoginPending"`, `TEMP_PASSWORD_TTL_MS`, `REISSUE_COOLDOWN_MS`, `MAX_ISSUES_PER_DAY`, `generateTemporaryPassword(): string`, `hashPassword(pw: string): {hash: string; salt: string}`, `passwordMatches(pw: string, stored: {hash: string; salt: string}): boolean`, `validatePermanentPassword(pw: string, ctx: {studentKey: string; temporary?: {hash: string; salt: string}}): void` (throws `HttpsError("invalid-argument")`), `mayReissue(issuance: {expiresAtMs: number; lastSentAtMs: number; issuedInWindow: number}, now: number): boolean`.
- [ ] Test (node:test): 1000 generated passwords are 12 chars from the allowed alphabet and unique; `validatePermanentPassword` rejects short / no-digit / equal-to-temp / equal-to-ID and accepts `"Str0ngPerm!9"`; `mayReissue` is true when expired, false at 30 min unexpired, true at 61 min with 2 issues, false with 3 issues.
- [ ] Run `cd functions && npm run build && node --test lib/student_login_domain.test.js`; expect FAIL (module missing).
- [ ] Implement with `node:crypto` (`randomInt`, `scryptSync`, `timingSafeEqual`).
- [ ] Rerun; expect PASS. Commit `feat(auth): student login domain helpers`.

### Task 2: `requestStudentLogin`
**Files:** Create `functions/src/student_login.ts`, `functions/src/student_login.test.ts`; Modify `functions/src/index.ts` (export), and add the test file to the runner list in `functions/scripts/run-tests.mjs` if it lists files.
**Interfaces:** Consumes Task 1. Produces `requestLogin(request: {data?: unknown; rawRequest?: {ip?: string}}, deps?: LoginDeps): Promise<{accepted: true}>`, `type LoginDeps = {now: () => number; sendMail: RecoveryDeps["sendMail"]; minResponseMs: number}`, callables `requestStudentLogin` (enforceAppCheck true, secrets `[smtpAppPassword]`) and `requestStudentLoginDev` (enforceAppCheck false, `assertDevEndpointAllowed(currentProjectId())`).
Algorithm: canonical key via `canonicalLoginId`; limits; load roster; eligible = status active, `activated !== true`, usable roster email (`normalizeRecoveryContactEmail` + `isAllowedPersonalEmail`), email not held by an unrelated Auth user (`authEmailTaken`). A transaction on `student_login_issuance/{key}` reserves `{uid, state:"creating", lockUntil}` for the single winner, with the uid chosen up front so a crash can resume. The winner calls `createUser({uid, email: alias, password: temp, emailVerified: true})`, then one transaction writes the profile (`rosterStudentProfile` + `mustChangePassword: true`), the reservation, the roster link, a verified recovery contact and email reservation, and the issuance `{state:"issued", expiresAtMs, lastSentAtMs, issuedInWindow, hash, salt}`. Then set claim `{firstLoginPending: true}` and send the mail (Student ID + password, to the roster email only). On mail failure mark `state:"send-failed"` so the next request may reissue. An existing issuance is reissued only if `mayReissue` (rotate with `updateUser`, new hash and expiry, claim, mail), otherwise no-op. An existing account with no issuance (old flow) or `state:"completed"` is a no-op. Every error goes to logs with a correlation id, never to the caller.
- [ ] Failing emulator tests (style of `student_account_setup.test.ts`, injected deps): unknown ID and no-email row return `{accepted:true}` with no mail and no Auth user; a real row sends exactly one mail to the normalized roster email containing the Student ID and a password that signs in (alias exists, claim set); payload `email`/`to` fields are ignored; `"qa-2026-0002 "`-style IDs equal canonical; 8 concurrent calls give one Auth user and one mail; a second call inside the cooldown sends no mail and does not rotate; after the clock advances 25 h it reissues and the old hash no longer matches; the 4th issue in 24 h is refused; an old-flow activated row gets no mail and no change; an email held by an unrelated Auth user creates no identity.
- [ ] Run; expect FAIL. Implement. Run; expect PASS. Commit `feat(auth): request student login by roster email`.

### Task 3: `completeStudentPasswordChange`
**Files:** Modify `functions/src/student_login.ts`, `student_login.test.ts`, `index.ts`
**Interfaces:** Produces `completePasswordChange(request: {auth?: {uid: string; token: {auth_time?: number; firstLoginPending?: boolean}} | null; data?: unknown}, deps?: {now: () => number; afterAuthUpdate?: () => Promise<void>}): Promise<{ok: true}>` and callable `completeStudentPasswordChange` (plain `onCall`, not aliased, like `saveStudentPersonalInfo`).
Checks in order: authenticated uid; claim `firstLoginPending` true; user is a student alias and the issuance for its key has the same uid, state `issued` or `completing`, not expired; `auth_time` within 5 min; `validatePermanentPassword`; state to `completing {completingAtMs}`; `updateUser(uid, {password})`; then one transaction (users `mustChangePassword:false, passwordChangedAt`; issuance `completed` with hash/salt removed; audit `STUDENT_PASSWORD_SET` with no secrets); then `setCustomUserClaims(uid, {})`. Reconcile branch: state `completing` and `auth_time*1000 >= completingAtMs` runs the second half only, with no password needed.
- [ ] Failing tests: missing/absent claim rejected; other uid rejected; expired issuance rejected; stale `auth_time` rejected; reuse of the temp password rejected; weak password rejected; success clears flag and claim, and the old temp password no longer signs in; a failure injected after `updateUser` (`deps.afterAuthUpdate` throws), then a retry with fresh `auth_time`, completes without a password; a second success call fails with `failed-precondition`.
- [ ] Run; expect FAIL. Implement. Run; expect PASS. Commit `feat(auth): server-side first-login password change`.

### Task 4: Callable gate
**Files:** Modify `functions/src/access.ts` (`requireUid` throws `permission-denied` with `details.reason:"first-login-pending"` when `request.auth.token.firstLoginPending === true`; widen the parameter type to include `token?`), and every direct reader found by `grep -rn "request.auth" functions/src --include=*.ts` outside tests and outside `student_login.ts`, `student_account_setup.ts`, `student_account_recovery.ts`, `account_recovery.ts` (switch them to `requireUid`); Create `functions/src/first_login_gate.test.ts`.
**Interfaces:** Consumes the claim name from Task 1. Produces nothing new.
- [ ] Failing tests: `requireUid` rejects a pending token and accepts a normal one; a source-scan test reads each `functions/src/*.ts` (excluding tests and the allow-list above plus `access.ts`) and fails if it reads `request.auth` without importing `requireUid`.
- [ ] Run; expect FAIL. Implement edits. Run; expect PASS and `npm run build` clean. Commit `feat(auth): block first-login sessions in callables`.

### Task 5: Firestore Rules gate
**Files:** Modify `firestore.rules` (`signedIn()` becomes `request.auth != null && request.auth.token.firstLoginPending != true`; `users/{userId}` read becomes `(request.auth != null && request.auth.uid == userId) || isSystemAdmin()`); Create `functions/src/first_login_rules.rules.ts`; add script `test:first-login-rules` to `functions/package.json`.
- [ ] Failing emulator rules tests (pattern of `profile_rules.rules.ts`): a pending token can read its own `users/{uid}` but not `moodEntries` or `student_personal_info`, and cannot write `mustChangePassword` or `firstLoginPending` on its own profile; the same token without the claim reads/writes as before; another user's profile is unreadable.
- [ ] Run; expect FAIL. Edit rules. Run; expect PASS, then run the existing `test:rules`, `test:profile-rules`, `test:roster-rules` for regressions. Commit `feat(auth): gate Firestore on first-login claim`.

### Task 6: Flutter request, change password, routing
**Files:** Create `lib/features/authentication/screens/student_login_request_screen.dart`, `lib/features/authentication/screens/student_change_password_screen.dart`; Modify `lib/services/firebase/firebase_callable_router.dart` (add `'requestStudentLogin'`), `lib/routes/route_names.dart` and `lib/routes/app_pages.dart` (`studentLoginRequest`, `studentChangePassword`), `lib/features/authentication/auth_flow_routes.dart`, `login_screen.dart` (button text "Email me my login"; `_openStudentActivation` opens the new route), `lib/repositories/student_roster_repository.dart` (`requestStudentLogin(String studentId)`, `completeStudentPasswordChange(String newPassword)`, then re-sign-in with the alias and new password and `getIdToken(true)`).
**Interfaces:** `gateRouteForUser(UserModel user)` returns `RouteNames.studentChangePassword` first for a student with `user.mustChangePassword` (the field already exists on `UserModel`); splash, login and Google paths already call it.
- [ ] Failing tests under `test/features/authentication/`: gate order (change password, then student information, then profile setup; non-students unaffected); the request screen shows the same neutral confirmation for any input and never shows the email; the change-password screen validates policy and confirmation and, on success, navigates to student information; the login screen shows "Email me my login" and no "Activate student account".
- [ ] Run `flutter test test/features/authentication`; expect FAIL. Implement. Run; expect PASS. Commit `feat(auth): student login request and forced password change`.

### Task 7: Remove app activation entry points
**Files:** Delete `student_activation_screen.dart`, `student_recovery_verification_screen.dart` and their tests and routes; fix `signup_screen.dart:288` and `email_verification_screen.dart:268` to route to the login screen; keep all Functions.
- [ ] `flutter analyze` first shows the dangling references; fix them; analyze clean for touched files. Commit `refactor(auth): drop student activation screens`.

### Task 8: Validation and report (Steps 6-7)
- [ ] `cd functions && npm run build && npm test` (copy `.env.local` and `.env.mindmate-staging` from `.worktrees/student-qa-preflight` first); all new security tests green; record pre-existing failures separately by rerunning on `e64dc5f`.
- [ ] `flutter analyze`; `flutter test test/features/authentication test/features/student_info test/features/splash test/features/admin`; the project's Staging APK build; Admin Web build (`flutter build web --release --target lib/admin_main.dart --dart-define=APP_ENV=staging --dart-define=RECAPTCHA_ENTERPRISE_SITE_KEY=<shape-valid placeholder>`) to prove compatibility.
- [ ] `git checkout -- linux macos windows pubspec.lock` if Flutter dirtied them. Write the Step 7 report: changed files, SHA, findings, tests, rollout order (Rules, then `requestStudentLogin(Dev)` + `completeStudentPasswordChange` + gated Functions, then Hosting, then APK), rollback (previous revisions and Rules release), legacy retirement plan, READY/BLOCKED. STOP.

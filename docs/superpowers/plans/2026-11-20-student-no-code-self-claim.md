# MindMate No-Code Student Account Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Replace the student activation-code workflow with roster-based student account setup using Student Number, full name, birth date, personal-email verification, and a student-set password, while preserving ordinary student features and per-UID data privacy.

**Architecture:** Keep the admin-imported student_roster, Firebase Auth, users, student_id_reservations, and existing Student Information gate. A rate-limited public precheck matches roster identity fields, Firebase email-link sign-in verifies the chosen personal email, and authenticated callables check claim eligibility and atomically link the first verified email/password Auth UID to the roster. Flutter and the admin portal remove all code-slip UI after a coordinated cutover; no old private records are reassigned by Student Number.

**Tech Stack:** Flutter/Dart 3.12, firebase_auth ^6.5.4, app_links ^7.2.2 (Dart >=3.12), Firebase Functions v2 / TypeScript / Node 22, Firebase Auth/Firestore Emulators, Firestore Security Rules, Flutter widget and Node test suites.

**Spec:** docs/superpowers/specs/2026-11-20-student-no-code-self-claim-design.md

## Global Constraints

- Start from the current main HEAD in an isolated worktree at execution time; the design branch is documentation-only. Do not use the stale feat/student-roster-import branch.
- One student roster row may be linked to only one active Firebase UID. Existing linked accounts, UIDs, and assessment/counseling/mood/appointment histories must remain unchanged.
- New roster rows have no generated activation code, printed slip, temporary password, or manually entered code.
- Students enter Student Number, first and last name (middle name optional), date of birth, and a personal email. The email is verified through a link; a new password is set afterward and verified by a fresh password sign-in before final linking.
- A completed claim has normal student feature access subject to the existing Student Information gate. No new feature-level limitations or special-mode UI labels.
- Every private record remains owned by its original Firebase UID. Never move a previous account's clinical history to a later claimant based on Student Number.
- Personal-email verification and roster attribute matching are not independent school-identity proof; keep claimMethod = "self-roster-match" in technical data/audit.
- Keep roster, reservations, and claim-attempt writes Admin SDK only; never loosen Firestore rules or log passwords, birthday, email links, activation secrets, or full identity inputs.
- Preserve staging-only Dev callable naming through FirebaseCallableRouter, with protected onCall enforceAppCheck:true and Dev enforceAppCheck:false matching existing project convention. Never weaken production App Check.
- Android IDs: development com.example.mind_mates; staging com.example.mind_mates.staging; production ph.edu.ucu.mindmates. Firebase projects: mindmate-dev-4e91c, mindmate-staging, mind-mates-cd2cf.
- Existing employee signup, email verification, password recovery, staff/counselor roles, and admin academic structure must not change except where explicitly named.
- Do not deploy, change Firebase console settings, provision accounts, or run cleanup against hosted projects without separate approval.

## File responsibility map

- functions/src/student_claim_domain.ts — parsing/matching official roster attributes; no Firestore or Auth calls.
- functions/src/student_claim_preflight.ts — public App Check protected roster precheck and bounded attempts.
- functions/src/student_claim.ts — authenticated claim-session authorization and final transaction.
- functions/src/student_roster.ts — preserve import/updates; remove code issuance and code-return behavior at coordinated cutover; keep revocation with no replacement code.
- functions/src/account_integrity.ts — preserve staff signup/cancellation; prevent unlinked student email sessions from being mis-handled.
- functions/src/account_recovery.ts — retain Student Number login/reset for claimed accounts.
- functions/src/index.ts — export protected/Dev claim callables; remove legacy exports only at cutover.
- lib/services/auth/student_email_link_service.dart — Firebase send/sign-in email-link operations and callback validation.
- lib/core/config/student_email_link_config.dart — per-flavor Android package, authenticated Hosting link URL, and ActionCodeSettings.
- lib/models/student_account_setup_models.dart — typed StudentClaimIdentity and current setup-step state.
- lib/features/authentication/screens/student_account_setup_screen.dart — new first-time student flow.
- lib/providers/auth_provider.dart, lib/repositories/auth_repository.dart, lib/repositories/student_roster_repository.dart — orchestration and callable contracts.
- lib/routes/route_names.dart, lib/routes/app_pages.dart, lib/features/authentication/auth_flow_routes.dart, lib/features/splash/screens/splash_screen.dart — old and new account routing.
- lib/features/admin/screens/student_roster_page.dart, lib/features/admin/services/student_roster_file_parser.dart, lib/models/student_roster_models.dart — keep academic import, remove code/slip administration.
- android/app/src/main/AndroidManifest.xml, android/app/build.gradle.kts, firebase.json — Android App Links and existing flavor/Hosting configuration.
- firestore.rules and relevant callables — privacy regression surface; change permissions only if a failing new test proves necessity.

## Review Focus

1. Two devices/users try to claim one Student Number simultaneously: exactly one UID wins, with no duplicate reservation or exposure of previous-UID records (Task 3 and Task 10 tests).
2. Student opens an email link on another device or after entering the wrong email: safe re-entry/correction, no student record bound until validated (Task 4 and Task 6 tests).
3. Email is already used by a staff account or by an existing student: never alter staff credentials, merge roles, or overwrite an existing linked profile (Task 3 and Task 5 tests).
4. Student signs in with email link but never sets a password or loses connectivity between Auth and Firestore: final claim refuses non-password sign-in and is safely retryable after Auth interruption (Task 3 and Task 5 tests).
5. Admin revokes a wrongful claim and another user reclaims the row: old UID and its counseling history remain inaccessible to the new UID (Task 8 and Task 10 tests).

---

### Task 1: Pure Student Claim Identity Contract

**Files:**
- Create: functions/src/student_claim_domain.ts
- Create: functions/src/student_claim_domain.test.ts
- Use: functions/src/student_roster_domain.ts, functions/src/account_recovery.ts

**Interfaces:**
- Produces: type StudentClaimInput = {studentNo:string; studentKey:string; firstName:string; middleName:string; lastName:string; dateOfBirthKey:string}.
- Produces: readStudentClaimInput(raw:unknown):StudentClaimInput; claimIdentityMatches(input:StudentClaimInput, row:Record<string,unknown>):boolean.
- Exact wire keys used by all later callables: studentNo, firstName, middleName, lastName, dateOfBirth. Email is never part of this roster identity DTO.

- [ ] **Step 1: Write failing unit tests** in student_claim_domain.test.ts: canonical Student Number variations match; trimmed/case-normalized first and last names match; omitted optional middle name is accepted; a supplied incorrect middle name, bad birthday, unknown/empty names, or malformed Student Number fails; no mismatch response includes stored PII.
- [ ] **Step 2: Verify RED** — run: cd functions && npm run build && node --test lib/student_claim_domain.test.js. Expected: missing implementation/test failure.
- [ ] **Step 3: Implement** the two exported pure functions, reusing canonicalLoginId, normalizeName, and parseDateKey without adding a new canonicalization scheme.
- [ ] **Step 4: Verify GREEN** — rerun the exact Task 1 command; expect all new cases pass and npm run test:roster-unit remains green.
- [ ] **Step 5: Commit** only Task 1 source/test: feat(auth): validate student self-claim identity.

### Task 2: Rate-Limited Roster Precheck

**Files:**
- Create: functions/src/student_claim_preflight.ts
- Create: functions/src/student_claim_preflight.test.ts
- Modify: functions/src/index.ts
- Modify: lib/services/firebase/firebase_callable_router.dart (add protected name)
- Use: functions/src/student_claim_domain.ts and student_roster Firestore documents

**Interfaces:**
- Produces: startStudentAccountSetup and startStudentAccountSetupDev callable exports.
- Input: StudentClaimInput wire fields from Task 1 (excluding studentKey).
- Output on success: {ok:true}; errors use HttpsError with generic public wording. No roster fields are returned.
- Limits: 5 failed attempts per canonical Student Number / 30-minute lock, bounded TTL and additional abuse control keyed by source; no raw IP/PII logging.

- [ ] **Step 1: Write failing emulator tests**: valid active unclaimed row returns {ok:true}; unknown row, wrong name, wrong DOB, locked Student Number, or inactive row all return the same generic public error; 5 attempts enforce the lock; concurrent attempts cannot evade the limit; attempt documents expire and client Firestore reads/writes remain denied.
- [ ] **Step 2: Verify RED** — cd functions && npm run build; then firebase emulators:exec --only auth,firestore --project demo-mindmate-self-claim "cd functions && node --test lib/student_claim_preflight.test.js". Expected: missing callable/tests fail.
- [ ] **Step 3: Implement** guarded precheck using one transaction to reserve attempts before sensitive comparison, with protected and Dev wrappers. The response must never reveal the roster name, course, birthday, or email.
- [ ] **Step 4: Verify GREEN** — rerun Task 2 emulator command and npm run test:roster-rules; all new and prior rules cases pass.
- [ ] **Step 5: Commit** Task 2 source/tests/routes: feat(auth): add guarded student roster precheck.

### Task 3: Verified Student Claim and Atomic Account Linking

**Files:**
- Create: functions/src/student_claim.ts
- Create: functions/src/student_claim.test.ts
- Modify: functions/src/index.ts
- Modify: lib/services/firebase/firebase_callable_router.dart
- Use: functions/src/account_integrity.ts (defaultActivityFields), functions/src/audit.ts, functions/src/access.ts

**Interfaces:**
- Produces: checkStudentAccountSetupSession + Dev (authenticated email-link session before password update).
- Produces: completeStudentAccountSetup + Dev (authenticated, email verified, freshly signed in by password).
- Both accept the exact StudentClaimInput wire fields from Task 1; completion returns {ok:true,userId:string,alreadyCompleted:boolean}.
- Completion writes users/{uid}, student_id_reservations/{studentKey}, student_roster/{studentKey} with activated:true, userId:uid, activationCode:null and server audit action STUDENT_ACCOUNT_CLAIMED. It copies existing official profile/academic data, personalInfoRequired:true, rosterLinked:true, claimMethod:"self-roster-match".
- Keep normal student app eligibility under the existing verificationStatus contract; do not equate emailVerified with official school identity proof.

- [ ] **Step 1: Write failing emulator tests**: verified-email session authorizes only an eligible unlinked student; a staff/employee profile or already-owned student UID is rejected before password changes; final completion rejects unauthenticated, unverified, email-link-only (not password-sign-in), revoked, conflicting reservation, and nonmatching details; success creates exactly one profile/reservation/roster link; concurrent claims have one winner; same-UID retry is idempotent.
- [ ] **Step 2: Verify RED** — cd functions && npm run build; then firebase emulators:exec --only auth,firestore --project demo-mindmate-self-claim "cd functions && node --test lib/student_claim.test.js".
- [ ] **Step 3: Implement** the two guarded callables and transactional finalization. Use Admin Auth state and token sign-in provider, not client-supplied verified/password flags. Read all transaction documents before writes and preserve defaultActivityFields.
- [ ] **Step 4: Verify GREEN** — rerun Task 3 emulator command, Task 2 suite, and Functions build. Confirm rejected attempts do not create reservations or migrate any older UID history.
- [ ] **Step 5: Commit** Task 3 changes: feat(auth): atomically claim student roster after verified password sign-in.

### Task 4: Email-Link Authentication and Android Return Route

**Files:**
- Create: lib/services/auth/student_email_link_service.dart
- Create: lib/core/config/student_email_link_config.dart
- Create: test/services/auth/student_email_link_service_test.dart
- Modify: pubspec.yaml, pubspec.lock, android/app/src/main/AndroidManifest.xml
- Modify: lib/main.dart or the existing app startup initialization entry points as actually present

**Interfaces:**
- StudentEmailLinkService.sendLink({required String email, required ActionCodeSettings settings}): Future<void>.
- StudentEmailLinkService.completeLink({required String email, required String emailLink}): Future<UserCredential>.
- StudentEmailLinkConfig.forEnvironment(AppEnvironment): ActionCodeSettings uses handleCodeInApp:true and environment-appropriate Android package/link URL; no user PII in URL.
- Expose an AppLinks event stream for initial/cold and already-running app links; never handle a non-Firebase link as a sign-in link.

- [ ] **Step 1: Write failing Flutter service tests** for valid link handling, wrong-email rejection, repeated link callback, malformed/non-email link, restart with pending email, and distinct Android package settings for development/staging/production.
- [ ] **Step 2: Verify RED** — flutter test test/services/auth/student_email_link_service_test.dart. Expected: missing classes fail.
- [ ] **Step 3: Implement** using firebase_auth and app_links ^7.2.2; instantiate AppLinks early, configure HTTPS Android App Links intent filters and Hosting action domain. Verify pub get can resolve with Dart 3.12. Do not invent an authorized Hosting domain; check the project configuration, and pause physical-device acceptance if the domain is not configured.
- [ ] **Step 4: Verify GREEN** — flutter pub get, flutter test test/services/auth/student_email_link_service_test.dart, dart analyze. Verify all three Android application IDs match build.gradle.kts and incoming links reach the intended app flavor.
- [ ] **Step 5: Commit** Task 4 changes: feat(auth): support student email sign-in links.

### Task 5: Account Setup Orchestration and Auth Session Gate

**Files:**
- Create: lib/models/student_account_setup_models.dart
- Create: test/features/authentication/student_account_setup_provider_test.dart
- Modify: lib/services/auth/auth_service.dart, lib/repositories/auth_repository.dart, lib/providers/auth_provider.dart
- Modify: lib/repositories/student_roster_repository.dart, lib/routes/route_names.dart, lib/features/splash/screens/splash_screen.dart, lib/features/authentication/auth_flow_routes.dart

**Interfaces:**
- StudentClaimIdentity contains exact Task 1 fields and map serialization.
- StudentRosterRepository.precheckClaim(StudentClaimIdentity):Future<void>; checkClaimSession(StudentClaimIdentity):Future<void>; completeClaim(StudentClaimIdentity):Future<String>.
- AuthProvider methods: requestStudentEmailLink(email), finishStudentEmailLink(email,emailLink), setInitialStudentPassword(password), completeStudentClaim(identity).
- Final linking must follow verified email link -> checkClaimSession -> updatePassword -> new signInWithEmailAndPassword -> completeClaim. Never persist the password in SharedPreferences or Firestore.

- [ ] **Step 1: Write failing provider/startup tests**: a signed-in link-only UID without a users profile remains in Student Account Setup, never Home or employee Profile Setup; existing student signs in normally; different account switch clears draft/link state; existing staff email cannot be overwritten; a password update failure cannot complete the roster claim.
- [ ] **Step 2: Verify RED** — flutter test test/features/authentication/student_account_setup_provider_test.dart test/features/authentication/startup_auth_flow_test.dart.
- [ ] **Step 3: Implement** provider/repository/session orchestration and a safe no-profile route; preserve existing staff signup and email verification callbacks. After updatePassword, authenticate with the new password so the backend can verify a fresh password sign-in.
- [ ] **Step 4: Verify GREEN** — rerun Task 5 tests plus flutter test test/features/authentication/login_screen_test.dart.
- [ ] **Step 5: Commit** Task 5 changes: feat(auth): orchestrate no-code student setup state.

### Task 6: Student Account Setup Screens and Login Entry

**Files:**
- Create: lib/features/authentication/screens/student_account_setup_screen.dart
- Create: test/features/authentication/student_account_setup_screen_test.dart
- Modify: lib/features/authentication/screens/login_screen.dart, lib/routes/app_pages.dart, lib/routes/route_names.dart
- Replace usage of: lib/features/authentication/screens/student_activation_screen.dart and its test
- Reuse visual components from: lib/features/authentication/screens/email_verification_screen.dart (do not change the employee flow)

**Interfaces:**
- Steps: Find Your Student Record -> Your Email -> Check Your Email -> Create Password -> Finish Setup -> existing Student Information gate.
- Student identity fields follow Task 1; one button Send verification link; generic mismatch copy; retry/correct-email action; clear success/navigation states.
- Display text "Set Up Student Account" rather than "Activate student account". No code field, slip/expiry copy, special-mode banner, or field that exposes official roster data before claim.

- [ ] **Step 1: Write failing widget tests** for field validation, no activation-code field, generic mismatch, resend cooldown, correction of typoed email, link callback, password mismatch, sign-in retry, cancellation, success route, and existing login route.
- [ ] **Step 2: Verify RED** — flutter test test/features/authentication/student_account_setup_screen_test.dart test/features/authentication/login_screen_test.dart.
- [ ] **Step 3: Implement** the new screen and route replacements. Preserve existing MindMate visual language and employee verification screen; avoid a separate visual/design-system refactor.
- [ ] **Step 4: Verify GREEN** — rerun Task 6 widget tests, then flutter test test/features/authentication/email_verification_screen_test.dart and dart analyze.
- [ ] **Step 5: Commit** Task 6 changes: feat(auth): replace student activation UI with account setup.

### Task 7: Import Students Without Generating Codes

**Files:**
- Modify: functions/src/student_roster.ts, functions/src/student_roster_domain.ts
- Modify: functions/src/student_roster.test.ts, functions/src/student_roster_domain.test.ts
- Modify: functions/package.json only if test scripts must include new claim suites
- Modify: lib/models/student_roster_models.dart and lib/repositories/student_roster_repository.dart (transitional no-codes response)

**Interfaces:**
- importStudentRoster continues {fileName,rows}, preview and 1,000-row chunk/partial-import behavior unchanged. New roster rows are active/available and activated:false,userId:null with no issued activation code.
- No new code objects returned; if a transitional codes array is needed to avoid crashing an older admin UI, it must be empty.
- Linked legacy students remain activated:true with original UID and official academic updates; do not generate codes for them.

- [ ] **Step 1: Write failing import tests** asserting 1,000-row partial and normal imports save the same academic fields and counts but never mint/return code slips, new rows are claimable, and reimport preserves linked accounts.
- [ ] **Step 2: Verify RED** — cd functions && npm run build; then firebase emulators:exec --only auth,firestore --project demo-mindmate-self-claim "cd functions && node --test lib/student_roster.test.js".
- [ ] **Step 3: Remove code minting/issuance from the new import path** while preserving classify/commit transaction behavior, partial status and import audit. Retain compatibility shape only as necessary for coordinated UI cutover.
- [ ] **Step 4: Verify GREEN** — rerun Task 7 emulator command plus npm run test:roster-unit and Flutter repository tests.
- [ ] **Step 5: Commit** Task 7 changes: refactor(roster): import students without activation codes.

### Task 8: Admin Roster Management and Code-Free Revocation

**Files:**
- Modify: functions/src/student_roster.ts, functions/src/student_roster.test.ts, functions/src/index.ts
- Modify: lib/features/admin/screens/student_roster_page.dart, lib/models/student_roster_models.dart, lib/repositories/student_roster_repository.dart
- Modify: test/features/admin/student_roster_page_test.dart, test/repositories/student_roster_repository_test.dart
- Modify: relevant admin portal leave-guard and file-parser tests
- Preserve: lib/features/admin/services/student_roster_file_parser.dart template columns

**Interfaces:**
- Rename/replace revokeStudentActivation with revokeStudentAccountClaim({studentNo,reason}) -> {ok:true}; old UID disabled, roster activated:false,userId:null, reservation released, old user profile flagged revoked and retained; no code returned.
- Replace labels with Ready to Set Up, Account Active, Information Incomplete, Deactivated.
- Eliminate Issue activation code, Download slips, Reset activation lock, and the undownloaded-code exit warning. Leave normal import-in-progress warnings intact.

- [ ] **Step 1: Write failing backend/widget/repository tests**: no code-related controls or DTO, no unsaved-code guard, reason-required revocation, new claimant can use released row, previous UID cannot read old records after revocation, academic template and partial-import warnings intact.
- [ ] **Step 2: Verify RED** — run Flutter admin tests and roster emulator tests from Tasks 7/8; expect old controls and old revoke response to fail new assertions.
- [ ] **Step 3: Implement** code-free revoke backend transaction, admin repository methods, labels, controls, response types, and guard cleanup. Stop exporting old code-issue/revoke endpoints only at coordinated cutover.
- [ ] **Step 4: Verify GREEN** — flutter test test/features/admin/student_roster_page_test.dart test/repositories/student_roster_repository_test.dart; rerun functions student_roster.test.js in emulator.
- [ ] **Step 5: Commit** Task 8 changes: feat(admin): manage student claims without code slips.

### Task 9: Email Correction, Cancellation, and Existing-Account Recovery

**Files:**
- Modify: functions/src/account_integrity.ts, functions/src/account_integrity.test.ts
- Modify: functions/src/account_recovery.ts and its existing tests only if regression proves necessary
- Modify: lib/features/authentication/screens/email_verification_screen.dart only for shared routing, not staff verification behavior
- Modify: lib/providers/auth_provider.dart, lib/repositories/auth_repository.dart
- Add focused Flutter tests under test/features/authentication/

**Interfaces:**
- Wrong email before link completion: discard/restart local pending email-link request, do not create roster link.
- Verified Auth UID without linked student profile: sign out/retry safely; no student reservation is deleted unless it belongs to that UID and an authenticated server transaction validates cancellation.
- Existing code-activated students keep Student Number/password and Forgot Password behavior. Never delete another account or revoke a staff registration through student cancellation.

- [ ] **Step 1: Write failing tests** for typo correction, expired/wrong-device link, cancel-before-claim, interrupted Auth-without-profile, same-email existing student, staff-email conflict, and old student password recovery.
- [ ] **Step 2: Verify RED** — run functions account_integrity and account_recovery tests in auth/firestore emulator; run focused Flutter verification/provider tests.
- [ ] **Step 3: Implement** bounded unlinked-session cleanup/cancellation and recovery routing while preserving the current staff cancellation semantics. Do not automatically delete verified UIDs with unrelated profiles.
- [ ] **Step 4: Verify GREEN** — rerun the exact Task 9 tests and the existing email_verification_screen_test.dart suite.
- [ ] **Step 5: Commit** Task 9 changes: fix(auth): recover interrupted student account setup safely.

### Task 10: Private Data and Legacy Compatibility Regression

**Files:**
- Create: functions/src/student_claim_privacy.rules.ts (or .test.ts consistent with rules harness)
- Modify only if a test fails: firestore.rules, functions/src/student_personal_info.ts, functions/src/student_case_history_callable.ts, affected appointment/assessment/MindAid callables
- Use: functions/src/student_roster_rules.rules.ts and the existing appointments, assessment, moods, MindAid tests

**Interfaces:**
- Every personal-data request is bound to request.auth.uid or current approved staff/counselor authorization. Student Number alone cannot transfer or select a previous UID's records.
- A newly claimed student can use Home, Mood, Assessments, MindAid, Services, Appointments, Notifications, and Student Information under existing eligibility rules; no special student feature restriction is introduced.

- [ ] **Step 1: Write privacy regression tests**: UID A creates assessments/moods/MindAid messages/appointment; revoke UID A and self-claim same Student Number with UID B; UID B cannot get/list UID A records, previous clinical notes remain counselor-only, UID B can create/read their own fresh records.
- [ ] **Step 2: Verify RED where an actual vulnerability exists** — run new rules/callable tests under auth/firestore emulators. Record whether existing UID-based rules already pass; do not manufacture a failing change if a rule correctly denies access.
- [ ] **Step 3: Implement minimal fixes only for observed failures**, preserving existing staff/counselor clinical access and all current verification/college-scope constraints.
- [ ] **Step 4: Verify GREEN** — run new privacy tests, npm run test:roster-rules, and targeted appointment, assessment, mood and MindAid tests; verify full student navigation integration still passes.
- [ ] **Step 5: Commit** tests and any proven fixes: test(auth): lock private histories to owning UID.

### Task 11: Coordinated Cutover and End-to-End Acceptance

**Files:**
- Modify: functions/src/index.ts, functions/package.json, lib/services/firebase/firebase_callable_router.dart
- Modify: docs/student-roster-user-guide.md and affected auth/admin tests
- Modify: exact obsolete activation-code files after confirming no callers (student_activation.ts, old widget/tests, code-only domain helpers)
- Verify: firebase.json, android/app/src/main/AndroidManifest.xml, android/app/build.gradle.kts, Flutter Firebase per-flavor configuration

**Interfaces:**
- New public start, authenticated session check, and final claim names remain stable and present in production and staging (Dev aliases only as existing convention).
- Old activateStudentAccount, issueStudentActivationCodes, resetStudentActivationLock, and code-returning revoke are no longer callable or linked from the new UI at cutover.
- Keep existing student login/recovery, PACC import partial state and all role-based access behavior.

- [ ] **Step 1: Write failing cutover tests** that assert old activation endpoints and UI actions are absent; old student records remain accessible to existing owners; new accounts complete end-to-end without an activation code; wrong email, duplicate claim and retries do not corrupt reservations.
- [ ] **Step 2: Verify RED** — Functions build/new cutover tests and Flutter activation/admin suite reveal remaining legacy exports/UI.
- [ ] **Step 3: Remove obsolete exports/callers and update guides**, keeping migration-safe stored historical fields and audit events. Update test scripts for the new suites. Do not delete old user data, academic data, or audit history.
- [ ] **Step 4: Verify GREEN** — cd functions && npm run build; run Functions roster/unit/privacy/emulator suites; dart analyze; flutter test; flutter build apk --flavor staging --dart-define=APP_ENV=staging (after configured Firebase link prerequisites). Perform physical email-action-link acceptance only with an authorized account/device and working link domain.
- [ ] **Step 5: Commit** cutover: refactor(auth): retire student activation codes after no-code claim rollout.
- [ ] **Step 6: Produce final handoff** with commits, modified files, exact test counts, unresolved prerequisites, and deployment status. No automatic push/PR merge/Firebase deploy without owner authorization.

## Self-Review and Stop Conditions

- Confirm every design requirement maps to Tasks 1–11 and every Review Focus case has an explicit owning test.
- Run task-specific tests before each commit; verify the current branch, staged paths, and diff before any commit. Preserve unrelated work.
- Do not silently relax a test or omit a failed suite. Keep partial implementation checkpoints rather than claiming completion.
- STOP if verified email links cannot return to the configured Android package, if a UID can read another UID's private data, if a new claim can change a staff account, or if the exact hosting/Auth settings are unknown. Ask the owner to supply the missing configuration/authority.
- No live project mutation, bulk account creation, external email sending, or production deployment is authorized by this plan alone.

## Execution Handoff

Review this document and the linked spec. After approval, choose either Superpowers subagent-driven development (each task independently implemented and reviewed) or native execution (one implementer with a final whole-branch review). For this identity-and-privacy-sensitive workflow, subagent-driven development is recommended.

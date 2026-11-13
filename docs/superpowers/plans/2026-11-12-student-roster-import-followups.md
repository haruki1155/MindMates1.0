# Student roster import — decisions and follow-up backlog

Companion to the design spec (`docs/superpowers/specs/2026-11-12-student-roster-import-design.md`)
and the verification report (`docs/superpowers/plans/2026-11-12-student-roster-import-verification.md`).

Everything here was recorded during implementation on `feat/student-roster-import`. Two independent
whole-branch reviews (server/security and Flutter client) judged none of the follow-ups below to be
merge blockers; every blocking finding they raised was fixed on the branch.

## Decisions taken during implementation

These were resolved without stopping the build. Each names what was decided and what it costs if the
call was wrong.

- Ruling R1: `test:roster` lists only test files that exist; T4 and T5 each append their own file to the script — else node --test fails on missing files — cost if wrong: none.
- Ruling R2: activation errors carry `details.reason`: `"mismatch"` (not-found), `"expired"` (deadline-exceeded), `"already-activated"` / `"email-in-use"` (already-exists), `"locked"` never used (locked returns mismatch); client switches on `details.reason` — avoids string-matching messages — cost if wrong: client copy mapping rework in T8.
- Ruling R3: T10 adds `archive` as a direct dependency pinned to the locked version — needed for date1904 detection — cost if wrong: one pubspec line.
- Ruling R4: multi-batch import (plan-mandated) must never lose codes or overstate results — keep each row's ops in one batch; import record created in batch 1 with status "pending"; on success final batch sets status "complete" + audit with counts; on a mid-way batch failure stop, set status "partial" with committed counts, write audit with committed counts, and RETURN normally {status:"partial", importId, counts(committed), codes(committed rows only), failedRows, message} instead of throwing; full success returns status "complete". Client (Task 7/10) must surface partial. — why: atomic 1,000-row import is impossible under batch limits; returning committed codes keeps slips recoverable — cost if wrong: one extra client state.
- Ruling R5: lockout counter increments before identity check (atomic under parallel guesses) and is cleared on any FULL identity match (incl. expired / already-activated / email-in-use outcomes) — a full match already proves code+DOB possession — cost if wrong: an attacker holding a valid code+DOB gets unlimited email retries (no identity gain).
- Ruling R6: (a) on activation success store the redeemed code as roster `consumedActivationCode` {hash, salt, issuedAt, expiresAt, consumedAt, userId} (activationCode → null); (b) identity check verifies against activationCode OR consumedActivationCode — full match against consumedActivationCode → already-activated error (fixes "already activated" being unreachable); (c) cancelPendingRegistration on a roster-activated profile (verifiedBy "roster-activation", Auth emailVerified false) additionally, in the same transaction as its existing deletes, resets the roster row: activated false, userId null, activationCode restored from consumedActivationCode, consumedActivationCode null — so the same slip works again; verified accounts are never cancellable (existing behavior). Revoke (Task 6) must clear consumedActivationCode. — why: keeps self-service recovery from a mistyped email and keeps roster consistent — cost if wrong: extra logic in shared cancel flow.
- Ruling R7: legacy student without a linked roster row → requestStudentCorrection returns failed-precondition (nothing official to correct until imported/linked) — cost if wrong: legacy students must wait for import to request corrections.
- Ruling R8: backfillStudentInfoRequirement must write an audit entry (new action STUDENT_INFO_REQUIREMENT_BACKFILLED, category userManagement, metadata {flagged, notInRoster}) — user required strict audit logging for admin actions — cost if wrong: one extra audit row.
- Ruling R9 (pre-Task 7): Flutter repository is testable via an injected `typedef StudentRosterCallableInvoker = Future<Object?> Function(String name, Map<String, Object?> data);` (default: FirebaseFunctions.instanceFor(region:'us-central1').routedCallable(name).call(data)); no fake FirebaseFunctions class exists in the repo — cost if wrong: none.
- Ruling R10 (pre-Task 7): add 'activateStudentAccount' to FirebaseCallableRouter._stagingAliases (staging uses the Dev variant like other unauthenticated/App Check callables) — cost if wrong: staging activation hits App Check-enforced variant.
- Ruling R11 (pre-Task 7): repository maps FirebaseFunctionsException with details.reason (R2) into `StudentActivationException(StudentActivationFailure reason)` enum {mismatch, expired, alreadyActivated, emailInUse, invalidInput, unknown}; commitImport returns status complete|partial with failedRows + message (R4) — cost if wrong: Task 8/10 mapping rework.
- Ruling R12: role check alignment — server student-info callables (saveStudentPersonalInfo, getMyStudentInformation, requestStudentCorrection) accept effective student role = populationRole ?? declaredRole ?? legacy role mapping to student (mirror UserModel.effectivePopulationRole) so the client gate and server agree — cost if wrong: a legacy non-student with role 'student' string could save info (harmless; they are a student).
- Ruling R13: consent checkbox shown at the top of the form whenever no prior consent exists (onboarding or edit mode); client sends the real checkbox value; Save disabled until checked in that case — spec "first screen of the form" + RA 10173 — cost if wrong: none.
- Ruling R14: plan's 1904 test example was wrong (38388 = 2005-02-05); correct pair for 2005-02-03 is 1900-serial 38386 / 1904-serial 36924 (verified with node) — implementer's tests use the correct values — cost if wrong: none.
- Ruling R15: the revoke dialog requires a reason and keeps its confirm button disabled until one is entered; that single dialog counts as reason + confirm — cost if wrong: one extra dialog.
- Ruling R16: 1904 correction must not depend on the excel_plus version — detect at runtime whether the decoded date already reflects date1904 (e.g. one-time cached probe: encode a workbook with a known DateCellValue, patch date1904="1", decode, compare) and apply +1,462 only when the library ignored it; plus an end-to-end test using a real patched 1904 xlsx with a date cell asserting the YYYY-MM-DD key — cost if wrong: small complexity.
- Ruling R17: the audit-log fallback must not hide failures — fetchAuditLogPage must stop swallowing callable errors for the student-info-view filter; a failed-precondition (missing index) must surface as a visible error ("Activity log unavailable: a required database index is not deployed."), never render as "no activity matches". Silent empty results on an access log are unacceptable for a DPA audit trail. Cost if wrong: one visible error state.
- Ruling R18: "All actions" does not include student-info views (owner field differs); do NOT merge queries this late — instead show a persistent hint under the action filter: "Student information views appear under their own filter." and record the limitation in the final report. Cost if wrong: an admin must select the filter explicitly.
- Ruling R19: backfillStudentInfoRequirement stays console-invoked (no admin button) — a one-time bulk write at rollout is safer run deliberately than exposed in the portal; the deployment checklist must state the invocation explicitly. Cost if wrong: admin needs a developer for that one step.

## Follow-up backlog (reviewed, deliberately deferred)

None of these block the merge. They are grouped as the reviewers triaged them.

- **Task 1** — package.json test:mood-v2 line reformatted (noise).
- **Task 1** — course ambiguity (same name twice in one college) takes first match.
- **Task 1** — test gaps — tampered stored hash, hashActivationCode invalid throw, yearLevel "1.0".
- **Task 1** — toUpperCase ß→SS quirk in normalizeActivationCode (harmless).
- **Task 2** — closed-collection rules loop omits staff/u2 contexts.
- **Task 3** — stale classification between classify and commit; issueCodesFor read-then-update without precondition.
- **Task 3** — link audit omits previous dateOfBirth (only dateOfBirthKey).
- **Task 3** — link doesn't guard linked user's populationRole is student.
- **Task 3** — actorNameSnapshot computed two ways (String(actor.name) vs actorName()).
- **Task 3** — test gaps (unauthenticated, preview writes nothing beyond roster, link over coded row), after-cleanup deletes all STUDENT_* audits for shared admin uid.
- **Task 3** — no-op updates counted as updated.
- **Task 3** — final status/audit batch failure leaves record "pending" and throws (codes for committed rows lost in that narrow window).
- **Task 3** — batch-failure catch drops error detail — log message (never codes).
- **Task 4** — first-call dummy scrypt timing skew (lazy dummy); locked path skips roster read; email-existence oracle for valid-code holders (R5); attempts docs accumulate without TTL; pre-createUser errors lack correlationId; crash between createUser and transaction orphans Auth user; duplicated name join; tests for attempts-clear on expired/email-in-use and concurrent mismatches.
- **Task 4** — legacy cancel test writes 2026xxxx key into shared emulator; restored code keeps original expiry; pre-R6 rows reset with activationCode null (admin reissues).
- **Task 5** — getStudentPersonalInfo doesn't reject non-student targets; nonexistent-id probe not audited (not-found before audit).
- **Task 5** — cross-college course+college correction impossible via requests (admin edit path is workaround; "Correct the course first" copy misleading).
- **Task 5** — consent check accepts any policyVersion (no re-consent on policy change).
- **Task 5** — name correction values not character-restricted.
- **Task 5** — tests missing for R7, legacy fallback in counselor view, college-correction approve success.
- **Task 6** — infoIncomplete predicate differs between exact-key and scan paths; no-op status changes still audit/toggle Auth; Auth update after commit (row deactivated, user enabled on failure); revoke on deactivated row mints unusable code; ~1h residual ID-token access after deactivate (no accountStatus set); tests don't assert tokensValidAfterTime; backfill test flags all shared-emulator students; partial backfill on concurrent delete; provisioning block precedes existing-profile return.
- **Task 7** — parsing helpers are public top-level in models file; parseIso falls back to epoch (nullable expiresAt would be cleaner).
- **Task 8** — post-activation sign-in failure doesn't clear session/sign out; signInWithEmail duplicates signIn; unnecessary ignore comment; _alreadyActivated flag reused for sign-in button; mismatch/expired errors shown on step 2; dead signup params (yearLevel/course); password min-length inconsistent between activation (8) and signup.
- **Task 9** — isStudentProfile comment claims to mirror client but order/normalization differ (role vs declaredRole precedence, case); _consent stays true after first edit-mode save; college→id matched by name (falls back to all courses).
- **Task 10** — header sign-out skips roster leave guard; no beforeunload guard (tab close loses codes); serials <61 off by one (irrelevant for DOB); t="d" ISO cells shifted in 1904 mode; edit dialog resends unchanged college/course; numeric Student No. cells lose leading zeros (template note); corrections show pending only; one import record per chunk; edit dialog can't prefill name/DOB.
- **Task 10** — choosing a new file clears the partial-import banner; codes of an in-flight chunk lost if admin leaves mid-chunk (warned; recover via Issue new activation code); probe "honours" branch untestable on excel_plus 2.20.0.
- **Task 11** — category+view-action combination is dead (SECURITY category absent from options); activity row shows raw student uid; no test for the Profiling dialog wiring; button spacing in _WorkCard; per-student "who viewed X" needs a console query (no targetId+action index, no UI).
- **Task 11** — dead ternary left in fallback; index error copy shown for any view-filter failure (incl. network); emulator after() deletes users/{adminUid}; error state replaces filter row (must retry to change filters).

## Known limitations to carry into operations

- **Deactivation leaves a ~1 hour access window.** Deactivating a roster row disables the Auth account
  and revokes refresh tokens, but an already-issued ID token stays valid until it expires. Revocation
  additionally sets `accountStatus: "revoked"`, which the Student Information save path honours
  immediately. Prefer revocation when access must stop at once.
- **Codes for an in-flight import chunk are lost if the admin leaves mid-upload.** The page warns before
  navigation, sign-out and tab close. Recovery is "Issue new activation code" for the affected students.
- **A crash between account creation and profile creation during activation** can leave an Auth user with
  no profile. That student cannot self-recover (self-registration is blocked by design); an admin must
  delete the orphaned Auth user, or the student can activate with a different email address.
- **Employee self-signup always registers Teaching.** Pre-existing behaviour, unchanged by this work:
  non-teaching staff cannot self-identify in the app and need an admin to correct the role afterwards.
- **The web `beforeunload` guard is covered by an injected-seam unit test only.** A real tab-close cannot
  be dispatched from the Flutter VM test runner — worth one manual check on a web build at rollout.

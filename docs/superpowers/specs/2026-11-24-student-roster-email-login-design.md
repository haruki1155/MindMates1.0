# Student login by roster email — design

Status: draft for approval. Base: `integrate/student-id-roster-email-20261124` (`e64dc5f`), new branch `feat/student-roster-email-login`.

## Intent
Students have no activation step. A student whose Student ID is on the roster with an email asks for their login on the login screen; the system emails that roster address the Student ID and a one-time temporary password. They sign in, must set a new password, then fill in Student Information. Employee registration and sign-in are unchanged. Replaces the roster-email auto-activation work in PR #82, which is dropped.

## Goals
- No code verification, no PACC approval, no activation for students. The roster email alone is the proof of identity (PACC chose that mailbox).
- Flow: login screen "Email me my login" → email → sign in → forced Change password → Student Information → Home.
- Reuse the alias login (`<id>@students.mindmate.local`), the SMTP mailer and rate limiting in `student_account_recovery.ts`, the roster link, and the `mustChangePassword` flag pattern from the admin portal.

## Non-goals
- Employee flows. Roster rows with no email (they get no login; the screen says to see PACC). Migrating existing accounts (QA-2026-0001/2/3 keep working). Link-based "set your password" emails.

## Constraints
- Staging only until told otherwise; no Production, no deploys, no push or merge without explicit authorization. Removing the old activation Functions from hosted Staging is a separate authorized step.
- Never reveal whether a Student ID exists or has an email: same response for every request.
- `mustChangePassword` and role fields must not be client-writable (verify Rules). Password-change completion is confirmed on the server, not trusted from the client.

## Approaches
1. **Rework on the integration branch (chosen):** delete setup screens, code verification and Account requests; add one callable and one Change password screen. Least new code.
2. Restart from `main`: cleaner history, but re-creates the alias login, rules, mailer and tests.
3. Email a set-password link: safest mailbox exposure, but not what was asked.

## Design
**Callable `requestStudentLogin` (+ `Dev` twin, App Check like the existing pair):** input Student ID. Always returns the same neutral result. Behind it: roster row exists, active and has an email → (a) no Auth user yet: create the alias user with a random temporary password, `users/{uid}` role student, `mustChangePassword: true`, roster link, ID reservation; (b) user exists and `mustChangePassword` still true: rotate the temporary password; (c) user exists and has already changed it: send nothing, the student uses Forgot password (existing flow, same roster email). Email contains Student ID and password only. Rate limits via `consumeWindow` per Student ID and per IP. Audit entry, no password in logs.

**App:** login screen button "Activate student account" becomes "Email me my login" (Student ID field, neutral confirmation). After sign-in, `auth_flow_routes.dart` routes `mustChangePassword` → new Change password screen → callable `completeStudentPasswordChange` (server checks the password really changed after the temporary one was issued, e.g. via `tokensValidAfterTime`, then clears the flag) → existing `personalInfoRequired` gate → Student Information.

**Removed:** `student_activation_screen`, recovery verification screen, setup callables, claim approval, Account requests tab, pending-claim collections' use. Roster import keeps the Email column (now required for a login).

## Known limits (builder to keep, not fix)
- The temporary password has no timed expiry: it stays valid until used or rotated by a new request. Enforcing expiry would need a custom login.
- A password in an email is only as safe as the mailbox; forced change at first login is the mitigation.

## V2 security revisions (approved 2026-11-24, supersede the sections below and above where they differ)
- Temporary passwords have a **server-enforced expiry (24 h)**. An expired issuance can never complete a password change; the student requests a new login.
- Requests do **not** rotate an unexpired temporary password on every call. Reissue (which rotates) only after expiry, or after a 60-minute cooldown with at most 3 issues per 24 h.
- The first-login restriction is a **custom Auth claim `firstLoginPending`**, enforced in Firestore Rules (`signedIn()`), callables (`requireUid` and every direct `request.auth` reader) and the Flutter gate. Only own-profile read is allowed while pending.
- The permanent password is set **server-side** (`completeStudentPasswordChange`, Admin `updateUser`) after recent-auth, UID, roster, issuance-expiry and password-policy checks and rejection of temp-password reuse (server-only scrypt hash). The claim and `mustChangePassword` clear only after Auth succeeds; an interrupted completion is reconciled on the next sign-in.
- The roster email is stored as a verified recovery contact at issuance so the existing Forgot Password flow works unchanged after setup.
- Existing activation/setup Functions stay deployed; only the app's entry points are removed.

## Left to the builder
Exact email wording, rate-limit numbers (suggest 3/hour per ID, 10/hour per IP), password length/charset (suggest 12 chars, no ambiguous characters), test layout, and migrating tests that assumed activation.

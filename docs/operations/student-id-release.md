# Student ID sign-in and account setup: Staging release (PR #82)

Status as of 2026-11-25, read-only checks against `mindmate-staging`. Nothing here deploys
on its own. Every backend step needs separate owner approval and targets
`--project mindmate-staging` only.

## What Staging runs today

Staging's backend is **ahead** of both `main` and this PR:

| Component | Deployed from | When (UTC) |
|---|---|---|
| Student setup, recovery and claim-review callables | this PR's student code (`f58c79a`) | 2026-11-23 |
| Firestore rules (first-login gate) | `feat/student-roster-email-login` (`475d7d1`, local, unpushed) | 2026-11-24 07:31 |
| 118 callables (first-login gate) plus `requestStudentLogin(Dev)` and `completeStudentPasswordChange` | `feat/student-roster-email-login` | 2026-11-24 07:33–07:36 |
| School-ID resolvers and admin reset (D2/D3b containment) | `feat/student-self-claim-staging-integration` (`32c31db`, `2246a26`, local, unpushed) | 2026-11-21 |
| TTL policies `_student_recovery_limits`, `student_recovery_verifications`, `student_claim_pending` | already active | |

One `student_login_issuance` record exists (counted only; contents not read).

## This PR needs no backend deployment

Every callable and TTL policy this PR adds is already live, and the deployed student code
matches the PR. Merging only redeploys the Staging Admin Web through the Hosting workflow.

**Do not deploy Functions or rules from this PR or from `main`.** It would:

- remove the first-login gate from the rules and from 118 callables while a roster-email
  login exists;
- replace the non-disclosing School-ID resolver with `main`'s version, which reads
  reservations and Auth accounts. `main` lacks `32c31db` and `2246a26`.

## Rollout order

1. **Merge this PR** (owner approval). The Hosting workflow deploys Staging Admin Web.
   Router change in this PR: App Check builds (the live Admin Web) call protected callables.
   The ordinary Staging APK keeps the Dev aliases. Every protected callable the router can
   select is deployed on Staging, except `sendMindAidMessage`, which is not deployed in
   either form (pre-existing).
2. **Integrate the Staging-only work into `main`** (branch
   `integrate/staging-backend-reconciliation`):
   - merges `feat/student-roster-email-login` onto `main`;
   - ports the pure School-ID resolver handler (`32c31db`), byte-identical to the deployed one.
   Checked against the deployed source archives: every file Staging's 2026-11-24 deploy
   ran is in this branch, which differs only by `main`'s newer recovery-link code and the
   resolver. The admin reset hardening (`2246a26`: timing floor, Dev project gate) is
   **not** in it; PR #78 carries it.
3. **PR #78** after step 2. It carries the admin reset hardening from `2246a26`: the reset
   handler and rate limit are identical to the deployed `requestAdminPasswordReset-00007`, and
   `requestAdminPasswordResetDev` refuses Staging. It also makes `requestStaffEmailVerificationDev`
   refuse production and unknown projects (Staging and Dev unchanged).

   The deployed `resolveSchoolIdAuthEmailDev` (`00008`) refuses on Staging and has **no invoker**
   binding. `main`'s Dev resolver (after `fix/staging-dev-resolver-project-gate`) serves Staging and
   Dev only and refuses production and unknown projects. The handler is pure either way.
   The current client does not need it for roster-email students: Student ID sign-in derives the
   `students.mindmate.local` alias locally. Only the legacy "School ID" sign-in and reset path
   calls the resolver.
4. **Recovery links**, after #78 is merged, from a clean worktree of that `main` commit with
   `functions/.env.mindmate-staging` copied in and `ADMIN_WEB_URL=https://paaccmindmate.com`
   (HTTPS and `/reset-password` verified 2026-11-25):

   ```sh
   FUNCTIONS_DISCOVERY_TIMEOUT=90 firebase deploy --project mindmate-staging --only functions:requestAdminPasswordReset,functions:requestStaffEmailVerification,functions:requestStaffEmailVerificationDev
   ```

   `requestAdminPasswordResetDev` is deliberately excluded. Its deployed revision (`00008`)
   already refuses Staging and has no invoker. firebase-tools 15.34.1 leaves invoker IAM alone
   when it updates a callable function, but sets `allUsers` when it creates one, so the no-invoker
   state cannot be guaranteed by a deploy. The three deployed functions keep their current
   invoker (`allUsers`).

   Afterwards: re-read the invoker policy of all six recovery and resolver services, and confirm
   `requestAdminPasswordResetDev` and `resolveSchoolIdAuthEmailDev` still have none.

5. **Legacy School-ID resolver** (separate approval, only if legacy School ID accounts must sign in
   from the Staging APK):

   ```sh
   FUNCTIONS_DISCOVERY_TIMEOUT=90 firebase deploy --project mindmate-staging --only functions:resolveSchoolIdAuthEmail,functions:resolveSchoolIdAuthEmailDev
   gcloud run services add-iam-policy-binding resolveschoolidauthemaildev --project mindmate-staging --region us-central1 --member=allUsers --role=roles/run.invoker
   ```

   The deploy alone does not reopen the Dev resolver: the IAM grant does. Undo with
   `gcloud run services remove-iam-policy-binding` (same arguments).

Never use `--force` or an unrestricted `firebase deploy`.

Indexes: none to deploy. If a future change adds some, use
`firebase deploy --project mindmate-staging --only firestore:indexes` and never `--force`.

## Before each backend deploy

```sh
gcloud functions list --project mindmate-staging --regions us-central1 \
  --format="value(name,updateTime,serviceConfig.revision)" > baseline-functions.txt
gcloud run services get-iam-policy requestadminpasswordresetdev \
  --project mindmate-staging --region us-central1
firebase firestore:indexes --project mindmate-staging > baseline-indexes.json
```

Note the current Firestore rules release (Firebase console, Firestore, Rules, History).

## Rollback

- **Admin Web:** Firebase Hosting, `mindmate-staging`, Release history, roll back. Or revert
  the merge commit.
- **Functions:** route traffic back to the recorded revision, per function:
  `gcloud run services update-traffic <service> --to-revisions=<revision>=100 --project mindmate-staging --region us-central1`.
  Never roll the School-ID resolvers back to `00007-*` (they disclose emails).
  Revisions serving on 2026-11-25, before the recovery deploy: `requestadminpasswordreset-00007-jaj`,
  `requestadminpasswordresetdev-00008-mub`, `requeststaffemailverification-00005-hez`,
  `requeststaffemailverificationdev-00005-yex`, `resolveschoolidauthemail-00008-mol`,
  `resolveschoolidauthemaildev-00008-rex`.
- **Rules:** re-release the recorded ruleset. Re-releasing a ruleset older than the first-login
  gate lifts the gate for any account still on a temporary password, so finish or revoke
  those logins first.
- **Data:** issuance, recovery and claim records are additive. Do not delete them without
  separate approval.

## Security review (2026-11-25)

Scope: roster-email login and temporary passwords (`feat/student-roster-email-login`), this
PR's account setup and Student ID recovery, and their App Check routing. No Critical findings.

| Severity | Finding | Status |
|---|---|---|
| High | App Check builds still routed to Dev aliases that skip App Check | Fixed in this PR |
| High | Staging runs code that exists only in two unpushed local branches; a deploy from `main` would undo the first-login gate and the resolver containment | Process: rollout step 2 |
| Medium | Unauthenticated Dev endpoints (`startStudentAccountSetupDev`, `requestStudentPasswordResetDev`, `requestStudentLoginDev`) are invocable by `allUsers` and skip App Check. They remain because the ordinary Staging APK has no App Check provider | Owner decision: remove their invoker once the Staging APK ships with App Check |
| Medium | Per-IP limits use `rawRequest.ip`; if the runtime trusts `X-Forwarded-For`, they can be bypassed. Per-Student-ID limits still apply. Same pattern as existing staff recovery | Verify on the runtime; open |
| Medium | A temporary password keeps signing in after its 24-hour expiry. The session stays confined by the first-login gate, and the change is refused as expired | Open (roster-email-login branch) |
| Low | Storage rules do not exclude first-login sessions (profile images any signed-in user can already read; own avatar upload) | Open (roster-email-login branch) |

Checked and sound:

- Uniform responses and minimum response time on the unauthenticated endpoints.
- Per-Student-ID limits that never lock a student out.
- Codes and temporary passwords stored only as scrypt hashes; codes are single use with an
  attempt cap.
- Mail goes only to roster or verified addresses.
- Automatic approval only when the verified email is the roster email.
- Administrator approval requires an identity attestation and re-checks the live roster in a
  transaction.
- Dev endpoints refuse production and unknown projects.
- Firestore first-login confinement (`signedIn()` and `currentAccessRole()`), and the callable
  gate in `requireUid`.

## Remaining browser acceptance (synthetic accounts only)

On `https://paaccmindmate.com` (private window), the Staging Admin Web after the merge:

1. Sign-in as a synthetic admin; sidebar, dashboard cards, header, dialogs, tables and action
   icons render.
2. Forgot password on the admin login sends a link that opens `/reset-password` on the
   Firebase host. This exercises the protected `requestAdminPasswordReset` with App Check.
3. Account requests tab: list, approve (with identity attestation) and reject a synthetic claim.
4. Roster: import a synthetic row; confirm a roster-email login issues mail only to that row's
   address.

Staging APK (`--flavor staging`, no App Check), synthetic students:

5. Account setup with a roster email: code arrives at the roster address; claim approves
   automatically.
6. Account setup without a roster email: waits for approval; appears in the admin tab.
7. Student ID password reset: same response for unknown and real IDs; mail only to the
   verified address.
8. Roster-email login: temporary password, forced change cannot be skipped, gated callables
   refuse the first-login session.

`www.paaccmindmate.com`: confirm the certificate is active and it redirects to the apex.

## Vercel retirement

The conditions and steps are in `firebase-hosting-cicd.md`, section "Retiring Vercel (gated)".
State on 2026-11-25:

- Custom domain served by Firebase with an active certificate: **done** (apex). `www` is
  still waiting for its certificate.
- Staging deploys and previews accepted: **done**.
- Sign-in, App Check and recovery links verified on Firebase: **open** (browser steps 1–2,
  and rollout step 4).
- Production unaffected: **done**.

Remaining references on `main`:

- `vercel.json`, `web/vercel.json`, `tool/vercel_build.sh` and `tool/test_vercel_build.sh`;
- the Vercel guard in `lib/admin_main.dart`;
- `mindmate-admin-staging.vercel.app` in the email-action allowlists and their tests;
- the Vercel rewrite test in `functions/src/account_recovery_email.test.ts`.

The Vercel GitHub app still builds and comments on every PR. The old
`mindmate-admin-staging.vercel.app` host returns 404.

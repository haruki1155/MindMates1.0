# Admin Web hosting: Firebase Hosting CI/CD

The staff Admin Web portal (`lib/admin_main.dart`, output `build/web`) is
hosted on Firebase Hosting. Vercel served it before. This page covers the
GitHub workflows, the credentials they need, and how to roll back.

| Environment | Firebase project | URL | How it deploys |
|---|---|---|---|
| Staging live | `mindmate-staging` | `https://mindmate-staging.web.app`, later `https://paaccmindmate.com` | Automatically after a verified push to `main` |
| PR preview | `mindmate-staging` | `https://mindmate-staging--pr-<N>-<hash>.web.app` | Automatically after a PR commit is verified |
| Production | `mind-mates-cd2cf` | `https://mind-mates-cd2cf.web.app` | Manually only (`firebase-hosting-production.yml`) |

`test/tooling/hosting_deploy_targets_test.dart` runs in the full Flutter suite.
It fails if a routine workflow can reach production, deploy backend resources,
expose the deploy credential outside a `main`-only environment, or bypass the
verification gate. `ci/preview_deploy_gate_test.py` covers the gate's decision
logic.

## Workflows

- **`android-verify.yml`** (unchanged) runs on every PR and every push to
  `main`: `flutter analyze`, the full Flutter suite, the Functions build, the
  Functions emulator suite, and the Android flavor builds. It is the quality
  gate. The Hosting workflows reuse its result instead of repeating it.
- **`firebase-hosting-pull-request.yml`** ("Build staging Admin Web preview")
  runs for PRs into `main`. It has no secrets and does not deploy. It tests the
  gate logic, builds with `APP_ENV=staging`, checks the bundle, and uploads it
  as a seven-day artifact. A newer commit cancels the older build.
- **`firebase-hosting-preview-deploy.yml`** runs (`workflow_run`) whenever
  either workflow above completes. Because of `workflow_run`, its definition,
  scripts and `firebase.json` always come from `main`. The PR's code reaches it
  only as the static bundle.
  - `gate` (`ci/preview_deploy_gate.py`) deploys only if all of these hold:
    the PR is open, from this repository, and targets `main`; the commit is
    still the PR head; and the latest runs of **both** workflows for that
    commit concluded `success`.
  - Failed, cancelled, timed-out or missing runs never deploy. While one run is
    still going, the gate waits for its completion to trigger it again.
  - Both required checks run the PR's own workflow files, so a PR could fake
    a pass by editing them. A PR that changes anything under `.github/` or
    `ci/` therefore gets no preview; it deploys only after review and merge.
    Previews still run the PR's own application code by design. Add required
    reviewers to `staging-preview` if that needs human approval too.
  - `deploy` uses the `staging-preview` environment. It checks out `main`,
    downloads that exact artifact, verifies the credential, and re-checks that
    the commit is still the PR head. It then deploys to `pr-<N>`, which
    expires after 7 days, and writes or updates one PR comment with the URL,
    commit and expiry.
  - Deploys for the same PR are serialized, and a deploy never cancels
    anything. Closing the PR cancels a running deploy.
- **`firebase-hosting-preview-cleanup.yml`** runs on PR close
  (`pull_request_target`, so the definition and checkout come from `main`; it
  never runs PR code). It cancels any in-flight deploy for that PR and deletes
  `pr-<N>`. It refuses any channel id that does not match `^pr-[0-9]+$`, so it
  can never delete `live`.
- **`firebase-hosting-merge.yml`** runs when `Verify Android flavors` completes
  successfully for a push to `main`, or manually (`workflow_dispatch`, `main`
  only, and only for a commit with a successful verify run).
  - It uses the `staging` environment, checks out that exact commit, builds it
    for staging with App Check on, and deploys Hosting only to the `live`
    channel of `mindmate-staging`.
  - It skips the deploy if `main` has moved on, because the newer commit
    deploys through its own run. Live deploys are serialized.
  - If a skipped commit is followed by one that fails verification, staging
    stays on the older release until `main` is green again.
- **`firebase-hosting-production.yml`** deploys production. It is manual,
  needs the confirmation input, runs only from `main`, and uses the
  `production` environment. It accepts only the dedicated
  `github-hosting-deployer@mind-mates-cd2cf` key in
  `FIREBASE_SERVICE_ACCOUNT_MIND_MATES_CD2CF`. There is no fallback, so it
  fails until that key exists.

## Credential boundary

Every deploy job runs `ci/verify_hosting_deployer.sh`, which does two checks:

1. The key's metadata must name the expected Hosting-only account of the right
   project.
2. The account's **effective** IAM permissions must allow Hosting deploys and
   include none of the sensitive permissions in
   `ci/verify_deployer_least_privilege.py` (IAM policy, keys, Firestore, Auth,
   Storage, Functions, Cloud Run, Secret Manager, Rules, App Check). It checks
   this through `projects.testIamPermissions`, so it catches broad roles
   however they were granted.

Only these jobs can read the deploy key:

- It is stored as an **environment secret** of `staging` and `staging-preview`,
  and both environments allow deployments from `main` only.
- A workflow edited inside a PR runs on the PR ref, so it cannot read the key,
  even if it names the environment.
- Jobs that can read it run workflow code from `main`. They handle PR changes
  only as a static bundle uploaded to a preview channel.

## Owner setup (one time)

### 1. Staging deployer (Hosting only)

```bash
gcloud iam service-accounts create github-hosting-deployer \
  --project mindmate-staging \
  --display-name "GitHub Actions: Hosting deploy (staging only)"
gcloud projects add-iam-policy-binding mindmate-staging \
  --member "serviceAccount:github-hosting-deployer@mindmate-staging.iam.gserviceaccount.com" \
  --role roles/firebasehosting.admin --condition None
# Must list exactly one role: roles/firebasehosting.admin
gcloud projects get-iam-policy mindmate-staging --flatten="bindings[].members" \
  --filter="bindings.members:github-hosting-deployer@" --format="value(bindings.role)"
```

Grant nothing broader. Firebase Authentication Admin is deliberately left out,
so previews cannot add their hostnames to Auth's authorized domains
(firebase-tools logs a warning and continues). If a deploy fails reading API
keys, the only extra role to consider is `roles/serviceusage.apiKeysViewer`.
The workflow's IAM check would reject anything broader.

### 2. GitHub environments and secret

1. Settings, Environments: create `staging` and `staging-preview`. For both,
   set Deployment branches and tags to **Selected: `main`**. Optionally add
   required reviewers to `staging-preview` so that each preview needs approval.
2. Create a key and store it as an **environment secret** named
   `FIREBASE_SERVICE_ACCOUNT_MINDMATE_STAGING` in both environments. Then
   delete the local key file, and delete the repository-level secret of that
   name (the old Admin SDK key):

   ```bash
   gcloud iam service-accounts keys create deployer.json \
     --iam-account github-hosting-deployer@mindmate-staging.iam.gserviceaccount.com
   gh secret set FIREBASE_SERVICE_ACCOUNT_MINDMATE_STAGING -R haruki1155/MindMates1.0 --env staging < deployer.json
   gh secret set FIREBASE_SERVICE_ACCOUNT_MINDMATE_STAGING -R haruki1155/MindMates1.0 --env staging-preview < deployer.json
   rm deployer.json
   gh secret delete FIREBASE_SERVICE_ACCOUNT_MINDMATE_STAGING -R haruki1155/MindMates1.0
   ```

3. Separately, check whether the old Admin SDK key
   (`firebase-adminsdk-fbsvc@…`, created 2026-09-27) is used anywhere else.
   Then disable it and finally delete it.
4. Branch protection for `main`: require `Verify Android flavors` and the
   `build` check of "Build staging Admin Web preview".
5. Disable the Hosting workflows of the retired repository
   `haruki1155/mind_mates`. Its `main` still deploys to **production** on every
   push.

### 3. Production deployer (before any production deploy)

Repeat step 1 in `mind-mates-cd2cf` (account
`github-hosting-deployer@mind-mates-cd2cf`). GitHub environment names are not
case-sensitive, so `environment: production` uses the existing
Vercel-created **Production** environment. As of 2026-11-24 it had no
protection rules. Add required reviewers and a `main`-only branch policy to it
first. Store its key as an environment
secret `FIREBASE_SERVICE_ACCOUNT_MIND_MATES_CD2CF` of `production`, restricted
to `main` and with required reviewers. Then remove the repository secrets
`FIREBASE_SERVICE_ACCOUNT` and `FIREBASE_SERVICE_ACCOUNT_MIND_MATES_CD2CF`.

### 4. Workload Identity Federation (follow-up)

WIF would remove the stored key. `action-hosting-deploy` accepts only a JSON
key, so WIF means deploying with the Firebase CLI through
`google-github-actions/auth`. The provider must be restricted to this
repository and to these workflow files on `main`
(`assertion.job_workflow_ref`). It is not part of this change because it
cannot be validated without that IAM setup.

## App Check, Authentication and previews

- **Live staging** builds with `ENABLE_STAGING_APP_CHECK=true` and the
  staging reCAPTCHA Enterprise key `6Le17JgtAAAAACbHth-LPHcS_P2n4ejBuddUYReM`.
  That key is registered in App Check for the staging web app and allows
  `mindmate-staging.web.app`, `paaccmindmate.com` and `www.paaccmindmate.com`.
  `mindmate-staging.firebaseapp.com` is deliberately not on it, so App Check
  fails there. Recovery links never point to it; use the `web.app` host. The
  production key likewise allows only `mind-mates-cd2cf.web.app`.
- **Callables:** on staging, `lib/services/firebase/firebase_callable_router.dart`
  still routes the listed callables to their `…Dev` aliases. Routing them to
  the App Check-protected callables is application work in PR #78.
  Enforcement for Firestore, Storage and Auth is `UNENFORCED` on staging
  (2026-11-24) and is not changed here.
- **Backend:** backend enforcement is unchanged. Development and production
  App Check behavior is unchanged.
- **Previews** build without App Check. Their hostnames are random, so they
  cannot be on the key without allowing all domains, which is not allowed.
  They are **limited UI testing**:
  - Sign in only with disposable staging test accounts.
  - Do not test App Check-protected callables or email links there.
- **Data:** previews use the shared staging backend, with the same Auth and
  Firestore rules as live staging, so they can show whatever staging holds.
  Staging must therefore contain only synthetic records, never real student or
  counselling data. If real data must ever be in staging, previews need a
  separate test project (with its own Firebase config and seeded synthetic
  data) before they are used again.
- **Auth authorized domains** should contain `mindmate-staging.web.app`,
  `mindmate-staging.firebaseapp.com` and `paaccmindmate.com`. Keep the Vercel
  host until Vercel is retired. Remove the 41 stale `mindmate-staging--pr…`
  entries (found 2026-11-24). Email and password sign-in does not need preview
  domains.

## Runtime configuration (separate Functions deploy, not part of this change)

The recovery and verification emails take their link origin from the
`ADMIN_WEB_URL` Functions parameter. Only allowlisted HTTPS origins are used:

- Staging: `mindmate-staging.web.app`, `paaccmindmate.com`,
  `www.paaccmindmate.com`. Anything else, including the old Vercel host,
  falls back to `https://mindmate-staging.web.app`.
- Production: `mind-mates-cd2cf.web.app` only. Anything else falls back to it.
- These are exactly the domains on each project's reCAPTCHA Enterprise key.
  The `firebaseapp.com` hosts are not on the keys, so App Check fails there,
  and recovery links never point to them.

Password-reset links use the app route `/reset-password`, because Firebase
Hosting reserves `/__/*`.

Deploy Hosting before these Functions. When they are deployed (separately
authorized, by name, never `--force`), the callables are:
`requestAdminPasswordReset`, `requestAdminPasswordResetDev` and
`requestStaffEmailVerification`. Set `ADMIN_WEB_URL=https://paaccmindmate.com`
only after the custom domain shows **Connected** and serves the app over HTTPS.

## Cost controls

- PR builds are cancelled by newer commits. Previews expire after 7 days and
  are deleted on close. Bundles are kept as seven-day artifacts. The Flutter SDK
  is cached. The test suites run once, in `android-verify.yml`.
- Firebase console, Hosting, Release storage: keep about the last 10 releases.
- Cloud Billing, Budgets: `mindmate-staging` only, USD 5 per month, alerts at
  50%, 80% and 100%. Budgets send alerts; they do not cap spending.
- Review GitHub Actions minutes under Settings, Billing.

## Transition from the legacy workflows

The legacy staging Hosting workflows are the same files,
`firebase-hosting-merge.yml` and `firebase-hosting-pull-request.yml`. Merging
this change replaces them in place, so nothing needs disabling in this
repository. The two new files (`firebase-hosting-preview-deploy.yml` and
`firebase-hosting-preview-cleanup.yml`) become active when they reach `main`.
`workflow_run` only fires from definitions on the default branch, so nothing
new runs before the merge. Non-Hosting CI (`android-verify.yml`,
`mood-v2-emulator-validation.yml`) is unchanged.

**Before merge**

1. Keep the repository-level secret `FIREBASE_SERVICE_ACCOUNT_MINDMATE_STAGING`
   for now. The current `main` merge workflow, and preview runs of other open
   PRs, still use it.
2. Branch protection: if the old job name `build_and_preview` is a required
   check, replace it with `build` ("Build staging Admin Web preview").
   Otherwise this PR and every later PR stay blocked waiting for a check that
   no longer exists. Keep the `Verify Android flavors` checks required.
3. Optionally disable "Inspect staging Hosting credential identity only"
   (branch `fix/hosting-preview-identity-diagnostic`). It reads the
   repository-level secret.
4. This PR's own checks: "Verify Android flavors" and "Build staging Admin Web
   preview" (which also runs `ci/preview_deploy_gate_test.py`) must pass. It
   gets no preview. The deploy workflow is not on `main` yet, and PRs that
   change `.github/` or `ci/` are never previewed.

**Merge**

5. Merge with owner approval. The push to `main` runs "Verify Android
   flavors". On success, the new merge workflow deploys staging live through
   the `staging` environment.

**After merge**

6. Actions tab: confirm that all five Hosting workflows are listed as active
   (`firebase-hosting-merge`, `-pull-request`, `-preview-deploy`,
   `-preview-cleanup`, `-production`).
7. Confirm that the first staging deploy succeeded:
   - its "Verify the deploy credential and its actual IAM permissions" step
     printed that the identity holds Hosting deploy rights only;
   - Deployments shows `staging`;
   - the Hosting release history shows the merge commit.
8. Only then delete the repository-level secret
   `FIREBASE_SERVICE_ACCOUNT_MINDMATE_STAGING`. From then on, any old-style run
   (for example a PR branch that still carries the old workflow file) fails
   closed instead of deploying with the Admin SDK key.
9. Run the acceptance procedure below. Retiring the old Admin SDK key needs
   separate approval.

## Integration with PRs #78 and #82

Recommended order: **this PR, then #82, then #78**, each rebased on the
updated `main`. A trial merge of all three was resolved as below. With #78's
test updated, the recovery and reset suites passed in the emulators (14/14).

- **#82** (merges cleanly into `main` today). Against this PR it conflicts in
  both Hosting workflows, `docs/admin_web_deployment.md` and
  `account_recovery.ts`.
  - Take this PR's workflows and docs. #82's
    `RECAPTCHA_ENTERPRISE_SITE_KEY_STAGING` secret and its build checks are
    superseded by the key in `firebase-hosting-merge.yml`, and that missing
    secret is what currently fails its preview.
  - In `account_recovery.ts`, keep #82's `export` of `smtpAppPassword` and this
    PR's `ADMIN_WEB_URL` default of `""`.
- **#78** (already conflicts with `main` in
  `appointment_availability_callable.test.ts` and
  `firebase_callable_router_test.dart`; those are its own conflicts).
  - Take this PR's `firebase-hosting-merge.yml`: it already builds with
    `ENABLE_STAGING_APP_CHECK=true` and the key.
  - Take this PR's `resolveStaffVerificationWebUrl`. It covers #78's
    production Vercel handling, and `OBSOLETE_ADMIN_WEB_HOSTS` no longer
    exists.
  - Keep #78's injectable `processAdminPasswordReset`, which already calls the
    resolver. Update its comment about `paaccmindmate.com` and
    `/__/auth/action`.
  - Take this PR's `account_recovery_email.test.ts`.
  - In `admin_password_reset.test.ts`, "Staging reset links use the supported
    admin host's action handler" must expect `https://mindmate-staging.web.app`
    and `/reset-password`.
  - #78's `staging_admin_web_build_config_test.dart` matches this PR's
    workflows unchanged.
  - #78's router change (protected `requestAdminPasswordReset` on staging)
    needs the App Check build enabled here.
- **Functions deploy:** after #78 is merged, the recovery callables still need
  a separately authorized Functions deploy. See "Runtime configuration".

## Acceptance procedure (after merge)

1. Open a draft PR from a branch of this repository that changes only app code
   (for example a comment in `lib/`). "Build staging Admin Web preview" and
   "Verify Android flavors" run. When both pass, "Deploy staging Firebase
   Hosting preview" deploys `pr-<N>` and comments the URL, commit and expiry.
   The deploy run shows the `staging-preview` environment, and its IAM step
   passes.
2. Push another commit. The same channel and comment update, and the old
   commit is never deployed after the new one (its gate or freshness step logs
   "Stale").
3. Push a commit that fails a test (test branch only). The gate logs the
   failure and nothing is deployed.
4. Push a commit that touches `ci/`. The gate logs "changes CI definitions" and
   nothing is deployed.
5. `https://mindmate-staging.web.app` still shows the previous release (Hosting,
   Release history: `live` is unchanged).
6. Close the PR. The cleanup workflow deletes `pr-<N>`
   (`firebase hosting:channel:list --project mindmate-staging`).
7. After the next approved merge, the merge workflow deploys after "Verify
   Android flavors". On `https://mindmate-staging.web.app`, the browser
   console shows no App Check errors and sign-in works.
8. Production Hosting release history is unchanged.

## Rollback

- **Staging Hosting:** Firebase console, Hosting, Release history, roll back.
  Or `firebase hosting:clone mindmate-staging:<previous-version> mindmate-staging:live`.
- **App Check on live staging:** remove the two App Check `--dart-define`s
  from `firebase-hosting-merge.yml` and redeploy.
- **Workflows:** revert the merge commit of this change. Vercel keeps serving
  `paaccmindmate.com` until DNS has fully moved.
- **Recovery links:** set `ADMIN_WEB_URL=https://mindmate-staging.web.app` and
  redeploy the three callables above.

## Retiring Vercel (gated)

Do this only after all of the following:

- the custom domain is Connected with an active certificate;
- staging deploys and previews have passed the acceptance procedure;
- sign-in, App Check and recovery links have been verified on Firebase;
- production is confirmed unaffected.

Then, with owner approval:

- Remove Vercel's required status checks.
- In a separate PR, remove `vercel.json`, `web/vercel.json`,
  `tool/vercel_build.sh`, `tool/test_vercel_build.sh`, the Vercel guard in
  `lib/admin_main.dart`, and the Vercel host from the email-action allowlists.
- Disconnect the Vercel project, and remove the Vercel host from Auth
  authorized domains.

# Admin Web hosting: Firebase Hosting CI/CD

The staff Admin Web portal (`lib/admin_main.dart`, output `build/web`) is
hosted on Firebase Hosting. Vercel served it before. This page covers the
GitHub workflows, the credentials they need, and how to roll back.

| Environment | Firebase project | URL | How it deploys |
|---|---|---|---|
| Staging live | `mindmate-staging` | `https://mindmate-staging.web.app`, later `https://paaccmindmate.com` | Automatically after a verified push to `main` |
| PR preview | `mindmate-staging` | `https://mindmate-staging--pr-<N>-<hash>.web.app` | Automatically for same-repository PRs |
| Production | `mind-mates-cd2cf` | `https://mind-mates-cd2cf.web.app` | Manually only (`firebase-hosting-production.yml`) |

`test/tooling/hosting_deploy_targets_test.dart` runs in the full Flutter suite
and fails if a routine workflow can reach production, deploys backend
resources, or stops using the pinned action and the Hosting-only credential.

## Workflows

- **`android-verify.yml`** (unchanged) runs on every PR and every push to
  `main`: `flutter analyze`, the full Flutter suite, the Functions build and
  the Functions emulator suite, and the Android flavor builds. It is the
  quality gate. The Hosting workflows do not repeat it.
- **`firebase-hosting-pull-request.yml`** runs for PRs into `main`.
  - `build` has no secrets. It builds with `APP_ENV=staging`, checks that the
    bundle carries the `mindmate-staging` config, and uploads the bundle as a
    one-day artifact. Tests run in `android-verify.yml`.
  - `deploy_preview` runs only for branches of this repository (never forks or
    Dependabot). It deploys that artifact to channel `pr-<N>`, which expires
    after 7 days. The action comments the URL, commit and expiry on the PR, and
    updates that comment on each new commit.
  - `cleanup_preview` deletes `pr-<N>` when the PR closes. It refuses any
    channel id that does not match `^pr-[0-9]+$`, so it can never delete
    `live`.
  - A newer commit cancels the PR's older run, so a stale build cannot
    overwrite a newer preview. A failed build never deploys.
- **`firebase-hosting-merge.yml`** runs when `Verify Android flavors` completes
  successfully for a push to `main`, or manually (`workflow_dispatch`, `main`
  only). It checks out that exact commit, builds it for staging, and deploys
  Hosting only to the `live` channel of `mindmate-staging`. It skips the deploy
  if `main` has moved on in the meantime, because the newer commit deploys
  through its own run. Live deploys are serialized.
  If a skipped commit is followed by one that fails verification, staging
  stays on the older release until `main` is green again. A manual run
  recovers this, and it also refuses any commit without a successful
  `Verify Android flavors` run.
- **`firebase-hosting-production.yml`** deploys production. Its credential still falls back to the
  generic `FIREBASE_SERVICE_ACCOUNT` secret. Replace both with a Hosting-only
  production deployer and pin it with `ci/verify_hosting_service_account.py`. It is manual,
  needs the confirmation input, runs only from `main`, and uses the
  `production` GitHub environment. Add required reviewers to that environment
  (Settings, Environments, production) where the GitHub plan allows it.

## Owner setup (one time)

### 1. Hosting-only deploy identity for staging

The staging workflows accept only
`github-hosting-deployer@mindmate-staging.iam.gserviceaccount.com`. Before this
change, the staging secret held a key of the Firebase Admin SDK service account,
which has broad Admin SDK, Auth, Storage and App Check rights. Do not use that
account for CI.

```bash
gcloud iam service-accounts create github-hosting-deployer \
  --project mindmate-staging \
  --display-name "GitHub Actions: Hosting deploy (staging only)"
gcloud projects add-iam-policy-binding mindmate-staging \
  --member "serviceAccount:github-hosting-deployer@mindmate-staging.iam.gserviceaccount.com" \
  --role roles/firebasehosting.admin --condition None
```

`roles/firebasehosting.admin` is the only role it gets. It deliberately does
not get Firebase Authentication Admin, so preview deployments cannot add their
hostnames to Auth's authorized domains. If the first deploy fails reading the
project's API keys, also grant `roles/serviceusage.apiKeysViewer`, and nothing
broader.

Create a key, store it as the repository Actions secret
`FIREBASE_SERVICE_ACCOUNT_MINDMATE_STAGING` (replacing the current value), then
delete the local file:

```bash
gcloud iam service-accounts keys create deployer.json \
  --iam-account github-hosting-deployer@mindmate-staging.iam.gserviceaccount.com
gh secret set FIREBASE_SERVICE_ACCOUNT_MINDMATE_STAGING -R haruki1155/MindMates1.0 < deployer.json
rm deployer.json
```

After that, check whether the old Admin SDK key
(`firebase-adminsdk-fbsvc@…`, created 2026-09-27) is used anywhere else. If it
is not, disable and then delete it in the Cloud console.

A follow-up can replace the stored key with Workload Identity Federation
(restricted to this repository and these workflow files). That means deploying
with the Firebase CLI instead of `action-hosting-deploy`, which accepts only a
JSON key.

### 2. GitHub settings

- Settings, Environments: the merge workflow uses an environment named
  `staging`. GitHub creates it on first use. Optionally, restrict it to the
  `main` branch.
- Settings, Branches, `main`: require the `Verify Android flavors` checks and
  the preview workflow's `build` job before merging.
- Disable the Hosting workflows of the retired repository
  `haruki1155/mind_mates` (Actions, select each workflow, Disable workflow).
  Its `main` still carries a workflow that deploys to **production** on every
  push.

### 3. Runtime configuration (separate Functions deploy)

The recovery and verification emails take their link origin from the
`ADMIN_WEB_URL` Functions parameter. Only allowlisted HTTPS origins are used:

- Staging: `mindmate-staging.web.app`, `mindmate-staging.firebaseapp.com`,
  `paaccmindmate.com`, `www.paaccmindmate.com`. Anything else, including the
  old Vercel host, falls back to `https://mindmate-staging.web.app`.
- Production: `mind-mates-cd2cf.web.app` and `mind-mates-cd2cf.firebaseapp.com`.
  Anything else falls back to `https://mind-mates-cd2cf.web.app`.

Password-reset links use the app route `/reset-password`, because Firebase
Hosting reserves `/__/*` for its own handler.

Deploy Hosting before these Functions, so that the origin the links point to
already serves the current portal. Any configured value that is not on the
allowlist, including the old Vercel host, falls back without an error.

Set `ADMIN_WEB_URL=https://paaccmindmate.com` in
`functions/.env.mindmate-staging` only after the custom domain shows
**Connected** in the Firebase console and serves the app over HTTPS. Until then,
leave it unset or set `https://mindmate-staging.web.app`. Changing it requires
an authorized deploy of `requestAdminPasswordReset`,
`requestAdminPasswordResetDev` and `requestStaffEmailVerification` (by name,
never with `--force`).

## App Check, Authentication and previews

Staging web builds do not enable App Check (`ENABLE_STAGING_APP_CHECK` is not
set). Turning it on for the live staging build is separate work. The staging
reCAPTCHA Enterprise key allows `mindmate-staging.web.app`, `paaccmindmate.com`
and `www.paaccmindmate.com`. Preview hostnames are random per channel, so they
are not on that key. Do not add `web.app` as a whole and do not use debug tokens.

PR previews are therefore **restricted testing**: use them for UI review. Sign
in only with disposable staging test accounts. Do not use previews to test App
Check-protected callables or email-action links. They use the shared staging
backend, so never put real student or counselling records there.

Firebase Authentication authorized domains should contain
`mindmate-staging.web.app`, `mindmate-staging.firebaseapp.com` and
`paaccmindmate.com`. Keep the Vercel host until Vercel is retired. Email and
password sign-in does not need preview domains to be authorized. On
2026-11-24 the list also held 41 old `mindmate-staging--pr…` preview hostnames.
The old Admin SDK key had `firebaseauth.admin`, so every preview deploy added
its hostname. The Hosting-only deployer cannot do that (firebase-tools logs a
warning and continues). Remove those stale entries in Authentication,
Settings, Authorized domains.

## Cost controls

- Previews expire after 7 days and are deleted when the PR closes. Bundles are
  kept as one-day artifacts. The Flutter SDK is cached.
- Firebase console, Hosting, Release storage: keep about the last 10 releases
  so you can still roll back.
- Cloud Billing, Budgets: `mindmate-staging` only, USD 5 per month, alerts at
  50%, 80% and 100%. Budgets send alerts; they do not cap spending.
- Review GitHub Actions minutes under Settings, Billing.

## Acceptance procedure

1. Open a draft PR from a branch of this repository. The `build` and
   `deploy_preview` jobs run, and a comment shows the `pr-<N>` URL, commit and
   expiry.
2. Push another commit. The same channel and comment update, and the older run
   is cancelled.
3. Push a commit that fails to build (on the test branch only). No preview is
   deployed.
4. `https://mindmate-staging.web.app` still shows the previous release
   (Hosting, Release history: the `live` channel is unchanged).
5. Close the PR. `cleanup_preview` deletes `pr-<N>`
   (`firebase hosting:channel:list --project mindmate-staging`).
6. After an approved merge, `Verify Android flavors` passes, then the merge
   workflow deploys. The live release time and commit match.
7. Production Hosting release history is unchanged.

## Rollback

- **Staging Hosting:** Firebase console, Hosting, Release history, roll back to
  the previous release. Or
  `firebase hosting:clone mindmate-staging:<previous-version> mindmate-staging:live`.
- **Workflows:** revert the merge commit of this change. While Vercel is still
  connected, it keeps serving `paaccmindmate.com` until DNS is moved.
- **Recovery links:** set `ADMIN_WEB_URL=https://mindmate-staging.web.app`
  (always valid) and redeploy the three callables above.

## Retiring Vercel (gated)

Do this only after the custom domain is Connected with an active certificate,
staging deploys and previews have passed the acceptance procedure, sign-in,
App Check and recovery links have been verified on Firebase, and production is
confirmed unaffected. Then, with owner approval:

- Remove Vercel's required status checks from branch protection. The Hosting
  workflow `build` job and `Verify Android flavors` replace them.
- Remove `vercel.json`, `web/vercel.json`, `tool/vercel_build.sh`,
  `tool/test_vercel_build.sh`, the Vercel guard in `lib/admin_main.dart`, and
  the Vercel host from the email-action allowlists. Do this in a separate PR.
- Disconnect the Vercel project and Git integration, and remove the Vercel host
  from Firebase Auth authorized domains.

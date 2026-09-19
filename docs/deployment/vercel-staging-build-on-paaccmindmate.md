# Deploying the admin web build to paaccmindmate.com

## Current arrangement

- Vercel team: `likhatech`; project: `web`.
- Public domain: `https://paaccmindmate.com` (Vercel Production deployment).
- Build environment: `APP_ENV=staging`, which selects Firebase project `mindmate-staging` in `lib/firebase_options_selector.dart`.
- The `mind-mates-cd2cf` Firebase production project is **not** used by this web build. The domain name and Vercel's Production deployment label do not determine the Firebase project; the Flutter build setting does.
- A separate staging URL, `https://mindmate-admin-staging.vercel.app`, can point to a different Vercel preview deployment. Updating the public domain does not automatically update that preview alias.

This arrangement exposes staging data and staging authentication to visitors of the public domain. Use test accounts and avoid entering real production data while this configuration is active.

## Before each deployment

1. In PowerShell, go to the `mind_mates` repository and run `git status --short`. A local build includes **all** current working-tree changes, including uncommitted files that the app imports. Review these before publishing.
2. Run the affected Flutter tests and `flutter analyze` for the changed files. If Functions or Firestore rules changed, test them separately and deploy them to `mindmate-staging` first.
3. Check that `.firebaserc` maps `staging` to `mindmate-staging`. Never infer the Firebase target from the Vercel domain.

## Build and publish the web app

Run these commands from the repository root:

```powershell
flutter build web --release --target lib/admin_main.dart --dart-define=APP_ENV=staging --no-wasm-dry-run
npx vercel deploy build/web --prod --project web --scope likhatech --yes
```

The first command generates the Flutter site in `build/web`. The second uploads that build to Vercel's Production environment for the `web` project. This is a **direct local deployment**: it does not commit or push code to GitHub.

In this project's current Vercel setup, the custom domains have manual aliases. A Ready Production deployment alone may leave them pointing at an older deployment. Copy the new deployment URL printed by Vercel (for example, `web-...-likhatech.vercel.app`), then run:

```powershell
npx vercel alias set NEW-DEPLOYMENT-URL paaccmindmate.com --scope likhatech
npx vercel alias set NEW-DEPLOYMENT-URL www.paaccmindmate.com --scope likhatech
npx vercel alias ls --scope likhatech
```

Replace `NEW-DEPLOYMENT-URL` with the exact URL from the successful deployment. Confirm that both domain rows in `alias ls` have that URL as their source.

Do not use `APP_ENV=production` for this particular staging-backed arrangement. Also do not use `firebase deploy` without an explicit project; `.firebaserc` defaults to staging today but defaults can change.

## If backend code changed

The Vercel command only publishes the web app. Deploy backend changes separately and explicitly to staging, after reviewing the Functions and rules diff:

```powershell
cd functions
npm test
cd ..
firebase deploy --project mindmate-staging --only functions,firestore:rules,firestore:indexes --non-interactive
```

Firebase deploy may update every Function in the codebase. Use `--only functions:<name>` for a narrower deployment when appropriate. Review any CLI request to delete existing functions before accepting it.

## Verify the live deployment

1. Open the new deployment in Vercel and confirm its status is **Ready**. Confirm the two domain aliases point to that deployment; do not rely on the Production badge alone.
2. Open `https://paaccmindmate.com` in a fresh/private browser window. Check that the admin sign-in page loads, sign in with a staging test account, and exercise the appointment flow.
3. Check the browser's Network panel or Firebase runtime diagnostics to confirm requests use `mindmate-staging`. An HTTP 200 for the page alone does not prove Firebase connectivity or authentication.
4. Confirm the staging backend functions are present with `firebase functions:list --project mindmate-staging`.

If the new web deployment fails, inspect Vercel's **Instant Rollback** option and recheck the custom domain aliases. Because these aliases are manually pinned, point both domains back to the last known good deployment with `vercel alias set` if rollback alone does not move them. A Vercel rollback does not roll back Firebase Functions or Firestore rules.

For the September 19 release, Vercel deployment `dpl_7Q6HR99CM7gW3H4DoPBhB9UvzUUe` (`web-9plspw874-likhatech.vercel.app`) was built locally with `APP_ENV=staging`. Both public aliases were moved to it. The served `main.dart.js` MD5 matched the local build (`C9BF20EBF5E13CF322C03A6790D70C75`), and both domain roots returned HTTP 200. An authenticated appointment smoke test still requires a staging test account.

## Later: automatic deployments

The connected Git `main` branch can trigger Vercel deployments. This local deployment does not update `main`, so a later Git-triggered production deployment may replace the current site. Before relying on Git pushes, decide which branch should own `paaccmindmate.com`, ensure its build uses the intended `APP_ENV`, and commit only reviewed changes.

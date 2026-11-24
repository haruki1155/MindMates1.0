#!/usr/bin/env bash
# Usage: verify_staging_web_bundle.sh <build/web>
#
# Checks that a Hosting bundle is a complete Admin Web build that carries the
# mindmate-staging web app config. All three environments' configs are compiled
# in; the APP_ENV=staging define selects staging, and the app refuses to start
# (AppEnvironmentConfig.validateFirebaseIdentity) if the selected project is not
# mindmate-staging. The build command itself is pinned by
# test/tooling/hosting_deploy_targets_test.dart.
set -euo pipefail

dir="${1:?usage: verify_staging_web_bundle.sh <build/web>}"
staging_web_app_id='1:978195258114:web:76a13336c1bc2088f5801b'

for file in index.html main.dart.js flutter_bootstrap.js; do
  [[ -s "$dir/$file" ]] || { echo "::error::$dir/$file is missing or empty."; exit 1; }
done
grep -q -F -- "$staging_web_app_id" "$dir/main.dart.js" \
  || { echo "::error::The bundle does not contain the mindmate-staging web app config."; exit 1; }
echo "Bundle in $dir carries the mindmate-staging web app config."

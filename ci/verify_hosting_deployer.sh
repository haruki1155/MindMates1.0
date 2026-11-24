#!/usr/bin/env bash
# Usage: FIREBASE_SERVICE_ACCOUNT=<json key> verify_hosting_deployer.sh <project_id> <service_account_email>
#
# 1. The key must be the expected Hosting-only deployer of that project
#    (metadata only, nothing printed).
# 2. That identity's effective IAM permissions must allow Hosting deploys and
#    nothing sensitive (ci/verify_deployer_least_privilege.py).
set -euo pipefail

project_id="${1:?usage: verify_hosting_deployer.sh <project_id> <service_account_email>}"
expected_email="${2:?usage: verify_hosting_deployer.sh <project_id> <service_account_email>}"
here="$(cd "$(dirname "$0")" && pwd)"

python3 "$here/verify_hosting_service_account.py" "$project_id" "$expected_email"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
(umask 077; printf '%s' "$FIREBASE_SERVICE_ACCOUNT" > "$work/key.json")
export CLOUDSDK_CONFIG="$work/gcloud"
gcloud auth activate-service-account --key-file "$work/key.json" --quiet > /dev/null 2>&1 \
  || { echo "::error::The deploy credential could not authenticate."; exit 1; }
GOOGLE_ACCESS_TOKEN="$(gcloud auth print-access-token)" \
  python3 "$here/verify_deployer_least_privilege.py" "$project_id"

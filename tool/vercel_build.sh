#!/usr/bin/env bash

# Vercel's standard build image does not include Flutter. Keep the SDK and Pub
# cache under .vercel/cache so subsequent deployments can reuse them.
set -euo pipefail

readonly flutter_version='3.44.4'
readonly flutter_cache_dir="$PWD/.vercel/cache/flutter-$flutter_version"
readonly flutter_sdk="$flutter_cache_dir/flutter"
readonly flutter_archive="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${flutter_version}-stable.tar.xz"

if [[ ! -x "$flutter_sdk/bin/flutter" ]]; then
  rm -rf "$flutter_cache_dir"
  mkdir -p "$flutter_cache_dir"
  curl --fail --location --retry 3 --retry-delay 2 "$flutter_archive" |
    tar -xJ -C "$flutter_cache_dir"
fi

export PATH="$flutter_sdk/bin:$PATH"
export PUB_CACHE="$PWD/.vercel/cache/pub"

# Vercel restores its cache with a different owner from the build process.
# Flutter uses Git internally, which requires this explicit trust declaration.
git config --global --add safe.directory "$flutter_sdk"

flutter --disable-analytics
flutter pub get
app_env="staging"
if [[ "${VERCEL_ENV:-}" == "production" ]]; then
  app_env="production"
fi
echo "Building MindMate Admin Portal with APP_ENV=$app_env"
flutter build web --release --target lib/admin_main.dart \
  --dart-define=APP_ENV="$app_env" \
  --dart-define=VERCEL_DEPLOYMENT_ENV="${VERCEL_ENV:-}"

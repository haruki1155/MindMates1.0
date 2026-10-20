#!/usr/bin/env bash
# Runs the staging-project emulator integration only inside an isolated Linux
# network namespace. A missing namespace capability is a BLOCKED validation
# result, never permission to contact a live Firebase project.
set -euo pipefail

: "${FIREBASE_BIN:?Set FIREBASE_BIN to the prepared firebase-tools executable.}"
: "${MOOD_V2_TEST_PILOT_UID:?Set a synthetic emulator-only pilot UID.}"

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="$root_dir/ci/firebase.mood-v2.emulators.json"
source_home="${HOME:?HOME is required for the preloaded emulator binaries.}"
isolated_home="$(mktemp -d)"
trap 'rm -rf "$isolated_home"' EXIT

# Copy only Firebase emulator binaries. Do not carry any configstore, tokens,
# ADC, or other host credentials into the isolated process.
if [[ -d "$source_home/.cache/firebase/emulators" ]]; then
  mkdir -p "$isolated_home/.cache/firebase"
  cp -a "$source_home/.cache/firebase/emulators" "$isolated_home/.cache/firebase/"
else
  echo "MODE_B=BLOCKED: Firebase emulator binaries were not prepared."
  exit 0
fi

if ! command -v unshare >/dev/null || ! command -v ip >/dev/null; then
  echo "MODE_B=BLOCKED: Linux network namespace tools are unavailable."
  exit 0
fi

# First prove the runner grants an isolated namespace with only loopback. This
# avoids treating a firewall failure as a valid staging-identity test.
if ! unshare --user --map-root-user --net bash -ceu '
  ip link set lo up
  test -z "$(ip route show default)"
  ! curl --noproxy "*" --connect-timeout 2 --max-time 3 http://1.1.1.1 >/dev/null 2>&1
'; then
  echo "MODE_B=BLOCKED: outbound network isolation could not be established and verified."
  exit 0
fi

export ROOT_DIR="$root_dir"
export EMULATOR_CONFIG="$config"
export ISOLATED_HOME="$isolated_home"
unshare --user --map-root-user --net bash -ceu '
  ip link set lo up
  test -z "$(ip route show default)"
  ! curl --noproxy "*" --connect-timeout 2 --max-time 3 http://1.1.1.1 >/dev/null 2>&1
  export HOME="$ISOLATED_HOME"
  export XDG_CONFIG_HOME="$ISOLATED_HOME/.config"
  export CLOUDSDK_CONFIG="$ISOLATED_HOME/.gcloud"
  export GOOGLE_APPLICATION_CREDENTIALS=""
  unset FIREBASE_TOKEN GOOGLE_OAUTH_ACCESS_TOKEN
  cd "$ROOT_DIR"
  "$FIREBASE_BIN" emulators:exec \
    --config "$EMULATOR_CONFIG" \
    --project mindmate-staging \
    --only auth,firestore,functions \
    "cd functions && FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FUNCTIONS_EMULATOR_HOST=127.0.0.1 FUNCTIONS_EMULATOR_PORT=5001 GCLOUD_PROJECT=mindmate-staging node --test --test-concurrency=1 lib/mood_entries.test.js lib/mood_entries_rules.test.js lib/mood_entries_callable_emulator.test.js"
'
echo "MODE_B=PASSED: staging-identity emulator integration ran with loopback-only networking."

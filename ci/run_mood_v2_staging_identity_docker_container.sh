#!/usr/bin/env bash
# Executes entirely inside a Docker --network none boundary. The container has
# no host mounts and receives only synthetic emulator configuration.
set -euo pipefail

# Cross-script contract consumed by the host launcher:
#   0  = all authenticated integration tests passed
#   42 = isolation/emulator infrastructure blocked before tests could run
#   1  = an authenticated integration assertion failed
readonly MODE_B_BLOCKED_EXIT_CODE=42
readonly FIREBASE_DEBUG_PATH=/tmp/firebase-debug.log
readonly FIREBASE_EMULATOR_WORKDIR=/tmp/mood-v2-emulators
readonly FIREBASE_FUNCTIONS_SOURCE=/tmp/mood-v2-functions
readonly FIREBASE_EMULATOR_CONFIG="$FIREBASE_EMULATOR_WORKDIR/firebase.mood-v2.emulators.json"

: "${MOOD_V2_TEST_PILOT_UID:?Set a synthetic emulator-only pilot UID.}"
: "${MOOD_V2_STAGING_PILOT_UIDS:?Set the synthetic pilot allowlist.}"

if [[ "$MOOD_V2_STAGING_PILOT_UIDS" != "$MOOD_V2_TEST_PILOT_UID" ]]; then
  echo "MODE_B=BLOCKED: The Docker pilot allowlist is not the exact synthetic pilot UID."
  exit "$MODE_B_BLOCKED_EXIT_CODE"
fi

# Docker's none network must retain loopback but have no default route or
# external reachability before any emulator or test process starts.
if ! ip link show lo | grep -q 'UP'; then
  echo "MODE_B=BLOCKED: Docker offline container does not have loopback networking."
  exit "$MODE_B_BLOCKED_EXIT_CODE"
fi
if [[ -n "$(ip route show default)" ]]; then
  echo "MODE_B=BLOCKED: Docker offline container has a default route."
  exit "$MODE_B_BLOCKED_EXIT_CODE"
fi
if curl --noproxy '*' --connect-timeout 2 --max-time 3 http://1.1.1.1 >/dev/null 2>&1; then
  echo "MODE_B=BLOCKED: Docker offline container reached an outbound endpoint."
  exit "$MODE_B_BLOCKED_EXIT_CODE"
fi

# The application filesystem is intentionally read-only. Firebase CLI normally
# writes firebase-debug.log in its working directory, so reserve a private
# writable path on the container-local tmpfs before starting any emulator.
umask 077
if ! : > "$FIREBASE_DEBUG_PATH"; then
  echo "MODE_B=BLOCKED: Docker offline container cannot create the Firebase debug log."
  exit "$MODE_B_BLOCKED_EXIT_CODE"
fi
if ! mkdir -p "$FIREBASE_EMULATOR_WORKDIR"; then
  echo "MODE_B=BLOCKED: Docker offline container cannot create the Firebase emulator work directory."
  exit "$MODE_B_BLOCKED_EXIT_CODE"
fi

# The Functions emulator updates its source-local dotenv file while resolving
# runtime parameters. Keep that mutable emulator-only source on tmpfs; the
# image's /workspace source and Firebase configuration stay read-only.
prepare_emulator_functions_source() {
  rm -rf "$FIREBASE_FUNCTIONS_SOURCE"
  mkdir -p "$FIREBASE_FUNCTIONS_SOURCE"
  tar -C /workspace/functions --exclude='./node_modules' -cf - . \
    | tar -C "$FIREBASE_FUNCTIONS_SOURCE" -xf -
  ln -s /workspace/functions/node_modules "$FIREBASE_FUNCTIONS_SOURCE/node_modules"

  node - "$FIREBASE_EMULATOR_CONFIG" "$FIREBASE_FUNCTIONS_SOURCE" <<'NODE'
const fs = require('node:fs');
const [configPath, functionsSource] = process.argv.slice(2);
const config = JSON.parse(
  fs.readFileSync('/workspace/firebase.mood-v2.emulators.json', 'utf8'),
);
config.functions = {...config.functions, source: functionsSource};
fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`, {
  mode: 0o600,
});
NODE
}

if ! prepare_emulator_functions_source; then
  echo "MODE_B=BLOCKED: Docker offline container could not prepare a writable Functions emulator source."
  exit "$MODE_B_BLOCKED_EXIT_CODE"
fi

run_emulators() {
  local command="$1"
  (
    # Firestore and Functions emit component logs relative to the Firebase CLI
    # working directory. Keep those files and the generated emulator config on
    # tmpfs while retaining the immutable workspace config as the template.
    cd "$FIREBASE_EMULATOR_WORKDIR"
    env -i \
      PATH="$PATH" \
      HOME="$HOME" \
      TMPDIR=/tmp \
      FIREBASE_DEBUG_PATH="$FIREBASE_DEBUG_PATH" \
      XDG_CONFIG_HOME=/tmp/config \
      CLOUDSDK_CONFIG=/tmp/gcloud \
      GOOGLE_APPLICATION_CREDENTIALS= \
      FIREBASE_TOKEN= \
      SUPER_ADMIN_UID=mood-v2-ci-super-admin \
      MOOD_V2_TEST_PILOT_UID="$MOOD_V2_TEST_PILOT_UID" \
      MOOD_V2_STAGING_PILOT_UIDS="$MOOD_V2_STAGING_PILOT_UIDS" \
      firebase emulators:exec \
        --config "$FIREBASE_EMULATOR_CONFIG" \
        --project mindmate-staging \
        --only auth,firestore,functions \
        "$command"
  )
}

if ! run_emulators "node -e \"const net = require('node:net'); const ports = [9099, 8080, 5001]; Promise.all(ports.map((port) => new Promise((resolve, reject) => { const socket = net.connect({host: '127.0.0.1', port}, () => { socket.end(); resolve(); }); socket.on('error', reject); }))).catch((error) => { console.error(error); process.exit(1); });\""; then
  echo "MODE_B=BLOCKED: Docker offline container could not start all local emulators."
  exit "$MODE_B_BLOCKED_EXIT_CODE"
fi

if run_emulators "cd /workspace/functions && printf '%s\\n' 'MODE_B: transactional idempotency' && FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=mindmate-staging node --test --test-concurrency=1 lib/mood_entries.test.js && printf '%s\\n' 'MODE_B: Firestore Rules' && FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=mindmate-staging node --test --test-concurrency=1 lib/mood_entries_rules.test.js && printf '%s\\n' 'MODE_B: authenticated callable integration' && FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FUNCTIONS_EMULATOR_HOST=127.0.0.1 FUNCTIONS_EMULATOR_PORT=5001 GCLOUD_PROJECT=mindmate-staging node --test --test-concurrency=1 lib/mood_entries_callable_emulator.test.js"; then
  echo "MODE_B=PASSED: Docker ran staging-identity emulators with loopback-only networking."
else
  echo "MODE_B=FAILED: Docker-isolated staging-identity emulator tests failed."
  exit 1
fi

#!/usr/bin/env bash
# Executes entirely inside a Docker --network none boundary. The container has
# no host mounts and receives only synthetic emulator configuration.
set -euo pipefail

: "${MOOD_V2_TEST_PILOT_UID:?Set a synthetic emulator-only pilot UID.}"
: "${MOOD_V2_STAGING_PILOT_UIDS:?Set the synthetic pilot allowlist.}"

if [[ "$MOOD_V2_STAGING_PILOT_UIDS" != "$MOOD_V2_TEST_PILOT_UID" ]]; then
  echo "MODE_B=BLOCKED: The Docker pilot allowlist is not the exact synthetic pilot UID."
  exit 0
fi

# Docker's none network must retain loopback but have no default route or
# external reachability before any emulator or test process starts.
if ! ip link show lo | grep -q 'UP'; then
  echo "MODE_B=BLOCKED: Docker offline container does not have loopback networking."
  exit 0
fi
if [[ -n "$(ip route show default)" ]]; then
  echo "MODE_B=BLOCKED: Docker offline container has a default route."
  exit 0
fi
if curl --noproxy '*' --connect-timeout 2 --max-time 3 http://1.1.1.1 >/dev/null 2>&1; then
  echo "MODE_B=BLOCKED: Docker offline container reached an outbound endpoint."
  exit 0
fi

run_emulators() {
  local command="$1"
  env -i \
    PATH="$PATH" \
    HOME="$HOME" \
    TMPDIR=/tmp \
    XDG_CONFIG_HOME=/tmp/config \
    CLOUDSDK_CONFIG=/tmp/gcloud \
    GOOGLE_APPLICATION_CREDENTIALS= \
    FIREBASE_TOKEN= \
    SUPER_ADMIN_UID=mood-v2-ci-super-admin \
    MOOD_V2_TEST_PILOT_UID="$MOOD_V2_TEST_PILOT_UID" \
    MOOD_V2_STAGING_PILOT_UIDS="$MOOD_V2_STAGING_PILOT_UIDS" \
    firebase emulators:exec \
      --config /workspace/firebase.mood-v2.emulators.json \
      --project mindmate-staging \
      --only auth,firestore,functions \
      "$command"
}

if ! run_emulators "node -e \"const net = require('node:net'); const ports = [9099, 8080, 5001]; Promise.all(ports.map((port) => new Promise((resolve, reject) => { const socket = net.connect({host: '127.0.0.1', port}, () => { socket.end(); resolve(); }); socket.on('error', reject); }))).catch((error) => { console.error(error); process.exit(1); });\""; then
  echo "MODE_B=BLOCKED: Docker offline container could not start all local emulators."
  exit 0
fi

if run_emulators "cd /workspace/functions && printf '%s\\n' 'MODE_B: transactional idempotency' && FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=mindmate-staging node --test --test-concurrency=1 lib/mood_entries.test.js && printf '%s\\n' 'MODE_B: Firestore Rules' && FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=mindmate-staging node --test --test-concurrency=1 lib/mood_entries_rules.test.js && printf '%s\\n' 'MODE_B: authenticated callable integration' && FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FUNCTIONS_EMULATOR_HOST=127.0.0.1 FUNCTIONS_EMULATOR_PORT=5001 GCLOUD_PROJECT=mindmate-staging node --test --test-concurrency=1 lib/mood_entries_callable_emulator.test.js"; then
  echo "MODE_B=PASSED: Docker ran staging-identity emulators with loopback-only networking."
else
  echo "MODE_B=FAILED: Docker-isolated staging-identity emulator tests failed."
  exit 1
fi

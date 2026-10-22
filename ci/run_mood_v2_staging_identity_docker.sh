#!/usr/bin/env bash
# Builds the complete emulator test image while networking is available, then
# starts the actual staging-identity test with Docker networking disabled.
set -euo pipefail

report_mode_b() {
  local status="$1"
  local detail="$2"
  echo "MODE_B=${status}: ${detail}"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "mode_b=${status,,}" >> "$GITHUB_OUTPUT"
  fi
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '## Mood V2 staging-identity integration\n\n**%s** - %s\n' "$status" "$detail" >> "$GITHUB_STEP_SUMMARY"
  fi
}

: "${MOOD_V2_TEST_PILOT_UID:?Set a synthetic emulator-only pilot UID.}"
: "${MOOD_V2_STAGING_PILOT_UIDS:?Set the synthetic pilot allowlist.}"

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  report_mode_b "BLOCKED" "Docker is unavailable; staging-identity tests were not run."
  exit 0
fi

tag_suffix="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}"
image="mindmate-mood-v2-mode-b:${tag_suffix}"
cleanup() {
  docker image rm --force "$image" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# The build has network access only to fetch the base image, npm dependencies,
# and the Firestore emulator. The following docker run receives no mounts,
# credentials, Docker socket, or network route.
if ! docker build --pull --file "$root_dir/ci/mood-v2-mode-b.Dockerfile" --tag "$image" "$root_dir"; then
  report_mode_b "BLOCKED" "Docker could not prepare the offline emulator image."
  exit 0
fi

if docker run --rm \
  --network none \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --tmpfs /tmp:rw,noexec,nosuid,size=256m \
  --env MOOD_V2_TEST_PILOT_UID="$MOOD_V2_TEST_PILOT_UID" \
  --env MOOD_V2_STAGING_PILOT_UIDS="$MOOD_V2_STAGING_PILOT_UIDS" \
  "$image"; then
  report_mode_b "PASSED" "Docker ran staging-identity emulators with loopback-only networking."
  exit 0
fi

report_mode_b "FAILED" "Docker-isolated staging-identity emulator tests failed."
exit 1

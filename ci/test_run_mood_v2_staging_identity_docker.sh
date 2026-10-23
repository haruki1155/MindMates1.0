#!/usr/bin/env bash
# Shell-level regression coverage for the Mode B Docker result contract. No
# Docker daemon, Firebase emulator, credentials, or network access is used.
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
launcher="$root_dir/ci/run_mood_v2_staging_identity_docker.sh"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

mock_docker="$temp_dir/docker"
cat > "$mock_docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
command="$1"
shift || true
case "$command" in
  info) exit "${MOCK_DOCKER_INFO_EXIT:-0}" ;;
  build) exit "${MOCK_DOCKER_BUILD_EXIT:-0}" ;;
  run)
    printf '%s\n' "$@" > "${MOCK_DOCKER_RUN_ARGS:?}"
    exit "${MOCK_DOCKER_RUN_EXIT:-0}"
    ;;
  image) exit 0 ;;
  *) exit 97 ;;
esac
MOCK
chmod 700 "$mock_docker"

run_case() {
  local name="$1"
  local expected_exit="$2"
  local expected_status="$3"
  shift 3
  local output="$temp_dir/${name}.log"
  set +e
  env \
    MOOD_V2_DOCKER_BIN="$mock_docker" \
    MOOD_V2_TEST_PILOT_UID=mood-v2-ci-synthetic-pilot \
    MOOD_V2_STAGING_PILOT_UIDS=mood-v2-ci-synthetic-pilot \
    MOCK_DOCKER_RUN_ARGS="$temp_dir/${name}.args" \
    "$@" \
    bash "$launcher" >"$output" 2>&1
  local actual_exit=$?
  set -e
  [[ "$actual_exit" -eq "$expected_exit" ]] || {
    cat "$output"
    echo "${name}: expected exit ${expected_exit}, got ${actual_exit}" >&2
    exit 1
  }
  grep -Fq "MODE_B=${expected_status}:" "$output" || {
    cat "$output"
    echo "${name}: expected MODE_B=${expected_status}" >&2
    exit 1
  }
  if [[ "$expected_status" != "PASSED" ]]; then
    ! grep -Fq 'MODE_B=PASSED:' "$output" || {
      cat "$output"
      echo "${name}: blocked/failed result was promoted to PASSED" >&2
      exit 1
    }
  fi
}

run_case container_blocked 42 BLOCKED MOCK_DOCKER_RUN_EXIT=42
run_case assertion_failed 1 FAILED MOCK_DOCKER_RUN_EXIT=1
run_case docker_unavailable 42 BLOCKED MOCK_DOCKER_INFO_EXIT=1
run_case docker_startup_failed 42 BLOCKED MOCK_DOCKER_RUN_EXIT=125
run_case integration_passed 0 PASSED MOCK_DOCKER_RUN_EXIT=0
run_case unexpected_exit 1 FAILED MOCK_DOCKER_RUN_EXIT=99

grep -Fxq -- '--network' "$temp_dir/integration_passed.args"
grep -Fxq -- 'none' "$temp_dir/integration_passed.args"
grep -Fxq -- '--read-only' "$temp_dir/integration_passed.args"
grep -Fxq -- '--cap-drop' "$temp_dir/integration_passed.args"
grep -Fxq -- 'ALL' "$temp_dir/integration_passed.args"
grep -Fxq -- '--security-opt' "$temp_dir/integration_passed.args"
grep -Fxq -- 'no-new-privileges:true' "$temp_dir/integration_passed.args"
grep -Fxq -- '--tmpfs' "$temp_dir/integration_passed.args"
grep -Fxq -- '/tmp:rw,noexec,nosuid,size=512m,mode=1777' "$temp_dir/integration_passed.args"
! grep -Fxq -- '--network=host' "$temp_dir/integration_passed.args"

# Firebase CLI must write only to the container-local tmpfs, even though the
# workspace remains read-only and the emulator command is credential-scrubbed.
grep -Fq 'readonly FIREBASE_DEBUG_PATH=/tmp/firebase-debug.log' "$root_dir/ci/run_mood_v2_staging_identity_docker_container.sh"
grep -Fq 'readonly FIREBASE_EMULATOR_WORKDIR=/tmp/mood-v2-emulators' "$root_dir/ci/run_mood_v2_staging_identity_docker_container.sh"
grep -Fq 'readonly FIREBASE_FUNCTIONS_SOURCE=/tmp/mood-v2-functions' "$root_dir/ci/run_mood_v2_staging_identity_docker_container.sh"
grep -Fq 'readonly FIREBASE_EMULATOR_CONFIG="$FIREBASE_EMULATOR_WORKDIR/firebase.mood-v2.emulators.json"' "$root_dir/ci/run_mood_v2_staging_identity_docker_container.sh"
grep -Fq 'if ! : > "$FIREBASE_DEBUG_PATH"; then' "$root_dir/ci/run_mood_v2_staging_identity_docker_container.sh"
grep -Fq 'if ! mkdir -p "$FIREBASE_EMULATOR_WORKDIR"; then' "$root_dir/ci/run_mood_v2_staging_identity_docker_container.sh"
grep -Fq 'cd "$FIREBASE_EMULATOR_WORKDIR"' "$root_dir/ci/run_mood_v2_staging_identity_docker_container.sh"
grep -Fq 'FIREBASE_DEBUG_PATH="$FIREBASE_DEBUG_PATH"' "$root_dir/ci/run_mood_v2_staging_identity_docker_container.sh"
grep -Fq 'tar -C /workspace/functions --exclude=' "$root_dir/ci/run_mood_v2_staging_identity_docker_container.sh"
grep -Fq 'ln -s /workspace/functions/node_modules "$FIREBASE_FUNCTIONS_SOURCE/node_modules"' "$root_dir/ci/run_mood_v2_staging_identity_docker_container.sh"
grep -Fq "fs.readFileSync('/workspace/firebase.mood-v2.emulators.json', 'utf8')" "$root_dir/ci/run_mood_v2_staging_identity_docker_container.sh"
grep -Fq 'config.functions = {...config.functions, source: functionsSource};' "$root_dir/ci/run_mood_v2_staging_identity_docker_container.sh"
grep -Fq -- '--config "$FIREBASE_EMULATOR_CONFIG"' "$root_dir/ci/run_mood_v2_staging_identity_docker_container.sh"

# The offline image must carry a Java 21 runtime because Firebase CLI 15 no
# longer supports the default Debian Java 17 runtime.
grep -Fq 'FROM eclipse-temurin:21-jre AS java21' "$root_dir/ci/mood-v2-mode-b.Dockerfile"
grep -Fq 'COPY --from=java21 /opt/java/openjdk /opt/java/openjdk' "$root_dir/ci/mood-v2-mode-b.Dockerfile"
grep -Fq 'ENV JAVA_HOME=/opt/java/openjdk' "$root_dir/ci/mood-v2-mode-b.Dockerfile"
grep -Fq '&& java -version' "$root_dir/ci/mood-v2-mode-b.Dockerfile"
echo 'Mode B Docker result contract tests passed.'

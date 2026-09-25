#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/.vercel/cache/flutter-3.44.4/flutter/bin"
cat > "$test_dir/.vercel/cache/flutter-3.44.4/flutter/bin/flutter" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BUILD_CALLS"
EOF
chmod +x "$test_dir/.vercel/cache/flutter-3.44.4/flutter/bin/flutter"

cd "$test_dir"
export BUILD_CALLS="$test_dir/build_calls"
export GIT_CONFIG_GLOBAL="$test_dir/gitconfig"

for deployment_env in production preview development unknown absent; do
  : > "$BUILD_CALLS"
  if [[ "$deployment_env" == absent ]]; then
    unset VERCEL_ENV
  else
    export VERCEL_ENV="$deployment_env"
  fi
  bash "$script_dir/vercel_build.sh" > /dev/null
  expected="staging"
  if [[ "$deployment_env" == production ]]; then expected="production"; fi
  if ! grep -Fq -- "--dart-define=APP_ENV=$expected" "$BUILD_CALLS"; then
    echo "Incorrect APP_ENV for VERCEL_ENV=$deployment_env" >&2
    exit 1
  fi
  expected_deployment="$deployment_env"
  if [[ "$deployment_env" == absent ]]; then expected_deployment=""; fi
  if ! grep -Fq -- "--dart-define=VERCEL_DEPLOYMENT_ENV=$expected_deployment" "$BUILD_CALLS"; then
    echo "Incorrect deployment marker for VERCEL_ENV=$deployment_env" >&2
    exit 1
  fi
  if ! grep -Fq -- "--target lib/admin_main.dart" "$BUILD_CALLS"; then
    echo "Admin target missing for VERCEL_ENV=$deployment_env" >&2
    exit 1
  fi
done
echo 'Vercel environment selection passed (production, preview, development, unknown, absent).'

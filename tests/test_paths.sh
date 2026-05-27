#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/helpers/assertions.sh
source "${TEST_DIR}/helpers/assertions.sh"
iw_test_init

conf="$(iw_config_path)"
write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
SCANNER_TRIVY=true
SCANNER_GRYPE=false

image "app" upstream="docker.io/library/nginx:stable"
EOF

run_iw iw-stage --config "${IW_TEST_TMP}/missing.conf"
assert_failure "$IW_LAST_STATUS" "missing config should fail"
assert_contains "$IW_LAST_OUTPUT" "config not found"

mkdir -p "${IW_TEST_TMP}/config-dir"
run_iw iw-release --config "${IW_TEST_TMP}/config-dir"
assert_failure "$IW_LAST_STATUS" "directory config should fail"
assert_contains "$IW_LAST_OUTPUT" "config exists but is not a readable regular file"

run_iw iw-cleanup --config "$conf" --secrets "${IW_TEST_TMP}/missing-secrets"
assert_failure "$IW_LAST_STATUS" "explicit missing secrets should fail"
assert_contains "$IW_LAST_OUTPUT" "secrets not found"

run_iw iw-cleanup --config "$conf" --dry-run
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_not_contains "$IW_LAST_OUTPUT" "secrets not found"

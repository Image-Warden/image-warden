#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/helpers/assertions.sh
source "${TEST_DIR}/helpers/assertions.sh"
iw_test_init

conf="$(iw_config_path)"
digest="sha256:1111111111111111111111111111111111111111111111111111111111111111"

write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
LOCAL_REGISTRY_TLS_VERIFY=false
QUARANTINE_HOURS=72

image "broken" \
  upstream="docker.io/library/nginx:stable"
EOF

export IW_FAKE_UPSTREAM_DIGEST="$digest"
export IW_FAKE_UPSTREAM_CREATED="2099-01-02T03:04:05Z"

mkdir -p "${XDG_STATE_HOME}/image-warden/candidates"
: > "${XDG_STATE_HOME}/image-warden/candidates/broken"

run_iw iw-stage --config "$conf" broken
assert_failure "$IW_LAST_STATUS" "candidate write failure should make stage fail"
assert_contains "$IW_LAST_OUTPUT" "could not write candidate state"
assert_contains "$IW_LAST_OUTPUT" "Stage run complete with 1 failure(s)."
assert_file_not_exists "${XDG_STATE_HOME}/image-warden/broken.digest"

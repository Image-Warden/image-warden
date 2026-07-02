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
SCANNER_SEVERITY="CRITICAL,HIGH"
PLATFORM="linux/amd64"

image "app" \
  upstream="docker.io/library/nginx:stable" \
  severity="HIGH" \
  scanner_ignore="CVE-2099-0001" \
  scanner_ignore_reason="accepted test finding" \
  production_tag="stable" \
  platform="linux/arm/v7"
EOF

run_iw iw-config check --config "$conf"
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "OK: config valid"

write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
image "app" \
  upstream="docker.io/library/nginx:stable" \
  scannerr_ignore="CVE-2099-0001"
EOF

run_iw iw-config check --config "$conf"
assert_failure "$IW_LAST_STATUS" "unknown option should fail"
assert_contains "$IW_LAST_OUTPUT" "unknown image option 'scannerr_ignore'"
assert_contains "$IW_LAST_OUTPUT" "config error(s)"

write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
image "app" \
  upstream="docker.io/library/nginx:stable" \
  cosign_key="/etc/image-warden/cosign.pub"
EOF

run_iw iw-config check --config "$conf"
assert_failure "$IW_LAST_STATUS" "unimplemented security option should fail"
assert_contains "$IW_LAST_OUTPUT" "image option 'cosign_key' for 'app' is not implemented yet"
assert_contains "$IW_LAST_OUTPUT" "config error(s)"

write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
image "app" \
  upstream="docker.io/library/nginx:stable" \
  signature_provider="cosign"
EOF

run_iw iw-config check --config "$conf"
assert_failure "$IW_LAST_STATUS" "unimplemented signature provider option should fail"
assert_contains "$IW_LAST_OUTPUT" "image option 'signature_provider' for 'app' is not implemented yet"
assert_contains "$IW_LAST_OUTPUT" "config error(s)"

write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
image "app" \
  upstream="docker.io/library/nginx:stable"
  quarantine_hours=60
EOF

run_iw iw-config check --config "$conf"
assert_failure "$IW_LAST_STATUS" "stray option should fail"
assert_contains "$IW_LAST_OUTPUT" "found 'quarantine_hours' outside image()"

write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
image "app" \ 
  upstream="docker.io/library/nginx:stable"
EOF

run_iw iw-config check --config "$conf"
assert_failure "$IW_LAST_STATUS" "trailing whitespace after backslash should fail"
assert_contains "$IW_LAST_OUTPUT" "trailing whitespace after backslash"

write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
IMAGES=()
EOF

run_iw iw-config check --config "$conf"
assert_failure "$IW_LAST_STATUS" "empty legacy array should fail"
assert_contains "$IW_LAST_OUTPUT" "empty legacy IMAGES=() config is no longer used"

write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
IMAGES=("docker.io/library/nginx:stable|nginx|HIGH")
EOF

run_iw iw-config check --config "$conf"
assert_failure "$IW_LAST_STATUS" "legacy array should fail"
assert_contains "$IW_LAST_OUTPUT" "legacy IMAGES=() config is no longer loaded"

run_iw iw-config legacy-to-dsl --config "$conf"
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" 'image "nginx"'
assert_contains "$IW_LAST_OUTPUT" 'upstream="docker.io/library/nginx:stable"'

write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
ALLOW_RELEASE_WITHOUT_SCANNER=maybe
image "app" upstream="docker.io/library/nginx:stable"
EOF

run_iw iw-config check --config "$conf"
assert_failure "$IW_LAST_STATUS" "invalid bool should fail"
assert_contains "$IW_LAST_OUTPUT" "ALLOW_RELEASE_WITHOUT_SCANNER must be true or false"

write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
NOTIFY_ON_BLOCKED_REPORT_CHANGE=maybe
image "app" upstream="docker.io/library/nginx:stable"
EOF

run_iw iw-config check --config "$conf"
assert_failure "$IW_LAST_STATUS" "invalid blocked report change notification bool should fail"
assert_contains "$IW_LAST_OUTPUT" "NOTIFY_ON_BLOCKED_REPORT_CHANGE must be true or false"

write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
SCANNER_TRIVY=false
SCANNER_GRYPE=false
image "app" upstream="docker.io/library/nginx:stable"
EOF

run_iw iw-config check --config "$conf"
assert_failure "$IW_LAST_STATUS" "all scanners disabled should fail closed"
assert_contains "$IW_LAST_OUTPUT" "at least one scanner must be enabled"

write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
IMAGE_RELEASE_HOOK="relative-hook"
image "app" upstream="docker.io/library/nginx:stable"
EOF

run_iw iw-config check --config "$conf"
assert_failure "$IW_LAST_STATUS" "relative hook path should fail"
assert_contains "$IW_LAST_OUTPUT" "IMAGE_RELEASE_HOOK must be an absolute path"

write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
IMAGE_RELEASE_HOOK_TIMEOUT=0
image "app" upstream="docker.io/library/nginx:stable"
EOF

run_iw iw-config check --config "$conf"
assert_failure "$IW_LAST_STATUS" "invalid hook timeout should fail"
assert_contains "$IW_LAST_OUTPUT" "IMAGE_RELEASE_HOOK_TIMEOUT must be a positive integer"

write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
IW_LOCK_TIMEOUT_SECONDS=soon
image "app" upstream="docker.io/library/nginx:stable"
EOF

run_iw iw-config check --config "$conf"
assert_failure "$IW_LAST_STATUS" "invalid lock timeout should fail"
assert_contains "$IW_LAST_OUTPUT" "IW_LOCK_TIMEOUT_SECONDS must be a non-negative integer"

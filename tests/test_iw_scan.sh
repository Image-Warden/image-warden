#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/helpers/assertions.sh
source "${TEST_DIR}/helpers/assertions.sh"
iw_test_init

conf="$(iw_config_path)"
write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
LOCAL_REGISTRY_TLS_VERIFY=false
SCANNER_TRIVY=true
SCANNER_GRYPE=false
SCANNER_SEVERITY="CRITICAL,HIGH"
PRODUCTION_TAG="production"

image "app" \
  upstream="docker.io/library/nginx:stable" \
  severity="HIGH" \
  scanner_ignore="CVE-2099-0001" \
  scanner_ignore_reason="accepted test finding" \
  production_tag="stable"
EOF

export IW_FAKE_TRIVY_MODE=clean
run_iw iw-scan --config "$conf" app
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "Scanning 127.0.0.1:5000/app:stable with trivy"
assert_contains "$(< "$IW_FAKE_LOG")" "trivy image=127.0.0.1:5000/app:stable"

: > "$IW_FAKE_LOG"
run_iw iw-scan --config "$conf" app --tag staged_20260524-1200_abcdef12
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "Scanning 127.0.0.1:5000/app:staged_20260524-1200_abcdef12 with trivy"
assert_contains "$(< "$IW_FAKE_LOG")" "trivy image=127.0.0.1:5000/app:staged_20260524-1200_abcdef12"

: > "$IW_FAKE_LOG"
run_iw iw-scan --config "$conf" app:custom
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "Scanning 127.0.0.1:5000/app:custom with trivy"
assert_contains "$(< "$IW_FAKE_LOG")" "trivy image=127.0.0.1:5000/app:custom"

: > "$IW_FAKE_LOG"
run_iw iw-scan --config "$conf" docker.io/library/nginx:stable
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "Scanning docker.io/library/nginx:stable with trivy"
assert_contains "$(< "$IW_FAKE_LOG")" "trivy image=docker.io/library/nginx:stable"

run_iw iw-scan --config "$conf" docker.io/library/nginx:stable --tag test
assert_failure "$IW_LAST_STATUS" "--tag with full ref should fail"
assert_contains "$IW_LAST_OUTPUT" "--tag is only valid"

run_iw iw-scan --config "$conf" app:custom --tag test
assert_failure "$IW_LAST_STATUS" "--tag with local name:tag should fail"
assert_contains "$IW_LAST_OUTPUT" "--tag cannot be combined with local name:tag syntax"

: > "$IW_FAKE_LOG"
export IW_FAKE_GRYPE_MODE=clean
run_iw iw-scan --config "$conf" --scanner grype --severity CRITICAL app
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "Scanning 127.0.0.1:5000/app:stable with grype"
assert_contains "$(< "$IW_FAKE_LOG")" "grype image=registry:127.0.0.1:5000/app:stable"

export IW_FAKE_TRIVY_MODE=blocked
run_iw iw-scan --config "$conf" --scanner trivy app
assert_eq "1" "$IW_LAST_STATUS" "blocked scan exits 1"
assert_contains "$IW_LAST_OUTPUT" "Scan complete: 1 scanner gate(s) blocked."

rm -f "${XDG_CACHE_HOME}/image-warden/trivy-reports/"*.json
export IW_FAKE_TRIVY_MODE=error
run_iw iw-scan --config "$conf" --scanner trivy app
assert_eq "2" "$IW_LAST_STATUS" "scanner error exits 2"
assert_contains "$IW_LAST_OUTPUT" "scan failed"

events="${XDG_STATE_HOME}/image-warden/events.log"
assert_file_exists "$events"
event_text="$(< "$events")"
assert_contains "$event_text" "scan_clean"
assert_contains "$event_text" "scan_blocked"
assert_contains "$event_text" "scan_error"

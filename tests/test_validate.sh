#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/helpers/assertions.sh
source "${TEST_DIR}/helpers/assertions.sh"
iw_test_init

source "${IW_TEST_ROOT}/lib/common.sh"
source "${IW_TEST_ROOT}/lib/validate.sh"

_iw_bool_enabled true
_iw_bool_enabled 1
_iw_bool_disabled false
_iw_bool_disabled 0

_iw_validate_local_name "postgres"
run_func _iw_validate_local_name "Postgres"
assert_failure "$IW_LAST_STATUS" "uppercase local name should fail"

_iw_validate_tag_component "production"
_iw_validate_tag_component "stable-1.2"
run_func _iw_validate_tag_component "bad/tag"
assert_failure "$IW_LAST_STATUS" "tag component with slash should fail"
run_func _iw_validate_tag_component "bad:tag"
assert_failure "$IW_LAST_STATUS" "tag component with colon should fail"

_iw_validate_local_tag "latest_20260524-1200_abcdef12"
run_func _iw_validate_local_tag "production"
assert_failure "$IW_LAST_STATUS" "production is not a staged local tag"

_iw_validate_digest "sha256:1111111111111111111111111111111111111111111111111111111111111111"
run_func _iw_validate_digest "sha256:notadigest"
assert_failure "$IW_LAST_STATUS" "invalid digest should fail"

_iw_validate_severity_list "severity" "CRITICAL,HIGH"
run_cmd _iw_validate_severity_list "severity" "CRITICAL,NOPE"
assert_failure "$IW_LAST_STATUS" "invalid severity should fail"
assert_contains "$IW_LAST_OUTPUT" "invalid severity"

_iw_validate_scanner_list "scanners" "trivy,grype"
run_cmd _iw_validate_scanner_list "scanners" "trivy,nope"
assert_failure "$IW_LAST_STATUS" "invalid scanner should fail"
assert_contains "$IW_LAST_OUTPUT" "unsupported scanner"

_iw_validate_platform "platform" "linux/amd64"
_iw_validate_platform "platform" "linux/arm/v7"
_iw_validate_platform "platform" "linux/x86_64"
run_cmd _iw_validate_platform "platform" "windows/amd64"
assert_failure "$IW_LAST_STATUS" "invalid platform should fail"
assert_contains "$IW_LAST_OUTPUT" "unsupported os"

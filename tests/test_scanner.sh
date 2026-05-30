#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/helpers/assertions.sh
source "${TEST_DIR}/helpers/assertions.sh"
iw_test_init

source "${IW_TEST_ROOT}/lib/common.sh"
source "${IW_TEST_ROOT}/lib/validate.sh"
source "${IW_TEST_ROOT}/lib/scanner.sh"

export LOCAL_REGISTRY_TLS_VERIFY=false
export SCANNER_REPORT_DIR="${IW_TEST_TMP}/reports"
mkdir -p "$SCANNER_REPORT_DIR"

SCANNER_TRIVY=true
SCANNER_GRYPE=false
_iw_scanner_init
assert_eq "trivy" "${_IW_SCANNER_ENGINES[*]}" "default scanner"

_iw_scanner_init "trivy,grype"
assert_eq "trivy grype" "${_IW_SCANNER_ENGINES[*]}" "explicit scanner list"

export IW_FAKE_TRIVY_MODE=blocked
run_func _iw_scanner_scan trivy "127.0.0.1:5000/app:tag" "app" "CRITICAL,HIGH" "CVE-2099-0001" "test ignore" "tag"
assert_eq "1" "$IW_LAST_STATUS" "trivy blocked return"
assert_contains "$IW_LAST_OUTPUT" "Trivy scan: 1 finding"
assert_contains "$IW_SCANNER_REPORT_FILE" "_trivy_"
assert_file_exists "$IW_SCANNER_REPORT_FILE"
hash="$(_iw_scanner_report_hash trivy "$IW_SCANNER_REPORT_FILE")"
assert_contains "$hash" "sha256:"

old_summary='{"finding_count":41,"critical":1,"high":40,"ids":["","CVE-2099-0001"]}'
new_summary='{"finding_count":43,"critical":1,"high":42,"ids":["","CVE-2099-0001","CVE-2099-0002"]}'
diff_output="$(_iw_scanner_report_summary_diff "$old_summary" "$new_summary")"
assert_contains "$diff_output" "findings 41 -> 43"
assert_contains "$diff_output" "new finding id(s): CVE-2099-0002"
assert_not_contains "$diff_output" "new finding id(s): ," "empty finding ids should be filtered"
_iw_scanner_report_summary_changed "$old_summary" "$new_summary" || fail "summary change should be detected"

same_summary='{"finding_count":41,"critical":1,"high":40,"ids":["CVE-2099-0001"]}'
same_summary_reordered='{"finding_count":41,"critical":1,"high":40,"ids":["","CVE-2099-0001"]}'
if _iw_scanner_report_summary_changed "$same_summary" "$same_summary_reordered"; then
    fail "empty finding ids should not make summary look changed"
fi

export IW_FAKE_TRIVY_MODE=clean
run_func _iw_scanner_scan trivy "127.0.0.1:5000/app:tag" "app" "CRITICAL,HIGH" "" "" "tag"
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "Trivy scan: clean"

export IW_FAKE_GRYPE_MODE=blocked
run_func _iw_scanner_scan grype "127.0.0.1:5000/app:tag" "app" "CRITICAL,HIGH" "CVE-2099-0002" "test ignore" "tag"
assert_eq "1" "$IW_LAST_STATUS" "grype blocked return"
assert_contains "$IW_LAST_OUTPUT" "Grype scan: 1 finding"
assert_contains "$IW_SCANNER_REPORT_FILE" "_grype_"
assert_file_exists "$IW_SCANNER_REPORT_FILE"
hash="$(_iw_scanner_report_hash grype "$IW_SCANNER_REPORT_FILE")"
assert_contains "$hash" "sha256:"

export IW_FAKE_GRYPE_MODE=clean
run_func _iw_scanner_scan grype "127.0.0.1:5000/app:tag" "app" "CRITICAL,HIGH" "" "" "tag"
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "Grype scan: clean"

fake_log="$(< "$IW_FAKE_LOG")"
assert_contains "$fake_log" "TRIVY_INSECURE=true" "trivy insecure flag"
assert_contains "$fake_log" "skip_tls=true" "grype insecure skip tls"
assert_contains "$fake_log" "http=true" "grype insecure http"

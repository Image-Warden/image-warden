#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/helpers/assertions.sh
source "${TEST_DIR}/helpers/assertions.sh"
iw_test_init

source "${IW_TEST_ROOT}/lib/notify.sh"

NOTIFY_BACKENDS=(discord)
DISCORD_WEBHOOK_URL="https://example.invalid/webhook"
export IW_FAKE_CURL_FAIL=1
run_func _notify_dispatch "error" "blocked" "Blocked" "body"
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "notify: discord send failed"
unset IW_FAKE_CURL_FAIL

_notify_dispatch() {
    IW_NOTIFY_COLOR="$1"
    IW_NOTIFY_EVENT="$2"
    IW_NOTIFY_TITLE="$3"
    IW_NOTIFY_BODY="$4"
}

notify_blocked \
    "app" \
    "stable_20990101-0000_aaaaaaaa" \
    "4" \
    "CRITICAL,HIGH" \
    "/tmp/report.json" \
    "production" \
    "Trivy" \
    "Reason: Trivy blocking report changed since last blocked scan
Findings: 3 -> 4
Critical: 1 -> 1
High: 2 -> 3"

assert_eq "error" "$IW_NOTIFY_COLOR" "blocked notification color"
assert_eq "blocked" "$IW_NOTIFY_EVENT" "blocked notification event"
assert_contains "$IW_NOTIFY_TITLE" "Blocked: app:stable_20990101-0000_aaaaaaaa"
assert_contains "$IW_NOTIFY_BODY" "Scanner gate: blocked"
assert_contains "$IW_NOTIFY_BODY" "Reason: Trivy blocking report changed since last blocked scan"
assert_contains "$IW_NOTIFY_BODY" "Findings: 3 -> 4"

notify_digest_mismatch \
    "app" \
    "stable_20990101-0000_aaaaaaaa" \
    "sha256:1111111111111111111111111111111111111111111111111111111111111111" \
    "sha256:2222222222222222222222222222222222222222222222222222222222222222"

assert_eq "error" "$IW_NOTIFY_COLOR" "digest mismatch notification color"
assert_eq "digest_mismatch" "$IW_NOTIFY_EVENT" "digest mismatch notification event"
assert_contains "$IW_NOTIFY_TITLE" "Staged digest changed: app:stable_20990101-0000_aaaaaaaa"
assert_contains "$IW_NOTIFY_BODY" "Expected digest: sha256:1111111111111111111111111111111111111111111111111111111111111111"
assert_contains "$IW_NOTIFY_BODY" "Registry digest: sha256:2222222222222222222222222222222222222222222222222222222222222222"

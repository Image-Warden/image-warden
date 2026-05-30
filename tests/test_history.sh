#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/helpers/assertions.sh
source "${TEST_DIR}/helpers/assertions.sh"
iw_test_init

events="${XDG_STATE_HOME}/image-warden/events.log"
mkdir -p "$(dirname -- "$events")"
cat > "$events" <<'EOF'
{"ts":"2026-05-25T08:00:00Z","event":"staged","source":"iw-stage","category":"stage","image":"app","upstream":"docker.io/library/nginx:stable","tag":"stable_20260525-0800_11111111","digest":"sha256:1111111111111111111111111111111111111111111111111111111111111111"}
{"ts":"2026-05-25T09:00:00Z","event":"scan_blocked","source":"iw-release","category":"scan","image":"app","tag":"stable_20260525-0800_11111111","digest":"sha256:1111111111111111111111111111111111111111111111111111111111111111","scanner":"trivy","scanner_label":"Trivy","finding_count":"2"}
{"ts":"2026-05-25T09:30:00Z","event":"scan_report_changed","source":"iw-release","category":"scan","image":"app","tag":"stable_20260525-0800_11111111","digest":"sha256:1111111111111111111111111111111111111111111111111111111111111111","scanner":"trivy","scanner_label":"Trivy","old_hash":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","new_hash":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","old_finding_count":"2","new_finding_count":"3","old_critical":"1","new_critical":"1","old_high":"1","new_high":"2","new_ids":"CVE-2026-0001","resolved_ids":"","summary_changed":"true"}
{"ts":"2026-05-25T09:45:00Z","event":"scan_report_changed","source":"iw-release","category":"scan","image":"app","tag":"stable_20260525-0800_11111111","digest":"sha256:1111111111111111111111111111111111111111111111111111111111111111","scanner":"trivy","scanner_label":"Trivy","old_hash":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","new_hash":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","old_finding_count":"3","new_finding_count":"3","old_critical":"1","new_critical":"1","old_high":"2","new_high":"2","new_ids":"","resolved_ids":"","summary_changed":"false"}
{"ts":"2026-05-25T10:00:00Z","event":"released","source":"iw-release","category":"release","image":"app","from_tag":"stable_20260525-0800_11111111","to_tag":"stable","digest":"sha256:1111111111111111111111111111111111111111111111111111111111111111"}
{"ts":"2026-05-25T11:00:00Z","event":"released","source":"iw-release","category":"release","image":"other","from_tag":"latest_20260525-0800_22222222","to_tag":"production","digest":"sha256:2222222222222222222222222222222222222222222222222222222222222222"}
EOF

run_iw iw-history --image app
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "released :stable_20260525-0800_11111111 -> :stable"
assert_contains "$IW_LAST_OUTPUT" "blocked :stable_20260525-0800_11111111 by Trivy findings=2"
assert_contains "$IW_LAST_OUTPUT" "Trivy report changed :stable_20260525-0800_11111111 findings 2 -> 3, critical 1 -> 1, high 1 -> 2"
assert_contains "$IW_LAST_OUTPUT" "Trivy report hash changed :stable_20260525-0800_11111111, blocking summary unchanged"
assert_not_contains "$IW_LAST_OUTPUT" "other"

first_line="$(printf '%s\n' "$IW_LAST_OUTPUT" | sed -n '1p')"
assert_contains "$first_line" "released :stable_20260525-0800_11111111" "default history order is newest first"

run_iw iw-history --image app --utc
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "2026-05-25T10:00:00Z"

run_iw iw-history --image app --event released --json
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_eq "released" "$(printf '%s\n' "$IW_LAST_OUTPUT" | jq -r '.event')" "json event filter"
assert_eq "stable" "$(printf '%s\n' "$IW_LAST_OUTPUT" | jq -r '.to_tag')" "json output release target"

run_iw iw-history --image app --scanner trivy
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "blocked"
assert_contains "$IW_LAST_OUTPUT" "report changed"
assert_not_contains "$IW_LAST_OUTPUT" "released"

run_iw iw-history --image app --event scan_report_changed --json
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_eq "2" "$(printf '%s\n' "$IW_LAST_OUTPUT" | wc -l | tr -d ' ')" "json report change event filter"
assert_contains "$IW_LAST_OUTPUT" '"summary_changed":"false"'

run_iw iw-history --image app --source iw-stage
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "staged"
assert_not_contains "$IW_LAST_OUTPUT" "blocked"

run_iw iw-history --image app --category release
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "released"
assert_not_contains "$IW_LAST_OUTPUT" "blocked"

run_iw iw-history --since "2026-05-25T09:30:00Z" --until "2026-05-25T10:30:00Z"
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "released :stable_20260525-0800_11111111"
assert_not_contains "$IW_LAST_OUTPUT" "blocked"

run_iw iw-history --since "2026-05-25" --until "2026-05-25"
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "released :stable_20260525-0800_11111111"
assert_contains "$IW_LAST_OUTPUT" "blocked :stable_20260525-0800_11111111"

run_iw iw-history --image app --limit 1
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_eq "1" "$(printf '%s\n' "$IW_LAST_OUTPUT" | wc -l | tr -d ' ')" "limit output lines"

run_iw iw-history --image app --reverse --limit 1
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "staged :stable_20260525-0800_11111111"

rm -f "$events"
run_iw iw-history
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "No history events found"

#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/helpers/assertions.sh
source "${TEST_DIR}/helpers/assertions.sh"
iw_test_init

conf="$(iw_config_path)"
events="${XDG_STATE_HOME}/image-warden/events.log"

write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
SCANNER_TRIVY=true
SCANNER_GRYPE=false

image "app" upstream="docker.io/library/nginx:stable"
EOF

run_iw iw-stage --config "$conf" --dry-run app
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_file_not_exists "$events"

run_iw iw-stage --config "$conf" app
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_file_exists "$events"

jq -s -e '
  all(.[];
    (.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
    and (.event | type == "string")
    and (.source | type == "string")
    and (.category | type == "string")
  )
' "$events" >/dev/null || fail "events log should be valid JSONL with ts and event"

assert_json_field "$events" 'select(.event == "staged") | .image' "app" "staged event image"
assert_json_field "$events" 'select(.event == "staged") | .source' "iw-stage" "staged event source"
assert_json_field "$events" 'select(.event == "staged") | .category' "stage" "staged event category"
assert_file_not_contains "$events" "remaining in quarantine" "status logs should not be event log entries"

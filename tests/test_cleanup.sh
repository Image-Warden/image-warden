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
LOCAL_REGISTRY_TLS_VERIFY=false
KEEP_IMAGES=1
PRODUCTION_TAG="stable"
SCANNER_TRIVY=true
SCANNER_GRYPE=false
REGISTRY_CONTAINER_NAME="staging-registry"
CONTAINER_RUNTIME="podman"

image "app" \
  upstream="docker.io/library/nginx:stable" \
  production_tag="stable"
EOF

run_iw iw-cleanup --config "$conf" --dry-run
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "[dry-run] Would delete: app:stable_20990101-0000_aaaaaaaa"
assert_file_not_exists "$events"

: > "$IW_FAKE_LOG"
run_iw iw-cleanup --config "$conf"
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "Deleted: app:stable_20990101-0000_aaaaaaaa"
assert_contains "$IW_LAST_OUTPUT" "Deleted: app:stable_20990102-0000_bbbbbbbb"
assert_contains "$IW_LAST_OUTPUT" "2 old image version(s) removed"
assert_file_contains "$IW_FAKE_LOG" "curl -sf -X DELETE" "cleanup uses registry delete"
assert_file_contains "$IW_FAKE_LOG" "podman exec staging-registry" "cleanup runs registry gc"
assert_file_contains "$events" '"event":"cleanup_deleted_tag"' "cleanup deletion event"
assert_file_contains "$events" '"event":"registry_gc"' "registry gc event"

old_report_dir="${XDG_CACHE_HOME}/image-warden/scanner-reports"
old_report="${old_report_dir}/old.json"
mkdir -p "$old_report_dir"
printf '{}\n' > "$old_report"
touch -d '40 days ago' "$old_report"

export IW_FAKE_PODMAN_GC_FAIL=1
run_iw iw-cleanup --config "$conf"
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "GC: gc failed"
assert_contains "$IW_LAST_OUTPUT" "registry garbage collection failed (exit code 42)"
assert_contains "$IW_LAST_OUTPUT" "1 scanner report(s) older than 30 days removed"
assert_file_not_exists "$old_report"
assert_file_contains "$events" '"event":"scanner_report_removed"' "scanner report pruning continued after gc failure"

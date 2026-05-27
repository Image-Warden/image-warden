#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/helpers/assertions.sh
source "${TEST_DIR}/helpers/assertions.sh"
iw_test_init

conf="$(iw_config_path)"
digest="sha256:1111111111111111111111111111111111111111111111111111111111111111"
tag="stable_20990102-0304_11111111"
candidate="${XDG_STATE_HOME}/image-warden/candidates/app/${digest#sha256:}.json"
hook="${IW_TEST_TMP}/post-release-hook"
hook_log="${IW_TEST_TMP}/post-release-hook.log"

cat > "$hook" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'name=%s\n' "$IW_IMAGE_NAME"
    printf 'from=%s\n' "$IW_RELEASE_FROM_TAG"
    printf 'to=%s\n' "$IW_RELEASE_TO_TAG"
    printf 'digest=%s\n' "$IW_RELEASE_DIGEST"
    printf 'registry=%s\n' "$IW_LOCAL_REGISTRY"
} > "$IW_TEST_HOOK_LOG"
EOF
chmod +x "$hook"
export IW_TEST_HOOK_LOG="$hook_log"

write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
LOCAL_REGISTRY_TLS_VERIFY=false
SCANNER_TRIVY=true
SCANNER_GRYPE=false
SCANNER_SEVERITY="CRITICAL,HIGH"
QUARANTINE_HOURS=72
PRODUCTION_TAG="production"
IMAGE_RELEASE_HOOK="__HOOK__"
IMAGE_RELEASE_HOOK_TIMEOUT=30

image "app" \
  upstream="docker.io/library/nginx:stable" \
  severity="HIGH" \
  quarantine_hours=72 \
  production_tag="stable" \
  platform="linux/armv7"
EOF
sed -i "s#__HOOK__#${hook}#" "$conf"

export IW_FAKE_UPSTREAM_DIGEST="$digest"
export IW_FAKE_UPSTREAM_CREATED="2099-01-02T03:04:05Z"
export IW_FAKE_PROD_DIGEST="sha256:9999999999999999999999999999999999999999999999999999999999999999"

run_iw iw-stage --config "$conf" app
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "Checking app: docker.io/library/nginx:stable"
assert_contains "$IW_LAST_OUTPUT" "Staged as :${tag}"
assert_file_exists "$candidate"
assert_json_field "$candidate" ".local_name" "app" "candidate local name"
assert_json_field "$candidate" ".tag" "$tag" "candidate tag"
assert_json_field "$candidate" ".digest" "$digest" "candidate digest"
assert_json_field "$candidate" ".quarantine_hours_at_stage" "72" "candidate quarantine hours"
assert_file_contains "$IW_FAKE_LOG" "--override-os=linux --override-arch=arm --override-variant=v7" "platform flags passed to skopeo"
assert_file_contains "$IW_FAKE_LOG" "docker://127.0.0.1:5000/app:${tag}" "staged copy destination"

run_iw iw-stage --config "$conf" app
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "No change (${digest})"

run_iw iw-release --config "$conf"
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "app: 1 candidate(s) queued, 0 eligible"
assert_contains "$IW_LAST_OUTPUT" "remaining in quarantine"
assert_not_contains "$IW_LAST_OUTPUT" "Released:"

export IW_FAKE_TRIVY_MODE=blocked
run_iw iw-release --config "$conf" --force-release app
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "manual release requested, quarantine bypassed"
assert_contains "$IW_LAST_OUTPUT" "BLOCKED: app:${tag} failed Trivy gate"
assert_file_exists "$candidate"
scanner_hash="$(jq -r '.scanner_blocked_report_hashes.trivy // empty' "$candidate")"
assert_contains "$scanner_hash" "sha256:"

run_iw iw-release --config "$conf" --force-release app
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "Block notification already sent for unchanged Trivy report"

: > "$IW_FAKE_LOG"
run_iw iw-release --config "$conf" --force-release app --ignore-scanner
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "scanner gate skipped (--ignore-scanner)"
assert_contains "$IW_LAST_OUTPUT" "Released: app:stable (from :${tag})"
assert_file_not_exists "$candidate"
assert_file_contains "$IW_FAKE_LOG" "docker://127.0.0.1:5000/app:${tag} docker://127.0.0.1:5000/app:stable" "promotion copy"
assert_file_contains "$hook_log" "name=app" "hook image name"
assert_file_contains "$hook_log" "from=${tag}" "hook source tag"
assert_file_contains "$hook_log" "to=stable" "hook production tag"
assert_file_contains "$hook_log" "digest=${digest}" "hook digest"
assert_file_contains "$hook_log" "registry=127.0.0.1:5000" "hook registry"

events="${XDG_STATE_HOME}/image-warden/events.log"
assert_file_exists "$events"
assert_file_contains "$events" '"event":"staged"' "staged event"
assert_file_contains "$events" '"event":"scan_blocked"' "blocked event"
assert_file_contains "$events" '"event":"scanner_gate_ignored"' "ignore scanner event"
assert_file_contains "$events" '"event":"released"' "released event"
assert_file_contains "$events" '"event":"image_release_hook_succeeded"' "image-release hook event"

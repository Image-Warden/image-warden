#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/helpers/assertions.sh
source "${TEST_DIR}/helpers/assertions.sh"
iw_test_init

# Resolve the host platform the same way iw-stage does, so the fake index can
# contain a matching entry regardless of which arch runs the tests.
source "${IW_TEST_ROOT}/lib/common.sh"
_iw_parse_platform "linux/$(uname -m)" "host platform" >/dev/null
host_arch="$_IW_PLAT_ARCH"
host_variant="$_IW_PLAT_VARIANT"
[[ -n "$host_arch" ]] || fail "could not resolve host arch for test setup"

conf="$(iw_config_path)"
list_digest="sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
platform_digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
other_digest="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
single_digest="sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
tag="stable_20990102-0304_aaaaaaaa"
candidate="${XDG_STATE_HOME}/image-warden/candidates/app/${platform_digest#sha256:}.json"

write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
LOCAL_REGISTRY_TLS_VERIFY=false
SCANNER_TRIVY=true
SCANNER_GRYPE=false
QUARANTINE_HOURS=72
PRODUCTION_TAG="production"

image "app" \
  upstream="docker.io/library/nginx:stable"
EOF

# -- multi-arch index, no platform configured: per-platform digest is recorded --
IW_FAKE_RAW_MANIFEST=$(jq -cn \
    --arg pd "$platform_digest" \
    --arg od "$other_digest" \
    --arg arch "$host_arch" \
    --arg variant "$host_variant" \
    '{manifests: [
        {digest: $od, platform: {os: "linux", architecture: "bogusarch"}},
        {digest: $pd, platform: ({os: "linux", architecture: $arch}
            + (if $variant != "" then {variant: $variant} else {} end))}
    ]}')
export IW_FAKE_RAW_MANIFEST
export IW_FAKE_UPSTREAM_DIGEST="$list_digest"
export IW_FAKE_UPSTREAM_CREATED="2099-01-02T03:04:05Z"

run_iw iw-stage --config "$conf" app
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "Platform: linux/${host_arch}${host_variant:+/$host_variant} (host default)"
assert_contains "$IW_LAST_OUTPUT" "New digest: ${platform_digest}"
assert_not_contains "$IW_LAST_OUTPUT" "$list_digest"
assert_file_exists "$candidate"
assert_json_field "$candidate" ".digest" "$platform_digest" "candidate records per-platform digest"
assert_file_contains "${XDG_STATE_HOME}/image-warden/app.digest" "$platform_digest" "digest cache holds per-platform digest"

events="${XDG_STATE_HOME}/image-warden/events.log"
assert_file_contains "$events" '"platform_source":"host default"' "staged event marks host default platform"

# -- release: staged registry digest matches, no mismatch removal ---------------
export IW_FAKE_STAGED_DIGEST="$platform_digest"
run_iw iw-release --config "$conf" --force-release app
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "Released: app:production (from :${tag})"
assert_not_contains "$IW_LAST_OUTPUT" "digest changed in registry"
assert_file_not_exists "$candidate"

# -- single-arch manifest, no platform configured: digest unchanged -------------
rm -f "${XDG_STATE_HOME}/image-warden/app.digest"
export IW_FAKE_RAW_MANIFEST='{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","config":{}}'
export IW_FAKE_UPSTREAM_DIGEST="$single_digest"
unset IW_FAKE_STAGED_DIGEST

run_iw iw-stage --config "$conf" app
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "New digest: ${single_digest}"
single_candidate="${XDG_STATE_HOME}/image-warden/candidates/app/${single_digest#sha256:}.json"
assert_file_exists "$single_candidate"
assert_json_field "$single_candidate" ".digest" "$single_digest" "single-arch digest recorded unchanged"

# -- configured platform: no host-default marker ---------------------------------
write_config "$conf" <<'EOF'
LOCAL_REGISTRY="127.0.0.1:5000"
LOCAL_REGISTRY_TLS_VERIFY=false
QUARANTINE_HOURS=72

image "pinned" \
  upstream="docker.io/library/nginx:stable" \
  platform="linux/arm/v7"
EOF

IW_FAKE_RAW_MANIFEST=$(jq -cn --arg pd "$platform_digest" \
    '{manifests: [{digest: $pd, platform: {os: "linux", architecture: "arm", variant: "v7"}}]}')
export IW_FAKE_RAW_MANIFEST

run_iw iw-stage --config "$conf" pinned
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "Platform: linux/arm/v7"
assert_not_contains "$IW_LAST_OUTPUT" "(host default)"

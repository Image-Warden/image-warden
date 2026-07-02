#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/helpers/assertions.sh
source "${TEST_DIR}/helpers/assertions.sh"
iw_test_init

source "${IW_TEST_ROOT}/lib/common.sh"

_iw_parse_platform "" "platform"
assert_eq "" "$_IW_PLAT_OS" "empty platform os"
assert_eq "" "$_IW_PLAT_ARCH" "empty platform arch"
assert_eq "" "$_IW_PLAT_VARIANT" "empty platform variant"

_iw_parse_platform "linux/amd64" "platform"
assert_eq "linux" "$_IW_PLAT_OS" "amd64 os"
assert_eq "amd64" "$_IW_PLAT_ARCH" "amd64 arch"
assert_eq "" "$_IW_PLAT_VARIANT" "amd64 variant"
assert_eq "--override-os=linux --override-arch=amd64" "$(_iw_platform_flags "$_IW_PLAT_OS" "$_IW_PLAT_ARCH" "$_IW_PLAT_VARIANT")" "amd64 flags"

_iw_parse_platform "linux/x86_64" "platform"
assert_eq "amd64" "$_IW_PLAT_ARCH" "x86_64 normalizes to amd64"

_iw_parse_platform "linux/x64" "platform"
assert_eq "amd64" "$_IW_PLAT_ARCH" "x64 normalizes to amd64"

_iw_parse_platform "linux/aarch64" "platform"
assert_eq "arm64" "$_IW_PLAT_ARCH" "aarch64 normalizes to arm64"

_iw_parse_platform "linux/armv7" "platform"
assert_eq "linux" "$_IW_PLAT_OS" "armv7 os"
assert_eq "arm" "$_IW_PLAT_ARCH" "armv7 arch"
assert_eq "v7" "$_IW_PLAT_VARIANT" "armv7 variant"
assert_eq "--override-os=linux --override-arch=arm --override-variant=v7" "$(_iw_platform_flags "$_IW_PLAT_OS" "$_IW_PLAT_ARCH" "$_IW_PLAT_VARIANT")" "armv7 flags"

_iw_parse_platform "linux/arm/v6" "platform"
assert_eq "arm" "$_IW_PLAT_ARCH" "arm/v6 arch"
assert_eq "v6" "$_IW_PLAT_VARIANT" "arm/v6 variant"

assert_eq "" "$(_iw_platform_flags "" "" "")" "empty platform flags"

run_func _iw_parse_platform "linux/sparc" "platform"
assert_failure "$IW_LAST_STATUS" "unknown arch should fail"
assert_contains "$IW_LAST_OUTPUT" "unrecognized arch"

assert_eq "nginx" "$(_iw_ref_repo "nginx")" "ref_repo bare name"
assert_eq "nginx" "$(_iw_ref_repo "nginx:stable")" "ref_repo strips tag"
assert_eq "docker.io/library/nginx" "$(_iw_ref_repo "docker.io/library/nginx:1.29")" "ref_repo strips tag from qualified ref"
assert_eq "registry:5000/app" "$(_iw_ref_repo "registry:5000/app:tag")" "ref_repo keeps registry port, strips tag"
assert_eq "registry:5000/app" "$(_iw_ref_repo "registry:5000/app")" "ref_repo keeps registry port without tag"
assert_eq "repo" "$(_iw_ref_repo "repo@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")" "ref_repo strips digest"
assert_eq "localhost:5000/app" "$(_iw_ref_repo "localhost:5000/app@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")" "ref_repo keeps port, strips digest"
assert_eq "repo" "$(_iw_ref_repo "repo:tag@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")" "ref_repo strips tag and digest"

STATE_DIR="${XDG_STATE_HOME}/image-warden"
export STATE_DIR
mkdir -p "${IW_TEST_TMP}/event-log-dir"
IW_EVENTS_LOG="${IW_TEST_TMP}/event-log-dir"
export IW_EVENTS_LOG
run_func _iw_event_log "staged" --arg image "app"
assert_success "$IW_LAST_STATUS" "$IW_LAST_OUTPUT"
assert_contains "$IW_LAST_OUTPUT" "WARNING: event log write failed"
unset IW_EVENTS_LOG

lock_file="${IW_TEST_TMP}/locks/test.lock"
mkdir -p "$(dirname -- "$lock_file")"
exec 8>"$lock_file"
flock 8
IW_LOCK_TIMEOUT_SECONDS=0
export IW_LOCK_TIMEOUT_SECONDS
run_func _iw_acquire_lock "$lock_file"
assert_failure "$IW_LAST_STATUS" "held lock should time out"
assert_contains "$IW_LAST_OUTPUT" "cannot acquire lock within 0s"
unset IW_LOCK_TIMEOUT_SECONDS
flock -u 8
exec 8>&-

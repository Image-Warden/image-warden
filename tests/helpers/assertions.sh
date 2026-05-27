#!/usr/bin/env bash
# Shared helpers for Image-Warden tests.

set -euo pipefail

IW_TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
    echo "not ok - $*" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-values differ}"
    [[ "$actual" == "$expected" ]] || fail "${msg}: expected '${expected}', got '${actual}'"
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-missing expected text}"
    [[ "$haystack" == *"$needle"* ]] || fail "${msg}: expected to find '${needle}' in '${haystack}'"
}

assert_not_contains() {
    local haystack="$1" needle="$2" msg="${3:-unexpected text found}"
    [[ "$haystack" != *"$needle"* ]] || fail "${msg}: did not expect '${needle}' in '${haystack}'"
}

assert_file_exists() {
    local file="$1"
    [[ -f "$file" ]] || fail "expected file to exist: $file"
}

assert_file_not_exists() {
    local file="$1"
    [[ ! -e "$file" ]] || fail "expected file to be absent: $file"
}

assert_file_contains() {
    local file="$1" needle="$2" msg="${3:-missing expected file text}"
    assert_file_exists "$file"
    local content
    content="$(< "$file")"
    assert_contains "$content" "$needle" "$msg"
}

assert_file_not_contains() {
    local file="$1" needle="$2" msg="${3:-unexpected file text found}"
    assert_file_exists "$file"
    local content
    content="$(< "$file")"
    assert_not_contains "$content" "$needle" "$msg"
}

assert_json_field() {
    local file="$1" jq_filter="$2" expected="$3" msg="${4:-json field differs}"
    assert_file_exists "$file"
    local actual
    actual="$(jq -r "$jq_filter" "$file")" || fail "could not read json field '${jq_filter}' from ${file}"
    assert_eq "$expected" "$actual" "$msg"
}

assert_success() {
    local rc="$1" output="${2:-command failed}"
    [[ "$rc" -eq 0 ]] || fail "${output} (exit ${rc})"
}

assert_failure() {
    local rc="$1" output="${2:-command unexpectedly succeeded}"
    [[ "$rc" -ne 0 ]] || fail "$output"
}

run_cmd() {
    local output rc
    set +e
    output="$("$@" 2>&1)"
    rc=$?
    set -e
    IW_LAST_OUTPUT="$output"
    IW_LAST_STATUS="$rc"
}

run_func() {
    local output_file rc
    output_file="${IW_TEST_TMP}/function-output.$$"
    set +e
    "$@" > "$output_file" 2>&1
    rc=$?
    set -e
    # shellcheck disable=SC2034 # Read by callers after run_func returns.
    IW_LAST_OUTPUT="$(< "$output_file")"
    # shellcheck disable=SC2034 # Read by callers after run_func returns.
    IW_LAST_STATUS="$rc"
    rm -f "$output_file"
}

iw_test_init() {
    IW_TEST_TMP="$(mktemp -d)"
    export IW_TEST_TMP

    export XDG_CONFIG_HOME="${IW_TEST_TMP}/config"
    export XDG_DATA_HOME="${IW_TEST_TMP}/data"
    export XDG_STATE_HOME="${IW_TEST_TMP}/state"
    export XDG_CACHE_HOME="${IW_TEST_TMP}/cache"
    export HOME="${IW_TEST_TMP}/home"

    mkdir -p \
        "${XDG_CONFIG_HOME}/image-warden" \
        "${XDG_DATA_HOME}/image-warden" \
        "${XDG_STATE_HOME}/image-warden" \
        "${XDG_CACHE_HOME}/image-warden" \
        "$HOME"

    cp -R "${IW_TEST_ROOT}/lib" "${XDG_DATA_HOME}/image-warden/lib"
    cp -R "${IW_TEST_ROOT}/bin" "${XDG_DATA_HOME}/image-warden/bin"
    chmod +x "${IW_TEST_ROOT}/tests/helpers/fakebin/"* 2>/dev/null || true

    export IW_FAKE_LOG="${IW_TEST_TMP}/fake.log"
    : > "$IW_FAKE_LOG"
    export IW_TEST_ORIGINAL_PATH="$PATH"
    export PATH="${IW_TEST_ROOT}/tests/helpers/fakebin:${PATH}"

    trap 'iw_test_cleanup' EXIT
}

iw_test_cleanup() {
    if [[ "${IW_TEST_KEEP_TMP:-0}" == "1" ]]; then
        echo "Keeping test temp dir: ${IW_TEST_TMP:-}" >&2
        return 0
    fi

    [[ -n "${IW_TEST_TMP:-}" && -d "$IW_TEST_TMP" ]] && rm -rf "$IW_TEST_TMP"
}

write_config() {
    local conf="${1:-${XDG_CONFIG_HOME}/image-warden/image-warden.conf}"
    mkdir -p "$(dirname -- "$conf")"
    cat > "$conf"
}

iw_config_path() {
    printf '%s\n' "${XDG_CONFIG_HOME}/image-warden/image-warden.conf"
}

iw_script() {
    local name="$1"
    printf '%s\n' "${IW_TEST_ROOT}/bin/${name}"
}

run_iw() {
    local name="$1"
    shift
    run_cmd bash "$(iw_script "$name")" "$@"
}

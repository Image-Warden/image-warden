#!/usr/bin/env bash
# lib/common.sh: shared helper functions
#
# Sourced by bin scripts. Not executed directly.

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

_iw_event_category() {
    case "$1" in
        staged) echo "stage" ;;
        released|force_release_requested) echo "release" ;;
        scan_clean|scan_blocked|scan_error|scan_report_changed|scanner_unavailable) echo "scan" ;;
        scanner_gate_ignored) echo "security" ;;
        notify_ready|quarantine_accelerated_notified) echo "notify" ;;
        candidate_removed|candidate_corrupt_removed) echo "state" ;;
        image_release_hook_failed) echo "hook" ;;
        image_release_hook_succeeded) echo "hook" ;;
        cleanup_deleted_tag|registry_gc|scanner_report_removed) echo "cleanup" ;;
        *) echo "other" ;;
    esac
}

_iw_event_log() {
    local event="$1"
    shift

    if [[ -z "${STATE_DIR:-}" ]]; then
        echo "WARNING: event log skipped: STATE_DIR is not set" >&2
        return 0
    fi
    if ! mkdir -p "$STATE_DIR"; then
        echo "WARNING: event log skipped: cannot create state directory: $STATE_DIR" >&2
        return 0
    fi

    local events_file="${IW_EVENTS_LOG:-${STATE_DIR}/events.log}"
    local ts
    ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local source="${IW_EVENT_SOURCE:-unknown}"
    local category
    category="$(_iw_event_category "$event")"

    if ! command -v jq &>/dev/null; then
        echo "WARNING: event log skipped: jq not found" >&2
        return 0
    fi

    if ! jq -cn \
        --arg ts "$ts" \
        --arg event "$event" \
        --arg source "$source" \
        --arg category "$category" \
        "$@" \
        '$ARGS.named' >> "$events_file" 2>/dev/null; then
        echo "WARNING: event log write failed: $events_file" >&2
    fi
}

_iw_bool_enabled() {
    case "${1,,}" in
        1|true|yes|on) return 0 ;;
        *)             return 1 ;;
    esac
}

_iw_bool_disabled() {
    case "${1,,}" in
        0|false|no|off) return 0 ;;
        *)              return 1 ;;
    esac
}

_iw_retry() {
    local label="$1"
    shift

    local attempts="${IW_RETRY_ATTEMPTS:-3}"
    local delay="${IW_RETRY_DELAY_SECONDS:-5}"
    local attempt rc

    for (( attempt = 1; attempt <= attempts; attempt++ )); do
        "$@"
        rc=$?

        [[ $rc -eq 0 ]] && return 0

        if [[ $attempt -lt $attempts ]]; then
            log "  WARNING: ${label} failed (attempt ${attempt}/${attempts}), retrying in ${delay}s" >&2
            sleep "$delay"
        fi
    done

    log "  ERROR: ${label} failed after ${attempts} attempt(s)" >&2
    return "$rc"
}

# Extract tag portion from a full image reference.
#   docker.io/library/nginx:stable  ->  stable
#   docker.io/library/nginx         ->  latest
#   localhost:5000/myapp:v1.2       ->  v1.2
_upstream_tag() {
    local ref="$1" part
    part="${ref##*:}"
    if [[ "$part" == "$ref" || "$part" == */* ]]; then
        echo "latest"
    else
        echo "$part"
    fi
}

_iw_parse_platform() {
    local platform="$1"
    local label="${2:-PLATFORM}"

    _IW_PLAT_OS="" _IW_PLAT_ARCH="" _IW_PLAT_VARIANT=""
    [[ -z "$platform" ]] && return 0

    if ! command -v jq &>/dev/null; then
        log "ERROR: 'jq' required when ${label} is set (multi-arch digest resolution)"
        return 1
    fi

    IFS='/' read -r _IW_PLAT_OS _IW_PLAT_ARCH _IW_PLAT_VARIANT <<< "$platform"
    case "$_IW_PLAT_ARCH" in
        x86_64|x86-64|x64)
            log "NOTICE: ${label}: normalizing arch '$_IW_PLAT_ARCH' -> 'amd64'"
            _IW_PLAT_ARCH="amd64" ;;
        aarch64|arm64v8)
            log "NOTICE: ${label}: normalizing arch '$_IW_PLAT_ARCH' -> 'arm64'"
            _IW_PLAT_ARCH="arm64" ;;
        armv7|armv7l|armhf)
            log "NOTICE: ${label}: normalizing arch '$_IW_PLAT_ARCH' -> 'arm' (variant v7)"
            _IW_PLAT_ARCH="arm"; _IW_PLAT_VARIANT="${_IW_PLAT_VARIANT:-v7}" ;;
        armv6|armv6l)
            log "NOTICE: ${label}: normalizing arch '$_IW_PLAT_ARCH' -> 'arm' (variant v6)"
            _IW_PLAT_ARCH="arm"; _IW_PLAT_VARIANT="${_IW_PLAT_VARIANT:-v6}" ;;
        amd64|arm64|arm|386|ppc64le|s390x|riscv64|mips64le)
            ;; # canonical
        "")
            log "ERROR: ${label}='$platform' missing arch (expected os/arch, e.g. linux/amd64)"
            return 1 ;;
        *)
            log "ERROR: unrecognized arch '$_IW_PLAT_ARCH' in ${label}='$platform'"
            log "Canonical values: amd64, arm64, arm, 386, ppc64le, s390x, riscv64, mips64le"
            return 1 ;;
    esac
}

_iw_platform_flags() {
    local os="$1" arch="$2" variant="${3:-}"
    [[ -z "$arch" ]] && return
    local flags="--override-os=$os --override-arch=$arch"
    [[ -n "$variant" ]] && flags+=" --override-variant=$variant"
    echo "$flags"
}

# skopeo TLS flags derived from LOCAL_REGISTRY_TLS_VERIFY
_src_tls_flag() {
    _iw_bool_enabled "${LOCAL_REGISTRY_TLS_VERIFY:-false}" \
        && echo "--src-tls-verify=true" || echo "--src-tls-verify=false"
}

_dest_tls_flag() {
    _iw_bool_enabled "${LOCAL_REGISTRY_TLS_VERIFY:-false}" \
        && echo "--dest-tls-verify=true" || echo "--dest-tls-verify=false"
}

_local_tls_flag() {
    _iw_bool_enabled "${LOCAL_REGISTRY_TLS_VERIFY:-false}" \
        && echo "--tls-verify=true" || echo "--tls-verify=false"
}

_iw_acquire_lock() {
    local lock_file="$1"
    local lock_dir

    lock_dir="$(dirname -- "$lock_file")"
    mkdir -p "$lock_dir"
    exec 9>"$lock_file"
    flock 9 || {
        echo "ERROR: cannot acquire lock: $lock_file" >&2
        return 1
    }
}

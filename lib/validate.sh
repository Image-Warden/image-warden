#!/usr/bin/env bash
# lib/validate.sh: sanitization and validation functions

_iw_require_bash() {
    if [[ -z "${BASH_VERSION:-}" ]]; then
        echo "ERROR: image-warden scripts must be run with bash" >&2
        return 1
    fi

    if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
        echo "ERROR: bash >= 4.4 required, got ${BASH_VERSION}" >&2
        return 1
    fi
}


_iw_validate_tag_component() {
    local value="$1"

    [[ -n "$value" ]] || return 1
    [[ ${#value} -le 128 ]] || return 1
    [[ "$value" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || return 1
}

_iw_validate_local_tag() {
    local tag="$1"

    [[ -n "$tag" ]] || return 1
    [[ ${#tag} -le 64 ]] || return 1
    [[ "$tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*_[0-9]{8}-[0-9]{4}(_[0-9a-f]{8})?$ ]] || return 1
}

_iw_validate_digest() {
    local digest="$1"

    [[ -n "$digest" ]] || return 1
    [[ ${#digest} -eq 71 ]] || return 1
    [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || return 1
}

_iw_validate_local_name() {
    local name="$1"

    [[ -n "$name" ]] || return 1
    [[ ${#name} -le 64 ]] || return 1
    [[ "$name" =~ ^[a-z0-9][a-z0-9_.-]*$ ]] || return 1
}

_iw_validate_bool() {
    local label="$1"
    local value="$2"

    [[ -z "$value" ]] && return 0

    if _iw_bool_enabled "$value" || _iw_bool_disabled "$value"; then
        return 0
    fi

    echo "ERROR: ${label} must be true or false, got: '$value'" >&2
    return 1
}

_iw_validate_severity_list() {
    local label="$1"
    local value="$2"
    local errors=0
    local sev
    local -a sevs=()

    IFS=',' read -ra sevs <<< "${value^^}"
    for sev in "${sevs[@]}"; do
        case "$sev" in
            CRITICAL|HIGH|MEDIUM|LOW|UNKNOWN) ;;
            *)
                echo "ERROR: ${label} contains invalid severity: '$sev'" >&2
                errors=$(( errors + 1 ))
                ;;
        esac
    done

    [[ $errors -eq 0 ]]
}

_iw_validate_platform() {
    local label="$1"
    local value="$2"
    local os arch variant extra

    [[ -n "$value" ]] || return 0

    IFS='/' read -r os arch variant extra <<< "$value"

    if [[ -n "${extra:-}" || -z "${os:-}" || -z "${arch:-}" ]]; then
        echo "ERROR: ${label} must be os/arch[/variant], got: '$value'" >&2
        return 1
    fi

    case "$os" in
        linux) ;;
        *)
            echo "ERROR: ${label} has unsupported os: '$os' (supported: linux)" >&2
            return 1
            ;;
    esac

    case "$arch" in
        amd64|arm64|arm|386|ppc64le|s390x|riscv64|mips64le|x86_64|x86-64|x64|aarch64|arm64v8|armv7|armv7l|armhf|armv6|armv6l) ;;
        *)
            echo "ERROR: ${label} has unsupported arch: '$arch'" >&2
            return 1
            ;;
    esac

    case "${variant:-}" in
        ""|v5|v6|v7|v8) ;;
        *)
            echo "ERROR: ${label} has unsupported variant: '$variant'" >&2
            return 1
            ;;
    esac
}

_iw_validate_trivy_ignore_list() {
    local label="$1"
    local value="$2"
    local errors=0
    local id
    local -a _ids

    [[ -n "$value" ]] || return 0

    if [[ "$value" =~ [[:space:]] ]]; then
        echo "ERROR: ${label} must not contain whitespace; use comma-separated vulnerability identifiers" >&2
        return 1
    fi

    IFS=',' read -ra _ids <<< "$value"
    for id in "${_ids[@]}"; do
        if [[ -z "$id" ]]; then
            echo "ERROR: ${label} contains an empty vulnerability identifier." >&2
            errors=$(( errors + 1 ))
            continue
        fi

        # Trivy .trivyignore vulnerability entries are one finding ID per line.
        # Keep this to non-whitespace identifier characters and write each ID
        # unchanged to the temporary ignore file.
        if ! [[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]*$ ]]; then
            echo "ERROR: ${label} contains invalid vulnerability identifier: '$id'" >&2
            errors=$(( errors + 1 ))
        fi
    done

    [[ $errors -eq 0 ]]
}

_iw_validate_scanner_list() {
    local label="$1"
    local value="$2"
    local errors=0
    local scanner
    local -a scanners

    [[ -n "$value" ]] || {
        echo "ERROR: ${label} must not be empty" >&2
        return 1
    }

    if [[ "$value" =~ [[:space:]] ]]; then
        echo "ERROR: ${label} must not contain whitespace; use comma-separated scanner names" >&2
        return 1
    fi

    IFS=',' read -ra scanners <<< "${value,,}"
    for scanner in "${scanners[@]}"; do
        case "$scanner" in
            trivy|grype) ;;
            "")
                echo "ERROR: ${label} contains an empty scanner name" >&2
                errors=$(( errors + 1 ))
                ;;
            *)
                echo "ERROR: ${label} contains unsupported scanner: '$scanner'" >&2
                errors=$(( errors + 1 ))
                ;;
        esac
    done

    [[ $errors -eq 0 ]]
}

#!/usr/bin/env bash
# lib/validate.sh: sanitization and validation functions for image-warden

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
    [[ "$tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*_[0-9]{8}-[0-9]{4}_[0-9a-f]{8}$ ]] || return 1
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

_iw_validate_severity_list() {
    local label="$1"
    local value="$2"
    local errors=0
    local sev

    IFS=',' read -ra _sevs <<< "${value^^}"
    for sev in "${_sevs[@]}"; do
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

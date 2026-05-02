#!/usr/bin/env bash
# lib/validate.sh: config validation for image-warden
#
# Sourced by bin scripts after sourcing the config file.
# Exits with error on invalid configuration.

_iw_validate_config() {
    local errors=0

    # -- QUARANTINE_HOURS must be a positive integer ---------------------------
    if [[ -n "${QUARANTINE_HOURS:-}" ]]; then
        if ! [[ "$QUARANTINE_HOURS" =~ ^[0-9]+$ ]] || [[ "$QUARANTINE_HOURS" -eq 0 ]]; then
            echo "ERROR: QUARANTINE_HOURS must be a positive integer, got: '$QUARANTINE_HOURS'" >&2
            errors=$(( errors + 1 ))
        fi
    fi

    # -- KEEP_IMAGES must be a positive integer --------------------------------
    if [[ -n "${KEEP_IMAGES:-}" ]]; then
        if ! [[ "$KEEP_IMAGES" =~ ^[0-9]+$ ]] || [[ "$KEEP_IMAGES" -eq 0 ]]; then
            echo "ERROR: KEEP_IMAGES must be a positive integer, got: '$KEEP_IMAGES'" >&2
            errors=$(( errors + 1 ))
        fi
    fi

    # -- TRIVY_SEVERITY must be valid comma-separated values -------------------
    if [[ -n "${TRIVY_SEVERITY:-}" ]]; then
        local sev
        IFS=',' read -ra _sevs <<< "${TRIVY_SEVERITY^^}"
        for sev in "${_sevs[@]}"; do
            case "$sev" in
                CRITICAL|HIGH|MEDIUM|LOW|UNKNOWN) ;;
                *) echo "ERROR: TRIVY_SEVERITY contains invalid value: '$sev'" >&2
                   errors=$(( errors + 1 )) ;;
            esac
        done
    fi

    # -- LOCAL_REGISTRY must be set --------------------------------------------
    if [[ -z "${LOCAL_REGISTRY:-}" ]]; then
        echo "ERROR: LOCAL_REGISTRY is not set" >&2
        errors=$(( errors + 1 ))
    fi

    # -- Image entries: validate names and check for duplicates -----------------
    if [[ ${#_IW_IMAGES[@]} -gt 0 ]]; then
        declare -A _seen_names=()
        local name upstream

        for name in "${_IW_IMAGES[@]}"; do
            upstream="${_IW_CFG["$name.upstream"]:-}"

            if [[ -z "$name" ]]; then
                echo "ERROR: image entry has empty name" >&2
                errors=$(( errors + 1 ))
                continue
            fi

            if [[ -z "$upstream" ]]; then
                echo "ERROR: image '$name' has no upstream configured" >&2
                errors=$(( errors + 1 ))
                continue
            fi

            if [[ "$name" =~ [^a-zA-Z0-9._-] ]]; then
                echo "ERROR: image name '$name' contains invalid characters (allowed: a-z A-Z 0-9 . _ -)" >&2
                errors=$(( errors + 1 ))
            fi

            if [[ -n "${_seen_names[$name]+x}" ]]; then
                echo "ERROR: duplicate image name '$name'" >&2
                errors=$(( errors + 1 ))
            fi
            _seen_names["$name"]=1
        done
    fi

    if [[ $errors -gt 0 ]]; then
        echo "ERROR: ${errors} config error(s) found in ${CONF:-image-warden.conf}" >&2
        exit 1
    fi
}

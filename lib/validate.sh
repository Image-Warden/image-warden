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

    # -- IMAGES entries: validate local_name and check for duplicates ----------
    if ! declare -p IMAGES &>/dev/null; then
        echo "ERROR: IMAGES array is not defined" >&2
        errors=$(( errors + 1 ))
    elif [[ "$(declare -p IMAGES 2>/dev/null)" != declare\ -a* ]]; then
        echo "ERROR: IMAGES must be a bash array, for example: IMAGES=(...)" >&2
        errors=$(( errors + 1 ))
    elif [[ ${#IMAGES[@]} -gt 0 ]]; then
        declare -A _seen_names=()
        local entry upstream local_name

        for entry in "${IMAGES[@]}"; do
            IFS='|' read -r upstream local_name _ <<< "$entry"

            if [[ -z "$upstream" ]]; then
                echo "ERROR: IMAGES entry has empty upstream reference: '$entry'" >&2
                errors=$(( errors + 1 ))
                continue
            fi

            if [[ -z "$local_name" ]]; then
                echo "ERROR: IMAGES entry has empty local_name: '$entry'" >&2
                errors=$(( errors + 1 ))
                continue
            fi

            if [[ "$local_name" =~ [^a-zA-Z0-9._-] ]]; then
                echo "ERROR: local_name '$local_name' contains invalid characters (allowed: a-z A-Z 0-9 . _ -)" >&2
                errors=$(( errors + 1 ))
            fi

            if [[ -n "${_seen_names[$local_name]+x}" ]]; then
                echo "ERROR: duplicate local_name '$local_name' in IMAGES" >&2
                errors=$(( errors + 1 ))
            fi
            _seen_names["$local_name"]=1
        done
    fi

    if [[ $errors -gt 0 ]]; then
        echo "ERROR: ${errors} config error(s) found in ${CONF:-image-warden.conf}" >&2
        exit 1
    fi
}

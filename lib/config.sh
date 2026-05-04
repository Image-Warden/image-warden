#!/usr/bin/env bash
# lib/config.sh: image configuration loader and validator for image-warden
#
# Sourced by bin scripts before the config file.
# Provides the image() DSL, legacy IMAGES=() import, and config validation.

_IW_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/validate.sh
source "${_IW_LIB_DIR}/validate.sh"

_iw_config_init() {
    _IW_IMAGES=()
    declare -gA _IW_CFG=()
}

image() {
    local name="$1"
    shift

    if [[ -z "$name" ]]; then
        echo "ERROR: image() called without a name" >&2
        return 1
    fi

    local kv key value
    for kv in "$@"; do
        key="${kv%%=*}"
        value="${kv#*=}"
        case "$key" in
            upstream|severity|notify_only|signature_provider|cosign_key)
                _IW_CFG["$name.$key"]="$value" ;;
            *) echo "ERROR: unknown image option '$key' for '$name'" >&2; return 1 ;;
        esac
    done

    _IW_IMAGES+=("$name")
}

_iw_import_legacy_images() {
    local entry upstream local_name severity notify

    [[ ${#IMAGES[@]} -eq 0 ]] && return 0

    echo "NOTICE: legacy IMAGES=() format detected. Consider migrating to image() syntax." >&2
    echo "  See config/image-warden.conf.example for the new format." >&2

    for entry in "${IMAGES[@]}"; do
        IFS='|' read -r upstream local_name severity notify <<< "$entry"

        if [[ "${severity:-}" == "notify_only" ]]; then
            severity=""
            notify="true"
        elif [[ "${notify:-}" == "notify_only" ]]; then
            notify="true"
        else
            notify="false"
        fi

        image "$local_name" \
            upstream="$upstream" \
            ${severity:+severity="$severity"} \
            notify_only="$notify"
    done
}

_iw_print_legacy_config_as_dsl() {
    local entry upstream local_name severity notify

    if ! declare -p IMAGES &>/dev/null; then
        echo "ERROR: no legacy IMAGES=() array found" >&2
        return 1
    fi

    for entry in "${IMAGES[@]}"; do
        IFS='|' read -r upstream local_name severity notify <<< "$entry"

        if [[ "${severity:-}" == "notify_only" ]]; then
            severity=""
            notify="true"
        elif [[ "${notify:-}" == "notify_only" ]]; then
            notify="true"
        else
            notify="false"
        fi

        printf 'image "%s" \\\n' "$local_name"
        printf '  upstream="%s"' "$upstream"

        if [[ -n "${severity:-}" ]]; then
            printf ' \\\n  severity="%s"' "$severity"
        fi

        if [[ "$notify" == "true" ]]; then
            printf ' \\\n  notify_only=true'
        fi

        printf '\n\n'
    done
}


_iw_validate_config() {
    local errors=0

    if [[ -n "${QUARANTINE_HOURS:-}" ]]; then
        if ! [[ "$QUARANTINE_HOURS" =~ ^[0-9]+$ ]] || [[ "$QUARANTINE_HOURS" -eq 0 ]]; then
            echo "ERROR: QUARANTINE_HOURS must be a positive integer, got: '$QUARANTINE_HOURS'" >&2
            errors=$(( errors + 1 ))
        fi
    fi

    if [[ -n "${KEEP_IMAGES:-}" ]]; then
        if ! [[ "$KEEP_IMAGES" =~ ^[0-9]+$ ]] || [[ "$KEEP_IMAGES" -eq 0 ]]; then
            echo "ERROR: KEEP_IMAGES must be a positive integer, got: '$KEEP_IMAGES'" >&2
            errors=$(( errors + 1 ))
        fi
    fi

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

    if [[ -z "${LOCAL_REGISTRY:-}" ]]; then
        echo "ERROR: LOCAL_REGISTRY is not set" >&2
        errors=$(( errors + 1 ))
    fi

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

_iw_load_config() {
    local conf="$1"

    _iw_config_init

    # shellcheck source=/dev/null
    source "$conf"

    if declare -p IMAGES &>/dev/null 2>&1; then
        _iw_import_legacy_images
    fi

    _iw_validate_config
}

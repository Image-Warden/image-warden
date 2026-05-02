#!/usr/bin/env bash
# lib/config.sh: image configuration loader for image-warden
#
# Sourced by bin scripts before the config file.
# Provides the image() DSL and legacy IMAGES=() import.

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


_iw_load_config() {
    local conf="$1"

    _iw_config_init

    # shellcheck source=/dev/null
    source "$conf"

    if declare -p IMAGES &>/dev/null 2>&1; then
        _iw_import_legacy_images
    fi
}

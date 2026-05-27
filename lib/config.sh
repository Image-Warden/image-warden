#!/usr/bin/env bash
# lib/config.sh: image configuration loader and validator
#
# Sourced by bin scripts before the config file.
# Provides the image() DSL and config validation.

_IW_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "${_IW_LIB_DIR}/common.sh"
# shellcheck source=lib/validate.sh
source "${_IW_LIB_DIR}/validate.sh"
_iw_require_bash || exit 1

_iw_config_init() {
    declare -ga _IW_IMAGES=()
    declare -ga _IW_TOP_LEVEL_IMAGE_OPTIONS=()
    declare -gA _IW_CFG=()
    declare -gi _IW_IMAGE_DSL_ERRORS=0
}

image() {
    local name="$1"
    shift

    if [[ -z "$name" ]]; then
        echo "ERROR: image() called without a name" >&2
        _IW_IMAGE_DSL_ERRORS=$(( _IW_IMAGE_DSL_ERRORS + 1 ))
        return 1
    fi

    local kv key value
    for kv in "$@"; do
        key="${kv%%=*}"
        value="${kv#*=}"
        case "$key" in
            upstream|severity|notify_only|scanner_ignore|scanner_ignore_reason|trivy_ignore|trivy_ignore_reason|grype_ignore|grype_ignore_reason|quarantine_hours|production_tag|scanners|platform|signature_provider|cosign_key)
                _IW_CFG["$name.$key"]="$value" ;;
            *)
                echo "ERROR: unknown image option '$key' for '$name'" >&2
                _IW_IMAGE_DSL_ERRORS=$(( _IW_IMAGE_DSL_ERRORS + 1 ))
                return 1
                ;;
        esac
    done

    _IW_IMAGES+=("$name")
}

_iw_legacy_config_as_dsl() {
    local entry upstream local_name severity notify

    if ! declare -p IMAGES &>/dev/null; then
        echo "ERROR: no legacy IMAGES=() array found" >&2
        return 1
    fi

    if [[ ${#IMAGES[@]} -eq 0 ]]; then
        echo "ERROR: legacy IMAGES=() array is empty; remove it from the config instead of converting it" >&2
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


_iw_check_config_line_continuations() {
    local conf="$1"
    local line_no=0
    local errors=0
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_no=$(( line_no + 1 ))
        if [[ "$line" =~ \\[[:space:]]+$ ]]; then
            echo "ERROR: ${conf}:${line_no}: trailing whitespace after backslash; the backslash must be the final character on the line" >&2
            errors=$(( errors + 1 ))
        fi
    done < "$conf"

    [[ $errors -eq 0 ]]
}


_iw_validate_production_tag() {
    local label="$1" tag="$2"

    if ! _iw_validate_tag_component "$tag"; then
        echo "ERROR: ${label} must be a valid registry tag, got: '$tag'" >&2
        return 1
    fi

    if _iw_validate_local_tag "$tag"; then
        echo "ERROR: ${label} must not look like an Image-Warden staged tag: '$tag'" >&2
        return 1
    fi

    return 0
}


_iw_validate_config() {
    local errors=0
    local top_level_key bool_key bool_value

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

    if [[ -n "${PRODUCTION_TAG:-}" ]]; then
        if ! _iw_validate_production_tag "PRODUCTION_TAG" "$PRODUCTION_TAG"; then
            errors=$(( errors + 1 ))
        fi
    fi

    if [[ -n "${PLATFORM:-}" ]]; then
        if ! _iw_validate_platform "PLATFORM" "$PLATFORM"; then
            errors=$(( errors + 1 ))
        fi
    fi

    if [[ -n "${IW_RETRY_ATTEMPTS:-}" ]]; then
        if ! [[ "$IW_RETRY_ATTEMPTS" =~ ^[0-9]+$ ]] || [[ "$IW_RETRY_ATTEMPTS" -eq 0 ]]; then
            echo "ERROR: IW_RETRY_ATTEMPTS must be a positive integer, got: '$IW_RETRY_ATTEMPTS'" >&2
            errors=$(( errors + 1 ))
        fi
    fi

    if [[ -n "${IW_RETRY_DELAY_SECONDS:-}" ]]; then
        if ! [[ "$IW_RETRY_DELAY_SECONDS" =~ ^[0-9]+$ ]]; then
            echo "ERROR: IW_RETRY_DELAY_SECONDS must be a non-negative integer, got: '$IW_RETRY_DELAY_SECONDS'" >&2
            errors=$(( errors + 1 ))
        fi
    fi

    if [[ -n "${IMAGE_RELEASE_HOOK:-}" ]]; then
        if [[ "$IMAGE_RELEASE_HOOK" != /* ]]; then
            echo "ERROR: IMAGE_RELEASE_HOOK must be an absolute path, got: '$IMAGE_RELEASE_HOOK'" >&2
            errors=$(( errors + 1 ))
        elif [[ ! -f "$IMAGE_RELEASE_HOOK" || ! -x "$IMAGE_RELEASE_HOOK" ]]; then
            echo "ERROR: IMAGE_RELEASE_HOOK must be an executable regular file, got: '$IMAGE_RELEASE_HOOK'" >&2
            errors=$(( errors + 1 ))
        fi
    fi

    if [[ -n "${IMAGE_RELEASE_HOOK_TIMEOUT:-}" ]]; then
        if ! [[ "$IMAGE_RELEASE_HOOK_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$IMAGE_RELEASE_HOOK_TIMEOUT" -eq 0 ]]; then
            echo "ERROR: IMAGE_RELEASE_HOOK_TIMEOUT must be a positive integer, got: '$IMAGE_RELEASE_HOOK_TIMEOUT'" >&2
            errors=$(( errors + 1 ))
        fi
    fi

    if declare -p IMAGES &>/dev/null 2>&1; then
        if [[ ${#IMAGES[@]} -eq 0 ]]; then
            echo "ERROR: empty legacy IMAGES=() config is no longer used; remove it from ${CONF:-image-warden.conf}" >&2
        else
            echo "ERROR: legacy IMAGES=() config is no longer loaded; run 'iw-config legacy-to-dsl ${CONF:-image-warden.conf}' to convert it" >&2
        fi
        errors=$(( errors + 1 ))
    fi

    if [[ ${_IW_IMAGE_DSL_ERRORS:-0} -gt 0 ]]; then
        errors=$(( errors + _IW_IMAGE_DSL_ERRORS ))
    fi

    if [[ ${#_IW_TOP_LEVEL_IMAGE_OPTIONS[@]} -gt 0 ]]; then
        for top_level_key in "${_IW_TOP_LEVEL_IMAGE_OPTIONS[@]}"; do
            echo "ERROR: found '$top_level_key' outside image(); did an image() line miss a trailing backslash?" >&2
            errors=$(( errors + 1 ))
        done
    fi

    if [[ -n "${SCANNER_SEVERITY:-}" ]]; then
        if ! _iw_validate_severity_list "SCANNER_SEVERITY" "$SCANNER_SEVERITY"; then
            errors=$(( errors + 1 ))
        fi
    elif [[ -n "${TRIVY_SEVERITY:-}" ]]; then
        if ! _iw_validate_severity_list "TRIVY_SEVERITY" "$TRIVY_SEVERITY"; then
            errors=$(( errors + 1 ))
        fi
    fi

    for bool_key in LOCAL_REGISTRY_TLS_VERIFY ALLOW_RELEASE_WITHOUT_SCANNER NOTIFY_ONLY SCANNER_TRIVY SCANNER_GRYPE; do
        bool_value="${!bool_key:-}"
        if ! _iw_validate_bool "$bool_key" "$bool_value"; then
            errors=$(( errors + 1 ))
        fi
    done

    if ! _iw_bool_enabled "${ALLOW_RELEASE_WITHOUT_SCANNER:-false}" \
        && _iw_bool_disabled "${SCANNER_TRIVY:-true}" \
        && _iw_bool_disabled "${SCANNER_GRYPE:-false}"; then
        echo "ERROR: at least one scanner must be enabled; set ALLOW_RELEASE_WITHOUT_SCANNER=true to release without scanners" >&2
        errors=$(( errors + 1 ))
    fi

    if [[ -z "${LOCAL_REGISTRY:-}" ]]; then
        echo "ERROR: LOCAL_REGISTRY is not set" >&2
        errors=$(( errors + 1 ))
    fi

    if [[ ${#_IW_IMAGES[@]} -gt 0 ]]; then
        declare -A _seen_names=()
        local name upstream severity quarantine_hours production_tag scanners platform scanner_ignore scanner_ignore_reason trivy_ignore trivy_ignore_reason grype_ignore grype_ignore_reason

        for name in "${_IW_IMAGES[@]}"; do
            upstream="${_IW_CFG["$name.upstream"]:-}"
            severity="${_IW_CFG["$name.severity"]:-}"
            quarantine_hours="${_IW_CFG["$name.quarantine_hours"]:-}"
            production_tag="${_IW_CFG["$name.production_tag"]:-}"
            scanners="${_IW_CFG["$name.scanners"]:-}"
            platform="${_IW_CFG["$name.platform"]:-}"
            scanner_ignore="${_IW_CFG["$name.scanner_ignore"]:-}"
            scanner_ignore_reason="${_IW_CFG["$name.scanner_ignore_reason"]:-}"
            trivy_ignore="${_IW_CFG["$name.trivy_ignore"]:-}"
            trivy_ignore_reason="${_IW_CFG["$name.trivy_ignore_reason"]:-}"
            grype_ignore="${_IW_CFG["$name.grype_ignore"]:-}"
            grype_ignore_reason="${_IW_CFG["$name.grype_ignore_reason"]:-}"

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

            if ! _iw_validate_local_name "$name"; then
                echo "ERROR: image name '$name' is invalid (allowed: lowercase a-z 0-9 . _ - , must start with a-z 0-9)" >&2
                errors=$(( errors + 1 ))
            fi

            if [[ -n "${_seen_names[$name]+x}" ]]; then
                echo "ERROR: duplicate image name '$name'" >&2
                errors=$(( errors + 1 ))
            fi
            _seen_names["$name"]=1

            if [[ -n "$severity" ]] \
                && ! _iw_validate_severity_list "image '$name' severity" "$severity"; then
                errors=$(( errors + 1 ))
            fi

            if [[ -n "${_IW_CFG["$name.notify_only"]:-}" ]] \
                && ! _iw_validate_bool "image '$name' notify_only" "${_IW_CFG["$name.notify_only"]}"; then
                errors=$(( errors + 1 ))
            fi

            if [[ -n "$quarantine_hours" ]]; then
                if ! [[ "$quarantine_hours" =~ ^[0-9]+$ ]] || [[ "$quarantine_hours" -eq 0 ]]; then
                    echo "ERROR: image '$name' quarantine_hours must be a positive integer, got: '$quarantine_hours'" >&2
                    errors=$(( errors + 1 ))
                fi
            fi

            if [[ -n "$production_tag" ]]; then
                if ! _iw_validate_production_tag "image '$name' production_tag" "$production_tag"; then
                    errors=$(( errors + 1 ))
                fi
            fi

            if [[ -n "$scanners" ]] \
                && ! _iw_validate_scanner_list "image '$name' scanners" "$scanners"; then
                errors=$(( errors + 1 ))
            fi

            if [[ -n "$platform" ]] \
                && ! _iw_validate_platform "image '$name' platform" "$platform"; then
                errors=$(( errors + 1 ))
            fi

            if [[ -n "$scanner_ignore" ]] \
                && ! _iw_validate_trivy_ignore_list "image '$name' scanner_ignore" "$scanner_ignore"; then
                errors=$(( errors + 1 ))
            fi

            if [[ -z "$scanner_ignore" && -n "$scanner_ignore_reason" ]]; then
                echo "ERROR: image '$name' sets scanner_ignore_reason without scanner_ignore" >&2
                errors=$(( errors + 1 ))
            fi

            if [[ -n "$trivy_ignore" ]] \
                && ! _iw_validate_trivy_ignore_list "image '$name' trivy_ignore" "$trivy_ignore"; then
                errors=$(( errors + 1 ))
            fi

            if [[ -z "$trivy_ignore" && -n "$trivy_ignore_reason" ]]; then
                echo "ERROR: image '$name' sets trivy_ignore_reason without trivy_ignore" >&2
                errors=$(( errors + 1 ))
            fi

            if [[ -n "$grype_ignore" ]] \
                && ! _iw_validate_trivy_ignore_list "image '$name' grype_ignore" "$grype_ignore"; then
                errors=$(( errors + 1 ))
            fi

            if [[ -z "$grype_ignore" && -n "$grype_ignore_reason" ]]; then
                echo "ERROR: image '$name' sets grype_ignore_reason without grype_ignore" >&2
                errors=$(( errors + 1 ))
            fi
        done
    fi

    if [[ $errors -gt 0 ]]; then
        echo "ERROR: ${errors} config error(s) found in ${CONF:-image-warden.conf}" >&2
        return 1
    fi
}

_iw_load_config() {
    local conf="$1"
    local top_level_key source_status=0

    _iw_config_init

    unset upstream severity notify_only scanner_ignore scanner_ignore_reason trivy_ignore trivy_ignore_reason grype_ignore grype_ignore_reason quarantine_hours production_tag scanners platform

    _iw_check_config_line_continuations "$conf" || return 1

    # shellcheck source=/dev/null
    source "$conf" || source_status=$?
    if [[ $source_status -ne 0 && ${_IW_IMAGE_DSL_ERRORS:-0} -eq 0 ]]; then
        return "$source_status"
    fi

    for top_level_key in upstream severity notify_only scanner_ignore scanner_ignore_reason trivy_ignore trivy_ignore_reason grype_ignore grype_ignore_reason quarantine_hours production_tag scanners platform; do
        if [[ -v "$top_level_key" ]]; then
            _IW_TOP_LEVEL_IMAGE_OPTIONS+=("$top_level_key")
        fi
    done

    _iw_validate_config  || return 1
}

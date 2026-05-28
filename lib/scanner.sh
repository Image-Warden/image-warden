#!/usr/bin/env bash
# lib/scanner.sh: scanner abstraction
#
# Generic scanner contract:
#   _iw_scanner_scan engine image name severity ignore_list ignore_reason staged_tag
# Returns:
#   0 - clean
#   1 - findings at or above severity threshold
#   2 - scanner not installed / unavailable
#   3 - scanner/config error
# Sets:
#   _IW_SCANNER_ENGINES
#   IW_SCANNER_ENGINE
#   IW_SCANNER_FINDING_COUNT
#   IW_SCANNER_REPORT_FILE

declare -ga _IW_SCANNER_ENGINES=()

IW_SCANNER_ENGINE=""
IW_SCANNER_FINDING_COUNT=""
IW_SCANNER_REPORT_FILE=""

_iw_scanner_init() {
    local scanner_list="${1:-}"
    local scanner
    local -a scanners=()

    _IW_SCANNER_ENGINES=()

    if [[ -n "$scanner_list" ]]; then
        IFS=',' read -ra scanners <<< "${scanner_list,,}"
        for scanner in "${scanners[@]}"; do
            _IW_SCANNER_ENGINES+=("$scanner")
        done
        return 0
    fi

    if _iw_bool_enabled "${SCANNER_TRIVY:-true}"; then
        _IW_SCANNER_ENGINES+=(trivy)
    fi

    if _iw_bool_enabled "${SCANNER_GRYPE:-false}"; then
        _IW_SCANNER_ENGINES+=(grype)
    fi
}

_iw_scanner_label() {
    local engine="${1:-${IW_SCANNER_ENGINE:-${_IW_SCANNER_ENGINES[0]:-trivy}}}"

    case "$engine" in
        trivy) echo "Trivy" ;;
        grype) echo "Grype" ;;
        *)     echo "$engine" ;;
    esac
}

_iw_scanner_scan() {
    local engine="${1:-${_IW_SCANNER_ENGINES[0]:-}}"
    [[ $# -gt 0 ]] && shift

    case "$engine" in
        trivy) _iw_trivy_scan "$@" ;;
        grype) _iw_grype_scan "$@" ;;
        "")
            log "  WARNING: no scanner enabled, security scan skipped"
            return 2
            ;;
        *)
            log "  WARNING: unsupported scanner engine: $engine"
            return 2
            ;;
    esac
}

_iw_scanner_report_hash() {
    local engine="${1:-${IW_SCANNER_ENGINE:-${_IW_SCANNER_ENGINES[0]:-}}}"
    [[ $# -gt 0 ]] && shift

    case "$engine" in
        trivy) _iw_trivy_report_hash "$@" ;;
        grype) _iw_grype_report_hash "$@" ;;
        *)     return 1 ;;
    esac
}

_iw_jq_severity_filter() {
    local severity="$1"
    jq -R 'split(",") | map(ascii_upcase)' <<< "$severity"
}

_iw_trivy_report_hash() {
    local report="$1"
    local normalized hash

    normalized=$(jq -S '
      [
        .Results[]?
        | .Target as $target
        | .Vulnerabilities[]?
        | {
            target: $target,
            id: .VulnerabilityID,
            pkg: .PkgName,
            installed: .InstalledVersion,
            fixed: .FixedVersion,
            severity: .Severity
          }
      ]
    ' "$report") || return 1

    hash=$(printf '%s' "$normalized" | sha256sum | awk '{print $1}') || return 1

    [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf 'sha256:%s\n' "$hash"
}

_iw_grype_report_hash() {
    local report="$1"
    local normalized hash

    normalized=$(jq -S '
      [
        .matches[]?
        | {
            id: .vulnerability.id,
            namespace: .vulnerability.namespace,
            pkg: .artifact.name,
            installed: .artifact.version,
            type: .artifact.type,
            fixed: ((.vulnerability.fix.versions // []) | join(",")),
            severity: (.vulnerability.severity | ascii_upcase)
          }
      ]
    ' "$report") || return 1

    hash=$(printf '%s' "$normalized" | sha256sum | awk '{print $1}') || return 1

    [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf 'sha256:%s\n' "$hash"
}

_iw_grype_scan() {
    local image="$1"
    local name="$2"
    local severity="${3:-${SCANNER_SEVERITY:-${TRIVY_SEVERITY:-CRITICAL,HIGH}}}"
    local ignore_list="${4:-}"
    local ignore_reason="${5:-}"
    local staged_tag="${6:-untagged}"
    severity="${severity^^}"

    IW_SCANNER_ENGINE="grype"
    IW_SCANNER_FINDING_COUNT=""
    IW_SCANNER_REPORT_FILE=""

    if ! command -v grype &>/dev/null; then
        log "  WARNING: grype not installed, security scan skipped"
        return 2
    fi

    local report_dir="${SCANNER_REPORT_DIR:-${TRIVY_REPORT_DIR:-}}"
    if [[ -z "$report_dir" ]]; then
        log "  ERROR: scanner report directory not configured"
        return 3
    fi
    mkdir -p "$report_dir"

    local report_file
    report_file="${report_dir}/${name}_${staged_tag}_grype_$(date '+%Y%m%d_%H%M%S').json"

    log "  Grype scan: checking severity >= ${severity} ..."

    local config_file=""
    local -a config_args=()
    local -a _ignore_ids=()
    if [[ -n "$ignore_list" ]]; then
        _iw_validate_trivy_ignore_list "image '$name' grype_ignore" "$ignore_list" || return 3

        config_file=$(mktemp "${report_dir}/${name}_grype_XXXXXX.yaml")
        {
            printf 'ignore:\n'
            IFS=',' read -ra _ignore_ids <<< "$ignore_list"
            for id in "${_ignore_ids[@]}"; do
                printf '  - vulnerability: "%s"\n' "$id"
            done
        } > "$config_file"
        config_args=(--config "$config_file")

        log "  Grype scan: using ${#_ignore_ids[@]} per-image ignore(s)"
        [[ -n "$ignore_reason" ]] && log "  Grype ignore reason: ${ignore_reason}"
    fi

    local insecure_skip_tls="false"
    local insecure_use_http="false"
    if ! _iw_bool_enabled "${LOCAL_REGISTRY_TLS_VERIFY:-false}"; then
        insecure_skip_tls="true"
        insecure_use_http="true"
    fi

    if ! GRYPE_REGISTRY_INSECURE_SKIP_TLS_VERIFY="$insecure_skip_tls" \
        GRYPE_REGISTRY_INSECURE_USE_HTTP="$insecure_use_http" \
        grype "registry:${image}" \
        "${config_args[@]}" \
        --only-fixed \
        -o json \
        -q \
        > "$report_file" 2>/dev/null; then
        log "  ERROR: Grype scan failed"
        [[ -n "$config_file" ]] && rm -f "$config_file"
        rm -f "$report_file"
        return 3
    fi

    [[ -n "$config_file" ]] && rm -f "$config_file"

    local severity_json
    severity_json=$(_iw_jq_severity_filter "$severity") || return 3

    IW_SCANNER_FINDING_COUNT=$(jq --argjson sevs "$severity_json" '
        [.matches[]? | select((.vulnerability.severity | ascii_upcase) as $sev | $sevs | index($sev))]
        | length
    ' "$report_file" 2>/dev/null) || {
        log "  ERROR: could not parse Grype report"
        return 3
    }

    if [[ "$IW_SCANNER_FINDING_COUNT" -gt 0 ]]; then
        IW_SCANNER_REPORT_FILE="$report_file"
        log "  Grype scan: ${IW_SCANNER_FINDING_COUNT} finding(s) at severity ${severity}"
        log "  Report: $IW_SCANNER_REPORT_FILE"
        return 1
    fi

    log "  Grype scan: clean"
    rm -f "$report_file"
    return 0
}

_iw_trivy_scan() {
    local image="$1"
    local name="$2"
    local severity="${3:-${SCANNER_SEVERITY:-${TRIVY_SEVERITY:-CRITICAL,HIGH}}}"
    local ignore_list="${4:-}"
    local ignore_reason="${5:-}"
    local staged_tag="${6:-untagged}"
    severity="${severity^^}"

    IW_SCANNER_ENGINE="trivy"
    IW_SCANNER_FINDING_COUNT=""
    IW_SCANNER_REPORT_FILE=""

    if ! command -v trivy &>/dev/null; then
        log "  WARNING: trivy not installed, security scan skipped"
        return 2
    fi

    local report_dir="${SCANNER_REPORT_DIR:-${TRIVY_REPORT_DIR:-}}"
    if [[ -z "$report_dir" ]]; then
        log "  ERROR: scanner report directory not configured"
        return 3
    fi
    mkdir -p "$report_dir"

    local report_file
    report_file="${report_dir}/${name}_${staged_tag}_trivy_$(date '+%Y%m%d_%H%M%S').json"

    log "  Trivy scan: checking severity >= ${severity} ..."

    local ignore_file=""
    local -a ignore_args=()
    local -a _ignore_ids=()
    if [[ -n "$ignore_list" ]]; then
        _iw_validate_trivy_ignore_list "image '$name' trivy_ignore" "$ignore_list" || return 3

        ignore_file=$(mktemp "${report_dir}/${name}_trivyignore_XXXXXX")
        IFS=',' read -ra _ignore_ids <<< "$ignore_list"
        printf '%s\n' "${_ignore_ids[@]}" > "$ignore_file"
        ignore_args=(--ignorefile "$ignore_file")

        log "  Trivy scan: using ${#_ignore_ids[@]} per-image ignore(s)"
        [[ -n "$ignore_reason" ]] && log "  Trivy ignore reason: ${ignore_reason}"
    fi

    # TRIVY_INSECURE mirrors LOCAL_REGISTRY_TLS_VERIFY
    local insecure="false"
    if ! _iw_bool_enabled "${LOCAL_REGISTRY_TLS_VERIFY:-false}"; then
        insecure="true"
    fi

    if TRIVY_INSECURE="$insecure" trivy image \
        "${ignore_args[@]}" \
        --severity "$severity" \
        --exit-code 1 \
        --format json \
        --output "$report_file" \
        --quiet \
        "$image" 2>/dev/null; then
        log "  Trivy scan: clean"
        rm -f "$report_file"
        [[ -n "$ignore_file" ]] && rm -f "$ignore_file"
        return 0
    else
        IW_SCANNER_REPORT_FILE="$report_file"
        if [[ ! -s "$report_file" ]]; then
            log "  ERROR: Trivy scan failed without producing a report"
            [[ -n "$ignore_file" ]] && rm -f "$ignore_file"
            rm -f "$report_file"
            return 3
        fi

        if ! IW_SCANNER_FINDING_COUNT=$(jq '[.Results[]?.Vulnerabilities // [] | .[]] | length' "$report_file" 2>/dev/null); then
            log "  ERROR: could not parse Trivy report"
            [[ -n "$ignore_file" ]] && rm -f "$ignore_file"
            return 3
        fi

        log "  Trivy scan: ${IW_SCANNER_FINDING_COUNT} finding(s) at severity >= ${severity}"
        log "  Report: $IW_SCANNER_REPORT_FILE"
        [[ -n "$ignore_file" ]] && rm -f "$ignore_file"
        return 1
    fi
}

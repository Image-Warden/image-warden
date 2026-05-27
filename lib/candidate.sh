#!/usr/bin/env bash
# lib/candidate.sh: candidate queue management
#
# State layout:
#   $STATE_DIR/candidates/<local_name>/<digest-hex>.json
#
# Each candidate JSON contains:
#   local_name, upstream, tag, digest, staged_at, quarantine_hours_at_stage,
#   quarantine_acceleration_notified, scanner_blocked_report_hashes
#
# Requires: jq >= 1.6

_iw_check_jq() {
    command -v jq &>/dev/null || { echo "ERROR: jq is required" >&2; exit 1; }
    jq -e -n --arg foo bar '$ARGS.named.foo == "bar"' >/dev/null 2>&1 || {
        echo "ERROR: jq >= 1.6 required (\$ARGS.named support)" >&2; exit 1
    }
}
_iw_check_jq

_iw_candidates_dir() {
    echo "${STATE_DIR}/candidates"
}

_iw_candidate_dir_for() {
    local name="$1"
    echo "${STATE_DIR}/candidates/${name}"
}

_iw_candidate_file() {
    local name="$1" digest="$2"
    local hex="${digest#sha256:}"
    echo "${STATE_DIR}/candidates/${name}/${hex}.json"
}

_iw_candidate_write() {
    local name="$1" upstream="$2" tag="$3" digest="$4" staged_at="$5" quarantine_hours_at_stage="$6"

    _iw_validate_local_name "$name" || { echo "ERROR: invalid local_name: $name" >&2; return 1; }
    _iw_validate_local_tag "$tag" || { echo "ERROR: invalid tag: $tag" >&2; return 1; }
    _iw_validate_digest "$digest" || { echo "ERROR: invalid digest: $digest" >&2; return 1; }
    [[ "$staged_at" =~ ^[0-9]+$ ]] || { echo "ERROR: invalid staged_at: $staged_at" >&2; return 1; }
    [[ "$quarantine_hours_at_stage" =~ ^[0-9]+$ && "$quarantine_hours_at_stage" -gt 0 ]] \
        || { echo "ERROR: invalid quarantine_hours_at_stage: $quarantine_hours_at_stage" >&2; return 1; }

    local dir file
    dir="$(_iw_candidate_dir_for "$name")"
    file="$(_iw_candidate_file "$name" "$digest")"

    mkdir -p "$dir"

    jq -n \
        --arg local_name "$name" \
        --arg upstream "$upstream" \
        --arg tag "$tag" \
        --arg digest "$digest" \
        --argjson staged_at "$staged_at" \
        --argjson quarantine_hours_at_stage "$quarantine_hours_at_stage" \
        '$ARGS.named' \
        > "$file"
}

_iw_candidate_mark_quarantine_acceleration_notified() {
    local name="$1" digest="$2"
    local file tmp

    file="$(_iw_candidate_file "$name" "$digest")"
    [[ -f "$file" ]] || return 1

    tmp="${file}.tmp.$$"
    if jq '.quarantine_acceleration_notified = true' "$file" > "$tmp" \
        && mv "$tmp" "$file"; then
        return 0
    fi

    rm -f "$tmp"
    return 1
}

_iw_candidate_get_scanner_report_hash() {
    local file="$1" scanner="$2"
    local hash

    [[ -f "$file" ]] || return 1
    _iw_validate_scanner_list "scanner" "$scanner" || return 1

    hash=$(jq -r --arg scanner "$scanner" '
        .scanner_blocked_report_hashes[$scanner]
        // if $scanner == "trivy" then (.trivy_blocked_report_hash // empty) else empty end
    ' "$file") || return 1

    [[ -z "$hash" || "$hash" =~ ^sha256:[0-9a-f]{64}$ ]] || return 1
    printf '%s\n' "$hash"
}

_iw_candidate_set_scanner_report_hash() {
    local name="$1" digest="$2" scanner="$3" value="$4"
    local file tmp

    _iw_validate_scanner_list "scanner" "$scanner" || return 1
    [[ "$value" =~ ^sha256:[0-9a-f]{64}$ ]] || return 1

    file="$(_iw_candidate_file "$name" "$digest")"
    [[ -f "$file" ]] || return 1

    tmp="${file}.tmp.$$"
    if jq \
        --arg scanner "$scanner" \
        --arg value "$value" \
        '.scanner_blocked_report_hashes = (.scanner_blocked_report_hashes // {})
         | .scanner_blocked_report_hashes[$scanner] = $value
         | del(.trivy_blocked_report_hash)' \
        "$file" > "$tmp" \
        && mv "$tmp" "$file"; then
        return 0
    fi

    rm -f "$tmp"
    return 1
}

_iw_candidate_read() {
    local file="$1"
    local tag digest staged_at quarantine_hours_at_stage quarantine_acceleration_notified
    declare -g _CAND_TAG=""
    declare -g _CAND_DIGEST=""
    declare -g _CAND_STAGED_AT=""
    declare -g _CAND_QUARANTINE_HOURS_AT_STAGE=""
    declare -g _CAND_QUARANTINE_ACCELERATION_NOTIFIED="false"

    [[ -f "$file" ]] || return 1

    local _json
    _json=$(< "$file")

    tag=$(printf '%s' "$_json" | jq -r '.tag // empty')
    digest=$(printf '%s' "$_json" | jq -r '.digest // empty')
    staged_at=$(printf '%s' "$_json" | jq -r '.staged_at // empty')
    quarantine_hours_at_stage=$(printf '%s' "$_json" | jq -r '.quarantine_hours_at_stage // empty')
    quarantine_acceleration_notified=$(printf '%s' "$_json" | jq -r '.quarantine_acceleration_notified // false')

    _iw_validate_local_tag "$tag" || return 1
    _iw_validate_digest "$digest" || return 1
    [[ "$staged_at" =~ ^[0-9]+$ ]] || return 1
    if [[ -n "$quarantine_hours_at_stage" ]]; then
        [[ "$quarantine_hours_at_stage" =~ ^[0-9]+$ && "$quarantine_hours_at_stage" -gt 0 ]] || return 1
    fi
    [[ "$quarantine_acceleration_notified" == "true" || "$quarantine_acceleration_notified" == "false" ]] || return 1
    printf '%s' "$_json" | jq -e '
        (.scanner_blocked_report_hashes // {}) as $hashes
        | ($hashes | type == "object")
        and all($hashes | keys[]; test("^[a-z][a-z0-9_.-]*$"))
        and all($hashes[]; test("^sha256:[0-9a-f]{64}$"))
        and ((.trivy_blocked_report_hash // "") | test("^(|sha256:[0-9a-f]{64})$"))
    ' >/dev/null || return 1

    _CAND_TAG="$tag"
    _CAND_DIGEST="$digest"
    _CAND_STAGED_AT="$staged_at"
    _CAND_QUARANTINE_HOURS_AT_STAGE="$quarantine_hours_at_stage"
    _CAND_QUARANTINE_ACCELERATION_NOTIFIED="$quarantine_acceleration_notified"
    # _CAND_UPSTREAM=$(printf '%s' "$_json" | jq -r '.upstream // empty')
    # _CAND_FILE="$file"
}

_iw_candidate_list() {
    local name="$1"
    local dir
    dir="$(_iw_candidate_dir_for "$name")"

    declare -ga _CAND_LIST=()
    [[ -d "$dir" ]] || return 0

    local files=()
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "$dir" -maxdepth 1 -name '*.json' -print0 2>/dev/null)

    [[ ${#files[@]} -eq 0 ]] && return 0

    local staged_at file
    local -a entries=()
    for file in "${files[@]}"; do
        staged_at=$(jq -r '.staged_at // "0"' "$file" 2>/dev/null) || continue
        [[ "$staged_at" =~ ^[0-9]+$ ]] || continue
        entries+=("${staged_at}|${file}")
    done

    # Sort newest-first (descending staged_at)
    mapfile -t _CAND_LIST < <(printf '%s\n' "${entries[@]}" | sort -t'|' -k1 -nr)
}

_iw_candidate_exists() {
    local name="$1" digest="$2"
    local file
    file="$(_iw_candidate_file "$name" "$digest")"
    [[ -f "$file" ]]
}

_iw_candidate_remove() {
    local name="$1" digest="$2"
    local file
    file="$(_iw_candidate_file "$name" "$digest")"
    rm -f "$file"
}

_iw_candidate_remove_older() {
    local name="$1" than_staged_at="$2"

    _iw_candidate_list "$name"
    [[ ${#_CAND_LIST[@]} -eq 0 ]] && return 0

    local entry staged_at file
    for entry in "${_CAND_LIST[@]}"; do
        staged_at="${entry%%|*}"
        file="${entry#*|}"
        if [[ $staged_at -lt $than_staged_at ]]; then
            rm -f "$file"
        fi
    done
}

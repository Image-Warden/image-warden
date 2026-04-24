#!/usr/bin/env bash
# lib/notify.sh: notification dispatch for image-warden
#
# Sourced by bin scripts; not executed directly.
#
# Configure backends in ~/.config/image-warden/secrets:
#
#   NOTIFY_BACKENDS=(discord)     # one or more: discord slack teams telegram ntfy
#
#   DISCORD_WEBHOOK_URL=""
#
#   SLACK_WEBHOOK_URL=""          # Slack incoming webhook URL
#
#   TEAMS_WEBHOOK_URL=""          # Teams incoming webhook connector URL
#
#   TELEGRAM_BOT_TOKEN=""         # from @BotFather
#   TELEGRAM_CHAT_ID=""           # channel/group/user ID
#
#   NTFY_URL=""                   # e.g. https://ntfy.sh/mytopic
#   NTFY_TOKEN=""                 # Bearer token (leave empty for public topics)
#
# Public functions (called by bin scripts):
#   notify_staged   name upstream digest quarantine_hours
#   notify_released name staged_tag digest
#   notify_blocked  name staged_tag vuln_count severity report_file
#   notify_ready    name digest
#   notify_vuln     name vuln_id score description


# ── Internal: colour/priority mapping ───────────────────────────────────────

_iw_discord_color() {
    case "$1" in
        info)    echo 3447003   ;;  # blue
        success) echo 3066993   ;;  # green
        error)   echo 15158332  ;;  # red
        *)       echo 8421504   ;;  # grey
    esac
}

_iw_slack_color() {
    case "$1" in
        info)    echo "#2196F3" ;;
        success) echo "#4CAF50" ;;
        error)   echo "#F44336" ;;
        *)       echo "#9E9E9E" ;;
    esac
}

_iw_teams_color() {
    case "$1" in
        info)    echo "2196F3" ;;
        success) echo "4CAF50" ;;
        error)   echo "F44336" ;;
        *)       echo "9E9E9E" ;;
    esac
}

_iw_ntfy_priority() {
    case "$1" in
        error) echo "high"    ;;
        *)     echo "default" ;;
    esac
}

_iw_ntfy_tags() {
    case "$2" in
        staged)   echo "package"          ;;
        released) echo "white_check_mark" ;;
        blocked)  echo "no_entry"         ;;
        ready)    echo "rocket"           ;;
        vuln)     echo "rotating_light"   ;;
        *)        echo "bell"             ;;
    esac
}

# ── Internal: curl wrapper ───────────────────────────────────────────────────
# Set IW_NOTIFY_DEBUG=1 to surface HTTP status and error responses.
# Normal mode: fully silent, never fatal.
_iw_curl() {
    if [[ "${IW_NOTIFY_DEBUG:-0}" == "1" ]]; then
        local out http_code body
        out=$(curl -s -w '\n<<<HTTP:%{http_code}>>>' "$@" 2>&1) || true
        http_code=$(printf '%s' "$out" | grep -o '<<<HTTP:[0-9]*>>>' | grep -o '[0-9]*')
        body=$(printf '%s' "$out" | sed 's/<<<HTTP:[0-9]*>>>//')
        if [[ "$http_code" =~ ^2 ]]; then
            echo "    HTTP ${http_code} OK" >&2
        else
            echo "    HTTP ${http_code} FAILED" >&2
            [[ -n "${body// }" ]] && echo "    Response: ${body}" >&2
        fi
    else
        curl -sf "$@" >/dev/null 2>&1 || true
    fi
}

# ── Internal: per-backend send functions ────────────────────────────────────

# _send_discord color_type title body
_send_discord() {
    [[ -z "${DISCORD_WEBHOOK_URL:-}" ]] && return 0

    local color
    color=$(_iw_discord_color "$1")

    local payload
    payload=$(jq -n \
        --arg title "$2" \
        --arg desc  "$3" \
        --argjson color "$color" \
        '{embeds:[{title:$title, description:$desc, color:$color,
           timestamp:(now|strftime("%Y-%m-%dT%H:%M:%SZ"))}]}')

    _iw_curl -X POST "$DISCORD_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$payload"
}

# _send_slack color_type title body
_send_slack() {
    [[ -z "${SLACK_WEBHOOK_URL:-}" ]] && return 0

    local color
    color=$(_iw_slack_color "$1")

    local payload
    payload=$(jq -n \
        --arg title "$2" \
        --arg body  "$3" \
        --arg color "$color" \
        '{attachments:[{color:$color, title:$title, text:$body,
           ts:(now|floor)}]}')

    _iw_curl -X POST "$SLACK_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$payload"
}

# _send_teams color_type title body
_send_teams() {
    [[ -z "${TEAMS_WEBHOOK_URL:-}" ]] && return 0

    local color
    color=$(_iw_teams_color "$1")

    local payload
    payload=$(jq -n \
        --arg title "$2" \
        --arg body  "$3" \
        --arg color "$color" \
        '{"@type":"MessageCard","@context":"https://schema.org/extensions",
          "themeColor":$color,"summary":$title,
          "sections":[{"activityTitle":$title,"activityText":$body}]}')

    _iw_curl -X POST "$TEAMS_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$payload"
}

# _send_telegram color_type title body
_send_telegram() {
    [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]] && return 0

    # Telegram HTML: bold title, monospace code blocks for technical values
    local text
    text="<b>${2}</b>
${3}"

    _iw_curl -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg chat_id "$TELEGRAM_CHAT_ID" \
            --arg text    "$text" \
            '{chat_id:$chat_id, text:$text, parse_mode:"HTML"}')"
}

# _send_ntfy color_type title body event_hint
_send_ntfy() {
    [[ -z "${NTFY_URL:-}" ]] && return 0

    local priority tags
    priority=$(_iw_ntfy_priority "$1")
    tags=$(_iw_ntfy_tags "$1" "$4")

    local -a auth_header=()
    [[ -n "${NTFY_TOKEN:-}" ]] && auth_header=(-H "Authorization: Bearer ${NTFY_TOKEN}")

    _iw_curl -X POST "$NTFY_URL" \
        "${auth_header[@]}" \
        -H "Title: $2" \
        -H "Priority: $priority" \
        -H "Tags: $tags" \
        -d "$3"
}

# ── Internal: dispatch to all configured backends ───────────────────────────

# _notify_dispatch color_type event_hint title body
_notify_dispatch() {
    local color_type="$1"
    local event_hint="$2"
    local title="$3"
    local body="$4"

    local backend
    for backend in "${NOTIFY_BACKENDS[@]:-}"; do
        [[ "${IW_NOTIFY_DEBUG:-0}" == "1" ]] && echo "  [${backend}]" >&2
        case "$backend" in
            discord)  _send_discord  "$color_type" "$title" "$body" ;;
            slack)    _send_slack    "$color_type" "$title" "$body" ;;
            teams)    _send_teams    "$color_type" "$title" "$body" ;;
            telegram) _send_telegram "$color_type" "$title" "$body" ;;
            ntfy)     _send_ntfy    "$color_type" "$title" "$body" "$event_hint" ;;
            "")       ;;  # NOTIFY_BACKENDS unset → silent
            *)        echo "[image-warden] notify: unknown backend '${backend}'" >&2 ;;
        esac
    done
}

# ── Public API ───────────────────────────────────────────────────────────────

# notify_staged name upstream local_tag digest quarantine_hours
notify_staged() {
    local name="$1" upstream="$2" local_tag="$3" digest="$4" hours="$5"

    local release_date
    release_date=$(date -d "+${hours} hours" '+%Y-%m-%d %H:%M' 2>/dev/null \
        || date -v "+${hours}H" '+%Y-%m-%d %H:%M' 2>/dev/null \
        || echo "in ${hours}h")

    local body
    body="Upstream: ${upstream}
Local tag: ${name}:${local_tag}
Digest: ${digest:0:19}...
Quarantine: ${hours}h
Earliest release: ${release_date}"

    _notify_dispatch "info" "staged" "Staged: ${name}" "$body"
}

# notify_released name staged_tag digest
notify_released() {
    local name="$1" staged_tag="$2" digest="$3"

    local body
    body="Tag: ${name}:${staged_tag} → :production
Digest: ${digest:0:19}...

podman auto-update will restart the container."

    _notify_dispatch "success" "released" "Released: ${name}" "$body"
}

# notify_ready name staged_tag digest
notify_ready() {
    local name="$1" staged_tag="$2" digest="$3"

    local body
    body="Tag: ${name}:${staged_tag}
Digest: ${digest:0:19}...

Passed quarantine and Trivy gate. To promote:
  iw-release --force-release ${name}"

    _notify_dispatch "info" "ready" "Ready to release: ${name}" "$body"
}

# notify_blocked name staged_tag vuln_count severity report_file
notify_blocked() {
    local name="$1" staged_tag="$2" count="$3" severity="$4" report="$5"

    local body
    body="Tag: ${name}:${staged_tag}
Vulnerabilities: ${count} (severity >= ${severity})
Report: ${report}

Image will NOT be promoted to :production."

    _notify_dispatch "error" "blocked" "Blocked: ${name}:${staged_tag}" "$body"
}

# notify_vuln name vuln_id score description
notify_vuln() {
    local name="$1" vuln_id="$2" score="$3" description="$4"

    local body
    body="ID: ${vuln_id}
Score: ${score}
${description}"

    _notify_dispatch "error" "vuln" "New CVE for ${name}: ${vuln_id}" "$body"
}

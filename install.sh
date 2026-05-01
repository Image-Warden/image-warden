#!/usr/bin/env bash
# install.sh: install or update image-warden
#
# Usage:
#   bash install.sh              Install or update
#   bash install.sh --uninstall  Remove all installed files
#
# Installs to XDG Base Directory locations:
#   Scripts + lib  ${XDG_DATA_HOME:-~/.local/share}/image-warden/
#   Symlinks       ~/.local/bin/
#   Config         ${XDG_CONFIG_HOME:-~/.config}/image-warden/   (not overwritten if exists)
#   Systemd units  ${XDG_CONFIG_HOME:-~/.config}/systemd/user/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -- target paths -------------------------------------------------------------
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/image-warden"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/image-warden"
BIN_LINK_DIR="$HOME/.local/bin"
SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

# -- double rainbow colors  ---------------------------------------------------
_green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
_yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
_red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }
_bold()   { printf '\033[1m%s\033[0m\n'   "$*"; }

ok()   { _green  "  [ok] $*"; }
skip() { _yellow "  [--] $*"; }
warn() { _yellow "  [!!] $*"; }
fail() { _red    "  [!!] $*"; }
info() { printf  "       %s\n" "$*"; }

# -- uninstall -----------------------------------------------------------------
uninstall() {
    _bold "Removing image-warden ..."

    # Disable and remove systemd units
    local units=(iw-stage iw-release iw-cleanup iw-vuln-scan)
    for unit in "${units[@]}"; do
        systemctl --user disable --now "${unit}.timer" 2>/dev/null && \
            ok "Disabled ${unit}.timer" || true
        rm -f "${SYSTEMD_DIR}/${unit}.service" \
               "${SYSTEMD_DIR}/${unit}.timer"
    done
    systemctl --user daemon-reload 2>/dev/null || true

    # Remove symlinks
    for script in "${SCRIPT_DIR}"/bin/iw-*; do
        local name
        name=$(basename "$script")
        rm -f "${BIN_LINK_DIR}/${name}"
    done
    ok "Symlinks removed from ${BIN_LINK_DIR}"

    # Remove data directory (scripts + lib)
    rm -rf "$DATA_DIR"
    ok "Removed ${DATA_DIR}"

    warn "Config preserved at ${CONFIG_DIR}"
    info "Remove manually if no longer needed: rm -rf ${CONFIG_DIR}"

    warn "State and cache preserved"
    info "  State : ${XDG_STATE_HOME:-$HOME/.local/state}/image-warden"
    info "  Cache : ${XDG_CACHE_HOME:-$HOME/.cache}/image-warden"
    info "Remove manually if no longer needed."

    _green "\nimage-warden uninstalled."
}

if [[ "${1:-}" == "--uninstall" ]]; then
    uninstall
    exit 0
fi

# -- dependency check ----------------------------------------------------------
_bold "Checking dependencies ..."

missing=0
for cmd in skopeo jq curl flock; do
    if command -v "$cmd" &>/dev/null; then
        ok "$cmd"
    else
        fail "$cmd  (required but not found)"
        missing=$(( missing + 1 ))
    fi
done

# Detect container runtime (podman preferred, docker fallback)
DETECTED_RUNTIME=""
if command -v podman &>/dev/null; then
    ok "podman  (container runtime)"
    DETECTED_RUNTIME="podman"
elif command -v docker &>/dev/null; then
    ok "docker  (container runtime)"
    DETECTED_RUNTIME="docker"
else
    fail "podman or docker  (one required but neither found)"
    missing=$(( missing + 1 ))
fi

if command -v trivy &>/dev/null; then
    ok "trivy found"
else
    skip "trivy not found. Images will not be promoted without security scan unless ALLOW_RELEASE_WITHOUT_SCANNER=1 is set."
fi

if [[ $missing -gt 0 ]]; then
    echo ""
    _red "Install missing dependencies before proceeding."
    info "Refer to README.md for more information."
    exit 1
fi

# -- PATH check ----------------------------------------------------------------
if [[ ":${PATH}:" != *":${BIN_LINK_DIR}:"* ]]; then
    warn "${BIN_LINK_DIR} is not in your PATH"
    info "Add to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
    info "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# -- Create directories --------------------------------------------------------
_bold "\nCreating directories ..."
mkdir -p \
    "${DATA_DIR}/bin" \
    "${DATA_DIR}/lib" \
    "${CONFIG_DIR}" \
    "${BIN_LINK_DIR}" \
    "${SYSTEMD_DIR}"
ok "Directories ready"

# -- Install scripts -----------------------------------------------------------
_bold "\nInstalling scripts ..."
for script in "${SCRIPT_DIR}"/bin/iw-*; do
    name=$(basename "$script")
    install -m 0755 "$script" "${DATA_DIR}/bin/${name}"
    ok "Installed ${DATA_DIR}/bin/${name}"
done

# -- Install library -----------------------------------------------------------
_bold "\nInstalling library ..."
install -m 0644 "${SCRIPT_DIR}/lib/validate.sh" "${DATA_DIR}/lib/validate.sh"
ok "Installed ${DATA_DIR}/lib/validate.sh"
install -m 0644 "${SCRIPT_DIR}/lib/notify.sh" "${DATA_DIR}/lib/notify.sh"
ok "Installed ${DATA_DIR}/lib/notify.sh"

# -- Create symlinks in ~/.local/bin -------------------------------------------
_bold "\nCreating symlinks in ${BIN_LINK_DIR} ..."
for script in "${DATA_DIR}"/bin/iw-*; do
    name=$(basename "$script")
    ln -sf "$script" "${BIN_LINK_DIR}/${name}"
    ok "${BIN_LINK_DIR}/${name} → ${script}"
done

# -- Install config (skip if already exists) -----------------------------------
_bold "\nInstalling config ..."

conf_target="${CONFIG_DIR}/image-warden.conf"
if [[ -f "$conf_target" ]]; then
    skip "Config already exists: ${conf_target}"
else
    install -m 0644 "${SCRIPT_DIR}/config/image-warden.conf.example" "$conf_target"
    # Patch CONTAINER_RUNTIME to match detected runtime
    if [[ -n "$DETECTED_RUNTIME" && "$DETECTED_RUNTIME" != "podman" ]]; then
        sed -i "s/^CONTAINER_RUNTIME=.*/CONTAINER_RUNTIME=\"${DETECTED_RUNTIME}\"/" "$conf_target"
    fi
    ok "Config installed: ${conf_target} (runtime: ${DETECTED_RUNTIME:-podman})"
fi

secrets_target="${CONFIG_DIR}/secrets"
if [[ -f "$secrets_target" ]]; then
    skip "Secrets file already exists: ${secrets_target}"
else
    install -m 0600 "${SCRIPT_DIR}/config/secrets.example" "$secrets_target"
    ok "Secrets file installed: ${secrets_target}"
    warn "Edit secrets file and set your notification backend:"
    info "  ${secrets_target}"
fi

# -- Install systemd user units ------------------------------------------------
#_bold "\nInstalling systemd units ..."
# for unit in iw-stage iw-release iw-cleanup; do
#    for ext in service timer; do
#        src="${SCRIPT_DIR}/systemd/${unit}.${ext}"
#        [[ -f "$src" ]] || continue
#        install -m 0644 "$src" "${SYSTEMD_DIR}/${unit}.${ext}"
#        ok "Installed ${SYSTEMD_DIR}/${unit}.${ext}"
#    done
# done
#
# systemctl --user daemon-reload
# ok "systemd user daemon reloaded"

# -- Quadlet: staging registry (manual step) -----------------------------------
_bold "\nStaging registry (manual step required) ..."
warn "Local staging-registry.container is NOT installed automatically"
info "It requires volume paths specific to your system."
info ""
info "  1. Edit the Quadlet template:"
info "       ${SCRIPT_DIR}/systemd/staging-registry.container"
info "  2. Set the Volume= paths for registry data and config.yml"
info "  3. Copy it to:"
info "       ${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd/staging-registry.container"
info "  4. Reload and start:"
info "       systemctl --user daemon-reload"
info "       systemctl --user enable --now staging-registry.service"

# -- Post-install summary ------------------------------------------------------
_green "image-warden installed successfully."

echo ""
_bold "Next steps:"
info ""
info "1. Add your images to:"
info "     ${conf_target}"
info ""
info "2. Configure notifications in:"
info "     ${secrets_target}"
info ""
info "3. Set up the staging registry (see README.md)."
info ""
# Skip for now, not everyone uses systemd timers
#info "4. Enable timers (optional):"
#info "     systemctl --user enable --now iw-stage.timer"
#info "     systemctl --user enable --now iw-release.timer"
#info "     systemctl --user enable --now iw-cleanup.timer"
#info ""
info "4. Run the first stage manually to verify:"
info "     iw-stage"

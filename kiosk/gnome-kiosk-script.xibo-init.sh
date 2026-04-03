#!/bin/bash
# Xibo First-Boot Setup
# ======================
# Runs xiboplayer-setup (player selection).
# Then hands off to the session holder.
#
# gnome-initial-setup is skipped — locale/timezone/keyboard are set
# by the image defaults or by Ansible provisioning.

XIBO_KIOSK_DIR="${XIBO_KIOSK_DIR:-/usr/share/xiboplayer-kiosk}"
XIBO_DATA_DIR="${XIBO_DATA_DIR:-${HOME}/.local/share/xibo}"
LOGFILE="/tmp/xibo-init.log"
NOTIFY_ID=1

# Log everything
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== xibo-init started at $(date -Iseconds) ==="

# Start dunst for notifications
dunst -conf "${XIBO_KIOSK_DIR}/dunstrc" &

# Wait for Wayland compositor
sleep 2

# Import display environment into systemd user manager
systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_RUNTIME_DIR

# Disable donation popup
gsettings set org.gnome.desktop.interface show-donation-popup false 2>/dev/null || true

# Skip gnome-initial-setup — mark as done so it never runs
mkdir -p "${HOME}/.config"
touch "${HOME}/.config/gnome-initial-setup-done"

# ── Player setup ─────────────────────────────────────────────────────────────
echo "[Setup] Checking setup-result.json..."
if [ ! -f "${XIBO_DATA_DIR}/setup-result.json" ]; then
    mkdir -p "${XIBO_DATA_DIR}"
    echo "[Setup] Launching player setup wizard..."

    # Try libadwaita wizard
    if [ -f "${XIBO_KIOSK_DIR}/xiboplayer-setup.py" ] && \
       python3 "${XIBO_KIOSK_DIR}/xiboplayer-setup.py" 2>&1; then
        echo "[Setup] Wizard completed."
    else
        echo "[Setup] Wizard failed (exit $?). Using zenity fallback..."

        PLAYER=$(zenity --list --title="Xibo Player Setup" \
            --text="Select a player:" \
            --column="Player" --column="Description" \
            "xiboplayer-electron" "Electron (recommended)" \
            "xiboplayer-chromium" "Chromium (lightweight)" \
            "arexibo" "arexibo (native Rust)" \
            --width=400 --height=300 2>&1)

        [ -z "$PLAYER" ] && PLAYER="xiboplayer-electron"

        case "$PLAYER" in
            xiboplayer-chromium) SERVICE="xiboplayer-chromium.service" ;;
            arexibo) SERVICE="arexibo.service" ;;
            *) PLAYER="xiboplayer-electron"; SERVICE="xiboplayer-electron.service" ;;
        esac

        doas alternatives --set xiboplayer "/usr/bin/${PLAYER}" 2>/dev/null || true

        cat > "${XIBO_DATA_DIR}/setup-result.json" << EOF
{"player": "${PLAYER}", "service": "${SERVICE}"}
EOF
        echo "[Setup] Selected: $PLAYER ($SERVICE)"
    fi
fi

# ── Hand off to session holder ───────────────────────────────────────────────
echo "[Setup] Starting session holder..."
sleep 2
pkill -u "$(whoami)" dunst 2>/dev/null || true
exec "${XIBO_KIOSK_DIR}/gnome-kiosk-script.xibo.sh"

#!/bin/bash
# Xibo Kiosk Init (legacy fallback)
# ==================================
# This script is kept for backward compatibility and edge cases where
# the first-boot wizard (xiboplayer-setup.py) did not run in GNOME.
# The normal flow is: GNOME session → wizard autostart → kiosk forever.
# This only runs if the dispatcher is somehow reached without setup.

XIBO_KIOSK_DIR="${XIBO_KIOSK_DIR:-/usr/share/xiboplayer-kiosk}"
XIBO_CONFIG_DIR="${HOME}/.config/xiboplayer"
XIBO_DATA_DIR="${HOME}/.local/share/xibo"
LOGFILE="/tmp/xibo-init.log"

exec > >(tee -a "$LOGFILE") 2>&1
echo "=== xibo-init fallback started at $(date -Iseconds) ==="

# Start dunst for notifications
dunst -conf "${XIBO_KIOSK_DIR}/dunstrc" &
sleep 2

# Import display environment into systemd user manager
systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_RUNTIME_DIR

# Mark gnome-initial-setup as done
mkdir -p "${HOME}/.config"
touch "${HOME}/.config/gnome-initial-setup-done"

# If no setup-result.json, create one with Chromium default
if [ ! -f "${XIBO_CONFIG_DIR}/setup-result.json" ]; then
    mkdir -p "${XIBO_CONFIG_DIR}"
    cat > "${XIBO_CONFIG_DIR}/setup-result.json" << 'EOF'
{"player": "Chromium", "service": "xiboplayer-chromium.service"}
EOF
    echo "[Init] Created default setup-result.json (Chromium)"
fi

# Hand off to session holder
echo "[Init] Starting session holder..."
sleep 2
pkill -u "$(whoami)" dunst 2>/dev/null || true
exec "${XIBO_KIOSK_DIR}/gnome-kiosk-script.xibo.sh"

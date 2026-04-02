#!/bin/bash
# Xibo First-Boot Setup
# ======================
# Runs gnome-initial-setup (language/keyboard/network/timezone/password)
# then xiboplayer-setup (player selection + CMS config).
# Hands off to the session holder when done.

XIBO_KIOSK_DIR="${XIBO_KIOSK_DIR:-/usr/share/xiboplayer-kiosk}"
XIBO_DATA_DIR="${XIBO_DATA_DIR:-${HOME}/.local/share/xibo}"
NOTIFY_ID=1

# Start dunst for notifications
dunst -conf "${XIBO_KIOSK_DIR}/dunstrc" &

# Wait for Wayland compositor
sleep 2

# Import display environment into systemd user manager
systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_RUNTIME_DIR

# Disable donation popup
gsettings set org.gnome.desktop.interface show-donation-popup false 2>/dev/null || true

# ── Phase 1: gnome-initial-setup (language, keyboard, network, timezone, password) ──
if [ ! -f "${HOME}/.config/gnome-initial-setup-done" ]; then
    notify-send -r $NOTIFY_ID -t 3000 "Xibo" "Starting system configuration..." 2>/dev/null || true
    /usr/libexec/gnome-initial-setup 2>/dev/null || true
fi

# ── Phase 2: xiboplayer-setup (player selection + CMS config) ──
if [ ! -f "${XIBO_DATA_DIR}/setup-result.json" ]; then
    notify-send -r $NOTIFY_ID -t 3000 "Xibo" "Starting player configuration..." 2>/dev/null || true
    python3 "${XIBO_KIOSK_DIR}/xiboplayer-setup.py"
fi

# ── Verify player started ──
IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")

if [ -f "${XIBO_DATA_DIR}/setup-result.json" ]; then
    SERVICE=$(python3 -c "import json; print(json.load(open('${XIBO_DATA_DIR}/setup-result.json'))['service'])" 2>/dev/null)
    PLAYER=$(python3 -c "import json; print(json.load(open('${XIBO_DATA_DIR}/setup-result.json'))['player'])" 2>/dev/null)

    if [ -n "$SERVICE" ]; then
        sleep 3
        if systemctl --user is-active --quiet "$SERVICE"; then
            notify-send -r $NOTIFY_ID -t 5000 "Xibo" "IP: $IP — ${PLAYER} running" 2>/dev/null || true
        else
            notify-send -r $NOTIFY_ID -t 0 "Xibo" "IP: $IP — Waiting for ${PLAYER} to start..." 2>/dev/null || true
        fi
    fi
fi

sleep 2

# Close dunst and hand off to session holder
pkill -u "$(whoami)" dunst 2>/dev/null || true
exec "${XIBO_KIOSK_DIR}/gnome-kiosk-script.xibo.sh"

#!/bin/bash
# Xibo First-Boot Setup
# ======================
# Runs gnome-initial-setup (language/keyboard/network/timezone/password)
# then xiboplayer-setup (player selection + CMS config).
# Reboots for clean session after setup completes.

XIBO_KIOSK_DIR="${XIBO_KIOSK_DIR:-/usr/share/xiboplayer-kiosk}"
XIBO_DATA_DIR="${XIBO_DATA_DIR:-${HOME}/.local/share/xibo}"
LOGFILE="/tmp/xibo-init.log"
NOTIFY_ID=1

# Log everything
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== xibo-init started at $(date -Iseconds) ==="
echo "USER=$(whoami) HOME=$HOME"
echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY DISPLAY=$DISPLAY"

# Start dunst for notifications
dunst -conf "${XIBO_KIOSK_DIR}/dunstrc" &

# Wait for Wayland compositor
sleep 2

# Import display environment into systemd user manager
systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_RUNTIME_DIR

# Disable donation popup
gsettings set org.gnome.desktop.interface show-donation-popup false 2>/dev/null || true

# ── Phase 1: gnome-initial-setup ─────────────────────────────────────────────
echo "[Phase 1] Checking gnome-initial-setup-done..."
if [ ! -f "${HOME}/.config/gnome-initial-setup-done" ]; then
    echo "[Phase 1] Not done yet. Launching gnome-initial-setup..."
    notify-send -r $NOTIFY_ID -t 3000 "Xibo" "Starting system configuration..." 2>/dev/null || true
    if [ -x /usr/libexec/gnome-initial-setup ]; then
        /usr/libexec/gnome-initial-setup 2>&1 || echo "[Phase 1] gnome-initial-setup exited with $?"
    else
        echo "[Phase 1] WARNING: /usr/libexec/gnome-initial-setup not found"
    fi
else
    echo "[Phase 1] Already done, skipping."
fi

# ── Phase 2: xiboplayer-setup ────────────────────────────────────────────────
echo "[Phase 2] Checking setup-result.json..."
if [ ! -f "${XIBO_DATA_DIR}/setup-result.json" ]; then
    mkdir -p "${XIBO_DATA_DIR}"

    echo "[Phase 2] No setup-result.json. Launching setup wizard..."
    notify-send -r $NOTIFY_ID -t 3000 "Xibo" "Starting player configuration..." 2>/dev/null || true

    # Check if wizard exists
    if [ ! -f "${XIBO_KIOSK_DIR}/xiboplayer-setup.py" ]; then
        echo "[Phase 2] ERROR: ${XIBO_KIOSK_DIR}/xiboplayer-setup.py not found!"
        echo "[Phase 2] Files in ${XIBO_KIOSK_DIR}:"
        ls -la "${XIBO_KIOSK_DIR}/" 2>&1
        notify-send -r $NOTIFY_ID -t 0 "Xibo" "ERROR: Setup wizard not found. Check /tmp/xibo-init.log" 2>/dev/null || true
        sleep 30
    fi

    # Try libadwaita wizard
    echo "[Phase 2] Running: python3 ${XIBO_KIOSK_DIR}/xiboplayer-setup.py"
    if python3 "${XIBO_KIOSK_DIR}/xiboplayer-setup.py" 2>&1; then
        echo "[Phase 2] Wizard completed successfully."
    else
        WIZARD_EXIT=$?
        echo "[Phase 2] Wizard failed with exit code $WIZARD_EXIT"
        echo "[Phase 2] Log: $(cat /tmp/xiboplayer-setup.log 2>/dev/null || echo 'no log')"

        # Zenity fallback
        echo "[Phase 2] Trying zenity fallback..."
        notify-send -r $NOTIFY_ID -t 5000 "Xibo" "Setup wizard failed (exit $WIZARD_EXIT). Using fallback..." 2>/dev/null || true

        PLAYER=$(zenity --list --title="Xibo Player Setup" \
            --text="Select a player:" \
            --column="Player" --column="Description" \
            "xiboplayer-electron" "Electron (recommended)" \
            "xiboplayer-chromium" "Chromium (lightweight)" \
            "arexibo" "arexibo (native Rust)" \
            --width=400 --height=300 2>&1)
        ZENITY_EXIT=$?
        echo "[Phase 2] Zenity returned: PLAYER='$PLAYER' exit=$ZENITY_EXIT"

        if [ -z "$PLAYER" ] || [ "$ZENITY_EXIT" -ne 0 ]; then
            PLAYER="xiboplayer-electron"
            echo "[Phase 2] Zenity failed or empty — defaulting to $PLAYER"
        fi

        case "$PLAYER" in
            xiboplayer-electron) SERVICE="xiboplayer-electron.service" ;;
            xiboplayer-chromium) SERVICE="xiboplayer-chromium.service" ;;
            arexibo) SERVICE="arexibo.service" ;;
            *) PLAYER="xiboplayer-electron"; SERVICE="xiboplayer-electron.service" ;;
        esac

        echo "[Phase 2] Setting alternatives to $PLAYER"
        doas alternatives --set xiboplayer "/usr/bin/${PLAYER}" 2>&1 || echo "[Phase 2] alternatives failed"

        echo "[Phase 2] Writing setup-result.json"
        cat > "${XIBO_DATA_DIR}/setup-result.json" << SETUPEOF
{"player": "${PLAYER}", "service": "${SERVICE}"}
SETUPEOF
    fi
else
    echo "[Phase 2] setup-result.json already exists: $(cat "${XIBO_DATA_DIR}/setup-result.json")"
fi

# ── Phase 3: Reboot or hand off ──────────────────────────────────────────────
echo "[Phase 3] Checking result..."
if [ -f "${XIBO_DATA_DIR}/setup-result.json" ]; then
    echo "[Phase 3] setup-result.json: $(cat "${XIBO_DATA_DIR}/setup-result.json")"
    echo "[Phase 3] Setup complete. Starting session holder (no reboot for debug)..."
    notify-send -r $NOTIFY_ID -t 5000 "Xibo" "Setup complete. Starting player..." 2>/dev/null || true
    sleep 3
    pkill -u "$(whoami)" dunst 2>/dev/null || true
    exec "${XIBO_KIOSK_DIR}/gnome-kiosk-script.xibo.sh"
else
    echo "[Phase 3] ERROR: No setup-result.json after setup! Something went very wrong."
    echo "[Phase 3] Pausing 60s for debug. Check /tmp/xibo-init.log"
    notify-send -r $NOTIFY_ID -t 0 "Xibo" "ERROR: Setup failed. Check /tmp/xibo-init.log via Ctrl+Alt+F3" 2>/dev/null || true
    sleep 60
    pkill -u "$(whoami)" dunst 2>/dev/null || true
    exec "${XIBO_KIOSK_DIR}/gnome-kiosk-script.xibo.sh"
fi

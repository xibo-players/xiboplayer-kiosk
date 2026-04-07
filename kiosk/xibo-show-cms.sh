#!/bin/bash
# Show CMS/player status, offer reconfiguration.
# Triggered by Ctrl+R (via keyd).
XIBO_KIOSK_DIR="${XIBO_KIOSK_DIR:-/usr/share/xiboplayer-kiosk}"
XIBO_DATA_DIR="${XIBO_DATA_DIR:-${HOME}/.local/share/xibo}"

# Read current player
PLAYER=$(python3 -c "import json; print(json.load(open('${XIBO_DATA_DIR}/setup-result.json'))['player'])" 2>/dev/null || echo "unknown")
SERVICE=$(python3 -c "import json; print(json.load(open('${XIBO_DATA_DIR}/setup-result.json'))['service'])" 2>/dev/null || echo "unknown")

# Get CMS info based on player type
case "$PLAYER" in
    Arexibo)
        CMS=$(grep -oP '"address"\s*:\s*"\K[^"]+' "${XIBO_DATA_DIR}/cms.json" 2>/dev/null || echo "not configured")
        DISPLAY_NAME=$(grep -oP '"display_name"\s*:\s*"\K[^"]+' "${XIBO_DATA_DIR}/cms.json" 2>/dev/null || echo "unknown")
        ;;
    Chromium|Electron)
        SUBDIR=$(echo "$PLAYER" | tr '[:upper:]' '[:lower:]')
        CONFIG="$HOME/.config/xiboplayer/${SUBDIR}/config.json"
        CMS=$(python3 -c "import json; print(json.load(open('${CONFIG}')).get('cmsUrl','not configured'))" 2>/dev/null || echo "not configured")
        DISPLAY_NAME=$(python3 -c "import json; print(json.load(open('${CONFIG}')).get('displayName','unknown'))" 2>/dev/null || echo "unknown")
        ;;
    *)
        CMS="unknown"
        DISPLAY_NAME="unknown"
        ;;
esac

ACTION=$(zenity --list --title="xiboplayer" \
    --text="Player: $PLAYER\nCMS: $CMS\nDisplay: $DISPLAY_NAME\n\nChoose an action:" \
    --column="Action" --column="Description" \
    "reconfigure" "Reset player config and restart" \
    "full-setup" "Return to first-boot wizard (WiFi, timezone, etc.)" \
    "cancel" "Do nothing" \
    --width=450 --height=350 2>/dev/null)

case "$ACTION" in
    reconfigure)
        # Stop player
        systemctl --user stop "$SERVICE" 2>/dev/null || true

        # Delete player config so it re-shows its setup UI on restart
        case "$PLAYER" in
            Arexibo)
                rm -f "${XIBO_DATA_DIR}/cms.json"
                ;;
            Chromium|Electron)
                SUBDIR=$(echo "$PLAYER" | tr '[:upper:]' '[:lower:]')
                rm -f "$HOME/.config/xiboplayer/${SUBDIR}/config.json"
                ;;
        esac

        # Restart player
        systemctl --user restart "$SERVICE" 2>/dev/null || true
        ;;

    full-setup)
        # Stop all player services
        for svc in arexibo.service xiboplayer-electron.service xiboplayer-chromium.service; do
            systemctl --user stop "$svc" 2>/dev/null || true
        done

        # Re-add wizard autostart
        mkdir -p "$HOME/.config/autostart"
        cp "${XIBO_KIOSK_DIR}/xiboplayer-setup.desktop" "$HOME/.config/autostart/"

        # Switch back to GNOME session for full reconfiguration
        doas "${XIBO_KIOSK_DIR}/xibo-deactivate-kiosk.sh"

        # Kill kiosk session — GDM will re-login into GNOME with wizard
        pkill -u "$(whoami)" -f gnome-kiosk-script 2>/dev/null || true
        ;;
esac

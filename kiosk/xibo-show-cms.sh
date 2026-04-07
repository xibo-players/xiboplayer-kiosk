#!/bin/bash
# Show CMS/player status, offer reconfiguration.
# Triggered by Ctrl+R (via keyd).
XIBO_KIOSK_DIR="${XIBO_KIOSK_DIR:-/usr/share/xiboplayer-kiosk}"
XIBO_CONFIG_DIR="${HOME}/.config/xiboplayer"
XIBO_DATA_DIR="${HOME}/.local/share/xibo"

# Read current player
PLAYER=$(python3 -c "import json; print(json.load(open('${XIBO_CONFIG_DIR}/setup-result.json'))['player'])" 2>/dev/null || echo "unknown")
SERVICE=$(python3 -c "import json; print(json.load(open('${XIBO_CONFIG_DIR}/setup-result.json'))['service'])" 2>/dev/null || echo "unknown")

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
    --width=350 --height=280 2>/dev/null)

case "$ACTION" in
    reconfigure)
        # Stop player
        systemctl --user stop "$SERVICE" 2>/dev/null || true

        case "$PLAYER" in
            Arexibo)
                # Arexibo has no built-in setup UI — ask for new CMS details via zenity
                rm -f "${XIBO_DATA_DIR}/cms.json"

                URL=$(zenity --entry --title="xiboplayer — CMS URL" \
                    --text="Enter the CMS server URL:" \
                    --entry-text="https://" --width=400 2>/dev/null) || true
                [ -z "$URL" ] && return

                KEY=$(zenity --entry --title="xiboplayer — CMS Key" \
                    --text="Enter the CMS key:" --width=400 2>/dev/null) || true
                [ -z "$KEY" ] && return

                NAME=$(zenity --entry --title="xiboplayer — Display Name" \
                    --text="Enter a display name:" \
                    --entry-text="$(hostname)" --width=400 2>/dev/null) || true
                [ -z "$NAME" ] && NAME="$(hostname)"

                # Ensure URL ends with /
                [[ "$URL" != */ ]] && URL="${URL}/"

                # Generate display ID
                MACHINE_ID=$(cat /etc/machine-id 2>/dev/null || echo "")
                DISPLAY_ID="xibo-$(echo -n "${MACHINE_ID}$(date +%s)${KEY}" | sha256sum | cut -c1-12)"

                mkdir -p "${XIBO_DATA_DIR}"
                cat > "${XIBO_DATA_DIR}/cms.json" << CMSEOF
{
    "address": "$URL",
    "key": "$KEY",
    "display_id": "$DISPLAY_ID",
    "display_name": "$NAME",
    "proxy": null
}
CMSEOF
                zenity --info --title="xiboplayer" \
                    --text="CMS configured.\nAuthorise this display in the CMS admin panel." \
                    --width=350 2>/dev/null || true
                ;;
            Chromium|Electron)
                # Delete config — player will re-show its own setup UI on restart
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

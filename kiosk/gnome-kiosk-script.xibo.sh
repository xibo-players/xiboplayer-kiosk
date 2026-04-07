#!/bin/bash
# Xibo GNOME Kiosk Session Holder
# ===================================
# Keeps the gnome-kiosk session alive while delegating player management
# to systemd (arexibo.service). Shows persistent status notifications.

XIBO_KIOSK_DIR="${XIBO_KIOSK_DIR:-/usr/share/xiboplayer-kiosk}"
XIBO_CONFIG_DIR="${HOME}/.config/xiboplayer"
XIBO_DATA_DIR="${HOME}/.local/share/xibo"
NOTIFY_ID=1

# Start supporting services
dunst -conf "${XIBO_KIOSK_DIR}/dunstrc" &
unclutter --timeout 3 &

# Wait for compositor
sleep 2

# Import display environment into systemd user manager
systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_RUNTIME_DIR

# Disable screen blanking and power management
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.settings-daemon.plugins.power idle-dim false
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
gsettings set org.gnome.desktop.interface show-donation-popup false

# Set audio volume (90%)
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.9 2>/dev/null || true

# Helper: get IP address
get_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown"
}

# Helper: send/update the persistent status notification
# Usage: status_notify "message" [urgency]
# urgency: low, normal, critical (default: normal)
status_notify() {
    local msg="$1"
    local urgency="${2:-normal}"
    notify-send -r "$NOTIFY_ID" -u "$urgency" -t 0 "Xibo" "$msg" 2>/dev/null || true
}

# Helper: extract error reason from player journal logs
get_player_error() {
    journalctl --user -u "$PLAYER_SERVICE" --no-pager -n 20 -q 2>/dev/null \
        | grep -iE 'error|fail|denied|unauthorized|not authorised|refused|timeout' \
        | tail -1 \
        | sed 's/.*xibo\[.*\]: //' \
        | head -c 200
}

# Clear any lingering notifications from previous session/wizard
dunstctl close-all 2>/dev/null || true

# Determine which service to manage from setup-result.json
PLAYER_SERVICE="arexibo.service"
if [ -f "${XIBO_CONFIG_DIR}/setup-result.json" ]; then
    SVC=$(python3 -c "import json; print(json.load(open('${XIBO_CONFIG_DIR}/setup-result.json'))['service'])" 2>/dev/null)
    [ -n "$SVC" ] && PLAYER_SERVICE="$SVC"
fi

# Show initial status briefly (5 seconds)
IP=$(get_ip)
CMS=$(grep -oP '"address"\s*:\s*"\K[^"]+' "${XIBO_DATA_DIR}/cms.json" 2>/dev/null || echo "not configured")
notify-send -t 5000 "Xibo" "IP: $IP\nCMS: $CMS\nStarting ${PLAYER_SERVICE}..."

# Start player via systemd — Electron/Chromium show their own setup UI if unconfigured.
# On first boot with no CMS config, wipe ALL player profile data to prevent stale
# Service Worker / Local Storage from triggering auto-registration loops.
has_cms_config() {
    case "$PLAYER_SERVICE" in
        xiboplayer-chromium.service)
            local cf="$HOME/.config/xiboplayer/chromium/config.json"
            [ -f "$cf" ] && python3 -c "import json,sys; sys.exit(0 if json.load(open('$cf')).get('cmsUrl') else 1)" 2>/dev/null
            ;;
        xiboplayer-electron.service)
            local cf="$HOME/.config/xiboplayer/electron/config.json"
            [ -f "$cf" ] && python3 -c "import json,sys; sys.exit(0 if json.load(open('$cf')).get('cmsUrl') else 1)" 2>/dev/null
            ;;
        arexibo.service)
            [ -f "${XIBO_DATA_DIR}/cms.json" ]
            ;;
    esac
}

if ! has_cms_config; then
    case "$PLAYER_SERVICE" in
        xiboplayer-chromium.service) rm -rf "$HOME/.config/xiboplayer/chromium/Default" 2>/dev/null ;;
        xiboplayer-electron.service) rm -rf "$HOME/.config/xiboplayer/electron/Default" 2>/dev/null ;;
    esac
fi
systemctl --user start "$PLAYER_SERVICE" 2>/dev/null || true

# Monitor player health
FAIL_COUNT=0
MAX_FAILS=3

while true; do
    sleep 10

    IP=$(get_ip)

    if systemctl --user is-active --quiet "$PLAYER_SERVICE"; then
        FAIL_COUNT=0
        # Close notification when connected — player is showing content
        dunstctl close-all 2>/dev/null || notify-send -r "$NOTIFY_ID" -t 1 " " " " 2>/dev/null || true
    else
        # If player has no CMS config, don't restart — let the user interact with the setup screen.
        # The player shows its own setup UI when unconfigured; restarting creates a loop.
        HAS_CONFIG=false
        case "$PLAYER_SERVICE" in
            xiboplayer-chromium.service)
                CF="$HOME/.config/xiboplayer/chromium/config.json"
                [ -f "$CF" ] && grep -q '"cmsUrl"' "$CF" 2>/dev/null && \
                    [ "$(python3 -c "import json; c=json.load(open('$CF')).get('cmsUrl',''); print('yes' if c else 'no')" 2>/dev/null)" = "yes" ] && HAS_CONFIG=true
                ;;
            xiboplayer-electron.service)
                CF="$HOME/.config/xiboplayer/electron/config.json"
                [ -f "$CF" ] && grep -q '"cmsUrl"' "$CF" 2>/dev/null && \
                    [ "$(python3 -c "import json; c=json.load(open('$CF')).get('cmsUrl',''); print('yes' if c else 'no')" 2>/dev/null)" = "yes" ] && HAS_CONFIG=true
                ;;
            arexibo.service)
                [ -f "${XIBO_DATA_DIR}/cms.json" ] && HAS_CONFIG=true
                ;;
        esac

        if [ "$HAS_CONFIG" = "false" ]; then
            # No CMS config — player is showing setup screen, don't restart
            status_notify "IP: $IP — Waiting for CMS configuration..." "normal"
            # Start it once if not running
            systemctl --user is-failed --quiet "$PLAYER_SERVICE" && \
                systemctl --user restart "$PLAYER_SERVICE" 2>/dev/null || true
        else
            # Has config but player stopped — real error, handle normally
            EXIT_CODE=$(systemctl --user show -p ExecMainStatus --value "$PLAYER_SERVICE" 2>/dev/null)

            if [ "$EXIT_CODE" = "2" ]; then
                status_notify "IP: $IP — Waiting for CMS authorization..." "normal"
            else
                FAIL_COUNT=$((FAIL_COUNT + 1))
                ERROR=$(get_player_error)
                if [ -n "$ERROR" ]; then
                    status_notify "IP: $IP — Error: $ERROR" "critical"
                else
                    status_notify "IP: $IP — Player not running (attempt $FAIL_COUNT/$MAX_FAILS)" "critical"
                fi

                if [ "$FAIL_COUNT" -ge "$MAX_FAILS" ]; then
                    status_notify "IP: $IP — Player failed $MAX_FAILS times." "critical"
                    FAIL_COUNT=0
                    systemctl --user restart "$PLAYER_SERVICE" 2>/dev/null || true
                    status_notify "IP: $IP — Restarting player..." "normal"
                fi
            fi
        fi
    fi
done

#!/bin/bash
# Xibo CMS Registration Wizard
# =================================
# First-boot wizard. Asks which player to use, then:
# - Electron/Chromium: start the player service (has its own setup UI)
# - Arexibo: collect CMS credentials via Zenity, write cms.json, start service

XIBO_KIOSK_DIR="${XIBO_KIOSK_DIR:-/usr/share/xiboplayer-kiosk}"
XIBO_DATA_DIR="${XIBO_DATA_DIR:-${HOME}/.local/share/xibo}"

# Start dunst for notifications
dunst -conf "${XIBO_KIOSK_DIR}/dunstrc" &

# Wait for Wayland compositor
sleep 2

# Import display environment into systemd user manager
systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_RUNTIME_DIR

# Get IP for display
IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
notify-send "Xibo Setup" "Starting configuration wizard..." -t 3000

# Main loop
while true; do
    # ── Step 1: Choose player ──────────────────────────────────────
    PLAYERS=()
    [ -f /usr/bin/xiboplayer-electron ] && PLAYERS+=(TRUE "Electron" "Web-based player (recommended)")
    [ -f /usr/bin/xiboplayer-chromium ] && PLAYERS+=(FALSE "Chromium" "Chromium kiosk wrapper")
    [ -f /usr/bin/arexibo ] && PLAYERS+=(FALSE "Arexibo" "Rust-based native player")

    if [ ${#PLAYERS[@]} -gt 3 ]; then
        PLAYER_CHOICE=$(zenity --list --radiolist \
            --title="Xibo Setup" \
            --text="Select player:" \
            --column="Select" --column="Player" --column="Description" \
            "${PLAYERS[@]}" \
            --width=450 --height=300)
        [ -z "$PLAYER_CHOICE" ] && PLAYER_CHOICE="${PLAYERS[1]}"
    else
        PLAYER_CHOICE="${PLAYERS[1]}"
    fi

    # Set alternatives
    case "$PLAYER_CHOICE" in
        Electron)  doas alternatives --set xiboplayer /usr/bin/xiboplayer-electron ;;
        Chromium)  doas alternatives --set xiboplayer /usr/bin/xiboplayer-chromium ;;
        Arexibo)   doas alternatives --set xiboplayer /usr/bin/arexibo ;;
    esac

    # Map to systemd service
    case "$PLAYER_CHOICE" in
        Electron)  PLAYER_SERVICE="xiboplayer-electron.service" ;;
        Chromium)  PLAYER_SERVICE="xiboplayer-chromium.service" ;;
        Arexibo)   PLAYER_SERVICE="xibo-player.service" ;;
    esac

    # ── Step 2: Player-specific setup ──────────────────────────────
    if [ "$PLAYER_CHOICE" = "Arexibo" ]; then
        # Arexibo needs CMS credentials — collect via Zenity
        CMS_HOST=$(zenity --entry \
            --title="Xibo Setup" \
            --text="Enter CMS Server URL (e.g., https://xibo.example.com/):" \
            --entry-text="https://" \
            --width=400)

        if [ -z "$CMS_HOST" ]; then
            continue
        fi

        [[ "${CMS_HOST}" != */ ]] && CMS_HOST="${CMS_HOST}/"

        CMS_KEY=$(zenity --entry \
            --title="Xibo Setup" \
            --text="Enter CMS Key:" \
            --width=400)

        if [ -z "$CMS_KEY" ]; then
            zenity --warning --title="Xibo Setup" --text="CMS Key is required." --width=300
            continue
        fi

        # Generate display ID
        MACHINE_ID=$(cat /etc/machine-id 2>/dev/null || echo "unknown")
        TIMESTAMP=$(date +%s)
        DISPLAY_ID=$(echo "${MACHINE_ID}${TIMESTAMP}${CMS_KEY}" | sha256sum | cut -c1-12)

        HOSTNAME=$(hostname)
        DISPLAY_NAME=$(zenity --entry \
            --title="Xibo Setup" \
            --text="Enter Display Name (optional):" \
            --entry-text="${HOSTNAME}" \
            --width=400)
        [ -z "$DISPLAY_NAME" ] && DISPLAY_NAME="${HOSTNAME}"

        # Write arexibo config
        mkdir -p "${XIBO_DATA_DIR}"
        cat > "${XIBO_DATA_DIR}/cms.json" << EOF
{
    "address": "${CMS_HOST}",
    "key": "${CMS_KEY}",
    "display_id": "xibo-${DISPLAY_ID}",
    "display_name": "${DISPLAY_NAME}",
    "proxy": null
}
EOF

        notify-send -r 1 -t 0 "Xibo" "IP: $IP — Configuration saved. Starting Arexibo..." 2>/dev/null || true

        # Enable and start arexibo
        systemctl --user enable --now "$PLAYER_SERVICE"
        sleep 5

        if systemctl --user is-active --quiet "$PLAYER_SERVICE"; then
            notify-send -r 1 -t 5000 "Xibo" "IP: $IP — Connected to CMS" 2>/dev/null || true
            sleep 3
        else
            EXIT_CODE=$(systemctl --user show -p ExecMainStatus --value "$PLAYER_SERVICE" 2>/dev/null)

            if [ "$EXIT_CODE" = "2" ]; then
                notify-send -r 1 -t 0 -u normal "Xibo" \
                    "IP: $IP — Waiting for CMS authorization\nDisplay ID: xibo-${DISPLAY_ID}" 2>/dev/null || true

                zenity --info \
                    --title="Xibo Setup - Authorization Pending" \
                    --text="Display registered but not yet authorized.\n\nDisplay ID: xibo-${DISPLAY_ID}\nIP Address: ${IP}\n\nPlease authorize this display in your Xibo CMS.\nThe player will retry automatically." \
                    --width=400
            else
                ERROR=$(journalctl --user -u "$PLAYER_SERVICE" --no-pager -n 20 -q 2>/dev/null \
                    | grep -iE 'error|fail|denied|refused|timeout' \
                    | tail -1 \
                    | sed 's/.*xibo\[.*\]: //' \
                    | head -c 200)

                zenity --question \
                    --title="Xibo Setup - Error" \
                    --text="Player failed to start.\n\nError: ${ERROR:-unknown}\nIP Address: ${IP}\n\nDo you want to reconfigure?" \
                    --width=400

                if [ $? -eq 0 ]; then
                    rm -f "${XIBO_DATA_DIR}/cms.json"
                    continue
                fi
            fi
        fi

    else
        # Electron / Chromium — they have their own setup UI
        notify-send -r 1 -t 3000 "Xibo" "IP: $IP — Starting ${PLAYER_CHOICE}..." 2>/dev/null || true
        systemctl --user enable --now "$PLAYER_SERVICE"
        sleep 3
    fi

    # ── Done — close dunst and hand off to session holder ──────────
    pkill -u "$(whoami)" dunst 2>/dev/null || true
    exec "${XIBO_KIOSK_DIR}/gnome-kiosk-script.xibo.sh"
done

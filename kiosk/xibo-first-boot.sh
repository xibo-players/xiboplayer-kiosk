#!/bin/bash
# xibo-first-boot.sh — zenity first-boot menu for xiboplayer-kiosk.
#
# Invoked from kiosk/gnome-kiosk-script.xibo.sh after GDM autologin,
# BEFORE the player service starts, guarded by a user-level sentinel
# at $XIBO_DATA_DIR/first-boot-done. Also invokable from the Ctrl+R
# reconfigure menu when the operator wants to re-run first-boot setup.
#
# Presents a zenity --list with 5 rows + live status column:
#
#   ┌─ xiboplayer first boot ────────────────────────────────┐
#   │ Action     Status                                      │
#   │ wifi       MyWiFi            (or "(wired)" or "(not connected)")
#   │ timezone   Europe/Madrid
#   │ cms        https://cms.test/ (or "(not configured)")
#   │ debug      Collect diagnostic bundle
#   │ done       Start player
#   └────────────────────────────────────────────────────────┘
#
# Each row dispatches to a handler function. The menu loops until the
# operator picks "done" (or the 2-minute --timeout fires and auto-
# skips to the player to prevent walkaway lockout).
#
# Wi-Fi picker calls the new xibo-set-wifi.sh helper via doas (the
# helper writes NM keyfiles directly — no PSK leak on the CLI).
# Timezone picker calls xibo-set-timezone.sh via doas (the helper
# validates the argument against timedatectl list-timezones before
# invoking the real command). Locale is similar.

set -u

XIBO_KIOSK_DIR="${XIBO_KIOSK_DIR:-/usr/share/xiboplayer-kiosk}"
# shellcheck source=./xibo-zenity-lib.sh
. "$XIBO_KIOSK_DIR/xibo-zenity-lib.sh"

# --- Wi-Fi handler --------------------------------------------------------
handle_wifi() {
    # Kick off a fresh scan in the background; nmcli list will return
    # whatever's cached or fresh.
    nmcli dev wifi rescan 2>/dev/null &
    sleep 2

    # Check for wireless hardware first — hide the row entirely if no wifi.
    if ! nmcli -t -f DEVICE,TYPE dev status 2>/dev/null | grep -q ':wifi$'; then
        zenity --info --title="xiboplayer — Wi-Fi" --width=400 \
            --text="No wireless hardware detected.\n\nUse a wired connection instead." 2>/dev/null
        return 0
    fi

    # Build the SSID list — format each line as three zenity columns.
    # nmcli -t output is colon-separated: SSID:SIGNAL:SECURITY:IN-USE.
    # Sort by signal descending, dedupe by SSID.
    local list
    list=$(nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list 2>/dev/null \
        | awk -F: '
            $2!="" && !seen[$2]++ {
                sec = ($4=="" || $4=="--") ? "open" : $4
                inuse = ($1=="*") ? "*" : " "
                printf "%s\n%s\n%d%%\n%s\n", inuse, $2, $3, sec
            }' \
        | head -80)

    if [ -z "$list" ]; then
        zenity --error --title="xiboplayer — Wi-Fi" --width=400 \
            --text="No Wi-Fi networks found. Try again or use wired." 2>/dev/null
        return 0
    fi

    # Show the picker.
    local ssid
    ssid=$(echo -e "$list" | zenity --list \
        --title="xiboplayer — Wi-Fi" \
        --text="Select a network" \
        --column="Active" --column="SSID" --column="Signal" --column="Security" \
        --width=500 --height=400 \
        --hide-column=1 \
        --print-column=2 \
        2>/dev/null) || return 0

    [ -z "$ssid" ] && return 0

    # Check security — open networks skip the password dialog.
    local sec
    sec=$(nmcli -t -f SSID,SECURITY dev wifi list 2>/dev/null \
        | awk -F: -v target="$ssid" '$1==target {print $2; exit}')

    local psk=""
    if [ -n "$sec" ] && [ "$sec" != "--" ]; then
        psk=$(zenity --password \
            --title="xiboplayer — Wi-Fi password" \
            --text="Enter password for $ssid" 2>/dev/null) || return 0
        [ -z "$psk" ] && return 0
    fi

    # Connect via the doas helper.
    zlib_notify "Connecting to $ssid..."
    if doas "$XIBO_KIOSK_DIR/xibo-set-wifi.sh" "$ssid" "$psk" 2>&1; then
        # Connectivity check — captive portal detection
        if curl --max-time 5 --silent --output /dev/null --fail \
            https://detectportal.firefox.com/success.txt 2>/dev/null; then
            zlib_notify "Wi-Fi connected to $ssid"
        else
            zenity --warning --title="xiboplayer — Wi-Fi" --width=480 \
                --text="Connected to $ssid, but internet access appears gated by a captive portal.\n\nThis network may not reach the CMS. Please use wired if available." 2>/dev/null
            zlib_notify "Wi-Fi: captive portal detected" critical
        fi
    else
        zenity --error --title="xiboplayer — Wi-Fi" --width=480 \
            --text="Failed to connect to $ssid.\n\nCheck the password and signal, then try again." 2>/dev/null
        zlib_notify "Wi-Fi authentication failed" critical
    fi
}

# --- Timezone handler -----------------------------------------------------
handle_timezone() {
    # Two-stage filter: prompt for a filter substring first, then show
    # the matching IANA zones. Avoids scrolling 593 rows.
    local filter
    filter=$(zenity --entry \
        --title="xiboplayer — Timezone" \
        --text="Type a city or region to filter (e.g. Madrid, Europe, UTC):" \
        --width=420 \
        2>/dev/null) || return 0
    [ -z "$filter" ] && return 0

    local tz
    tz=$(timedatectl list-timezones 2>/dev/null \
        | grep -i -- "$filter" \
        | zenity --list \
            --title="xiboplayer — Timezone (matching $filter)" \
            --column="IANA timezone" \
            --width=420 --height=500 \
            2>/dev/null) || return 0
    [ -z "$tz" ] && return 0

    zlib_notify "Setting timezone to $tz..."
    if doas "$XIBO_KIOSK_DIR/xibo-set-timezone.sh" "$tz" 2>&1; then
        zlib_notify "Timezone: $tz"
    else
        zenity --error --title="xiboplayer — Timezone" --width=400 \
            --text="Failed to set timezone to $tz." 2>/dev/null
    fi
}

# --- CMS handler ----------------------------------------------------------
handle_cms() {
    CMS_URL=""; CMS_KEY=""; DISPLAY_NAME=""
    zlib_cms_form || return 0
    [ -z "$CMS_URL" ] && return 0
    [ -z "$CMS_KEY" ] && return 0

    zlib_write_player_config "$CMS_URL" "$CMS_KEY" "$DISPLAY_NAME"
    zlib_notify "CMS configured: $CMS_URL"

    # Post-save guidance — tell the operator to authorise the display.
    zenity --info --title="xiboplayer — CMS configured" --width=500 \
        --text="Display registered with CMS:

  URL:  $CMS_URL
  Name: $DISPLAY_NAME

The display will appear as PENDING in the CMS admin panel.

Ask your CMS administrator to authorise this display under
Displays → (find your display name) → Authorise.

Content will start playing within 60 seconds after authorisation." \
        2>/dev/null || true
}

# --- Language handler -----------------------------------------------------
#
# Two-stage filter picker, same UX as handle_timezone:
#
#   1. zenity --entry asks for a substring to filter against
#      `localectl list-locales` output (case-insensitive grep).
#   2. zenity --list shows the filtered matches so the operator picks
#      one. Works for any locale the system supports without us having
#      to curate a list.
#
# The filter pipeline strips "non-primary" variants per user direction
# "skip the ... selection for non-primary languages":
#
#   - Entries with @variant suffix (e.g. es_ES.UTF-8@euro) — same
#     language with a different collation / currency variant. One
#     per locale is enough.
#   - Non-UTF-8 encodings (ISO-8859-1 / KOI8-R / etc.) — legacy, not
#     worth showing.
#   - The special C.UTF-8 and POSIX locales — not user-facing.
handle_language() {
    local filter
    filter=$(zenity --entry \
        --title="xiboplayer — Language" \
        --text="Type a language or country to filter (e.g. English, en_, en_GB):" \
        --width=480 \
        2>/dev/null) || return 0
    [ -z "$filter" ] && return 0

    local matches
    matches=$(localectl list-locales 2>/dev/null \
        | grep -Ev '@|\.(iso|ISO|koi|KOI|gb|GB|euc|EUC|big|BIG)' \
        | grep -v '^C\.' \
        | grep -v '^POSIX$' \
        | grep -i -- "$filter")

    if [ -z "$matches" ]; then
        zenity --info --title="xiboplayer — Language" --width=420 \
            --text="No locale matches '$filter'.\n\nTry a shorter filter like 'es' or 'en'." \
            2>/dev/null
        return 0
    fi

    local locale
    locale=$(echo "$matches" \
        | zenity --list \
            --title="xiboplayer — Language (matching '$filter')" \
            --column="Locale" \
            --width=420 --height=500 \
            2>/dev/null) || return 0
    [ -z "$locale" ] && return 0

    zlib_notify "Setting language to $locale..."
    if doas "$XIBO_KIOSK_DIR/xibo-set-locale.sh" "$locale" 2>&1; then
        zlib_notify "Language: $locale"
    else
        zenity --error --title="xiboplayer — Language" --width=400 \
            --text="Failed to set language to $locale." 2>/dev/null
    fi
}

# --- Player handler -------------------------------------------------------
#
# Chromium ↔ Electron switch (#96). Deliberately excludes arexibo
# because arexibo is netinstall opt-in only per the 0.4.30 scope — the
# default image ships Chromium + Electron, so those are the only two
# rows we offer interactively.
#
# Calls xibo-set-player.sh via doas. That helper:
#   - runs `alternatives --set xiboplayer /usr/bin/xiboplayer-<name>`
#   - rewrites ~/.config/xiboplayer/setup-result.json
#   - stops any currently-running player service
#
# Operator needs to reboot (or log out / back in) for the new player
# to actually start. The helper does NOT kill the session itself —
# matches the deliberately-minimal scope in #96.
handle_player() {
    local current
    current=$(zlib_status_player)

    local pick
    pick=$(zenity --list \
        --title="xiboplayer — Player" \
        --text="Current player: $current\n\nChoose which player runs on next session." \
        --column="Player" --column="Description" \
        --width=520 --height=260 \
        "Chromium" "Chromium kiosk (default, lighter)" \
        "Electron" "Electron wrapper (heavier, more compatible)" \
        2>/dev/null) || return 0
    [ -z "$pick" ] && return 0

    local arg
    case "$pick" in
        Chromium) arg=chromium ;;
        Electron) arg=electron ;;
        *)        return 0 ;;
    esac

    if [ "$pick" = "$current" ]; then
        zlib_notify "Player already set to $pick"
        return 0
    fi

    zlib_notify "Switching player to $pick..."
    if doas "$XIBO_KIOSK_DIR/xibo-set-player.sh" "$arg" 2>&1; then
        zlib_notify "Player: $pick (reboot or log out to apply)"
        zenity --info --title="xiboplayer — Player" --width=460 \
            --text="Player switched to $pick.\n\nReboot the kiosk (or log out and back in) to start the new player." \
            2>/dev/null
    else
        zenity --error --title="xiboplayer — Player" --width=400 \
            --text="Failed to switch player to $pick." 2>/dev/null
    fi
}

# --- Debug handler --------------------------------------------------------
handle_debug() {
    if [ -x "$XIBO_KIOSK_DIR/xibo-debug-dump.sh" ]; then
        "$XIBO_KIOSK_DIR/xibo-debug-dump.sh"
    elif command -v xibo-debug-dump >/dev/null 2>&1; then
        xibo-debug-dump
    else
        zenity --error --title="xiboplayer — Debug" --width=400 \
            --text="xibo-debug-dump.sh not found." 2>/dev/null
    fi
}

# --- main loop ------------------------------------------------------------
# The menu re-displays itself after each row completes, so the operator
# can configure WiFi → check status → configure TZ → ... → done in one
# sitting. Auto-skip on 2-minute timeout (exit code 5).
main_loop() {
    while true; do
        local wifi_status tz_status cms_status lang_status player_status
        wifi_status=$(zlib_status_wifi)
        tz_status=$(zlib_status_tz)
        cms_status=$(zlib_status_cms)
        lang_status=$(zlib_status_locale)
        player_status=$(zlib_status_player)

        local action
        action=$(zenity --list \
            --title="xiboplayer — First boot setup" \
            --text="Configure the kiosk, then select Done to start the player." \
            --column="Action" --column="Setting" --column="Current status" \
            --width=620 --height=420 \
            --hide-column=1 \
            --print-column=1 \
            --timeout=120 \
            "language" "Language" "$lang_status" \
            "wifi"     "Wi-Fi"    "$wifi_status" \
            "timezone" "Timezone" "$tz_status" \
            "player"   "Player"   "$player_status" \
            "cms"      "CMS"      "$cms_status" \
            "debug"    "Collect debug info" "" \
            "done"     "Start player" "" \
            2>/dev/null)
        local rc=$?

        # Exit code 5 = timeout. Exit code 1 = cancel / close button.
        # In either case, fall through to "done" (start the player) so
        # the kiosk doesn't stall forever on walkaway.
        if [ $rc -eq 5 ] || [ $rc -eq 1 ]; then
            zlib_notify "First-boot menu dismissed, starting player"
            return 0
        fi

        case "$action" in
            language) handle_language ;;
            wifi)     handle_wifi ;;
            timezone) handle_timezone ;;
            player)   handle_player ;;
            cms)      handle_cms ;;
            debug)    handle_debug ;;
            done)     zlib_notify "First-boot complete, starting player"; return 0 ;;
            *)        return 0 ;;
        esac
    done
}

main_loop

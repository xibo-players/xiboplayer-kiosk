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
#
# Delegates to xibo-show-cms.sh — the same script that Ctrl+R invokes.
# This keeps the first-boot CMS row and the Ctrl+R reconfigure menu
# as ONE source of truth for CMS configuration, instead of two
# divergent zenity flows. Per user directive 2026-04-12 "in 1st
# screen: CMS setting and open the current window".
#
# xibo-show-cms.sh shows the Ctrl+R top-level menu with "reconfigure"
# (per-player CMS form), "full-setup" (re-run first-boot), and
# "cancel" actions. From the first-boot CMS row the operator would
# typically pick "reconfigure" to set CMS URL / key / display name.
#
# Note on recursion: if the operator picks "full-setup" while we're
# inside this handler, xibo-show-cms.sh re-invokes xibo-first-boot.sh.
# That nested invocation runs its own main_loop() and returns here
# when the operator hits Done. The outer main_loop() then continues
# as normal. Messy but functional — no infinite recursion because
# each invocation writes the first-boot-done sentinel before
# returning, and the sentinel is the gate that prevents auto-launch.
handle_cms() {
    if [ -x "$XIBO_KIOSK_DIR/xibo-show-cms.sh" ]; then
        "$XIBO_KIOSK_DIR/xibo-show-cms.sh" || true
    else
        zenity --error --title="xiboplayer — CMS" --width=400 \
            --window-icon="$XIBO_LOGO" \
            --text="xibo-show-cms.sh not found — cannot configure CMS." 2>/dev/null
    fi
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
        --text="Type a locale code to filter (e.g. en, en_GB, ca, es, fr, de):" \
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

# --- Keyboard handler -----------------------------------------------------
#
# Two-stage filter picker over `localectl list-x11-keymap-layouts`, same
# UX as the Language and Timezone rows. Closes the keyboard half of #94
# that was deferred from 0.4.30 scope.
#
# Language auto-inference (see xibo-set-locale.sh) gives a sensible
# default keyboard when the operator picks Language — this explicit row
# is for operators who need something different (e.g. a Portuguese kiosk
# in a Spanish office that wants to keep Spanish layout).
handle_keyboard() {
    local filter
    filter=$(zenity --entry \
        --title="xiboplayer — Keyboard layout" \
        --window-icon="$XIBO_LOGO" \
        --text="Type a layout code or country to filter (e.g. us, es, fr, gb):" \
        --width=480 \
        2>/dev/null) || return 0
    [ -z "$filter" ] && return 0

    local matches
    matches=$(localectl list-x11-keymap-layouts 2>/dev/null \
        | grep -i -- "$filter")

    if [ -z "$matches" ]; then
        zenity --info --title="xiboplayer — Keyboard layout" --width=420 \
            --window-icon="$XIBO_LOGO" \
            --text="No layout matches '$filter'.\n\nTry a shorter filter like 'es', 'fr', 'de'." \
            2>/dev/null
        return 0
    fi

    local layout
    layout=$(echo "$matches" \
        | zenity --list \
            --title="xiboplayer — Keyboard layout (matching '$filter')" \
            --window-icon="$XIBO_LOGO" \
            --column="Layout" \
            --width=420 --height=500 \
            2>/dev/null) || return 0
    [ -z "$layout" ] && return 0

    zlib_notify "Setting keyboard to $layout..."
    if doas "$XIBO_KIOSK_DIR/xibo-set-keyboard.sh" "$layout" 2>&1; then
        zlib_notify "Keyboard: $layout"
    else
        zenity --error --title="xiboplayer — Keyboard layout" --width=400 \
            --window-icon="$XIBO_LOGO" \
            --text="Failed to set keyboard layout to $layout." 2>/dev/null
    fi
}

# --- Terminal handler -----------------------------------------------------
#
# Launches a terminal emulator directly in the xibo user's session (no
# doas needed — we're already running as xibo). Used as a row in the
# Settings sub-menu for operator debugging. Also bound to Ctrl+S via keyd.
#
# Terminal selection order (per user directive 2026-04-12 "gnome-terminal
# not installed, we have a more modern option called ptyxis"):
#   1. ptyxis     — Fedora 43's modern GNOME Console successor (default)
#   2. kgx        — legacy GNOME Console
#   3. gnome-terminal — traditional GNOME Terminal, deprecated
#   4. xterm      — last-ditch fallback
handle_terminal() {
    local term=""
    for candidate in ptyxis kgx gnome-terminal xterm; do
        if command -v "$candidate" >/dev/null 2>&1; then
            term="$candidate"
            break
        fi
    done

    if [ -n "$term" ]; then
        # Fire-and-forget — we don't wait for the terminal to close.
        # Disown so the terminal survives even if the first-boot menu
        # closes.
        setsid "$term" >/dev/null 2>&1 &
        disown 2>/dev/null || true
        zlib_notify "Opened $term"
    else
        zenity --error --title="xiboplayer — Terminal" --width=400 \
            --window-icon="$XIBO_LOGO" \
            --text="No terminal emulator installed (tried ptyxis, kgx, gnome-terminal, xterm)." 2>/dev/null
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
            --window-icon="$XIBO_LOGO" \
            --text="xibo-debug-dump.sh not found." 2>/dev/null
    fi
}

# --- GNOME Settings handler -----------------------------------------------
#
# Launches gnome-control-center as an escape hatch for operators who
# need tweaks not covered by the first-boot menu (bluetooth pairing,
# display resolution, advanced accessibility, etc.).
#
# NOTE on the policy update: the earlier "avoid gnome-control-center
# at all cost" directive referred to RELYING on it for the core
# first-boot flows (WiFi / timezone / language). Those still go
# through direct nmcli / timedatectl / localectl via the zenity
# pickers — gnome-control-center is NEVER invoked from the Language,
# Wi-Fi, Timezone, Keyboard, Player, or CMS rows. It's only offered
# here as an optional ESCAPE HATCH under the Settings sub-menu for
# operators who need something the main rows don't expose.
handle_gnome_settings() {
    if command -v gnome-control-center >/dev/null 2>&1; then
        setsid gnome-control-center >/dev/null 2>&1 &
        disown 2>/dev/null || true
        zlib_notify "Opened GNOME Settings"
    else
        zenity --error --title="xiboplayer — GNOME Settings" --width=400 \
            --window-icon="$XIBO_LOGO" \
            --text="gnome-control-center is not installed on this system." 2>/dev/null
    fi
}

# --- Settings sub-menu ----------------------------------------------------
#
# Two-tier menu split per user directive 2026-04-12 "keep the needed
# things separated from the settings". The main menu holds first-boot
# essentials (Language / Keyboard / Wi-Fi / Timezone / Player / CMS).
# This sub-menu holds advanced and diagnostic actions that most
# operators won't need — Open Terminal, GNOME Settings, Debug, Back.
handle_settings() {
    while true; do
        local action
        action=$(zenity --list \
            --title="xiboplayer" \
            --window-icon="$XIBO_LOGO" \
            --text="$(zlib_brand_header "Settings")" \
            --ok-label="Open" \
            --cancel-label=" " \
            --column="id" --column="" \
            --hide-header \
            --hide-column=1 \
            --print-column=1 \
            --width=480 --height=320 \
            "terminal" "Open terminal" \
            "gnome"    "GNOME Settings" \
            "debug"    "Collect debug bundle" \
            "back"     "‹ Back" \
            2>/dev/null) || return 0

        case "$action" in
            terminal) handle_terminal ;;
            gnome)    handle_gnome_settings ;;
            debug)    handle_debug ;;
            back|'')  return 0 ;;
        esac
    done
}

# --- Welcome splash -------------------------------------------------------
#
# One-shot info prompt shown BEFORE the main menu on first boot. The
# branded "xiboplayer" name (blue `xibo` + white `player` Pango markup)
# is set in --text; the logo is the window icon. Per 2026-04-12 user
# direction plus the deferred Option C in the consolidated plan's
# "still pending" section.
welcome_splash() {
    zenity --info \
        --title="xiboplayer — First boot" \
        --window-icon="$XIBO_LOGO" \
        --width=560 \
        --text="$(zlib_brand_header "Welcome — this is the first boot of this kiosk — v${XIBO_KIOSK_VERSION} (${XIBO_KIOSK_BUILD_DATE})")

The next screen lets you configure:

  • Language and keyboard
  • Wi-Fi or wired network
  • Timezone
  • Player (Chromium or Electron)
  • CMS connection

Advanced and diagnostic actions (terminal, GNOME Settings, debug bundle)
live under the Settings row. When everything is ready, press Start to
launch the player.

Press OK to continue." \
        2>/dev/null || true
}

# --- main loop ------------------------------------------------------------
# The menu re-displays itself after each row completes, so the operator
# can configure Language → Wi-Fi → Timezone → ... → Done in one sitting.
# Auto-skip on 2-minute timeout (exit code 5) so a walkaway doesn't stall
# the kiosk forever.
#
# Menu structure — two tiers per user directive 2026-04-12 ("keep the
# needed things separated from the settings"):
#
#   Main menu (first-boot essentials):
#     Language  Keyboard  Wi-Fi  Timezone  Player  CMS  Settings  Done
#
#   Settings sub-menu (advanced / diagnostic):
#     Open Terminal  Collect debug info  Back
main_loop() {
    while true; do
        local wifi_status tz_status cms_status lang_status player_status kbd_status
        wifi_status=$(zlib_status_wifi)
        tz_status=$(zlib_status_tz)
        cms_status=$(zlib_status_cms)
        lang_status=$(zlib_status_locale)
        kbd_status=$(zlib_status_keyboard)
        player_status=$(zlib_status_player)

        local action
        action=$(zenity --list \
            --title="xiboplayer" \
            --window-icon="$XIBO_LOGO" \
            --text="$(zlib_brand_header "First boot setup — v${XIBO_KIOSK_VERSION}")" \
            --ok-label="Start" \
            --cancel-label=" " \
            --column="id" --column="" --column="" \
            --hide-header \
            --hide-column=1 \
            --print-column=1 \
            --width=560 --height=440 \
            --timeout=120 \
            "language" "Language"  "$lang_status" \
            "keyboard" "Keyboard" "$kbd_status" \
            "wifi"     "Wi-Fi"    "$wifi_status" \
            "timezone" "Timezone" "$tz_status" \
            "player"   "Player"   "$player_status" \
            "cms"      "CMS"      "$cms_status" \
            "settings" "Settings ›" "" \
            2>/dev/null)
        local rc=$?

        # Exit code 5 = timeout. Exit code 1 = cancel / close button.
        # In either case, fall through to "start player" so the kiosk
        # doesn't stall forever on walkaway.
        if [ $rc -eq 5 ] || [ $rc -eq 1 ]; then
            zlib_notify "First-boot menu dismissed, starting player"
            return 0
        fi

        # Empty action = user clicked Start without selecting a row →
        # start the player. This replaces the old "done" row.
        if [ -z "$action" ]; then
            zlib_notify "First-boot complete, starting player"
            return 0
        fi

        case "$action" in
            language) handle_language ;;
            keyboard) handle_keyboard ;;
            wifi)     handle_wifi ;;
            timezone) handle_timezone ;;
            player)   handle_player ;;
            cms)      handle_cms ;;
            settings) handle_settings ;;
            *)        return 0 ;;
        esac
    done
}

welcome_splash
main_loop

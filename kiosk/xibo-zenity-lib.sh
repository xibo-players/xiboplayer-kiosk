#!/bin/bash
# xibo-zenity-lib.sh — shared zenity + preseed helpers for xiboplayer-kiosk.
#
# Sourced by (not executed):
#   - kiosk/xibo-first-boot.sh  (#67 — the zenity main menu)
#   - kiosk/xibo-show-cms.sh    (existing Ctrl+R reconfigure, refactor TBD)
#
# Contains:
#   - Path constants: XIBO_KIOSK_DIR, XIBO_CONFIG_DIR, XIBO_DATA_DIR
#   - _preseed_get — extract a value from /etc/xiboplayer-preseed.env
#   - zlib_notify — notify-send wrapper with fallback to stderr
#   - zlib_status_wifi / zlib_status_tz / zlib_status_cms — live status one-liners
#   - zlib_cms_form — zenity --forms for URL/key/display-name
#   - zlib_write_chromium_config / zlib_write_electron_config — player config.json writers
#   - zlib_write_arexibo_cms_json — Arexibo cms.json writer (netinstall opt-in path)
#
# This file is sourced, not executed. It MUST NOT have any side effects
# at load time — only function definitions and `readonly` constants.
#
# The XIBO_KIOSK_DIR bootstrap: every sourcing script should set this
# before sourcing the lib, or rely on the default fallback below:
#   XIBO_KIOSK_DIR="${XIBO_KIOSK_DIR:-/usr/share/xiboplayer-kiosk}"

# --- constants ------------------------------------------------------------
# Self-bootstrapping defaults — if the caller hasn't set any of these, use
# the installed-system paths. Callers can override by exporting before
# sourcing the lib (e.g. unit tests set them to tmpdirs).
: "${XIBO_KIOSK_DIR:=/usr/share/xiboplayer-kiosk}"
: "${XIBO_CONFIG_DIR:=${HOME}/.config/xiboplayer}"
: "${XIBO_DATA_DIR:=${HOME}/.local/share/xibo}"
: "${XIBO_PRESEED_FILE:=/etc/xiboplayer-preseed.env}"

# --- _preseed_get ---------------------------------------------------------
# Extract a single key's value from the preseed env file. Never uses
# `source` — the env file may contain values that would misbehave under
# shell parsing (the #68 jq allowlist regex filters those out at write
# time, but this is defense in depth). Returns empty string if the file
# is missing or the key is absent. Callers check with [ -n "$value" ].
#
# Usage:
#   tz=$(_preseed_get "xibo.timezone")
#   cms=$(_preseed_get "xibo.cms_url")
_preseed_get() {
    [ -f "$XIBO_PRESEED_FILE" ] || { echo ""; return 0; }
    grep "^$1=" "$XIBO_PRESEED_FILE" 2>/dev/null | head -1 | cut -d= -f2-
}

# --- zlib_notify ----------------------------------------------------------
# notify-send wrapper. Uses the persistent-notification slot id=1 so
# successive calls REPLACE the previous notification rather than stacking.
# Falls back to stderr if notify-send is missing or dbus is unreachable
# (e.g. script invoked from ssh without a graphical session).
#
# Usage:
#   zlib_notify "Connecting to MyWiFi..."
#   zlib_notify "Timezone set to Europe/Madrid" normal
#   zlib_notify "Wi-Fi authentication failed" critical
zlib_notify() {
    local msg="$1"
    local urgency="${2:-normal}"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -r 1 -u "$urgency" -t 0 "Xibo" "$msg" 2>/dev/null && return 0
    fi
    echo "xibo: $msg" >&2
}

# --- status helpers -------------------------------------------------------
# Return a one-line human-readable status for the zenity main menu's
# "Status" column. Used by the status-aware --list that shows the
# current WiFi SSID, timezone, and CMS URL alongside each row.

zlib_status_wifi() {
    # Prefer active wifi connection name; fall back to "(wired)" or "(not connected)".
    local wifi
    wifi=$(nmcli -t -f NAME,TYPE,STATE conn show --active 2>/dev/null \
        | awk -F: '$2=="802-11-wireless" && $3=="activated" {print $1; exit}')
    if [ -n "$wifi" ]; then
        echo "$wifi"
        return 0
    fi
    if nmcli -t -f TYPE,STATE conn show --active 2>/dev/null \
        | grep -q '^802-3-ethernet:activated$'; then
        echo "(wired)"
        return 0
    fi
    echo "(not connected)"
}

zlib_status_tz() {
    timedatectl show -p Timezone --value 2>/dev/null || echo "(unknown)"
}

# Return the current player — "Chromium", "Electron", "Arexibo" or
# "(unknown)". Reads /etc/alternatives/xiboplayer which is the
# authoritative source (alternatives --set flips it via
# xibo-set-player.sh). Used by the Player row in the first-boot menu.
zlib_status_player() {
    local target
    target=$(readlink /etc/alternatives/xiboplayer 2>/dev/null) || {
        echo "(unknown)"
        return
    }
    case "$(basename "$target")" in
        xiboplayer-chromium) echo "Chromium" ;;
        xiboplayer-electron) echo "Electron" ;;
        arexibo)             echo "Arexibo" ;;
        *)                   echo "(unknown)" ;;
    esac
}

# Return the current X11 keyboard layout — the "Layout:" line from
# `localectl status`, e.g. "us", "es", "ch(fr)". Used by the Keyboard
# row in the first-boot menu. Falls back to reading
# /etc/X11/xorg.conf.d/00-keyboard.conf if localectl status is empty
# (which happens on freshly-installed systems before the first boot
# completes).
zlib_status_keyboard() {
    local layout variant
    layout=$(localectl status 2>/dev/null | awk -F: '/X11 Layout:/{gsub(/^ +/,"",$2); print $2; exit}')
    variant=$(localectl status 2>/dev/null | awk -F: '/X11 Variant:/{gsub(/^ +/,"",$2); print $2; exit}')
    if [ -z "$layout" ] && [ -r /etc/X11/xorg.conf.d/00-keyboard.conf ]; then
        layout=$(grep -oE '"XkbLayout" *"[^"]*"' /etc/X11/xorg.conf.d/00-keyboard.conf 2>/dev/null | sed -E 's/.*"([^"]*)".*/\1/')
        variant=$(grep -oE '"XkbVariant" *"[^"]*"' /etc/X11/xorg.conf.d/00-keyboard.conf 2>/dev/null | sed -E 's/.*"([^"]*)".*/\1/')
    fi
    [ -z "$layout" ] && layout="(unknown)"
    if [ -n "$variant" ]; then
        echo "${layout}(${variant})"
    else
        echo "$layout"
    fi
}

# Shared branding constants — the logo and the blue `xibo` + white
# `player` Pango markup for zenity --text. Per
# reference_xiboplayer_branding memory and BrandName.vue, the blue
# is #0097D8 (cyan) and `player` is white. The logo ships via the
# kiosk RPM.
XIBO_LOGO="${XIBO_KIOSK_DIR}/xiboplayer-kiosk-logo.png"

# zlib_brand <trailing text> — emit Pango markup with the branded
# name followed by optional trailing text. Example:
#   zlib_brand "— First boot setup"
# yields:
#   <span font_weight="bold" foreground="#0097D8">xibo</span><span font_weight="bold" foreground="#FFFFFF">player</span> — First boot setup
zlib_brand() {
    local trailing="$1"
    printf '<span font_weight="bold" foreground="#0097D8">xibo</span><span font_weight="bold" foreground="#FFFFFF">player</span>%s' "${trailing:+ $trailing}"
}

# Return the current system locale (LANG=) in the form en_US.UTF-8
# or "(unknown)" if it can't be read. Used by the Language row in
# the first-boot menu.
zlib_status_locale() {
    local lang
    lang=$(localectl status 2>/dev/null | awk -F= '/System Locale:.*LANG=/{gsub(/.*LANG=/,"",$0); gsub(/[[:space:]].*/,"",$0); print; exit}')
    if [ -z "$lang" ] && [ -r /etc/locale.conf ]; then
        lang=$(awk -F= '/^LANG=/ {gsub(/"/,"",$2); print $2; exit}' /etc/locale.conf)
    fi
    [ -z "$lang" ] && lang=$(printf '%s' "${LANG:-}" | cut -d: -f1)
    echo "${lang:-(unknown)}"
}

zlib_status_cms() {
    # CMS URL is player-specific — read from the config file of whichever
    # player is the current alternative. For Arexibo, it's cms.json.
    local player_config
    if [ -f "$XIBO_CONFIG_DIR/chromium/config.json" ]; then
        player_config="$XIBO_CONFIG_DIR/chromium/config.json"
    elif [ -f "$XIBO_CONFIG_DIR/electron/config.json" ]; then
        player_config="$XIBO_CONFIG_DIR/electron/config.json"
    fi
    if [ -n "$player_config" ]; then
        local url
        url=$(grep -oE '"cmsUrl"\s*:\s*"[^"]*"' "$player_config" 2>/dev/null \
            | head -1 | sed -E 's/.*"cmsUrl"\s*:\s*"([^"]*)".*/\1/')
        if [ -n "$url" ]; then
            echo "$url"
            return 0
        fi
    fi
    # Arexibo path
    if [ -f "$XIBO_DATA_DIR/cms.json" ]; then
        local url
        url=$(grep -oE '"address"\s*:\s*"[^"]*"' "$XIBO_DATA_DIR/cms.json" 2>/dev/null \
            | head -1 | sed -E 's/.*"address"\s*:\s*"([^"]*)".*/\1/')
        if [ -n "$url" ]; then
            echo "$url"
            return 0
        fi
    fi
    # Check the preseed env file for a pre-filled value
    local preset
    preset=$(_preseed_get "xibo.cms_url")
    if [ -n "$preset" ]; then
        echo "$preset (preseed)"
        return 0
    fi
    echo "(not configured)"
}

# --- zlib_cms_form --------------------------------------------------------
# Show a zenity --forms dialog for CMS URL, key, and display name.
# Pre-fills from the preseed env file if present. Writes the user's
# answers to the global variables CMS_URL, CMS_KEY, DISPLAY_NAME for
# the caller to consume. Returns 0 on OK, 1 on Cancel.
#
# Usage:
#   if zlib_cms_form; then
#       echo "Got: $CMS_URL / $CMS_KEY / $DISPLAY_NAME"
#   fi
zlib_cms_form() {
    local preset_url preset_key preset_name
    preset_url=$(_preseed_get "xibo.cms_url")
    preset_key=$(_preseed_get "xibo.cms_key")
    preset_name=$(_preseed_get "xibo.display_name")
    [ -z "$preset_url" ] && preset_url="https://"
    [ -z "$preset_name" ] && preset_name="$(hostname)"

    local result
    result=$(zenity --forms \
        --title="xiboplayer — CMS" \
        --text="Enter your Xibo CMS server details" \
        --add-entry="CMS Server URL" \
        --add-entry="CMS Key" \
        --add-entry="Display Name" \
        --separator="|" \
        --width=500 \
        2>/dev/null) || return 1

    # Split on the | separator. Guard against missing values.
    CMS_URL=$(echo "$result" | cut -d'|' -f1)
    CMS_KEY=$(echo "$result" | cut -d'|' -f2)
    DISPLAY_NAME=$(echo "$result" | cut -d'|' -f3)

    # If the user left a field blank and we have a preseed value, fall back
    [ -z "$CMS_URL" ] && CMS_URL="$preset_url"
    [ -z "$CMS_KEY" ] && CMS_KEY="$preset_key"
    [ -z "$DISPLAY_NAME" ] && DISPLAY_NAME="$preset_name"

    # Ensure URL ends with /
    [ -n "$CMS_URL" ] && [[ "$CMS_URL" != */ ]] && CMS_URL="${CMS_URL}/"
    return 0
}

# --- config writers -------------------------------------------------------

zlib_write_chromium_config() {
    local url="$1" key="$2" name="$3"
    local config_dir="$XIBO_CONFIG_DIR/chromium"
    mkdir -p "$config_dir"
    cat > "$config_dir/config.json" << EOF
{
    "cmsUrl": "$url",
    "cmsKey": "$key",
    "displayName": "$name"
}
EOF
}

zlib_write_electron_config() {
    local url="$1" key="$2" name="$3"
    local config_dir="$XIBO_CONFIG_DIR/electron"
    mkdir -p "$config_dir"
    cat > "$config_dir/config.json" << EOF
{
    "cmsUrl": "$url",
    "cmsKey": "$key",
    "displayName": "$name"
}
EOF
}

# Arexibo display_id is autogenerated via uuidgen. We do NOT derive it
# from /etc/machine-id or any other system identifier — the display is
# identified by its own hwKey that's stable across reboots but unique
# per kiosk install.
zlib_write_arexibo_cms_json() {
    local url="$1" key="$2" name="$3"
    local display_id
    display_id="xibo-$(uuidgen 2>/dev/null | tr -d - | cut -c1-12)"
    [ -z "$display_id" ] && display_id="xibo-$(hostname | tr -c '[:alnum:]' '_' | cut -c1-12)"
    mkdir -p "$XIBO_DATA_DIR"
    cat > "$XIBO_DATA_DIR/cms.json" << EOF
{
    "address": "$url",
    "key": "$key",
    "display_id": "$display_id",
    "display_name": "$name",
    "proxy": null
}
EOF
}

# --- zlib_write_player_config ---------------------------------------------
# Dispatches to the right writer based on the current player alternative.
# Reads setup-result.json (written by kickstart %post) to know which
# player is active. Falls back to Chromium if the file is missing.
zlib_write_player_config() {
    local url="$1" key="$2" name="$3"
    local player="Chromium"
    if [ -f "$XIBO_CONFIG_DIR/setup-result.json" ]; then
        player=$(python3 -c "import json; print(json.load(open('$XIBO_CONFIG_DIR/setup-result.json'))['player'])" 2>/dev/null)
        [ -z "$player" ] && player="Chromium"
    fi
    case "$player" in
        Electron)  zlib_write_electron_config "$url" "$key" "$name" ;;
        Arexibo)   zlib_write_arexibo_cms_json "$url" "$key" "$name" ;;
        *)         zlib_write_chromium_config "$url" "$key" "$name" ;;
    esac
}

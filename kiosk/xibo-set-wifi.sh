#!/bin/bash
# xibo-set-wifi.sh — NetworkManager keyfile writer for xiboplayer-kiosk.
#
# Usage:
#   xibo-set-wifi.sh <SSID> <password> [key-mgmt]
#
# Arguments:
#   SSID       — network name (exact, used as NM connection id)
#   password   — pre-shared key (empty string for open networks)
#   key-mgmt   — wpa-psk (default) | none (open network)
#
# Writes /etc/NetworkManager/system-connections/<safe-name>.nmconnection
# at mode 0600 root:root, then calls `nmcli connection reload` and
# `nmcli connection up`. The password is NEVER passed on an nmcli CLI
# argument, so it does not appear in /proc/<pid>/cmdline — closing the
# brief exposure window that `nmcli dev wifi connect … password …` has.
#
# Invoked via doas from the xibo user (see /etc/doas.conf), or directly
# as root from kickstart %post (no doas needed — already root there).
# Either way, the script must be owned root:root with mode 0755 and
# doas.conf must grant the xibo user the exact path.
#
# SECURITY: input validation rejects control characters (newline/tab/
# null) and NM INI section headers inside the SSID or PSK. Without
# this, a PSK containing e.g.
#   "password\n[wifi-security]\nkey-mgmt=none"
# could inject a fake INI section into the generated keyfile. Not an
# RCE (bash parameter expansion is single-pass, heredoc values are
# not re-parsed) but a format-injection risk. Fail closed with exit 2.
#
# The _validate_nm_string function below is the authoritative source
# of this validation. The same function is copied VERBATIM into
# kickstart/xibo-wifi-tui.sh (invoked by the pre-anaconda WiFi picker
# in issue #72) so both paths produce byte-identical NM keyfiles for
# the same input. bats test at tests/unit/set-wifi.bats (issue #74)
# enforces this identity.

set -e

SSID="$1"
PSK="$2"
KEYMGMT="${3:-wpa-psk}"

[ -z "$SSID" ] && { echo "xibo-set-wifi.sh: SSID required" >&2; exit 1; }

# --- input validation (authoritative source — see header) ---------------
_validate_nm_string() {
    local label="$1" value="$2"
    if printf '%s' "$value" | grep -qE $'[\x00-\x1f]'; then
        echo "xibo-set-wifi.sh: $label contains control characters (newline/tab/null) — rejected" >&2
        exit 2
    fi
    if printf '%s' "$value" | grep -qE '^\[|\[(connection|wifi|wifi-security|ipv4|ipv6)\]'; then
        echo "xibo-set-wifi.sh: $label contains an NM INI section header — rejected" >&2
        exit 2
    fi
}
_validate_nm_string "SSID" "$SSID"
[ -n "$PSK" ] && _validate_nm_string "PSK" "$PSK"

# --- filename sanitisation -------------------------------------------------
# NM connection `id=` accepts the raw SSID verbatim, but the keyfile
# filename must be safe (no slashes, quotes, etc.). Replace any non-
# alphanumeric + `._-` character with `_`. The `/` character is NOT in
# the allowed set so path-traversal attempts like `../../etc/passwd`
# become `______etc_passwd` — the resulting file lives safely inside
# /etc/NetworkManager/system-connections/ regardless of SSID content.
SAFE_NAME=$(printf '%s' "$SSID" | tr -c '[:alnum:]._-' '_')
KEYFILE="/etc/NetworkManager/system-connections/${SAFE_NAME}.nmconnection"
UUID=$(cat /proc/sys/kernel/random/uuid)

# --- delete any previous connection with the same id (idempotent re-run) --
# NM matches by connection id, not by filename, so we delete by $SSID.
if nmcli -t -f NAME con show 2>/dev/null | grep -Fxq "$SSID"; then
    nmcli con delete "$SSID" 2>/dev/null || true
fi

# --- write the keyfile ----------------------------------------------------
# umask ensures the file is created with no group/other perms; chmod
# below is belt-and-braces for the case where umask was lax.
umask 077
mkdir -p /etc/NetworkManager/system-connections

if [ "$KEYMGMT" = "none" ] || [ -z "$PSK" ]; then
    # Open network — no [wifi-security] section.
    cat > "$KEYFILE" << EOF
[connection]
id=$SSID
uuid=$UUID
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=$SSID

[ipv4]
method=auto

[ipv6]
method=ignore
EOF
else
    cat > "$KEYFILE" << EOF
[connection]
id=$SSID
uuid=$UUID
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=$SSID

[wifi-security]
key-mgmt=$KEYMGMT
psk=$PSK

[ipv4]
method=auto

[ipv6]
method=ignore
EOF
fi

chmod 600 "$KEYFILE"
chown root:root "$KEYFILE"

# --- activate -------------------------------------------------------------
# nmcli matches by connection id (the SSID), not by filename. Use the
# raw SSID here so SSIDs with special characters that got sanitised in
# the filename still work. `|| true` tolerates transient NM states
# during early boot.
nmcli connection reload 2>/dev/null || true
nmcli connection up "$SSID" 2>/dev/null || true

# --- persist SSID (never the PSK) to the preseed env file for visibility
# on Ctrl+R full-setup re-runs (issue #67). The preseed env file is
# written by kickstart %post at install time and may be updated here
# when the zenity menu writes a new connection at runtime. PSK is never
# recorded — the NM keyfile itself is the authoritative PSK store.
if [ -f /etc/xiboplayer-preseed.env ] || [ -w /etc ]; then
    sed -i '/^xibo\.wifi_ssid=/d' /etc/xiboplayer-preseed.env 2>/dev/null || true
    echo "xibo.wifi_ssid=$SSID" >> /etc/xiboplayer-preseed.env 2>/dev/null || true
fi

echo "xibo-set-wifi.sh: wrote $KEYFILE (id=$SSID)"

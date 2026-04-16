#!/bin/bash
# xibo-debug-dump.sh — support bundle collector for xiboplayer-kiosk.
#
# Usage:
#   xibo-debug-dump                    — write to $HOME/Downloads/
#   xibo-debug-dump [DEST_DIR]         — write to DEST_DIR/
#   xibo-debug-dump --to-usb           — write to a mounted USB labeled XIBO-DEBUG
#
# Creates a zstd-compressed tarball with logs, configs, hardware info,
# and networking state — enough for an MSP technician to diagnose a
# field incident without shell access to the kiosk. Sensitive values
# (CMS keys, Wi-Fi PSKs, basic-auth URL credentials) are redacted
# BEFORE the files go into the tarball. A post-tar security assertion
# refuses to ship the bundle if any known-sensitive path sneaks in
# (NetworkManager keyfiles containing cleartext PSKs, /etc/shadow,
# browser Cookies directories, etc).
#
# Triggers (per issue #70):
#   1. Ctrl+D via keyd — kiosk/keyd-xibo.conf binds Ctrl+D to this script
#   2. Zenity row — xibo-show-cms.sh and xibo-first-boot.sh both offer
#      a "Collect debug info" action that invokes this script
#   3. CLI — /usr/bin/xibo-debug-dump symlink created by the rpm spec
#   4. Labeled USB — plug in a USB stick with filesystem label
#      XIBO-DEBUG, the udev rule (if/when installed) fires this script
#      with --to-usb and the tarball lands on the stick
#
# Output filename:
#   xibo-debug-<hostname>-<timestamp>.tar.zst
#
# The script is deliberately conservative — every external command is
# run with `|| true` or inside an `if … then` check so a transient
# failure on one data source (e.g. nmcli not responding) never aborts
# the whole collection. The goal is "something useful even if partial".

set -u
# Note: deliberately NOT `set -e`. Partial bundles are useful; aborting
# on first error is not. Each collection step handles its own failure.

XIBO_DATA_DIR="${XIBO_DATA_DIR:-$HOME/.local/share/xibo}"
XIBO_CONFIG_DIR="${XIBO_CONFIG_DIR:-$HOME/.config/xiboplayer}"

# --- destination ----------------------------------------------------------
DEST=""
if [ "${1:-}" = "--to-usb" ]; then
    # Find the first mounted filesystem with label XIBO-DEBUG.
    # findmnt is more reliable than parsing /proc/mounts by hand.
    DEST=$(findmnt -n -o TARGET -S LABEL=XIBO-DEBUG 2>/dev/null | head -1)
    if [ -z "$DEST" ]; then
        echo "xibo-debug-dump: no mounted USB labeled XIBO-DEBUG found" >&2
        notify-send -u critical "Xibo debug dump" "No USB labeled XIBO-DEBUG found" 2>/dev/null || true
        exit 3
    fi
elif [ -n "${1:-}" ]; then
    DEST="$1"
else
    DEST="$HOME/Downloads"
fi

mkdir -p "$DEST" 2>/dev/null || {
    echo "xibo-debug-dump: cannot create destination $DEST" >&2
    exit 4
}

HOSTNAME_SAFE=$(hostname 2>/dev/null | tr -c '[:alnum:]._-' '_')
[ -z "$HOSTNAME_SAFE" ] && HOSTNAME_SAFE="kiosk"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TARBALL="$DEST/xibo-debug-${HOSTNAME_SAFE}-${TIMESTAMP}.tar.zst"

# --- staging dir under /var/tmp (not /tmp) so it survives reboot ---------
STAGE=$(mktemp -d -t xibo-debug-XXXXXX)
trap 'rm -rf "$STAGE"' EXIT INT TERM

echo "xibo-debug-dump: collecting to $STAGE (will tar into $TARBALL)"

# --- redaction helpers ---------------------------------------------------
# Replace CMS keys, Wi-Fi PSKs, and basic-auth URL credentials with ***.
# Used on any captured text that might contain secrets. Conservative —
# prefers over-redaction to leaking. Applied per-file as files are staged.
_redact() {
    # Reads stdin, writes redacted output to stdout.
    # 1. xibo.cms_key=VALUE → xibo.cms_key=***
    # 2. xibo.wifi_psk=VALUE → xibo.wifi_psk=***
    # 3. xibo.config_url=https://USER:PASS@host/... → strip credentials
    # 4. "cmsKey": "VALUE" in JSON → "cmsKey": "***"
    # 5. "key": "VALUE" in cms.json → "key": "***"
    sed -E \
        -e 's|(xibo\.cms_key=)[^ ]*|\1***|g' \
        -e 's|(xibo\.wifi_psk=)[^ ]*|\1***|g' \
        -e 's|(xibo\.config_url=https?://)[^@ ]+@|\1***:***@|g' \
        -e 's|("cmsKey"[[:space:]]*:[[:space:]]*")[^"]*|\1***|g' \
        -e 's|("key"[[:space:]]*:[[:space:]]*")[^"]*|\1***|g'
}

# --- collect ---------------------------------------------------------------

# 1. System identity + OS release
{
    echo "=== hostname ==="; hostname 2>/dev/null || :
    echo
    echo "=== /etc/os-release ==="; cat /etc/os-release 2>/dev/null || :
    echo
    echo "=== uname -a ==="; uname -a 2>/dev/null || :
    echo
    echo "=== uptime ==="; uptime 2>/dev/null || :
    echo
    echo "=== date ==="; date 2>/dev/null || :
} > "$STAGE/00-system.txt" 2>/dev/null || :

# 2. /proc/cmdline (redacted — secrets leak here)
cat /proc/cmdline 2>/dev/null | _redact > "$STAGE/01-proc-cmdline.txt" || :

# 3. Installed xibo/arexibo packages
{
    rpm -qa 2>/dev/null | grep -E 'xibo|arexibo' || :
    echo
    echo "=== full rpm list (top 50) ==="
    rpm -qa 2>/dev/null | sort | head -50 || :
} > "$STAGE/02-packages.txt" 2>/dev/null || :

# 4. Preseed env file (redacted)
if [ -f /etc/xiboplayer-preseed.env ]; then
    _redact < /etc/xiboplayer-preseed.env > "$STAGE/03-preseed.env.txt" 2>/dev/null || :
fi

# 5. Player configs (redacted)
for f in "$XIBO_CONFIG_DIR/chromium/config.json" \
         "$XIBO_CONFIG_DIR/electron/config.json" \
         "$XIBO_CONFIG_DIR/setup-result.json" \
         "$XIBO_DATA_DIR/cms.json"; do
    [ -f "$f" ] || continue
    name=$(echo "$f" | tr '/' '_' | sed 's/^_//')
    _redact < "$f" > "$STAGE/04-${name}.txt" 2>/dev/null || :
done

# 6. Systemd — user services
{
    echo "=== systemctl --user status xiboplayer-*.service arexibo.service ==="
    systemctl --user status xiboplayer-electron.service xiboplayer-chromium.service arexibo.service --no-pager 2>/dev/null || :
    echo
    echo "=== systemctl --user is-enabled ==="
    for svc in xiboplayer-electron xiboplayer-chromium arexibo gnome-kiosk-script; do
        echo -n "$svc: "
        systemctl --user is-enabled "$svc" 2>/dev/null || echo "not-found"
    done
} > "$STAGE/05-systemd-user.txt" 2>/dev/null || :

# 7. Systemd — system services relevant to kiosk
{
    echo "=== systemctl status (system) ==="
    systemctl status gdm avahi-daemon keyd sshd NetworkManager --no-pager 2>/dev/null || :
    echo
    echo "=== systemctl is-enabled ==="
    for svc in gdm avahi-daemon keyd sshd NetworkManager xiboplayer-kiosk-firstboot; do
        echo -n "$svc: "
        systemctl is-enabled "$svc" 2>/dev/null || echo "not-found"
    done
} > "$STAGE/06-systemd-system.txt" 2>/dev/null || :

# 8. journalctl — user scope (player logs)
journalctl --user -b --no-pager 2>/dev/null | _redact > "$STAGE/07-journal-user.txt" 2>/dev/null || :

# 9. journalctl — kernel
journalctl -b -k --no-pager > "$STAGE/08-journal-kernel.txt" 2>/dev/null || :

# 10. journalctl — boot services (gdm, avahi, keyd, NetworkManager)
journalctl -b -u gdm -u avahi-daemon -u keyd -u NetworkManager --no-pager 2>/dev/null | _redact > "$STAGE/09-journal-services.txt" 2>/dev/null || :

# 11. Hardware inventory
{
    echo "=== lscpu ==="; lscpu 2>/dev/null || :
    echo
    echo "=== free -h ==="; free -h 2>/dev/null || :
    echo
    echo "=== df -h ==="; df -h 2>/dev/null || :
    echo
    echo "=== lsblk -f ==="; lsblk -f 2>/dev/null || :
    echo
    echo "=== lspci -nnk ==="; lspci -nnk 2>/dev/null || :
    echo
    echo "=== lsusb ==="; lsusb 2>/dev/null || :
} > "$STAGE/10-hardware.txt" 2>/dev/null || :

# 12. Display / GPU / Wayland
{
    echo "=== loginctl show-user xibo ==="
    loginctl show-user xibo 2>/dev/null || :
    echo
    echo "=== glxinfo -B (subset) ==="
    glxinfo -B 2>/dev/null | head -20 || :
    echo
    echo "=== /sys/class/drm/ ==="
    ls -la /sys/class/drm/ 2>/dev/null | head -20 || :
} > "$STAGE/11-display.txt" 2>/dev/null || :

# 13. NetworkManager state (NO PSKs — keyfiles are explicitly excluded below)
{
    echo "=== nmcli -t -f NAME,TYPE,DEVICE,STATE con show ==="
    nmcli -t -f NAME,TYPE,DEVICE,STATE con show 2>/dev/null || :
    echo
    echo "=== nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev status ==="
    nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev status 2>/dev/null || :
    echo
    echo "=== nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list ==="
    nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list 2>/dev/null || :
    echo
    echo "=== ip -4 addr ==="
    ip -4 addr 2>/dev/null || :
    echo
    echo "=== ip -6 addr ==="
    ip -6 addr 2>/dev/null || :
    echo
    echo "=== ip route ==="
    ip route 2>/dev/null || :
    echo
    echo "=== resolvectl status (short) ==="
    resolvectl status 2>/dev/null | head -30 || :
} > "$STAGE/12-network.txt" 2>/dev/null || :

# 14. Time + locale
{
    echo "=== timedatectl status ==="; timedatectl status 2>/dev/null || :
    echo
    echo "=== localectl status ==="; localectl status 2>/dev/null || :
} > "$STAGE/13-time-locale.txt" 2>/dev/null || :

# 15. Kiosk-specific state
{
    echo "=== /etc/xiboplayer-kiosk-firstboot-done ==="
    ls -la /var/lib/xiboplayer-kiosk-firstboot-done 2>/dev/null || echo "not present"
    echo
    echo "=== XIBO_DATA_DIR first-boot-done ==="
    ls -la "$XIBO_DATA_DIR/first-boot-done" 2>/dev/null || echo "not present"
    echo
    echo "=== alternatives --display xiboplayer ==="
    alternatives --display xiboplayer 2>/dev/null || :
    echo
    echo "=== /etc/systemd/logind.conf.d/no-idle.conf ==="
    cat /etc/systemd/logind.conf.d/no-idle.conf 2>/dev/null || echo "not present"
    echo
    echo "=== /etc/dconf/profile/gdm ==="
    cat /etc/dconf/profile/gdm 2>/dev/null || echo "not present"
} > "$STAGE/14-kiosk-state.txt" 2>/dev/null || :

# --- build the tarball ---------------------------------------------------
# zstd is fast and gives good ratios for mixed text. -19 is too slow for
# a kiosk; default level is fine.
if command -v zstd >/dev/null 2>&1; then
    tar -C "$STAGE" --zstd -cf "$TARBALL" . 2>/dev/null
else
    # Fall back to gz if zstd is somehow missing (shouldn't happen — it's in
    # systemd's base deps). Rename the output accordingly.
    TARBALL="${TARBALL%.zst}.gz"
    tar -C "$STAGE" -czf "$TARBALL" . 2>/dev/null
fi

if [ ! -f "$TARBALL" ]; then
    echo "xibo-debug-dump: ERROR — tarball creation failed" >&2
    exit 5
fi

# --- SECURITY assertion — refuse to ship if a sensitive path snuck in ---
# This is belt-and-braces: the script deliberately does NOT stage any of
# these paths, but if a future maintainer adds a broad wildcard or forgets
# to redact, this assertion catches it before the user sees the tarball.
SENSITIVE_PATTERNS='NetworkManager/system-connections|/shadow$|/gshadow$|/Cookies|doas\.conf$|/\.ssh/id_'
if tar --zstd -tf "$TARBALL" 2>/dev/null | grep -qE "$SENSITIVE_PATTERNS"; then
    echo "xibo-debug-dump: SECURITY — sensitive path detected in tarball, refusing to ship" >&2
    echo "xibo-debug-dump: offending paths:" >&2
    tar --zstd -tf "$TARBALL" 2>/dev/null | grep -E "$SENSITIVE_PATTERNS" >&2 || :
    rm -f "$TARBALL"
    notify-send -u critical "Xibo debug dump" "Aborted — sensitive path detected" 2>/dev/null || true
    exit 10
fi

SIZE=$(du -h "$TARBALL" 2>/dev/null | cut -f1)
echo "xibo-debug-dump: wrote $TARBALL ($SIZE)"

# --- notify the user ------------------------------------------------------
# notify-send reaches dunst if we're in the xibo kiosk session. Always
# print to stderr as well in case this script is run from a non-graphical
# context (e.g. SSH or a systemd unit with no DISPLAY).
if command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical -t 15000 "Xibo debug dump" \
        "$TARBALL ($SIZE)
Copy to USB or email to support." 2>/dev/null || true
fi

# Also show zenity dialog if we're in a graphical session and zenity is
# available. Skip silently if not — the notify-send above is enough.
if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v zenity >/dev/null 2>&1; then
    zenity --info --title="Xibo debug dump" --width=500 \
        --text="Debug bundle created:

$TARBALL ($SIZE)

Copy to a USB stick or email to support.
Sensitive values (CMS keys, Wi-Fi passwords) have been redacted." \
        2>/dev/null || true
fi

echo "xibo-debug-dump: done"
exit 0

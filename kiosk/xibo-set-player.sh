#!/bin/bash
# xibo-set-player.sh — validated doas helper for switching between
# xiboplayer-chromium and xiboplayer-electron.
#
# Usage:
#   xibo-set-player.sh chromium
#   xibo-set-player.sh electron
#
# Scope:
#   - Updates `alternatives` so /usr/bin/xiboplayer → chosen player
#   - Rewrites /home/xibo/.config/xiboplayer/setup-result.json with the
#     new player + service names (this is the file that
#     gnome-kiosk-script.xibo.sh reads to decide which service to
#     start on session login)
#   - Stops any running xiboplayer-* user service so the new one takes
#     over on the next session start — operator reboots or logs out to
#     actually switch, which matches the deliberately-minimal scope
#     (no session-killing inside the helper)
#
# Deliberately excludes arexibo — arexibo is netinstall opt-in only per
# 0.4.30 scope (#71), so the interactive picker only offers the two
# players that are shipped in every ISO variant.
#
# Invoked via doas from the xibo user — the matching rule lives in
# /etc/doas.conf (`permit nopass xibo cmd
# /usr/share/xiboplayer-kiosk/xibo-set-player.sh`). Argument is
# validated against a fixed allowlist to prevent injection.
#
# Closes #96

set -e

PLAYER_ARG="${1:-}"

case "$PLAYER_ARG" in
    chromium)
        PLAYER_BIN=/usr/bin/xiboplayer-chromium
        PLAYER_NAME="Chromium"
        PLAYER_SERVICE=xiboplayer-chromium.service
        ;;
    electron)
        PLAYER_BIN=/usr/bin/xiboplayer-electron
        PLAYER_NAME="Electron"
        PLAYER_SERVICE=xiboplayer-electron.service
        ;;
    *)
        echo "xibo-set-player.sh: usage: xibo-set-player.sh chromium|electron" >&2
        exit 1
        ;;
esac

# Validate the binary actually exists. Guards against a chromium-or-
# electron-less image (e.g. a hypothetical slim build) invoking this
# helper with the wrong name.
if [ ! -x "$PLAYER_BIN" ]; then
    echo "xibo-set-player.sh: $PLAYER_BIN not installed — cannot switch" >&2
    exit 2
fi

# Switch the system-wide alternative
alternatives --set xiboplayer "$PLAYER_BIN"

# Rewrite the per-user setup-result.json so gnome-kiosk-script.xibo.sh
# picks the new service on next session. Match the schema used by
# gnome-kiosk-script.xibo-init.sh: {"player": "<Capitalized>",
# "service": "xiboplayer-<lower>.service"}
XIBO_HOME=/home/xibo
XIBO_CONFIG_DIR="$XIBO_HOME/.config/xiboplayer"
mkdir -p "$XIBO_CONFIG_DIR"
cat > "$XIBO_CONFIG_DIR/setup-result.json" << EOF
{"player": "$PLAYER_NAME", "service": "$PLAYER_SERVICE"}
EOF
chown -R xibo:xibo "$XIBO_CONFIG_DIR"
chmod 644 "$XIBO_CONFIG_DIR/setup-result.json"

# Stop any currently-running player services so the new one starts
# fresh. Both services run in the xibo user's systemd instance; loop
# over both names defensively so we don't need to know which one is
# active right now.
for svc in xiboplayer-chromium.service xiboplayer-electron.service; do
    runuser -u xibo -- systemctl --user stop "$svc" 2>/dev/null || true
done

echo "xibo-set-player.sh: switched to $PLAYER_NAME ($PLAYER_SERVICE)"

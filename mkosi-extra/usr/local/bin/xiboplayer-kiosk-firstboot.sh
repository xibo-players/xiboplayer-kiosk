#!/bin/bash
# Xibo Kiosk first-boot — minimal runtime setup
# Most config is baked into the image via sysusers.d + tmpfiles.d.
# This only handles what needs a running system:
# - Password (can't be set declaratively in a public image)
# - Lingering (loginctl needs running systemd)

set -e

MARKER="/var/lib/xiboplayer-kiosk-firstboot-done"
[ -f "$MARKER" ] && exit 0

echo "xibo:xibo" | chpasswd
loginctl enable-linger xibo 2>/dev/null || true

# Install setup wizard autostart for first boot (normal GNOME session)
AUTOSTART_DIR="/home/xibo/.config/autostart"
mkdir -p "$AUTOSTART_DIR"
cp /usr/share/xiboplayer-kiosk/xiboplayer-setup.desktop "$AUTOSTART_DIR/"
chown -R xibo:xibo /home/xibo/.config

touch "$MARKER"
echo "Xibo Kiosk first-boot complete"

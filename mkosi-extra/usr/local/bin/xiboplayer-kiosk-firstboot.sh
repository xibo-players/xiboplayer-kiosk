#!/bin/bash
# Xibo Kiosk first-boot setup script
# Runs once on first boot to set password and configure the system

set -e

MARKER="/var/lib/xiboplayer-kiosk-firstboot-done"

# Check if already run
[ -f "$MARKER" ] && exit 0

echo "Xibo Kiosk first-boot setup starting..."

# Set xibo password (user created by sysusers)
echo "xibo:xibo" | chpasswd

# Fix ownership of home directory
chown -R xibo:xibo /home/xibo

# Set permissions on scripts
chmod 755 /home/xibo/.local/bin/*.sh 2>/dev/null || true
chmod 755 /home/xibo/.local/bin/gnome-kiosk-script 2>/dev/null || true

# Mark as complete
touch "$MARKER"
echo "Xibo Kiosk first-boot setup complete"

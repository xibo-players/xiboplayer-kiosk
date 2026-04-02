#!/bin/bash
# Show IP address, CMS and player status via dunst notification.
# Triggered by Ctrl+I (via keyd).
XIBO_DATA_DIR="${XIBO_DATA_DIR:-${HOME}/.local/share/xibo}"
IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
# Check all player services, report whichever is active
STATUS="unknown"
for svc in arexibo.service xiboplayer-electron.service xiboplayer-chromium.service; do
  s=$(systemctl --user is-active "$svc" 2>/dev/null)
  if [ "$s" = "active" ]; then STATUS="active ($svc)"; break; fi
done
CMS=$(grep -oP '"address"\s*:\s*"\K[^"]+' "${XIBO_DATA_DIR}/cms.json" 2>/dev/null || echo "not configured")
PLAYER=$(basename "$(readlink /etc/alternatives/xiboplayer 2>/dev/null)" 2>/dev/null || echo "unknown")
notify-send -t 5000 "Xibo Status" "IP: $IP\nCMS: $CMS\nPlayer: $PLAYER\nStatus: $STATUS"

#!/bin/bash
# Xibo Kiosk Dispatcher
# =====================
# Dispatches to the registration wizard or session holder based on
# whether cms.json exists. This script is installed as the GNOME Kiosk
# session script (gnome-kiosk-script in $PATH).

XIBO_KIOSK_DIR="${XIBO_KIOSK_DIR:-/usr/share/xibo-kiosk}"
XIBO_DATA_DIR="${XIBO_DATA_DIR:-${HOME}/.local/share/xibo}"

if [ -f "${XIBO_DATA_DIR}/cms.json" ]; then
    exec "${XIBO_KIOSK_DIR}/gnome-kiosk-script.xibo.sh"
else
    exec "${XIBO_KIOSK_DIR}/gnome-kiosk-script.xibo-init.sh"
fi

#!/bin/bash
# Run a command in the kiosk user's graphical session.
# Called by keyd (which runs as root) to bridge into the user session.
#
# The previous version only exported XDG_RUNTIME_DIR and
# DBUS_SESSION_BUS_ADDRESS. That's enough for zenity (which auto-
# discovers the Wayland compositor via the portal / DBus), but NOT
# enough for gnome-terminal and other GUI binaries that expect
# WAYLAND_DISPLAY / DISPLAY / GDK_BACKEND to be set explicitly.
# Without those, gnome-terminal silently exits and the operator
# sees "nothing happens" on Ctrl+S.
#
# This version inherits every GUI-related env var from the user's
# systemd --user instance (where gnome-kiosk-script.xibo.sh imported
# them at session start via `systemctl --user import-environment`).

set -e

KIOSK_USER=$(who | awk 'NR==1{print $1}')
[ -z "$KIOSK_USER" ] && KIOSK_USER=xibo
[ -z "$KIOSK_USER" ] && exit 1

KIOSK_UID=$(id -u "$KIOSK_USER")
XDG_RUNTIME_DIR="/run/user/${KIOSK_UID}"

# Pull the user's systemd environment. Each line is KEY=VALUE; we
# extract only the GUI-relevant variables below. Run the fetch via
# runuser so systemctl --user can find the right instance.
USER_ENV=$(runuser -u "$KIOSK_USER" -- env \
    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus" \
    systemctl --user show-environment 2>/dev/null || true)

# Extract and forward the GUI-related subset. XDG_RUNTIME_DIR and
# DBUS_SESSION_BUS_ADDRESS are always set from the UID; the rest
# come from the user systemd env, with WAYLAND_DISPLAY falling
# back to wayland-0 if the lookup failed (e.g. session not fully
# imported yet).
declare -a ENV_ARGS=(
    "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
    "DBUS_SESSION_BUS_ADDRESS=unix:path=${XDG_RUNTIME_DIR}/bus"
)
for var in WAYLAND_DISPLAY DISPLAY GDK_BACKEND QT_QPA_PLATFORM \
           XDG_SESSION_TYPE XDG_CURRENT_DESKTOP XCURSOR_THEME XCURSOR_SIZE; do
    val=$(printf '%s\n' "$USER_ENV" | grep -m1 "^${var}=" | cut -d= -f2-)
    [ -n "$val" ] && ENV_ARGS+=("${var}=${val}")
done
# Fallback — typical GNOME Wayland sessions use wayland-0 as the
# socket name in $XDG_RUNTIME_DIR/wayland-0.
if ! printf '%s\n' "${ENV_ARGS[@]}" | grep -q '^WAYLAND_DISPLAY='; then
    ENV_ARGS+=("WAYLAND_DISPLAY=wayland-0")
fi

exec runuser -u "$KIOSK_USER" -- env "${ENV_ARGS[@]}" "$@"

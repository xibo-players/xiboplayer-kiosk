#!/bin/bash
# xibo-keyd-open-terminal.sh — launch the first available terminal emulator.
#
# Invoked by keyd via xibo-keyd-run.sh (which sets XDG_RUNTIME_DIR /
# DBUS_SESSION_BUS_ADDRESS / WAYLAND_DISPLAY / etc. for the xibo user's
# session before exec'ing this script).
#
# Preference order mirrors handle_terminal() in xibo-first-boot.sh:
#   1. ptyxis          — Fedora 43's modern GNOME Console successor (default)
#   2. kgx             — legacy GNOME Console
#   3. gnome-terminal  — traditional GNOME Terminal (deprecated)
#   4. xterm           — last-ditch fallback
#
# Using a wrapper script (instead of a hardcoded binary path in
# keyd-xibo.conf) avoids breakage when the default terminal changes
# between Fedora releases. The keyd binding just points at this
# wrapper and the wrapper picks the best available option at runtime.

for candidate in ptyxis kgx gnome-terminal xterm; do
    if command -v "$candidate" >/dev/null 2>&1; then
        exec "$candidate"
    fi
done

# None found — emit a zenity error. This runs via the same env that
# the wrapper set up, so zenity reaches the compositor correctly.
zenity --error --title="xiboplayer — Terminal" --width=400 \
    --text="No terminal emulator installed (tried ptyxis, kgx, gnome-terminal, xterm)." 2>/dev/null
exit 1

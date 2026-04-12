#!/bin/bash
# xibo-set-keyboard.sh — validated doas helper for setting the X11 keyboard layout.
#
# Usage:
#   xibo-set-keyboard.sh <layout>         # e.g. us, es, fr, de, gb
#   xibo-set-keyboard.sh 'ch(fr)'         # variant syntax accepted
#
# Invoked via doas from the xibo user. Replaces the blanket
# 'permit nopass xibo cmd localectl' permit with a narrower helper
# that validates the argument against `localectl list-x11-keymap-layouts`
# before invoking the real `localectl set-x11-keymap` command.
#
# Matches the security pattern of xibo-set-locale.sh and
# xibo-set-timezone.sh — validate against the authoritative system
# catalog, fail closed on anything that isn't a real layout.
#
# Ships with #94's Keyboard row in the first-boot menu.

set -e

LAYOUT_ARG="${1:-}"

if [ -z "$LAYOUT_ARG" ]; then
    echo "xibo-set-keyboard.sh: usage: xibo-set-keyboard.sh <layout>" >&2
    echo "xibo-set-keyboard.sh: hint — common layouts: us, gb, es, fr, de, it, pt, br" >&2
    exit 1
fi

# Split variant if the layout is in the form 'base(variant)'. localectl
# set-x11-keymap takes the base and the variant as separate args:
#   localectl set-x11-keymap <base> '' <variant>
BASE_LAYOUT="${LAYOUT_ARG%%(*}"
VARIANT=""
if [[ "$LAYOUT_ARG" =~ \((.+)\)$ ]]; then
    VARIANT="${BASH_REMATCH[1]}"
fi

# Validate the base layout against the authoritative list.
if ! localectl list-x11-keymap-layouts 2>/dev/null | grep -Fxq "$BASE_LAYOUT"; then
    echo "xibo-set-keyboard.sh: '$BASE_LAYOUT' is not a valid X11 keymap layout — rejected" >&2
    exit 2
fi

# Validate the variant (if present) against the list for this layout.
# localectl list-x11-keymap-variants <layout> returns the variants; if
# the variant isn't in that list we reject it.
if [ -n "$VARIANT" ]; then
    if ! localectl list-x11-keymap-variants "$BASE_LAYOUT" 2>/dev/null | grep -Fxq "$VARIANT"; then
        echo "xibo-set-keyboard.sh: variant '$VARIANT' is not valid for layout '$BASE_LAYOUT' — rejected" >&2
        exit 3
    fi
fi

# Apply. Empty model string is fine — localectl keeps the current model.
localectl set-x11-keymap "$BASE_LAYOUT" "" "$VARIANT"

if [ -n "$VARIANT" ]; then
    echo "xibo-set-keyboard.sh: X11 keyboard set to ${BASE_LAYOUT}(${VARIANT})"
else
    echo "xibo-set-keyboard.sh: X11 keyboard set to ${BASE_LAYOUT}"
fi

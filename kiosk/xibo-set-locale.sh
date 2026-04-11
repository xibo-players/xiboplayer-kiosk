#!/bin/bash
# xibo-set-locale.sh — validated doas helper for setting the system locale.
#
# Usage:
#   xibo-set-locale.sh <locale>         # e.g. en_US.UTF-8
#
# Invoked via doas from the xibo user. Replaces the blanket
# 'permit nopass xibo cmd localectl' permit with a narrower helper
# that validates the argument against 'localectl list-locales' before
# invoking the real command.
#
# Paired with xibo-set-timezone.sh — both exist for the same Phase
# 6-quinquies security reason: the blanket localectl permit would let
# a compromised xibo-user process run 'doas localectl set-locale
# LANG=…' with arbitrary arguments, potentially including locale
# injection (the LANG value is passed through to glibc and various
# GNOME apps that read it with minimal validation).

set -e

LOCALE_ARG="${1:-}"

if [ -z "$LOCALE_ARG" ]; then
    echo "xibo-set-locale.sh: usage: xibo-set-locale.sh <locale>" >&2
    exit 1
fi

# Validate against the real locale list. Fail closed on anything that
# isn't in 'localectl list-locales'.
if ! localectl list-locales 2>/dev/null | grep -Fxq "$LOCALE_ARG"; then
    echo "xibo-set-locale.sh: '$LOCALE_ARG' is not a valid locale — rejected" >&2
    echo "xibo-set-locale.sh: hint — common values: en_US.UTF-8, en_GB.UTF-8, es_ES.UTF-8, ca_ES.UTF-8, fr_FR.UTF-8, de_DE.UTF-8" >&2
    exit 2
fi

localectl set-locale "LANG=$LOCALE_ARG"

echo "xibo-set-locale.sh: locale set to LANG=$LOCALE_ARG"

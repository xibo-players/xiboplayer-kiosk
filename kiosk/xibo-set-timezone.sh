#!/bin/bash
# xibo-set-timezone.sh — validated doas helper for setting the system timezone.
#
# Usage:
#   xibo-set-timezone.sh <IANA-zone>
#
# Invoked via doas from the xibo user. Replaces the blanket
# 'permit nopass xibo cmd timedatectl' permit with a narrower helper
# that validates the argument against 'timedatectl list-timezones'
# before invoking the real command.
#
# Why the narrowing matters (Phase 6-quinquies security hardening):
#
#   The blanket 'doas timedatectl' permit let a compromised xibo-user
#   process run 'doas timedatectl set-time 2020-01-01' to roll the
#   system clock backwards and bypass TLS certificate validity for
#   attacker-controlled CMS servers. By wrapping it in a helper that
#   only accepts 'set-timezone' with a validated argument, we remove
#   the set-time attack surface entirely — there's no way to reach
#   timedatectl set-time from this script.
#
# Also enables NTP as a side effect — drift correction is expected
# on a kiosk that's set a fresh timezone, and 'timedatectl set-ntp
# true' is idempotent.

set -e

TZ_ARG="${1:-}"

if [ -z "$TZ_ARG" ]; then
    echo "xibo-set-timezone.sh: usage: xibo-set-timezone.sh <IANA-zone>" >&2
    exit 1
fi

# Validate against the real timezone list. This is the security gate —
# if the caller passes e.g. '; rm -rf /' or 'set-time 2020-01-01', the
# string won't match any line in 'timedatectl list-timezones' and we
# fail closed.
if ! timedatectl list-timezones 2>/dev/null | grep -Fxq "$TZ_ARG"; then
    echo "xibo-set-timezone.sh: '$TZ_ARG' is not a valid IANA timezone — rejected" >&2
    exit 2
fi

# Apply. set-ntp is belt-and-braces — usually already on, but if the
# kiosk had NTP disabled for some reason, re-enabling it after a TZ
# change avoids clock drift showing stale layouts.
timedatectl set-timezone "$TZ_ARG"
timedatectl set-ntp true 2>/dev/null || true

echo "xibo-set-timezone.sh: timezone set to $TZ_ARG"

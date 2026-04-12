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

# Also infer a sensible X11 keyboard layout from the locale (#94). Picking
# a language without getting the matching keyboard leaves operators typing
# their Wi-Fi password, CMS URL, etc. on US-QWERTY, which is the bug the
# keyboard half of #94 was meant to fix.
#
# The mapping below is a "good default", not a curated gate — the Keyboard
# row in the first-boot menu lets the operator override with ANY layout
# from `localectl list-x11-keymap-layouts` via xibo-set-keyboard.sh. So
# if a Dutch operator on a Belgian kiosk disagrees with the nl_BE → be
# default, they pick `us` (or whatever) via the Keyboard row.
infer_x11_layout() {
    case "$1" in
        en_US*|en_CA*|en_AU*|en_NZ*|en_IN*|en_PH*|en_SG*|en_ZA*) echo us ;;
        en_GB*|en_IE*)       echo gb ;;
        en_*)                echo us ;;
        es_MX*|es_AR*|es_CL*|es_CO*|es_PE*|es_UY*|es_VE*|es_BO*|es_EC*|es_PY*|es_GT*|es_HN*|es_NI*|es_CR*|es_PA*|es_DO*|es_SV*|es_PR*|es_CU*) echo latam ;;
        es_*)                echo es ;;
        ca_*)                echo es ;;
        eu_*)                echo es ;;
        gl_*)                echo es ;;
        fr_CA*)              echo ca ;;
        fr_BE*)              echo be ;;
        fr_CH*)              echo 'ch(fr)' ;;
        fr_*)                echo fr ;;
        de_CH*)              echo 'ch(de)' ;;
        de_*)                echo de ;;
        pt_BR*)              echo br ;;
        pt_*)                echo pt ;;
        it_*)                echo it ;;
        nl_BE*)              echo be ;;
        nl_*)                echo us ;;
        sv_*)                echo se ;;
        da_*)                echo dk ;;
        nb_*|nn_*|no_*)      echo no ;;
        fi_*)                echo fi ;;
        pl_*)                echo pl ;;
        cs_*)                echo cz ;;
        sk_*)                echo sk ;;
        hu_*)                echo hu ;;
        ro_*)                echo ro ;;
        bg_*)                echo bg ;;
        el_*)                echo gr ;;
        tr_*)                echo tr ;;
        ru_*)                echo ru ;;
        uk_*)                echo ua ;;
        he_*)                echo il ;;
        ar_*)                echo ara ;;
        fa_*)                echo ir ;;
        hi_*)                echo in ;;
        ja_*)                echo jp ;;
        ko_*)                echo kr ;;
        zh_CN*|zh_SG*)       echo cn ;;
        zh_TW*|zh_HK*)       echo tw ;;
        *)                   echo us ;;
    esac
}

INFERRED_LAYOUT=$(infer_x11_layout "$LOCALE_ARG")
if [ -n "$INFERRED_LAYOUT" ]; then
    BASE="${INFERRED_LAYOUT%%(*}"
    VARIANT=""
    if [[ "$INFERRED_LAYOUT" =~ \((.+)\)$ ]]; then
        VARIANT="${BASH_REMATCH[1]}"
    fi
    localectl set-x11-keymap "$BASE" "" "$VARIANT" 2>/dev/null || true
    if [ -n "$VARIANT" ]; then
        echo "xibo-set-locale.sh: X11 keyboard inferred to ${BASE}(${VARIANT})"
    else
        echo "xibo-set-locale.sh: X11 keyboard inferred to ${BASE}"
    fi
fi

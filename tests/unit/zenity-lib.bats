#!/usr/bin/env bats
# Tests for kiosk/xibo-zenity-lib.sh — shared helper library.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
LIB="$REPO_ROOT/kiosk/xibo-zenity-lib.sh"

@test "xibo-zenity-lib.sh exists and is a shell script" {
    [ -f "$LIB" ]
    head -1 "$LIB" | grep -q 'bash\|sh'
}

@test "xibo-zenity-lib.sh defines _preseed_get" {
    grep -q '_preseed_get' "$LIB"
}

@test "_preseed_get uses grep+cut, never source" {
    # Security: never source the preseed env file. grep+cut only.
    ! grep -E '^\s*source\s+.*preseed' "$LIB"
    ! grep -E '^\s*\.\s+.*preseed' "$LIB"
    grep -q 'grep.*preseed' "$LIB"
}

@test "xibo-zenity-lib.sh defines zlib_notify wrapper" {
    grep -q 'zlib_notify' "$LIB"
}

@test "xibo-zenity-lib.sh defines status helpers for wifi/tz/cms" {
    grep -q 'zlib_status_wifi' "$LIB"
    grep -q 'zlib_status_tz' "$LIB"
    grep -q 'zlib_status_cms' "$LIB"
}

@test "xibo-zenity-lib.sh defines zlib_cms_form" {
    grep -q 'zlib_cms_form' "$LIB"
}

@test "xibo-zenity-lib.sh defines per-player config writers" {
    grep -q 'zlib_write_chromium_config' "$LIB"
    grep -q 'zlib_write_electron_config' "$LIB"
    grep -q 'zlib_write_arexibo_cms_json' "$LIB"
}

@test "display IDs are generated via uuidgen, not derived from machine-id" {
    # Per the plan's hwkeys directive. A resurrected machine-id-based
    # derivation would break the clone-safe property.
    grep -q 'uuidgen' "$LIB"
    ! grep -E 'MACHINE_ID.*sha256|machine-id.*sha256' "$LIB"
}

@test "xibo-zenity-lib.sh can be sourced without errors" {
    # Source in a subshell so we don't pollute the test env. The lib
    # should define functions but not execute any commands at source
    # time (other than local variable assignments).
    run bash -c "source '$LIB' && declare -F _preseed_get"
    [ "$status" -eq 0 ]
}

@test "xibo-first-boot.sh sources xibo-zenity-lib.sh" {
    grep -qE '(source|\.) .*xibo-zenity-lib' "$REPO_ROOT/kiosk/xibo-first-boot.sh"
}

#!/usr/bin/env bats
# Tests for kiosk/xibo-set-wifi.sh — the NetworkManager keyfile writer.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

@test "xibo-set-wifi.sh exits non-zero with no SSID" {
    run bash "$REPO_ROOT/kiosk/xibo-set-wifi.sh"
    [ "$status" -ne 0 ]
}

@test "xibo-set-wifi.sh contains _validate_nm_string" {
    grep -q '_validate_nm_string' "$REPO_ROOT/kiosk/xibo-set-wifi.sh"
}

@test "xibo-set-wifi.sh rejects control characters via regex" {
    grep -q 'x00-\\x1f' "$REPO_ROOT/kiosk/xibo-set-wifi.sh"
}

@test "xibo-set-wifi.sh rejects NM INI section headers" {
    grep -q 'wifi-security\|connection.*wifi\|wifi.*wifi-security' "$REPO_ROOT/kiosk/xibo-set-wifi.sh"
}

@test "xibo-set-wifi.sh writes keyfile with 0600 permissions" {
    grep -q 'chmod 600' "$REPO_ROOT/kiosk/xibo-set-wifi.sh"
}

@test "xibo-set-wifi.sh umasks 077 before writing" {
    grep -q 'umask 077' "$REPO_ROOT/kiosk/xibo-set-wifi.sh"
}

@test "xibo-set-wifi.sh uses nmcli by id, not by filename" {
    grep -q 'nmcli connection up "\$SSID"' "$REPO_ROOT/kiosk/xibo-set-wifi.sh"
}

@test "xibo-set-wifi.sh never passes psk on nmcli cli argument" {
    # The leak window we're closing — psk must NEVER appear adjacent
    # to an nmcli command line. Excludes comment lines (the script's
    # header block explains WHY this is forbidden).
    ! grep -v '^#' "$REPO_ROOT/kiosk/xibo-set-wifi.sh" \
        | grep -v '^\s*#' \
        | grep -E 'nmcli.*password[= ]'
}

@test "xibo-set-wifi.sh sanitises SSID for filename" {
    grep -q "tr -c '\[:alnum:\]._-' '_'" "$REPO_ROOT/kiosk/xibo-set-wifi.sh"
}

@test "kickstart embeds a mirrored _validate_nm_string" {
    # Behavioral contract: the kickstart %pre whiptail TUI contains a
    # copy of _validate_nm_string that rejects the same class of inputs
    # as xibo-set-wifi.sh (control chars + INI section headers).
    grep -q '_validate_nm_string' "$REPO_ROOT/kickstart/xiboplayer-kiosk.ks"
    grep -q 'x00-\\x1f' "$REPO_ROOT/kickstart/xiboplayer-kiosk.ks"
    grep -q 'wifi-security' "$REPO_ROOT/kickstart/xiboplayer-kiosk.ks"
}

@test "kickstart never passes the PSK on an nmcli cli argument" {
    ! grep -v '^#' "$REPO_ROOT/kickstart/xiboplayer-kiosk.ks" \
        | grep -v '^\s*#' \
        | grep -E 'nmcli.*password[= ]'
}

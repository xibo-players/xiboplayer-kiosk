#!/usr/bin/env bats
# Tests for the kickstart %post preseed parser and the preseed env
# security contract.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
KS="$REPO_ROOT/kickstart/xiboplayer-kiosk.ks"

@test "kickstart extracts xibo.* params from /proc/cmdline" {
    grep -qE 'xibo\\\.\[a-z_\]\+=' "$KS"
}

@test "kickstart writes to /etc/xiboplayer-preseed.env" {
    grep -q '/etc/xiboplayer-preseed.env' "$KS"
}

@test "preseed file is never sourced by any script (grep+cut only)" {
    # Critical security property. If this fails, a future maintainer
    # has introduced a sourcing regression — grep the reason.
    ! grep -rE '^\s*source\s+[^#]*xiboplayer-preseed' \
        "$REPO_ROOT/kiosk" "$REPO_ROOT/kickstart" 2>/dev/null
    ! grep -rE '^\s*\.\s+[^#]*xiboplayer-preseed' \
        "$REPO_ROOT/kiosk" 2>/dev/null
}

@test "preseed env keys use xibo.* namespace" {
    grep -qE 'xibo\.(profile|cms_url|cms_key|display_name|timezone|locale|wifi_ssid|wifi_psk|config_url|ssh_pubkey)' "$KS"
}

@test "xibo.config_url= triggers curl+jq fetch" {
    grep -qE 'xibo\\\.config_url' "$KS"
    grep -qE 'curl.*jq|jq.*<' "$KS"
}

@test "kickstart contains the best-available-disk heuristic (#68)" {
    grep -qE 'nvme|best.available|preferred|class' "$KS"
    grep -qE 'disk-autodetect|DISK_SIZE' "$KS"
}

@test "kickstart %pre WiFi TUI (#72) is guarded by entry conditions" {
    # The TUI must be skipped when wired is up, preseeded, or no hw
    grep -qE 'ethernet:connected|xibo\\\.wifi_ssid.*proc/cmdline|dev status.*wifi' "$KS"
}

@test "kickstart %post calls xibo-usb-preseed.sh with --trust (#73)" {
    grep -qE 'xibo-usb-preseed\.sh.*--trust' "$KS"
}

@test "kickstart doas.conf uses script-specific permits (#67 security)" {
    # The blanket timedatectl/localectl permits were replaced in #67
    ! grep -qE '^permit nopass xibo cmd timedatectl$' "$KS"
    ! grep -qE '^permit nopass xibo cmd localectl$' "$KS"
    grep -q 'xibo-set-timezone.sh' "$KS"
    grep -q 'xibo-set-locale.sh' "$KS"
}

@test "kickstart has no active (non-comment) reference to the Python wizard" {
    # #71 removed the cp xiboplayer-setup.desktop block entirely. Comments
    # documenting the historical removal are OK; active code referencing
    # the deleted file would break the install.
    ! grep -v '^#' "$KS" | grep -q 'xiboplayer-setup\.desktop'
    ! grep -v '^#' "$KS" | grep -q 'xiboplayer-setup\.py'
}

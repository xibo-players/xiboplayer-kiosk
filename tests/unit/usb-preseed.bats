#!/usr/bin/env bats
# Tests for kiosk/xibo-usb-preseed.sh — USB /setup.json auto-detect.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
SCRIPT="$REPO_ROOT/kiosk/xibo-usb-preseed.sh"

@test "xibo-usb-preseed.sh exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "xibo-usb-preseed.sh supports --trust flag" {
    grep -q -- '--trust' "$SCRIPT"
}

@test "xibo-usb-preseed.sh uses lsblk TRAN=usb filter" {
    grep -qE 'TRAN|lsblk.*usb|tran.*usb' "$SCRIPT"
}

@test "xibo-usb-preseed.sh parses install target from /tmp/disk-config" {
    grep -qE '/tmp/disk-config|disk-config' "$SCRIPT"
    grep -qE 'drives=|TARGET_DISK' "$SCRIPT"
}

@test "xibo-usb-preseed.sh mounts read-only" {
    grep -qE 'mount.*-o.*ro|mount.*ro' "$SCRIPT"
}

@test "xibo-usb-preseed.sh uses jq allowlist regex" {
    grep -qE 'test\("\^' "$SCRIPT"
}

@test "jq allowlist regex rejects dollar sign in value" {
    run bash -c "echo '{\"cms_key\":\"bad\$value\"}' | jq -r '
        to_entries[]
        | select(.value | type == \"string\")
        | select(.value | test(\"^[A-Za-z0-9._/@:+=\\\\- ]+\$\"))
        | \"xibo.\\(.key)=\\(.value)\"
    '"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "jq allowlist regex rejects semicolon in value" {
    run bash -c "echo '{\"cms_key\":\"evil;rm -rf /\"}' | jq -r '
        to_entries[]
        | select(.value | type == \"string\")
        | select(.value | test(\"^[A-Za-z0-9._/@:+=\\\\- ]+\$\"))
        | \"xibo.\\(.key)=\\(.value)\"
    '"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "jq allowlist regex rejects backtick in value" {
    run bash -c "echo '{\"cms_key\":\"bad\`whoami\`\"}' | jq -r '
        to_entries[]
        | select(.value | type == \"string\")
        | select(.value | test(\"^[A-Za-z0-9._/@:+=\\\\- ]+\$\"))
        | \"xibo.\\(.key)=\\(.value)\"
    '"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "jq allowlist regex accepts https URL" {
    run bash -c "echo '{\"cms_url\":\"https://cms.example.com\"}' | jq -r '
        to_entries[]
        | select(.value | type == \"string\")
        | select(.value | test(\"^[A-Za-z0-9._/@:+=\\\\- ]+\$\"))
        | \"xibo.\\(.key)=\\(.value)\"
    '"
    [ "$status" -eq 0 ]
    [ "$output" = "xibo.cms_url=https://cms.example.com" ]
}

@test "jq allowlist regex accepts hyphenated display name" {
    run bash -c "echo '{\"display_name\":\"Reception-3\"}' | jq -r '
        to_entries[]
        | select(.value | type == \"string\")
        | select(.value | test(\"^[A-Za-z0-9._/@:+=\\\\- ]+\$\"))
        | \"xibo.\\(.key)=\\(.value)\"
    '"
    [ "$status" -eq 0 ]
    [ "$output" = "xibo.display_name=Reception-3" ]
}

@test "xibo-usb-preseed.sh is invoked from kickstart with --trust" {
    grep -qE 'xibo-usb-preseed\.sh.*--trust' "$REPO_ROOT/kickstart/xiboplayer-kiosk.ks"
}

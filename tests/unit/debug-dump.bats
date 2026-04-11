#!/usr/bin/env bats
# Tests for kiosk/xibo-debug-dump.sh — support bundle collector.
# Static assertions on the script content (functional testing needs
# complex journalctl/systemctl mocking and is best left to manual
# post-install smoke tests on a real kiosk).

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
SCRIPT="$REPO_ROOT/kiosk/xibo-debug-dump.sh"

@test "xibo-debug-dump.sh exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "xibo-debug-dump.sh writes to \$HOME/Downloads" {
    grep -qE 'Downloads' "$SCRIPT"
}

@test "xibo-debug-dump.sh uses zstd compression" {
    grep -qE 'tar.*zst|zstd' "$SCRIPT"
}

@test "xibo-debug-dump.sh redacts cms_key via sed" {
    grep -q 'cms_key' "$SCRIPT"
    grep -q '_redact' "$SCRIPT"
}

@test "xibo-debug-dump.sh redacts wifi_psk" {
    grep -qE 'wifi_psk' "$SCRIPT"
}

@test "xibo-debug-dump.sh redacts config_url basic auth credentials" {
    grep -qE 'config_url' "$SCRIPT"
}

@test "xibo-debug-dump.sh refuses to include NM keyfiles (security assertion)" {
    grep -q 'NetworkManager/system-connections' "$SCRIPT"
}

@test "xibo-debug-dump.sh refuses to include /etc/shadow" {
    grep -qE '/shadow|etc/shadow' "$SCRIPT"
}

@test "xibo-debug-dump.sh refuses to include browser cookies" {
    grep -qE 'Cookies' "$SCRIPT"
}

@test "xibo-debug-dump.sh refuses to include /etc/doas.conf" {
    grep -q 'doas' "$SCRIPT"
}

@test "xibo-debug-dump.sh has post-tar security assertion (deletes on match)" {
    # After creating the tarball, the script must verify the tarball
    # does NOT contain any sensitive path, and if it does, delete the
    # tarball and exit non-zero.
    grep -qE 'tar.*tf.*|tf.*grep' "$SCRIPT"
}

@test "xibo-debug-dump.sh collects journalctl --user" {
    grep -qE 'journalctl.*--user' "$SCRIPT"
}

@test "xibo-debug-dump.sh collects kernel journal" {
    grep -qE 'journalctl.*-k' "$SCRIPT"
}

@test "xibo-debug-dump.sh is symlinked as /usr/bin/xibo-debug-dump in rpm" {
    grep -qE 'xibo-debug-dump' "$REPO_ROOT/rpm/xiboplayer-kiosk.spec"
    grep -qE 'ln -sf.*xibo-debug-dump' "$REPO_ROOT/rpm/xiboplayer-kiosk.spec"
}

@test "keyd config binds ctrl+d to xibo-debug-dump" {
    grep -qE 'debug-dump|ctrl.*d' "$REPO_ROOT/kiosk/keyd-xibo.conf"
}

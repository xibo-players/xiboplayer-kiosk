#!/usr/bin/env bash
# Test environment loader — sets up a sandboxed HOME, PATH mocks, and
# sources the xibo-zenity-lib.sh under test.
#
# Usage inside a .bats file:
#   load "../bats-helpers/load-lib"

# Absolute path to the repo root regardless of bats working directory.
TESTS_DIR="$(cd "${BATS_TEST_DIRNAME}" && pwd)"
REPO_ROOT="$(cd "${TESTS_DIR}/../.." && pwd)"
export REPO_ROOT

# Sandbox $HOME so tests don't touch the developer's real config.
export TEST_HOME
TEST_HOME=$(mktemp -d)
export HOME="$TEST_HOME"
mkdir -p "$HOME/.config/xiboplayer/chromium"
mkdir -p "$HOME/.config/xiboplayer/electron"
mkdir -p "$HOME/.local/share/xibo"
mkdir -p "$HOME/Downloads"

# Sandboxed PATH with stub binaries injected ahead of /usr/bin.
export STUB_DIR
STUB_DIR=$(mktemp -d)
export PATH="$STUB_DIR:$PATH"

# Sandbox XIBO_KIOSK_DIR to point at the repo kiosk/ directory so scripts
# can source their siblings without being installed.
export XIBO_KIOSK_DIR="$REPO_ROOT/kiosk"

teardown_common() {
    rm -rf "$TEST_HOME" "$STUB_DIR"
}

# Install a simple stub that echoes its arguments to a log file.
# Usage: install_stub <name> [canned_output]
install_stub() {
    local name="$1"
    local output="${2:-}"
    cat > "$STUB_DIR/$name" << STUB
#!/bin/bash
echo "\$0 \$*" >> "$STUB_DIR/.calls"
STUB
    if [ -n "$output" ]; then
        printf '%s\n' "$output" >> "$STUB_DIR/$name"
    fi
    chmod +x "$STUB_DIR/$name"
}

# Install a stub that writes canned output (for readers like nmcli).
# Usage: install_stub_output <name> "line1\nline2"
install_stub_output() {
    local name="$1"
    local output="$2"
    cat > "$STUB_DIR/$name" << STUB
#!/bin/bash
cat << 'CANNEDOUT'
$output
CANNEDOUT
STUB
    chmod +x "$STUB_DIR/$name"
}

# Capture what a stub was called with — reads $STUB_DIR/.calls
stub_calls() {
    cat "$STUB_DIR/.calls" 2>/dev/null || true
}

reset_stub_calls() {
    : > "$STUB_DIR/.calls"
}

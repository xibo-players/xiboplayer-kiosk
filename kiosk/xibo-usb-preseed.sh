#!/bin/bash
# xibo-usb-preseed.sh — auto-detect /setup.json on USB devices.
#
# Usage:
#   xibo-usb-preseed.sh [--trust]
#
# Scans removable USB block devices for a file named /setup.json at the
# root of the first filesystem, validates the JSON via a jq allowlist
# regex (rejects shell metacharacters), and appends the validated
# key=value pairs to /etc/xiboplayer-preseed.env.
#
# The --trust flag skips the interactive confirmation dialog. It MUST
# only be passed when the caller is the kickstart %post (install time,
# operator physically present). The first-boot menu and Ctrl+R
# reconfigure paths NEVER pass --trust — a zenity confirmation is shown
# instead, to prevent an evil-maid attack where a visitor plugs a USB
# stick + triggers the reconfigure path to silently re-register the
# kiosk with an attacker-controlled CMS.
#
# Precedence: this script sits between Layer 1 (xibo.config_url= JSON
# fetch) and Layer 2 (per-field xibo.*= kernel params) in the preseed
# architecture. Per-field kernel params ALWAYS win — they're applied
# after this script in the kickstart %post.
#
# Security:
#   - lsblk TRAN=usb filter — only USB transport devices are considered
#   - Install target (parsed from /tmp/disk-config) is excluded
#   - jq allowlist regex rejects $, backtick, ;, &, |, >, <, \, newline
#     BEFORE values are ever written to the env file
#   - /etc/xiboplayer-preseed.env is NEVER sourced — values are read
#     via _preseed_get() which uses grep+cut (no shell parser)
#
# Errors:
#   - Missing lsblk/jq/mount — exit 0 (graceful skip)
#   - No USB devices — exit 0
#   - No setup.json on any USB — exit 0
#   - Invalid JSON — warn, continue
#   - User declines confirmation — exit 0

set -e

TRUST=0
if [ "${1:-}" = "--trust" ]; then
    TRUST=1
fi

# Graceful skip if required tools are missing
for tool in lsblk jq mount umount; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "xibo-usb-preseed: $tool missing, skipping" >&2
        exit 0
    fi
done

# Parse the install target from /tmp/disk-config so we never scan it.
# The kickstart %pre disk-autodetect writes --drives=$DISK on one line.
TARGET_DISK=""
if [ -r /tmp/disk-config ]; then
    TARGET_DISK=$(grep -oE 'drives=[^ ]+' /tmp/disk-config 2>/dev/null | cut -d= -f2 | head -1)
fi

# Enumerate USB-transport block devices with a supported FS.
# NAME  — /dev/sdb1 style path (lsblk -p)
# TRAN  — usb / sata / nvme / virtio
# FSTYPE — vfat / exfat / ntfs / ext4 / etc
# MOUNTPOINT — empty if unmounted; skip already-mounted partitions
#             (they're likely /mnt/sysimage or similar anaconda targets)
CANDIDATES=$(lsblk -pno NAME,TRAN,FSTYPE,MOUNTPOINT 2>/dev/null \
    | awk -v tgt="$TARGET_DISK" '
        $2 == "usb" && $3 ~ /^(vfat|exfat|ntfs|ext4)$/ && $4 == "" {
            # Skip any device whose name contains the install target basename
            if (tgt != "" && index($1, tgt) > 0) next
            print $1
        }')

if [ -z "$CANDIDATES" ]; then
    echo "xibo-usb-preseed: no USB candidates" >&2
    exit 0
fi

FOUND_DEV=""
FOUND_JSON=""
MNT=""

for dev in $CANDIDATES; do
    MNT=$(mktemp -d)
    if mount -o ro "$dev" "$MNT" 2>/dev/null; then
        if [ -f "$MNT/setup.json" ]; then
            FOUND_DEV="$dev"
            FOUND_JSON="$MNT/setup.json"
            break
        fi
        umount "$MNT" 2>/dev/null || true
    fi
    rm -rf "$MNT"
    MNT=""
done

if [ -z "$FOUND_DEV" ]; then
    echo "xibo-usb-preseed: no setup.json on any USB" >&2
    exit 0
fi

echo "xibo-usb-preseed: found $FOUND_JSON on $FOUND_DEV"

# Runtime (non-kickstart) callers must confirm before applying — prevents
# the "visitor plugs USB + triggers Ctrl+R full-setup to silently rewrite
# the CMS URL" evil-maid attack.
if [ "$TRUST" -eq 0 ]; then
    if command -v zenity >/dev/null 2>&1; then
        PREVIEW=$(head -c 1000 "$FOUND_JSON")
        if ! zenity --question \
            --title="xiboplayer — USB config detected" \
            --width=500 \
            --text="A USB stick with xiboplayer config was found at $FOUND_DEV.\n\nApply these settings?\n\n$PREVIEW"; then
            echo "xibo-usb-preseed: user declined" >&2
            umount "$MNT" 2>/dev/null || true
            rm -rf "$MNT"
            exit 0
        fi
    else
        # No zenity available and no --trust → fail closed
        echo "xibo-usb-preseed: no zenity + no --trust, refusing silent apply" >&2
        umount "$MNT" 2>/dev/null || true
        rm -rf "$MNT"
        exit 0
    fi
fi

# Validate + append. The jq allowlist regex rejects shell metacharacters
# BEFORE values reach the env file. Acceptable characters: alphanumerics,
# ._/@:+=-, and spaces (for display names). Rejected: $, backtick, ;, &,
# |, >, <, \, newlines. Operators whose password contains ! or # must
# preseed via xibo.wifi_psk= kernel param instead.
install -d /etc
TMPOUT=$(mktemp)
if jq -r '
    to_entries[]
    | select(.value | type == "string")
    | select(.value | test("^[A-Za-z0-9._/@:+=\\- ]+$"))
    | "xibo.\(.key)=\(.value)"
' < "$FOUND_JSON" > "$TMPOUT" 2>/dev/null; then
    # Merge into /etc/xiboplayer-preseed.env: remove any existing entries
    # for keys present in the USB setup.json, then append the new ones.
    while IFS='=' read -r key val; do
        [ -z "$key" ] && continue
        sed -i "/^${key//./\\.}=/d" /etc/xiboplayer-preseed.env 2>/dev/null || true
        echo "${key}=${val}" >> /etc/xiboplayer-preseed.env
    done < "$TMPOUT"
    n=$(wc -l < "$TMPOUT")
    echo "xibo-usb-preseed: merged $n key(s) from $FOUND_DEV into /etc/xiboplayer-preseed.env"
else
    echo "xibo-usb-preseed: jq failed on $FOUND_JSON — ignoring" >&2
fi
rm -f "$TMPOUT"

umount "$MNT" 2>/dev/null || true
rm -rf "$MNT"

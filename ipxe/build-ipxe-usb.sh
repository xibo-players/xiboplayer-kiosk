#!/usr/bin/env bash
# =============================================================================
# Build a bootable iPXE USB image for xiboplayer network install.
#
# Produces: xiboplayer-ipxe-bios.img (~1 MB)
# Flash:    sudo dd if=xiboplayer-ipxe-bios.img of=/dev/sdX bs=4M
#
# The USB boots into an iPXE menu that downloads and installs
# xiboplayer-kiosk over the internet. No ISO needed.
#
# Requirements: git, gcc, make, mtools, perl, xz-devel, liblzma
# Fedora:  sudo dnf install git gcc make mtools perl xz-devel
# Ubuntu:  sudo apt install git gcc make mtools perl liblzma-dev
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOT_SCRIPT="${SCRIPT_DIR}/boot.ipxe"
BUILD_DIR="/tmp/ipxe-build-$$"
OUTPUT="${SCRIPT_DIR}/xiboplayer-ipxe-bios.img"

if [ ! -f "$BOOT_SCRIPT" ]; then
    echo "ERROR: boot.ipxe not found at $BOOT_SCRIPT"
    exit 1
fi

echo "Building iPXE USB image..."
echo "  Boot script: $BOOT_SCRIPT"
echo "  Output:      $OUTPUT"
echo ""

# Clone iPXE source
echo "[1/3] Cloning iPXE source..."
rm -rf "$BUILD_DIR"
git clone --depth 1 https://github.com/ipxe/ipxe.git "$BUILD_DIR"

# Copy boot script
cp "$BOOT_SCRIPT" "$BUILD_DIR/src/boot.ipxe"

# Enable HTTPS support (required for GitHub + dl.xiboplayer.org)
cat >> "$BUILD_DIR/src/config/general.h" << 'EOF'
#define DOWNLOAD_PROTO_HTTPS
#define IMAGE_TRUST_CMD
EOF

# Build BIOS USB image with embedded script
echo "[2/3] Compiling iPXE (BIOS)..."
cd "$BUILD_DIR/src"
make -j$(nproc) bin/ipxe.usb EMBED=boot.ipxe 2>&1 | tail -5

# Copy output
cp bin/ipxe.usb "$OUTPUT"

echo ""
echo "[3/3] Build complete!"
echo ""
echo "  Output: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
echo ""
echo "  Flash to USB:"
echo "    sudo dd if=$OUTPUT of=/dev/sdX bs=4M"
echo ""
echo "  Or build an EFI version too:"
echo "    cd $BUILD_DIR/src"
echo "    make bin-x86_64-efi/ipxe.efi EMBED=boot.ipxe"
echo ""

# Cleanup
rm -rf "$BUILD_DIR"

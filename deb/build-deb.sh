#!/bin/bash
# Build xiboplayer-kiosk DEB package
# Usage: ./deb/build-deb.sh [VERSION]
set -euo pipefail

VERSION="${1:-0.4.4}"
PACKAGE="xiboplayer-kiosk"
ARCH="all"
DEB_DIR="dist/${PACKAGE}_${VERSION}_${ARCH}"

echo "Building ${PACKAGE} ${VERSION} (${ARCH})..."

# Create DEB directory structure
rm -rf "${DEB_DIR}"
mkdir -p "${DEB_DIR}/DEBIAN"
mkdir -p "${DEB_DIR}/usr/share/xiboplayer-kiosk"
mkdir -p "${DEB_DIR}/usr/lib/systemd/user"
mkdir -p "${DEB_DIR}/etc/keyd"
mkdir -p "${DEB_DIR}/etc/skel/.local/bin"

# Install kiosk scripts
install -m755 kiosk/gnome-kiosk-script.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m755 kiosk/gnome-kiosk-script.xibo.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m755 kiosk/gnome-kiosk-script.xibo-init.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m644 kiosk/dunstrc "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m755 kiosk/xibo-keyd-run.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m755 kiosk/xibo-show-ip.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m755 kiosk/xibo-show-cms.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"

# Install dispatcher to skel (copied to new users' ~/.local/bin/)
install -m755 kiosk/gnome-kiosk-script.sh "${DEB_DIR}/etc/skel/.local/bin/gnome-kiosk-script"

# Install systemd service
install -m644 kiosk/xibo-player.service "${DEB_DIR}/usr/lib/systemd/user/"

# Install keyd config
install -m644 kiosk/keyd-xibo.conf "${DEB_DIR}/etc/keyd/xibo.conf"

# Create control file
cat > "${DEB_DIR}/DEBIAN/control" << EOF
Package: ${PACKAGE}
Version: ${VERSION}
Architecture: ${ARCH}
Maintainer: Pau Aliagas <linuxnow@gmail.com>
Description: Kiosk session scripts for Xibo digital signage players
 Kiosk session scripts for running Xibo digital signage players as full-screen
 displays under GNOME Kiosk. Includes a first-boot registration wizard,
 session holder with health monitoring, dunst notification config, and
 a systemd user unit for the player process.
Depends: gnome-kiosk, dunst, unclutter, zenity, xiboplayer-electron | xiboplayer-chromium | arexibo
Recommends: keyd
Section: misc
Priority: optional
Homepage: https://xiboplayer.org
EOF

# Build DEB
mkdir -p dist
dpkg-deb --build "${DEB_DIR}" "dist/${PACKAGE}_${VERSION}_${ARCH}.deb"

# Clean up build directory
rm -rf "${DEB_DIR}"

echo "Built: dist/${PACKAGE}_${VERSION}_${ARCH}.deb"

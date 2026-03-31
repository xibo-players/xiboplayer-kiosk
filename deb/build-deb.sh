#!/bin/bash
# Build xiboplayer-kiosk DEB package
# Usage: ./deb/build-deb.sh [VERSION]
set -euo pipefail

VERSION="${1:-0.4.10}"
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

# Create postinst script — enable codec repos and install recommends
cat > "${DEB_DIR}/DEBIAN/postinst" << 'POSTINST'
#!/bin/bash
set -e

# Enable multiverse (Ubuntu) or non-free (Debian) for codec packages
if [ -f /etc/os-release ]; then
  . /etc/os-release
  case "$ID" in
    ubuntu)
      # Enable multiverse and restricted components
      if command -v add-apt-repository >/dev/null 2>&1; then
        add-apt-repository -y multiverse 2>/dev/null || true
        add-apt-repository -y restricted 2>/dev/null || true
      fi
      ;;
    debian)
      # Enable non-free and non-free-firmware in sources
      if [ -f /etc/apt/sources.list.d/debian.sources ]; then
        sed -i 's/Components: main/Components: main contrib non-free non-free-firmware/' \
          /etc/apt/sources.list.d/debian.sources 2>/dev/null || true
      fi
      ;;
  esac
fi

# Install recommended codec packages (best-effort, don't fail)
apt-get update -qq 2>/dev/null || true
apt-get install -y --no-install-recommends \
  ffmpeg vlc mpv \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-ugly gstreamer1.0-plugins-bad \
  gstreamer1.0-libav \
  libva2 mesa-va-drivers \
  avahi-daemon libnss-mdns \
  2>/dev/null || true

exit 0
POSTINST
chmod 755 "${DEB_DIR}/DEBIAN/postinst"

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
Recommends: keyd, ffmpeg, vlc, mpv,
 gstreamer1.0-plugins-base, gstreamer1.0-plugins-good,
 gstreamer1.0-plugins-ugly, gstreamer1.0-plugins-bad,
 gstreamer1.0-libav,
 libva2, mesa-va-drivers, intel-media-va-driver-non-free | intel-media-va-driver,
 avahi-daemon, libnss-mdns, wireguard-tools
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

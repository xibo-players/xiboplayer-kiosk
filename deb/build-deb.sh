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
mkdir -p "${DEB_DIR}/usr/share/glib-2.0/schemas"
mkdir -p "${DEB_DIR}/usr/lib/systemd/user"
mkdir -p "${DEB_DIR}/etc/keyd"
mkdir -p "${DEB_DIR}/etc/skel/.local/bin"
mkdir -p "${DEB_DIR}/etc/systemd/logind.conf.d"
mkdir -p "${DEB_DIR}/etc/dconf/profile"
mkdir -p "${DEB_DIR}/etc/dconf/db/gdm.d/locks"
mkdir -p "${DEB_DIR}/etc/chromium/policies/managed"

# Install kiosk scripts
install -m755 kiosk/gnome-kiosk-script.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m755 kiosk/gnome-kiosk-script.xibo.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m755 kiosk/gnome-kiosk-script.xibo-init.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m644 kiosk/dunstrc "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m755 kiosk/xibo-keyd-run.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m755 kiosk/xibo-show-ip.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m755 kiosk/xibo-show-cms.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m755 kiosk/xibo-activate-kiosk.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m755 kiosk/xibo-deactivate-kiosk.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m755 kiosk/xibo-set-wifi.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m755 kiosk/xibo-debug-dump.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
# Issue #67 — zenity first-boot menu scripts
install -m755 kiosk/xibo-zenity-lib.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m755 kiosk/xibo-first-boot.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m755 kiosk/xibo-set-timezone.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
install -m755 kiosk/xibo-set-locale.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"
# Issue #73 — USB /setup.json auto-detect
install -m755 kiosk/xibo-usb-preseed.sh "${DEB_DIR}/usr/share/xiboplayer-kiosk/"

# /usr/bin/xibo-debug-dump symlink (mirrors the RPM spec) — lets techs run
# `xibo-debug-dump` from any shell without typing the full share path.
mkdir -p "${DEB_DIR}/usr/bin"
ln -sf /usr/share/xiboplayer-kiosk/xibo-debug-dump.sh "${DEB_DIR}/usr/bin/xibo-debug-dump"

# System config files — the kiosk DEB IS the kiosk definition, so the
# system-level config that makes a kiosk stay on forever + suppresses the
# GNOME donation popup ships with the package (mirrors the RPM spec).
# Sources live under mkosi-extra/ (also reused by mkosi builds + atomic
# Containerfile COPYs with identical content — harmless).
#
# Layer 1: logind idle/lid/power key suppression
install -m644 mkosi-extra/etc/systemd/logind.conf.d/no-idle.conf "${DEB_DIR}/etc/systemd/logind.conf.d/no-idle.conf"
# Layer 2: system-wide GSchema override
install -m644 mkosi-extra/usr/share/glib-2.0/schemas/90_xiboplayer-kiosk.gschema.override "${DEB_DIR}/usr/share/glib-2.0/schemas/90_xiboplayer-kiosk.gschema.override"
# Layer 4: GDM greeter dconf profile + db + locks
install -m644 mkosi-extra/etc/dconf/profile/gdm "${DEB_DIR}/etc/dconf/profile/gdm"
install -m644 mkosi-extra/etc/dconf/db/gdm.d/00-xiboplayer-kiosk "${DEB_DIR}/etc/dconf/db/gdm.d/00-xiboplayer-kiosk"
install -m644 mkosi-extra/etc/dconf/db/gdm.d/locks/00-xiboplayer-kiosk "${DEB_DIR}/etc/dconf/db/gdm.d/locks/00-xiboplayer-kiosk"
# Chromium managed policies (#98) — disables Save Password, autofill, translate
install -m644 mkosi-extra/etc/chromium/policies/managed/xiboplayer-kiosk.json "${DEB_DIR}/etc/chromium/policies/managed/xiboplayer-kiosk.json"

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

# Compile GSchema overrides + refresh dconf database so the Layer 2 and
# Layer 4 files installed above take effect. glib-compile-schemas is
# idempotent, and dconf update MUST run explicitly because dconf has no
# file trigger — without it the /etc/dconf/db/gdm.d/00-xiboplayer-kiosk
# file is not compiled into the /etc/dconf/db/gdm database that the GDM
# greeter reads, and Layer 4 is silently inert.
glib-compile-schemas /usr/share/glib-2.0/schemas/ 2>/dev/null || true
dconf update 2>/dev/null || true

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
Depends: gnome-kiosk, dunst, unclutter, zenity, dconf-cli, libglib2.0-bin, xiboplayer-electron | xiboplayer-chromium
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

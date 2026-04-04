#version=F43
# Xibo Kiosk Kickstart File
# =============================
# Automated Fedora 43 installation for Xibo digital signage
#
# Usage:
#   Boot from Fedora netinstall and add to kernel cmdline:
#   inst.ks=https://raw.githubusercontent.com/xibo-players/xiboplayer-kiosk/main/kickstart/xiboplayer-kiosk.ks
#
# Or create a custom ISO with this kickstart embedded.

# Installation source — Fedora mirror for netinstall, cdrom for Everything ISO
# Anaconda auto-detects cdrom when booting from Everything ISO and ignores url.
# For netinstall, the mirrorlist provides automatic mirror selection.
url --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-43&arch=$basearch

# Installation settings
text
skipx
firstboot --enable
reboot --eject

# Localization
lang en_US.UTF-8
keyboard --xlayouts='us'
timezone Europe/Madrid --utc

# Network - DHCP by default
network --bootproto=dhcp --device=link --activate --onboot=yes
network --hostname=xiboplayer-kiosk

# Root password (change this or use --lock)
rootpw --lock

# User configuration
user --name=xibo --groups=wheel --password=xibo --plaintext --gecos="Xibo Kiosk User"

# Disk configuration — use entire first non-removable disk
# reqpart creates EFI + biosboot partitions automatically
# ignoredisk with no args tells Anaconda to skip any removable/USB drives
zerombr
clearpart --all --initlabel --disklabel=gpt
reqpart --add-boot
autopart --nolvm --nohome --type=plain --fstype=xfs

# Bootloader — network boot options for dracut, predictable interface naming disabled
bootloader --location=mbr --timeout=0 --append="quiet rhgb splash loglevel=3 rd.neednet=1 ip=dhcp keep-configuration=no allowed-connections=except:origin:nm-initrd-generator net.ifnames=0 biosdevname=0"

# Package selection
%packages
@core
@hardware-support

# Fonts — minimal set (saves ~100 MB vs @fonts group)
dejavu-sans-fonts
dejavu-sans-mono-fonts
liberation-sans-fonts
liberation-mono-fonts
google-noto-sans-fonts
google-noto-emoji-color-fonts

# Display manager and kiosk
gdm
gnome-kiosk
gnome-kiosk-script-session

# gnome-initial-setup: language/keyboard/network/timezone/password on first boot
gnome-initial-setup

# Media playback
vlc
mpv
gstreamer1-plugins-base
gstreamer1-plugins-good
gstreamer1-plugins-bad-free
gstreamer1-plugins-ugly-free
gstreamer1-plugin-openh264
gstreamer1-plugin-libav

# Kiosk utilities
zenity
dunst
unclutter
opendoas

# First-boot wizard (libadwaita GTK4 app)
python3-gobject
libadwaita

# Networking
avahi
nss-mdns
wireguard-tools
NetworkManager-wifi

# Remove unnecessary packages
-gnome-tour
-gnome-software
-gnome-terminal
-gnome-text-editor
-gnome-calculator
-gnome-characters
-gnome-clocks
-gnome-connections
-gnome-contacts
-gnome-logs
-gnome-maps
-gnome-weather
-totem
-cheese
-evince
-loupe
-yelp
-gnome-user-docs
-abrt*
%end

# RPMFusion repositories
%post --erroronfail
# Add RPMFusion repos
dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-43.noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-43.noarch.rpm

# Swap ffmpeg-free for full ffmpeg (all codecs)
dnf swap -y ffmpeg-free ffmpeg --allowerasing || true

# Install RPM Fusion codec packages (H.264, H.265, AAC, DTS, etc.)
dnf install -y \
  gstreamer1-plugins-ugly \
  gstreamer1-plugins-bad-freeworld \
  || true

# GPU drivers — install what's available for the hardware
dnf install -y \
  libva-intel-media-driver \
  libva-nvidia-driver \
  mesa-va-drivers \
  mesa-dri-drivers \
  || true
%end

# Install xiboplayer-release (ships GPG key + repo config + keyd COPR)
%post --erroronfail
# --nogpgcheck for the release RPM only — it ships the signing key.
# On Everything ISO: installs from local repo (offline).
# On netinstall: fetches from network (fallback URL).
# All subsequent dnf installs verify GPG normally.
dnf install -y --nogpgcheck xiboplayer-release || \
  dnf install -y --nogpgcheck \
  https://dl.xiboplayer.org/rpm/fedora/43/noarch/xiboplayer-release-43-7.fc43.noarch.rpm

# Install players based on xibo.profile kernel parameter
# Profiles: full (default), electron, chromium
# Set via iPXE: kernel vmlinuz inst.ks=... xibo.profile=electron
PROFILE=$(sed -n 's/.*xibo\.profile=\([^ ]*\).*/\1/p' /proc/cmdline)
PROFILE="${PROFILE:-full}"

case "$PROFILE" in
  electron)
    dnf install -y xiboplayer-kiosk xiboplayer-electron
    alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/xiboplayer-electron 30
    ;;
  chromium)
    dnf install -y xiboplayer-kiosk xiboplayer-chromium
    alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/xiboplayer-chromium 20
    ;;
  *)
    dnf install -y xiboplayer-kiosk xiboplayer-electron xiboplayer-chromium arexibo
    alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/xiboplayer-electron 30
    alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/xiboplayer-chromium 20
    alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/arexibo 10
    ;;
esac
echo "Installed profile: $PROFILE"
%end

# Configure xibo user and directories
%post --erroronfail
# Enable lingering for xibo user
loginctl enable-linger xibo

# Create directories
mkdir -p /home/xibo/.local/bin
mkdir -p /home/xibo/.local/share/xibo
mkdir -p /home/xibo/Videos

chown -R xibo:xibo /home/xibo
%end

# Configure GDM autologin
%post --erroronfail
cat > /etc/gdm/custom.conf << 'EOF'
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=xibo

[security]

[xdmcp]

[chooser]

[debug]
EOF
%end

# Configure AccountsService
%post --erroronfail
mkdir -p /var/lib/AccountsService/users
cat > /var/lib/AccountsService/users/xibo << 'EOF'
[User]
Session=gnome-kiosk-script-wayland
SystemAccount=false
EOF
%end

# Configure opendoas
%post --erroronfail
cat > /etc/doas.conf << 'EOF'
permit nopass xibo cmd reboot
permit nopass xibo cmd shutdown
permit nopass xibo cmd alternatives
permit nopass xibo cmd localectl
EOF
chmod 600 /etc/doas.conf
%end

# Install kiosk dispatcher for xibo user
# (skel handles new users, but the kickstart-created user needs it too)
%post --erroronfail
cp /etc/skel/.local/bin/gnome-kiosk-script /home/xibo/.local/bin/gnome-kiosk-script
chmod 755 /home/xibo/.local/bin/gnome-kiosk-script

# Add local bin to PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/xibo/.bashrc
chown -R xibo:xibo /home/xibo
%end

# Create reboot/shutdown wrappers
%post --erroronfail
cat > /home/xibo/.local/bin/reboot << 'EOF'
#!/bin/bash
doas reboot
EOF
chmod 755 /home/xibo/.local/bin/reboot

cat > /home/xibo/.local/bin/shutdown << 'EOF'
#!/bin/bash
doas shutdown -h now
EOF
chmod 755 /home/xibo/.local/bin/shutdown

chown xibo:xibo /home/xibo/.local/bin/reboot /home/xibo/.local/bin/shutdown
%end

# gnome-initial-setup: only show locale/keyboard/network/timezone
%post --erroronfail
mkdir -p /usr/share/gnome-initial-setup
cat > /usr/share/gnome-initial-setup/vendor.conf << 'EOF'
[pages]
skip=privacy;software;account;summary;welcome
EOF
%end

# Disable GNOME donation popup
%post --erroronfail
su - xibo -c "dbus-run-session gsettings set org.gnome.desktop.interface show-donation-popup false" || true
%end

# Enable services
%post --erroronfail
systemctl enable gdm avahi-daemon keyd
systemctl set-default graphical.target

# Prevent idle suspend and lid close (kiosk must stay on)
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/no-idle.conf << 'LOGINDEOF'
[Login]
IdleAction=ignore
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
LOGINDEOF
%end

# Hide grub menu — kiosk boots straight to OS
%post --erroronfail
if [ -f /etc/default/grub ]; then
  sed -i 's/^GRUB_TIMEOUT=[0-9]\+$/GRUB_TIMEOUT=0/' /etc/default/grub
  grep -q GRUB_TIMEOUT_STYLE /etc/default/grub || echo "GRUB_TIMEOUT_STYLE=hidden" >> /etc/default/grub
  grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
fi
%end

# Final cleanup
%post --erroronfail
# Ensure all xibo files have correct ownership
chown -R xibo:xibo /home/xibo

# Clean dnf cache
dnf clean all
%end

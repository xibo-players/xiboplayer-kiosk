#version=F43
# Xibo Kiosk Kickstart File
# =============================
# Automated Fedora 43 installation for Xibo digital signage
#
# Usage:
#   Boot from Fedora netinstall and add to kernel cmdline:
#   inst.ks=https://raw.githubusercontent.com/xibo-players/xibo-kiosk/main/kickstart/xibo-kiosk.ks
#
# Or create a custom ISO with this kickstart embedded.

# Installation settings
text
skipx
firstboot --disable
reboot --eject

# Localization
lang en_US.UTF-8
keyboard --xlayouts='us'
timezone Europe/Madrid --utc

# Network - DHCP by default
network --bootproto=dhcp --device=link --activate --onboot=yes
network --hostname=xibo-kiosk

# Root password (change this or use --lock)
rootpw --lock

# User configuration
user --name=xibo --groups=wheel --password=xibo --plaintext --gecos="Xibo Kiosk User"

# Disk configuration - use entire disk
clearpart --all --initlabel
autopart --type=plain --nohome

# Bootloader
bootloader --append="quiet rhgb"

# Package selection
%packages
@core
@hardware-support
@fonts

# Display manager and kiosk
gdm
gnome-kiosk
gnome-kiosk-script-session

# Media playback
vlc
firefox
gstreamer1-plugins-base
gstreamer1-plugins-good
gstreamer1-plugins-bad-free
gstreamer1-plugins-ugly-free
gstreamer1-plugin-openh264
gstreamer1-plugin-libav

# Kiosk utilities (also pulled by xibo-kiosk, listed for clarity)
zenity
dunst
unclutter
opendoas

# Networking
avahi
nss-mdns
wireguard-tools
NetworkManager-wifi

# Remove unnecessary packages
-gnome-initial-setup
-gnome-tour
%end

# RPMFusion repositories
%post --erroronfail
# Add RPMFusion repos
dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-43.noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-43.noarch.rpm

# Swap ffmpeg-free for ffmpeg
dnf swap -y ffmpeg-free ffmpeg --allowerasing || true
%end

# Install xibo-kiosk and player packages from central package portal
%post --erroronfail
# Add xiboplayer repository (hosts all packages: xibo-kiosk, xiboplayer-electron,
# xiboplayer-chromium, arexibo)
cat > /etc/yum.repos.d/xiboplayer.repo << 'EOF'
[xiboplayer]
name=Xibo Players
baseurl=https://dnf.xiboplayer.org/rpm/fedora/$releasever/$basearch/
enabled=1
gpgcheck=0
EOF

# Install all available players
dnf install -y xibo-kiosk xiboplayer-electron xiboplayer-chromium arexibo

# Register players via alternatives (highest priority = default)
alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/xiboplayer-electron 30
alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/xiboplayer-chromium 20
alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/arexibo 10
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

# Enable services
%post --erroronfail
systemctl enable gdm
systemctl enable avahi-daemon
systemctl set-default graphical.target
%end

# Final cleanup
%post --erroronfail
# Ensure all xibo files have correct ownership
chown -R xibo:xibo /home/xibo

# Clean dnf cache
dnf clean all
%end

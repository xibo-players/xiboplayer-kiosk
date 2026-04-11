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
firstboot --disable
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

# Disk configuration — auto-detect first non-USB, non-removable disk
# The %pre script writes the disk name to /tmp/install-disk
# which is included here via %include
%include /tmp/disk-config


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
openssh-server

# Preseed tooling — jq parses xibo.config_url JSON + USB setup.json (#73)
jq

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

# Install ALL players — the boot menu selects the default via xibo.profile=
# Profiles: chromium (default), electron, arexibo
# Set via ISO boot menu or iPXE: kernel vmlinuz inst.ks=... xibo.profile=electron
dnf install -y xiboplayer-kiosk xiboplayer-chromium xiboplayer-electron arexibo

# Register all players with alternatives
alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/xiboplayer-chromium 30
alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/xiboplayer-electron 20
alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/arexibo 10

# ========================================================================
# Preseed parsing (#68) — extract xibo.* kernel cmdline params and the
# xibo.config_url= JSON fetch into /etc/xiboplayer-preseed.env.
# ========================================================================
# Four-layer precedence (most specific wins):
#   Layer 0  — baked-in defaults (profile=chromium if nothing given)
#   Layer 1  — xibo.config_url=https://…/setup.json (curl+jq in %post)
#   Layer 2  — USB /setup.json (#73 adds xibo-usb-preseed.sh)
#   Layer 3  — per-field xibo.*= kernel params (this block, overrides above)
#   Layer 4  — interactive zenity menu (#67, reads preseed.env, prompts gaps)
#
# Layer 1 and 3 are implemented here. Layer 2 reuses the same env file via
# xibo-usb-preseed.sh. Layer 4 reads the env file via a _preseed_get()
# helper in kiosk/xibo-zenity-lib.sh (#67).
#
# Security: the jq allowlist regex rejects shell metacharacters BEFORE
# writing to preseed.env. The preseed file is NEVER sourced with `.` —
# values are extracted via grep+cut to avoid the shell parser entirely
# (defense-in-depth against a future maintainer weakening the regex).

install -d /etc

# --- Layer 1: xibo.config_url= JSON fetch -------------------------------
CONFIG_URL=$(sed -n 's/.*xibo\.config_url=\([^ ]*\).*/\1/p' /proc/cmdline)
if [ -n "$CONFIG_URL" ]; then
    echo "preseed: fetching $CONFIG_URL"
    # curl is in the anaconda environment; jq was added to %packages.
    # --fail → non-zero on HTTP error. --max-time 30 → bounded wait.
    # --silent → no progress meter in install log. Allowlist regex:
    # alphanumerics, dot, underscore, slash, hyphen, colon, at, plus,
    # equals, space. Rejects $, backtick, ;, &, |, >, <, \, newline.
    if curl --silent --fail --max-time 30 "$CONFIG_URL" \
        | jq -r '
            to_entries[]
            | select(.value | type == "string")
            | select(.value | test("^[A-Za-z0-9._/@:+=\\- ]+$"))
            | "xibo.\(.key)=\(.value)"
        ' > /etc/xiboplayer-preseed.env 2>/dev/null; then
        echo "preseed: fetched $(wc -l < /etc/xiboplayer-preseed.env) key(s) from config_url"
    else
        echo "preseed: WARNING — config_url fetch failed or returned invalid JSON, continuing" >&2
        : > /etc/xiboplayer-preseed.env
    fi
else
    : > /etc/xiboplayer-preseed.env
fi

# --- Layer 3: per-field xibo.*= kernel params (override Layer 1) --------
# Walk every token on /proc/cmdline, extract anything matching xibo.KEY=VAL,
# overwrite the corresponding line in preseed.env. The xibo.config_url key
# itself is skipped — it's an instruction for Layer 1, not a value to store.
for tok in $(tr ' ' '\n' < /proc/cmdline | grep -E '^xibo\.[a-z_]+='); do
    key="${tok%%=*}"
    val="${tok#*=}"
    if [ "$key" = "xibo.config_url" ]; then
        continue
    fi
    # Remove any previous entry for this key (from Layer 1), then append.
    sed -i "/^${key//./\\.}=/d" /etc/xiboplayer-preseed.env 2>/dev/null || true
    echo "${key}=${val}" >> /etc/xiboplayer-preseed.env
done

echo "preseed: /etc/xiboplayer-preseed.env now has $(wc -l < /etc/xiboplayer-preseed.env) line(s)"

# --- _preseed_get helper (inline — no sourcing the env file) ------------
# Extracts a single key's value by exact name. Fails closed (empty string)
# if the file is missing or the key is absent. Used below + by Item A's
# xibo-zenity-lib.sh at runtime.
_preseed_get() {
    grep "^$1=" /etc/xiboplayer-preseed.env 2>/dev/null | head -1 | cut -d= -f2-
}

# --- Profile selection (was the whole previous block, still authoritative) --
# Keeps the old behaviour: default chromium if unset or unrecognised.
PROFILE=$(_preseed_get "xibo.profile")
PROFILE="${PROFILE:-chromium}"

case "$PROFILE" in
  electron)
    alternatives --set xiboplayer /usr/bin/xiboplayer-electron
    PLAYER="Electron"; SERVICE="xiboplayer-electron.service" ;;
  arexibo)
    alternatives --set xiboplayer /usr/bin/arexibo
    PLAYER="Arexibo"; SERVICE="arexibo.service" ;;
  *)
    alternatives --set xiboplayer /usr/bin/xiboplayer-chromium
    PLAYER="Chromium"; SERVICE="xiboplayer-chromium.service" ;;
esac

# Write setup-result.json so the kiosk knows which player to start
mkdir -p /home/xibo/.config/xiboplayer
cat > /home/xibo/.config/xiboplayer/setup-result.json << SETUPEOF
{"player": "$PLAYER", "service": "$SERVICE"}
SETUPEOF
chown -R xibo:xibo /home/xibo/.config/xiboplayer
echo "Default player: $PLAYER ($SERVICE)"

# --- Apply system-level preseed values immediately (we're already root) --
# Timezone and locale are straightforward system-level calls. Wi-Fi uses
# the xibo-set-wifi.sh helper installed by the xiboplayer-kiosk RPM at
# /usr/share/xiboplayer-kiosk/xibo-set-wifi.sh (new in #68). The SSH
# pubkey (if set) writes the xibo user's authorized_keys and enables
# sshd.service so MSPs can remote-diagnose via the debug dump (#70).

XIBO_TIMEZONE=$(_preseed_get "xibo.timezone")
if [ -n "$XIBO_TIMEZONE" ]; then
    timedatectl set-timezone "$XIBO_TIMEZONE" 2>/dev/null \
        && echo "preseed: timezone set to $XIBO_TIMEZONE" \
        || echo "preseed: WARNING — timedatectl set-timezone $XIBO_TIMEZONE failed" >&2
fi

XIBO_LOCALE=$(_preseed_get "xibo.locale")
if [ -n "$XIBO_LOCALE" ]; then
    localectl set-locale "LANG=$XIBO_LOCALE" 2>/dev/null \
        && echo "preseed: locale set to $XIBO_LOCALE" \
        || echo "preseed: WARNING — localectl set-locale $XIBO_LOCALE failed" >&2
fi

XIBO_WIFI_SSID=$(_preseed_get "xibo.wifi_ssid")
XIBO_WIFI_PSK=$(_preseed_get "xibo.wifi_psk")
if [ -n "$XIBO_WIFI_SSID" ]; then
    # Already root in kickstart %post — call the helper directly, no doas.
    /usr/share/xiboplayer-kiosk/xibo-set-wifi.sh "$XIBO_WIFI_SSID" "$XIBO_WIFI_PSK" \
        && echo "preseed: wifi connected to $XIBO_WIFI_SSID" \
        || echo "preseed: WARNING — wifi helper failed for $XIBO_WIFI_SSID" >&2
fi

# SSH pubkey — allows MSP remote support. The value is URL-encoded (spaces
# as %20) to survive kernel cmdline quoting. Example:
#   xibo.ssh_pubkey=ssh-ed25519%20AAAAC3...%20operator@msp
# We decode the spaces back before writing the key.
XIBO_SSH_PUBKEY=$(_preseed_get "xibo.ssh_pubkey")
if [ -n "$XIBO_SSH_PUBKEY" ]; then
    install -d -m 0700 -o xibo -g xibo /home/xibo/.ssh
    # Replace %20 with space (the most common case) and trim trailing newline.
    # Any other percent-encoding the operator used will be preserved as-is
    # in the authorized_keys line, which is harmless if it matches what the
    # client sends (it won't match if the operator made a mistake, and the
    # only symptom is "key not accepted" — fail closed, operator fixes).
    decoded=$(printf '%s' "$XIBO_SSH_PUBKEY" | sed 's/%20/ /g')
    echo "$decoded" > /home/xibo/.ssh/authorized_keys
    chmod 0600 /home/xibo/.ssh/authorized_keys
    chown xibo:xibo /home/xibo/.ssh/authorized_keys
    systemctl enable sshd.service 2>/dev/null || true
    echo "preseed: ssh pubkey installed, sshd enabled"
fi
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

# Configure AccountsService — default GNOME session for first boot
# The setup wizard will switch to gnome-kiosk-script-wayland after configuration
%post --erroronfail
mkdir -p /var/lib/AccountsService/users
cat > /var/lib/AccountsService/users/xibo << 'EOF'
[User]
Session=gnome
SystemAccount=false
EOF
%end

# Configure opendoas.
# MUST match mkosi-extra/etc/doas.conf byte-for-byte. The two copies serve
# parallel install paths (kickstart-installed targets don't get mkosi-extra/)
# and drift between them causes bugs like #67's WiFi flow failing with
# 'permission denied' on kickstart-installed machines (Phase 6-bis finding).
%post --erroronfail
cat > /etc/doas.conf << 'EOF'
permit nopass xibo cmd reboot
permit nopass xibo cmd shutdown
permit nopass xibo cmd alternatives
permit nopass xibo cmd /usr/share/xiboplayer-kiosk/xibo-activate-kiosk.sh
permit nopass xibo cmd /usr/share/xiboplayer-kiosk/xibo-deactivate-kiosk.sh
permit nopass xibo cmd /usr/share/xiboplayer-kiosk/xibo-set-wifi.sh
permit nopass xibo cmd /usr/share/xiboplayer-kiosk/xibo-set-timezone.sh
permit nopass xibo cmd /usr/share/xiboplayer-kiosk/xibo-set-locale.sh
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

# Skip gnome-initial-setup completely — our wizard handles system config
%post --erroronfail
mkdir -p /usr/share/gnome-initial-setup
cat > /usr/share/gnome-initial-setup/vendor.conf << 'EOF'
[pages]
skip=language;keyboard;network;timezone;privacy;software;account;summary;welcome;password
EOF
systemctl mask gnome-initial-setup.service gnome-initial-setup-first-login.service
%end

# Install setup wizard autostart for first boot (normal GNOME session)
%post --erroronfail
mkdir -p /home/xibo/.config/autostart
cp /usr/share/xiboplayer-kiosk/xiboplayer-setup.desktop /home/xibo/.config/autostart/
chown -R xibo:xibo /home/xibo/.config/autostart
%end

# Disable GNOME donation popup.
# 0x0 Singularity 4 #374: the correct key is donation-reminder-enabled on the
# housekeeping plugin. The old show-donation-popup key (on desktop.interface)
# was confirmed ineffective in Singularity 6 #370 on 0.4.19. Set BOTH keys
# for belt-and-braces across GNOME versions — unknown keys are harmless.
%post --erroronfail
su - xibo -c "dbus-run-session bash -c '
  gsettings set org.gnome.settings-daemon.plugins.housekeeping donation-reminder-enabled false
  gsettings set org.gnome.desktop.interface show-donation-popup false
'" || true
%end

# Enable services
%post --erroronfail
systemctl enable gdm avahi-daemon keyd
systemctl set-default graphical.target
# Note: the system-level power management config files — Layer 1 logind
# (/etc/systemd/logind.conf.d/no-idle.conf), Layer 2 gschema override
# (/usr/share/glib-2.0/schemas/90_xiboplayer-kiosk.gschema.override), and
# Layer 4 GDM dconf profile + db + locks (/etc/dconf/profile/gdm,
# /etc/dconf/db/gdm.d/00-xiboplayer-kiosk, /etc/dconf/db/gdm.d/locks/
# 00-xiboplayer-kiosk) — are all shipped by the xiboplayer-kiosk RPM
# installed earlier in %post. The RPM's %post scriptlet runs
# glib-compile-schemas + dconf update to activate them. No manual heredoc
# or compilation needed here since 0.4.21 — see commit / issue #69.
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

# Auto-detect install disk — "best available" heuristic.
#
# Preference order (most→least preferred bus class): NVMe > virtio > SATA.
# Within the first class that yields ANY qualifying disk, pick the LARGEST.
# Stop at the first class with a match — don't mix NVMe and SATA candidates.
#
# Rationale: kiosk hardware typically has a single internal disk that
# belongs to the fastest available bus class. When a machine has e.g. one
# NVMe + one SATA spinner, the NVMe should always win. When a machine has
# two identical NVMes (rare), the larger one wins. When a machine has only
# SATA, that's what we install on.
#
# Skipped: removable devices (USB sticks, SD-card-in-USB-reader,
# CD-ROMs), disks smaller than 8 GB (too small for a kiosk image).
#
# Logs EVERY candidate considered to /tmp/disk-autodetect.log so the
# anaconda install log shows the full selection trail.
%pre --erroronfail
DISK=""
DISK_SIZE=0
LOG=/tmp/disk-autodetect.log
: > "$LOG"
echo "xibo disk autodetect: $(date)" >> "$LOG"

# Outer loop: bus preference order (stop at first class with any match)
for class in nvme vd sd; do
    for dev in /sys/block/${class}*; do
        [ -e "$dev" ] || continue
        name=$(basename "$dev")

        # Skip removable (USB sticks, CD-ROMs, SD cards via usb-storage)
        if [ "$(cat "$dev/removable" 2>/dev/null)" = "1" ]; then
            echo "  skip $name: removable=1" >> "$LOG"
            continue
        fi

        # Skip small disks (< 8 GB) — almost certainly not the install target
        size_bytes=$(( $(cat "$dev/size" 2>/dev/null || echo 0) * 512 ))
        if [ "$size_bytes" -lt 8000000000 ]; then
            echo "  skip $name: too small (${size_bytes} bytes)" >> "$LOG"
            continue
        fi

        rotational=$(cat "$dev/queue/rotational" 2>/dev/null || echo "?")
        echo "  candidate: $name (${size_bytes} bytes, rotational=$rotational, class=$class)" >> "$LOG"

        # Within this class, track the LARGEST qualifying disk
        if [ "$size_bytes" -gt "$DISK_SIZE" ]; then
            DISK="$name"
            DISK_SIZE="$size_bytes"
        fi
    done
    # If this class yielded a match, skip lower-priority classes
    if [ -n "$DISK" ]; then
        echo "  class $class yielded winner $DISK, stopping search" >> "$LOG"
        break
    fi
done

if [ -z "$DISK" ]; then
    echo "ERROR: No suitable install disk found" >&2
    echo "ERROR: No suitable install disk found" >> "$LOG"
    # Hard fallback — sda may not exist, but the kickstart must still produce
    # /tmp/disk-config or anaconda fails the %include at the top of the file.
    DISK="sda"
    DISK_SIZE=0
fi

echo "Selected install disk: /dev/$DISK ($DISK_SIZE bytes)" >&2
echo "WINNER: $DISK ($DISK_SIZE bytes)" >> "$LOG"
cat > /tmp/disk-config << EOF
zerombr
clearpart --all --initlabel --disklabel=gpt --drives=$DISK
ignoredisk --only-use=$DISK
autopart --nolvm --nohome --type=plain --fstype=xfs
EOF
%end

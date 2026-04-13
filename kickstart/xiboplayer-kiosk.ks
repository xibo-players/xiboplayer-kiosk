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
#
# Mode: default to graphical anaconda so operators get a progress bar +
# slide carousel during install (#104). Text-mode fallback is still
# available via a dedicated grub/isolinux menuentry that appends
# `inst.text` to the kernel line — use it on headless / low-VRAM /
# serial-only targets.
#
# `skipx` is still set — the installed TARGET system does not run X11
# at all (gnome-kiosk + gdm use Wayland). skipx tells anaconda to not
# bother configuring an X11 server on the target; it does NOT affect
# whether anaconda ITSELF uses a graphical (GTK) or text UI during
# install. Those are orthogonal.
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
# ── Lean baseline: start from @^minimal-environment, add ONLY what
# the kiosk explicitly needs. No -exclude lines anywhere — every
# excluded package we've tried created hidden dep-tree conflicts
# (xdg-user-dirs-gtk + gdm cascade, #127→#140 debugging saga).
# Apps we don't want (gnome-tour, cheese, etc.) either don't get
# pulled by @^minimal-environment at all, or we remove them via
# `dnf remove` in %post where failures are loud and the system is
# already booting.
#
# Codec stack (ffmpeg + gstreamer-plugin-libav + friends) lives in
# RPM Fusion free, which isn't enabled until %post installs
# xiboplayer-release. Those packages therefore install via
# `dnf install` in %post, NOT here — doing it here would cause the
# "Software Selection: missing packages" warning that spurred the
# earlier --ignoremissing detour.

# ── Environment ────────────────────────────────────────────────
@^minimal-environment

# ── Display manager + kiosk compositor ─────────────────────────
gdm
gnome-kiosk
gnome-kiosk-script-session
xorg-x11-server-Xwayland

# ── Audio (pipewire + wireplumber pulled transitively) ─────────
pipewire-alsa

# ── Networking + WiFi + mDNS + VPN + SSH ───────────────────────
NetworkManager-wifi
avahi
nss-mdns
wireguard-tools
openssh-server

# ── GPU / VA-API drivers ───────────────────────────────────────
mesa-dri-drivers
mesa-va-drivers
mesa-vulkan-drivers
intel-media-driver
libva

# ── Fonts ──────────────────────────────────────────────────────
dejavu-sans-fonts
dejavu-sans-mono-fonts
google-noto-sans-fonts
google-noto-emoji-color-fonts

# ── Locale coverage for the first-boot Language picker (#103) ──
glibc-all-langpacks

# ── Kiosk runtime + first-boot menu ────────────────────────────
zenity
python3-gobject
dunst
unclutter
opendoas
keyd
ptyxis
vim-enhanced
jq
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

# Install the default players — the boot menu selects the default via xibo.profile=
# Profiles: chromium (default), electron. Arexibo is netinstall opt-in only —
# the arexibo package is pulled conditionally below when xibo.profile=arexibo
# was passed on the kernel line (the profile switch %post handles the install).
dnf install -y xiboplayer-kiosk xiboplayer-chromium xiboplayer-electron

# Register default players with alternatives
alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/xiboplayer-chromium 30
alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/xiboplayer-electron 20

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

# --- Layer 2: USB /setup.json auto-detect (#73) -------------------------
# Scan USB-transport block devices for /setup.json at the root of the
# first filesystem, validate via jq allowlist regex, merge into the
# preseed env file. Runs with --trust because kickstart %post is the
# install-time operator-present context. First-boot reconfigure calls
# the same script without --trust (zenity confirmation dialog).
if [ -x /usr/share/xiboplayer-kiosk/xibo-usb-preseed.sh ]; then
    /usr/share/xiboplayer-kiosk/xibo-usb-preseed.sh --trust 2>&1 || true
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
    # Netinstall opt-in only — arexibo is NOT in default %packages (#71).
    # Pull it on-demand from the network + register with alternatives.
    # Best-effort: if the network is down, fall back to chromium so the
    # install still produces a working kiosk.
    if dnf install -y arexibo 2>/dev/null; then
        alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/arexibo 10
        alternatives --set xiboplayer /usr/bin/arexibo
        PLAYER="Arexibo"; SERVICE="arexibo.service"
    else
        echo "preseed: WARNING — arexibo install failed, falling back to chromium" >&2
        alternatives --set xiboplayer /usr/bin/xiboplayer-chromium
        PLAYER="Chromium"; SERVICE="xiboplayer-chromium.service"
    fi
    ;;
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
elif [ -f /tmp/xibo-wifi-preseed ]; then
    # #72 — the pre-anaconda whiptail TUI stashed WiFi credentials in
    # /tmp when /mnt/sysimage was not yet mounted. Apply them now that
    # we're in %post (target is / here — chroot semantics).
    . /tmp/xibo-wifi-preseed
    if [ -n "$SSID" ]; then
        echo "preseed: applying stashed WiFi credentials for $SSID"
        /usr/share/xiboplayer-kiosk/xibo-set-wifi.sh "$SSID" "$PSK" "$KEYMGMT" \
            && echo "preseed: wifi connected to $SSID (from whiptail TUI)" \
            || echo "preseed: WARNING — wifi helper failed for $SSID" >&2
    fi
    # Always wipe the stash — contains the PSK in plaintext.
    shred -u /tmp/xibo-wifi-preseed 2>/dev/null || rm -f /tmp/xibo-wifi-preseed
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
#
# Defensive mkdir: the gdm RPM ships /etc/gdm/ via %files, but intermittent
# install failures (dnf resolution drift, missing weak deps on noninteractive
# builds, etc.) have been seen where /etc/gdm/ is absent when %post runs,
# causing `cat > /etc/gdm/custom.conf` to fail with ENOENT on the parent
# directory and aborting anaconda under --erroronfail. Creating the dir
# unconditionally costs nothing and makes this step robust against upstream
# packaging changes.
%post --erroronfail
mkdir -p /etc/gdm
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

# Configure AccountsService — default session for the xibo user.
#
# Sets the xibo user's GDM session DIRECTLY to gnome-kiosk-script-wayland
# (the gnome-kiosk-script-session package provides
# /usr/share/wayland-sessions/gnome-kiosk-script-wayland.desktop). On
# first boot, GDM auto-login lands directly inside
# kiosk/gnome-kiosk-script.xibo.sh — no intermediate vanilla-GNOME
# session, no session switch mid-flight.
#
# History: before #71 (commit 12b003c, 0.4.25) this was `Session=gnome`
# because the libadwaita Python wizard (xiboplayer-setup.py) was
# expected to autostart in vanilla GNOME on first boot, fill in the CMS
# config, then switch AccountsService to gnome-kiosk-script-wayland via
# doas and log out. #71 deleted the Python wizard (0x0 rejected the
# libadwaita approach in S6 #313-378) and was supposed to also flip
# this Session= line, but that edit was forgotten — which stranded
# every 0.4.25+ install in vanilla GNOME forever. Fixed in #91.
#
# The zenity first-boot menu (#67) now runs INSIDE the kiosk session
# via kiosk/gnome-kiosk-script.xibo.sh, gated by the
# ~/.local/share/xibo/first-boot-done sentinel. No separate
# "wizard session → kiosk session" switch is needed.
#
# Mirrored at mkosi-extra/var/lib/AccountsService/users/xibo for the
# mkosi + atomic/bootc build paths.
%post --erroronfail
mkdir -p /var/lib/AccountsService/users
cat > /var/lib/AccountsService/users/xibo << 'EOF'
[User]
Session=gnome-kiosk-script-wayland
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
permit nopass xibo cmd /usr/share/xiboplayer-kiosk/xibo-set-player.sh
permit nopass xibo cmd /usr/share/xiboplayer-kiosk/xibo-set-keyboard.sh
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

# NOTE: gnome-initial-setup is no longer installed as of #101 — the
# package is removed from %packages at the top of this file. The old
# vendor.conf / systemctl mask block that used to live here (skip
# every page + mask both services) is gone because it's unreachable
# when the package isn't on disk.

# NOTE: the old libadwaita/GTK4 first-boot wizard (Python .py + .desktop
# autostart) was replaced by the zenity first-boot menu (#67,
# kiosk/xibo-first-boot.sh). The menu runs inside the kiosk session
# itself — gated by ~/.local/share/xibo/first-boot-done — so no
# desktop-file autostart is needed, and the session never switches out
# of gnome-kiosk to a normal GNOME session.

# Disable GNOME donation popup + workspace overview.
# 0x0 Singularity 4 #374: the correct key is donation-reminder-enabled on the
# housekeeping plugin. The old show-donation-popup key (on desktop.interface)
# was confirmed ineffective in Singularity 6 #370 on 0.4.19. Set BOTH keys
# for belt-and-braces across GNOME versions — unknown keys are harmless.
#
# wm.preferences/theme='Adwaita' (#99) suppresses the workspace preview /
# Activities Overview that would flash on first login of a gnome-kiosk
# session. Mirrored in the gschema override (Layer 2), GDM dconf db +
# locks (Layer 4), and gnome-kiosk-script.xibo.sh runtime (Layer 3).
%post --erroronfail
su - xibo -c "dbus-run-session bash -c '
  gsettings set org.gnome.settings-daemon.plugins.housekeeping donation-reminder-enabled false
  gsettings set org.gnome.desktop.interface show-donation-popup false
  gsettings set org.gnome.desktop.wm.preferences theme \"Adwaita\"
  gsettings set org.gnome.desktop.interface color-scheme \"prefer-dark\"
  gsettings set org.gnome.desktop.interface gtk-theme \"Adwaita-dark\"
  gsettings set org.gnome.desktop.background picture-uri \"\"
  gsettings set org.gnome.desktop.background picture-uri-dark \"\"
  gsettings set org.gnome.desktop.background picture-options \"none\"
  gsettings set org.gnome.desktop.background primary-color \"#000000\"
  gsettings set org.gnome.desktop.screensaver picture-uri \"\"
  gsettings set org.gnome.desktop.screensaver picture-options \"none\"
  gsettings set org.gnome.desktop.screensaver primary-color \"#000000\"
'" || true
%end

# Suppress the xdg-user-dirs locale-rename dialog via config file
# only (we can no longer exclude the xdg-user-dirs-gtk package because
# Fedora 43's anaconda hard-requires it — see the NOTE at the end of
# %packages). `enabled=False` in /etc/xdg/user-dirs.conf tells both
# xdg-user-dirs-update and the xdg-user-dirs-gtk GTK listener to not
# touch ~/.config/user-dirs.dirs on login — GNOME never prompts
# "rename ~/Downloads to ~/Baixades?" and XDG paths stay in English
# for script / doc consistency.
%post --erroronfail
mkdir -p /etc/xdg
cat > /etc/xdg/user-dirs.conf << 'EOF'
# enabled=False tells xdg-user-dirs-update to NOT touch ~/.config/
# user-dirs.dirs on login. Prevents locale-based directory renaming.
enabled=False
EOF
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

# ========================================================================
# Pre-anaconda WiFi picker (#72) — whiptail TUI for WiFi-only machines
# ========================================================================
# Runs BEFORE anaconda's network phase so the user never sees the complex
# built-in GTK WiFi dialog. Closes the gap for netinstall / iPXE users
# booting off a machine with NO wired ethernet.
#
# Skip conditions (any one of these triggers fall-through):
#   1. Network is already up (wired link found)
#   2. xibo.wifi_ssid= was preseeded via kernel cmdline (#68)
#   3. No wireless hardware detected
#
# Flow:
#   - Wait for NetworkManager to settle (10s retry loop)
#   - nmcli dev wifi rescan + 2s sleep for results
#   - whiptail --menu picker built from `nmcli dev wifi list`
#   - whiptail --passwordbox if secured
#   - write NM keyfile to installer env AND /mnt/sysimage if mounted
#   - fall back to /tmp/xibo-wifi-preseed stash if target not yet mounted
#   - nmcli connection up so the installer has network for the rest
#
# Security: the _validate_nm_string function is copied VERBATIM from
# kiosk/xibo-set-wifi.sh (authoritative source). Both paths must produce
# byte-identical keyfiles for the same input — this will be enforced by
# a bats test in #74. Any change to one MUST be mirrored in the other.
#
# Error handling: all failures are non-fatal (|| true). If whiptail /
# nmcli aren't available in the %pre environment, or the user cancels,
# we fall through to anaconda's own network phase (which is the status
# quo). The worst case is "user sees anaconda's WiFi dialog" — never
# "install aborted with no network".
#
# --- NOTE ---
# Despite --erroronfail on the %pre, the block body wraps every step in
# `|| true` so only a hard failure of the `cat /tmp/…` exit-hook aborts.
# See the trailing `exit 0` below.
%pre --erroronfail
set +e
LOG=/tmp/xibo-wifi-tui.log
: > "$LOG"
echo "xibo wifi-tui: $(date)" >> "$LOG"

# Bail if whiptail or nmcli aren't available (older installer envs)
if ! command -v whiptail >/dev/null 2>&1 || ! command -v nmcli >/dev/null 2>&1; then
    echo "  whiptail or nmcli missing — skipping" >> "$LOG"
    exit 0
fi

# Skip if wired is already up
if nmcli -t -f TYPE,STATE dev status 2>/dev/null | grep -qE '^ethernet:connected'; then
    echo "  wired connected — skipping" >> "$LOG"
    exit 0
fi

# Skip if preseeded via kernel cmdline (#68 / Layer 2)
if grep -qE 'xibo\.wifi_ssid=' /proc/cmdline; then
    echo "  xibo.wifi_ssid= preseeded — skipping" >> "$LOG"
    exit 0
fi

# Skip if no wireless hardware
if ! nmcli -t -f DEVICE,TYPE dev status 2>/dev/null | grep -q ':wifi$'; then
    echo "  no wireless hardware — skipping" >> "$LOG"
    exit 0
fi

# --- Wait for NetworkManager readiness (up to 10s) --------------------
nmcli radio wifi on 2>/dev/null || true
for i in 1 2 3 4 5 6 7 8 9 10; do
    state=$(nmcli -t -f STATE general status 2>/dev/null)
    case "$state" in
        connected|disconnected) break ;;
    esac
    sleep 1
done
echo "  nmcli state after wait: $state" >> "$LOG"

whiptail --title "xiboplayer kiosk — Wi-Fi" --infobox "Scanning for Wi-Fi networks..." 8 50
nmcli dev wifi rescan 2>/dev/null || true
sleep 2

# Build the whiptail menu options from nmcli output. Format:
#   "SSID" "signal% security"
# Dedupe by SSID (keep strongest), sort by signal desc, skip empties.
MENU_OPTS=$(nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list 2>/dev/null \
    | awk -F: 'NF>=3 && $1!="" { if (!seen[$1] || $2 > seen[$1]) { seen[$1]=$2; sec[$1]=$3 } }
               END { for (s in seen) printf "%s|%s|%s\n", s, seen[s], sec[s] }' \
    | sort -t'|' -k2,2nr)

if [ -z "$MENU_OPTS" ]; then
    whiptail --title "xiboplayer kiosk — Wi-Fi" \
        --msgbox "No Wi-Fi networks found.\n\nContinuing with anaconda's built-in network phase." 10 60
    exit 0
fi

# Convert to whiptail --menu tag/item pairs
WHIPTAIL_ARGS=""
while IFS='|' read -r ssid signal security; do
    [ -z "$ssid" ] && continue
    # Sanity-cap signal to reasonable bounds for display
    [ "$signal" -gt 100 ] 2>/dev/null && signal=100
    label="${signal}%% ${security:-open}"
    WHIPTAIL_ARGS="$WHIPTAIL_ARGS \"$ssid\" \"$label\""
done <<< "$MENU_OPTS"

# Also offer hidden network + skip rows as synthetic options
WHIPTAIL_ARGS="$WHIPTAIL_ARGS \"(hidden)\" \"Enter SSID manually\""
WHIPTAIL_ARGS="$WHIPTAIL_ARGS \"(skip)\"   \"Use wired / configure later\""

# Use eval to expand the quoted pairs into whiptail's argv
SSID=$(eval "whiptail --title 'xiboplayer kiosk — Wi-Fi' \
    --menu 'Select a Wi-Fi network:' 20 70 12 $WHIPTAIL_ARGS" \
    3>&1 1>&2 2>&3) || exit 0

if [ "$SSID" = "(skip)" ] || [ -z "$SSID" ]; then
    echo "  user skipped" >> "$LOG"
    exit 0
fi

if [ "$SSID" = "(hidden)" ]; then
    SSID=$(whiptail --title "xiboplayer kiosk — Hidden SSID" \
        --inputbox "Enter the hidden network SSID:" 10 60 \
        3>&1 1>&2 2>&3) || exit 0
    [ -z "$SSID" ] && exit 0
    SECURITY="WPA2"  # assume secured for hidden networks
else
    # Extract security for the chosen SSID from the menu data
    SECURITY=$(printf '%s\n' "$MENU_OPTS" | awk -F'|' -v ssid="$SSID" '$1==ssid {print $3; exit}')
fi

# Ask for password if secured
PSK=""
if [ -n "$SECURITY" ] && [ "$SECURITY" != "--" ] && [ "$SECURITY" != "open" ]; then
    PSK=$(whiptail --title "xiboplayer kiosk — Wi-Fi password" \
        --passwordbox "Enter password for \"$SSID\":" 10 60 \
        3>&1 1>&2 2>&3) || exit 0
fi

# --- Input validation (verbatim from kiosk/xibo-set-wifi.sh) -----------
# ⚠ SYNC: kiosk/xibo-set-wifi.sh is the authoritative source. If you
# change _validate_nm_string there, mirror the change here.
_validate_nm_string() {
    local label="$1" value="$2"
    if printf '%s' "$value" | grep -qE $'[\x00-\x1f]'; then
        echo "$label contains control characters — rejected" >&2
        return 2
    fi
    if printf '%s' "$value" | grep -qE '^\[|\[(connection|wifi|wifi-security|ipv4|ipv6)\]'; then
        echo "$label contains an NM INI section header — rejected" >&2
        return 2
    fi
    return 0
}

if ! _validate_nm_string "SSID" "$SSID"; then
    whiptail --title "xiboplayer kiosk — Invalid SSID" \
        --msgbox "The SSID contains characters that are not allowed. Skipping Wi-Fi." 10 60
    exit 0
fi
if [ -n "$PSK" ] && ! _validate_nm_string "PSK" "$PSK"; then
    whiptail --title "xiboplayer kiosk — Invalid password" \
        --msgbox "The password contains characters that are not allowed. Skipping Wi-Fi." 10 60
    exit 0
fi

# --- Write NM keyfile (also from kiosk/xibo-set-wifi.sh, simplified) ---
SAFE_NAME=$(printf '%s' "$SSID" | tr -c '[:alnum:]._-' '_')
UUID=$(cat /proc/sys/kernel/random/uuid)
KEYMGMT="wpa-psk"
[ -z "$PSK" ] && KEYMGMT="none"

write_keyfile_at() {
    local dir="$1"
    mkdir -p "$dir"
    umask 077
    if [ "$KEYMGMT" = "none" ]; then
        cat > "$dir/${SAFE_NAME}.nmconnection" << INIEOF
[connection]
id=$SSID
uuid=$UUID
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=$SSID

[ipv4]
method=auto

[ipv6]
method=ignore
INIEOF
    else
        cat > "$dir/${SAFE_NAME}.nmconnection" << INIEOF
[connection]
id=$SSID
uuid=$UUID
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=$SSID

[wifi-security]
key-mgmt=$KEYMGMT
psk=$PSK

[ipv4]
method=auto

[ipv6]
method=ignore
INIEOF
    fi
    chmod 600 "$dir/${SAFE_NAME}.nmconnection"
    chown root:root "$dir/${SAFE_NAME}.nmconnection" 2>/dev/null || true
}

# Layer 1: installer environment NM (active right now in %pre)
write_keyfile_at "/etc/NetworkManager/system-connections"

# Layer 2: if /mnt/sysimage is already mounted by anaconda, write there too
#          so the keyfile survives into the installed system
if [ -d "/mnt/sysimage/etc/NetworkManager" ]; then
    write_keyfile_at "/mnt/sysimage/etc/NetworkManager/system-connections"
    echo "  wrote keyfile to /mnt/sysimage (target already mounted)" >> "$LOG"
else
    # Stash for %post to re-apply once /mnt/sysimage is available.
    # SSID/PSK in /tmp is acceptable — the file is mode 0600 and %post
    # will wipe it after processing.
    umask 077
    cat > /tmp/xibo-wifi-preseed << STASHEOF
SSID=$SSID
PSK=$PSK
KEYMGMT=$KEYMGMT
STASHEOF
    chmod 600 /tmp/xibo-wifi-preseed
    echo "  stashed to /tmp/xibo-wifi-preseed (target not yet mounted)" >> "$LOG"
fi

# Activate in the installer env so anaconda has network for %packages
nmcli connection reload 2>/dev/null || true
nmcli connection up "$SSID" 2>/dev/null || true

whiptail --title "xiboplayer kiosk — Wi-Fi" --infobox "Connected to $SSID. Proceeding with install..." 8 60
sleep 2

exit 0
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

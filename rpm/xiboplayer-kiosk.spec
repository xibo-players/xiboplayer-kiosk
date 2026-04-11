Name:           xiboplayer-kiosk
Version:        0.4.23
Release:        1%{?dist}
Summary:        Kiosk session scripts for Xibo digital signage players

License:        AGPLv3+
URL:            https://xiboplayer.org
Source0:        %{name}-%{version}.tar.gz

BuildArch:      noarch
BuildRequires:  systemd-rpm-macros

Requires:       gnome-kiosk-script-session
Requires:       dunst
Requires:       unclutter
Requires:       zenity
Requires:       opendoas
Requires:       keyd
Requires:       mesa-va-drivers
Requires:       libva
Requires:       dconf
Requires:       glib2
Requires:       alternatives
Requires:       python3-gobject
Requires:       libadwaita
Requires:       gnome-control-center
Recommends:     xiboplayer-chromium
Suggests:       xiboplayer-electron
Suggests:       arexibo
Recommends:     libva-intel-driver

%description
Kiosk session scripts for running Xibo digital signage players as full-screen
displays under GNOME Kiosk. Includes a first-boot registration wizard,
session holder with health monitoring, dunst notification config, and
a systemd user unit for the player process.

The player binary is managed via the alternatives system (/usr/bin/xiboplayer).
Each player package registers itself:

  sudo alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/xiboplayer-electron 30
  sudo alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/xiboplayer-chromium 20
  sudo alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/arexibo 10

Select the active player:

  sudo alternatives --config xiboplayer

%prep
%autosetup -n %{name}-%{version}

%install
install -Dm755 kiosk/gnome-kiosk-script.sh %{buildroot}%{_datadir}/xiboplayer-kiosk/gnome-kiosk-script.sh
install -Dm755 kiosk/gnome-kiosk-script.xibo.sh %{buildroot}%{_datadir}/xiboplayer-kiosk/gnome-kiosk-script.xibo.sh
install -Dm755 kiosk/gnome-kiosk-script.xibo-init.sh %{buildroot}%{_datadir}/xiboplayer-kiosk/gnome-kiosk-script.xibo-init.sh
install -Dm644 kiosk/dunstrc %{buildroot}%{_datadir}/xiboplayer-kiosk/dunstrc
install -Dm755 kiosk/xibo-keyd-run.sh %{buildroot}%{_datadir}/xiboplayer-kiosk/xibo-keyd-run.sh
install -Dm755 kiosk/xibo-show-ip.sh %{buildroot}%{_datadir}/xiboplayer-kiosk/xibo-show-ip.sh
install -Dm755 kiosk/xibo-show-cms.sh %{buildroot}%{_datadir}/xiboplayer-kiosk/xibo-show-cms.sh
install -Dm644 kiosk/keyd-xibo.conf %{buildroot}%{_sysconfdir}/keyd/xibo.conf
install -Dm644 kiosk/copr-keyd.repo %{buildroot}%{_sysconfdir}/yum.repos.d/copr-keyd.repo
install -Dm755 kiosk/xiboplayer-setup.py %{buildroot}%{_datadir}/xiboplayer-kiosk/xiboplayer-setup.py
install -Dm644 kiosk/xiboplayer-setup.desktop %{buildroot}%{_datadir}/xiboplayer-kiosk/xiboplayer-setup.desktop
install -Dm755 kiosk/xibo-activate-kiosk.sh %{buildroot}%{_datadir}/xiboplayer-kiosk/xibo-activate-kiosk.sh
install -Dm755 kiosk/xibo-deactivate-kiosk.sh %{buildroot}%{_datadir}/xiboplayer-kiosk/xibo-deactivate-kiosk.sh
# Issue #68 — NM keyfile writer (called by doas from the xibo user or directly
# by root from kickstart %post). Never passes the PSK on the nmcli CLI,
# closing the /proc/<pid>/cmdline leak window.
install -Dm755 kiosk/xibo-set-wifi.sh %{buildroot}%{_datadir}/xiboplayer-kiosk/xibo-set-wifi.sh
# Issue #70 — support bundle collector (Ctrl+D via keyd, zenity row in
# the first-boot + reconfigure menus, /usr/bin/xibo-debug-dump CLI).
install -Dm755 kiosk/xibo-debug-dump.sh %{buildroot}%{_datadir}/xiboplayer-kiosk/xibo-debug-dump.sh
# /usr/bin/xibo-debug-dump symlink so technicians can run it from an
# SSH session by just typing `xibo-debug-dump`.
install -d %{buildroot}%{_bindir}
ln -sf %{_datadir}/xiboplayer-kiosk/xibo-debug-dump.sh %{buildroot}%{_bindir}/xibo-debug-dump

# System config files — the kiosk RPM IS the kiosk definition, so the
# system-level config that makes a kiosk stay on forever + suppresses the
# GNOME donation popup ships with the package, not via image overlay. The
# source paths under mkosi-extra/ are reused here (mkosi-extra is also
# copied by ExtraTrees in mkosi builds and by atomic/Containerfile COPY;
# both overwrite with identical content which is harmless).
#
# Layer 1: logind idle/lid/power key suppression (system-level, never blanks)
install -Dm644 mkosi-extra/etc/systemd/logind.conf.d/no-idle.conf %{buildroot}%{_sysconfdir}/systemd/logind.conf.d/no-idle.conf
# Layer 2: system-wide GSchema override (default values for every session)
install -Dm644 mkosi-extra/usr/share/glib-2.0/schemas/90_xiboplayer-kiosk.gschema.override %{buildroot}%{_datadir}/glib-2.0/schemas/90_xiboplayer-kiosk.gschema.override
# Layer 4: GDM greeter dconf profile + db + locks (gdm user session, LOCKED)
install -Dm644 mkosi-extra/etc/dconf/profile/gdm %{buildroot}%{_sysconfdir}/dconf/profile/gdm
install -Dm644 mkosi-extra/etc/dconf/db/gdm.d/00-xiboplayer-kiosk %{buildroot}%{_sysconfdir}/dconf/db/gdm.d/00-xiboplayer-kiosk
install -Dm644 mkosi-extra/etc/dconf/db/gdm.d/locks/00-xiboplayer-kiosk %{buildroot}%{_sysconfdir}/dconf/db/gdm.d/locks/00-xiboplayer-kiosk

# Create skel directory for gnome-kiosk-script dispatcher
install -d %{buildroot}%{_sysconfdir}/skel/.local/bin
install -m755 kiosk/gnome-kiosk-script.sh %{buildroot}%{_sysconfdir}/skel/.local/bin/gnome-kiosk-script

%files
%dir %{_datadir}/xiboplayer-kiosk
%{_datadir}/xiboplayer-kiosk/gnome-kiosk-script.sh
%{_datadir}/xiboplayer-kiosk/gnome-kiosk-script.xibo.sh
%{_datadir}/xiboplayer-kiosk/gnome-kiosk-script.xibo-init.sh
%{_datadir}/xiboplayer-kiosk/dunstrc
%{_datadir}/xiboplayer-kiosk/xibo-keyd-run.sh
%{_datadir}/xiboplayer-kiosk/xibo-show-ip.sh
%{_datadir}/xiboplayer-kiosk/xibo-show-cms.sh
%{_datadir}/xiboplayer-kiosk/xiboplayer-setup.py
%{_datadir}/xiboplayer-kiosk/xiboplayer-setup.desktop
%{_datadir}/xiboplayer-kiosk/xibo-activate-kiosk.sh
%{_datadir}/xiboplayer-kiosk/xibo-deactivate-kiosk.sh
%{_datadir}/xiboplayer-kiosk/xibo-set-wifi.sh
%{_datadir}/xiboplayer-kiosk/xibo-debug-dump.sh
%{_bindir}/xibo-debug-dump
%{_sysconfdir}/keyd/xibo.conf
%{_sysconfdir}/yum.repos.d/copr-keyd.repo
%{_sysconfdir}/skel/.local/bin/gnome-kiosk-script
%config(noreplace) %{_sysconfdir}/systemd/logind.conf.d/no-idle.conf
%{_datadir}/glib-2.0/schemas/90_xiboplayer-kiosk.gschema.override
%config %{_sysconfdir}/dconf/profile/gdm
%config %{_sysconfdir}/dconf/db/gdm.d/00-xiboplayer-kiosk
%config %{_sysconfdir}/dconf/db/gdm.d/locks/00-xiboplayer-kiosk

%post
# Compile GSchema overrides + refresh dconf database so the Layer 2 and
# Layer 4 files installed above take effect. glib-compile-schemas is
# normally run by glib2's file trigger on any RPM that ships a file under
# /usr/share/glib-2.0/schemas/, so this is belt-and-braces. dconf update
# has NO file trigger and MUST be run explicitly — without it, the file
# at /etc/dconf/db/gdm.d/00-xiboplayer-kiosk is not compiled into the
# /etc/dconf/db/gdm database that the GDM greeter actually reads, and
# Layer 4 is silently inert.
/usr/bin/glib-compile-schemas %{_datadir}/glib-2.0/schemas/ &>/dev/null || :
/usr/bin/dconf update &>/dev/null || :

%changelog
* Sat Apr 11 2026 Pau Aliagas <linuxnow@gmail.com> - 0.4.23-1
- Support bundle collector xibo-debug-dump.sh (#70). Gathers logs
  (journalctl user + kernel + services), configs (preseed.env, player
  config.json, cms.json, setup-result.json), hardware inventory
  (lscpu, lspci, lsusb, lsblk, GPU), NetworkManager state, timedate,
  locale, and kiosk-specific state (firstboot sentinels, alternatives,
  logind.conf) into a zstd-compressed tarball at
  \$HOME/Downloads/xibo-debug-<hostname>-<timestamp>.tar.zst.
- Sensitive values (CMS keys, Wi-Fi PSKs, basic-auth URL credentials)
  redacted before staging via an inline _redact() helper with 5 sed
  patterns. Post-tar SECURITY assertion refuses to ship the bundle if
  any NetworkManager keyfile, /etc/shadow, browser Cookies directory,
  doas.conf, or .ssh/id_ private key sneaks in — deletes the tarball
  and fires a critical notify-send.
- Three triggers: Ctrl+D via keyd (new d = command(...) binding in
  kiosk/keyd-xibo.conf); direct CLI via the new /usr/bin/xibo-debug-
  dump symlink; zenity menu row (wired up in #67). A fourth trigger
  — labeled-USB auto-collect via udev — is supported via
  xibo-debug-dump --to-usb but the udev rule itself is not yet
  installed (follow-up).
- notify-send + zenity --info confirmation dialog show the tarball
  path and size when the collection succeeds, so non-technical
  operators know where to find the file.

* Sat Apr 11 2026 Pau Aliagas <linuxnow@gmail.com> - 0.4.22-1
- iPXE / kernel preseed infrastructure + best-available-disk autodetect
  (#68). Kickstart %post now parses every xibo.* kernel param, fetches
  xibo.config_url= JSON via curl+jq with an inline allowlist regex that
  rejects shell metacharacters, writes everything to
  /etc/xiboplayer-preseed.env, and applies system-level values
  (timedatectl, localectl, wifi via xibo-set-wifi.sh, ssh pubkey with
  sshd enablement).
- Supported xibo.* params: profile, config_url, cms_url, cms_key,
  display_name, timezone, locale, wifi_ssid, wifi_psk, ssh_pubkey.
- 4-layer precedence: baked defaults -> xibo.config_url= JSON ->
  USB /setup.json (reserved for #73) -> per-field xibo.*= kernel params
  -> zenity menu prompts (reserved for #67). Per-field params override
  the URL JSON.
- New kiosk/xibo-set-wifi.sh — NetworkManager keyfile writer that avoids
  the /proc/<pid>/cmdline PSK leak of 'nmcli dev wifi connect … password
  …'. Input validation rejects control characters and NM INI section
  headers in the SSID/PSK. Permitted via doas for the xibo user in both
  mkosi-extra/etc/doas.conf and the kickstart heredoc.
- Best-available-disk %pre autodetect — replaces the previous 'first
  non-removable >8GB' walk with a 'largest in best-preferred bus class'
  heuristic. Preference order NVMe > virtio > SATA; stops at first class
  with any match; within the winning class, picks the largest qualifying
  disk; logs every candidate to /tmp/disk-autodetect.log for debug.
- Added 'jq' and 'openssh-server' to kickstart %packages. jq is needed
  by the config_url fetch pipeline and by #73's USB setup.json scanner.
  sshd is enabled only when xibo.ssh_pubkey= is set.

* Sat Apr 11 2026 Pau Aliagas <linuxnow@gmail.com> - 0.4.21-1
- 4-layer power management fix + correct GNOME donation popup suppression
  (#69). Fixes screen blanking observed on 0.4.19 (Singularity 6 #370) and
  the donation popup still appearing despite the old show-donation-popup
  gsetting (the correct key per 0x0 Singularity 4 #374 is
  donation-reminder-enabled on the housekeeping plugin).
- Philosophy shift: the kiosk RPM IS the kiosk definition, not just a
  lockdown helper. All 5 system config files (Layer 1 logind, Layer 2
  gschema override, Layer 4 gdm dconf profile + db + locks) now ship with
  the RPM/DEB. Install paths are consistent across mkosi builds,
  atomic/bootc, kickstart-from-ISO, and plain 'dnf install xiboplayer-
  kiosk' on any Fedora system — all four now produce identical on-disk
  state for the power/donation keys.
- Layer 1: /etc/systemd/logind.conf.d/no-idle.conf extended with
  HandlePowerKey, HandleSuspendKey, HandleHibernateKey. Shipped by the
  RPM/DEB (was previously only in mkosi-extra + kickstart heredoc — that
  heredoc is now removed since the RPM covers it).
- Layer 2: new /usr/share/glib-2.0/schemas/90_xiboplayer-kiosk.gschema.override
  with power/screensaver/idle keys + BOTH donation keys
  (donation-reminder-enabled AND show-donation-popup, belt-and-braces).
  Shipped by RPM/DEB. glib2's file trigger compiles it automatically on
  install; RPM %post scriptlet also invokes glib-compile-schemas as a
  guard.
- Layer 3: runtime session gsettings in gnome-kiosk-script.xibo.sh
  updated to set donation-reminder-enabled alongside the legacy
  show-donation-popup, plus power-button-action='nothing' and
  idle-activation-enabled=false which were missing.
- Layer 4: new GDM greeter dconf lock. Three new files shipped by the
  RPM/DEB: /etc/dconf/profile/gdm (critical — Fedora's gdm RPM does NOT
  ship it; without it dconf update compiles a database GDM never reads,
  and Layer 4 is silently inert), /etc/dconf/db/gdm.d/00-xiboplayer-kiosk,
  and /etc/dconf/db/gdm.d/locks/00-xiboplayer-kiosk. RPM %post scriptlet
  runs 'dconf update' to compile the database (no file trigger for dconf,
  so this is mandatory — not just a guard).
- Added Requires: dconf, glib2 so the RPM %post scriptlet commands are
  always available.
- Removed the now-redundant inline heredocs from kickstart %post (the RPM
  install covers all 5 files when 'dnf install xiboplayer-kiosk' runs in
  anaconda's transaction), removed the redundant COPY lines from
  atomic/Containerfile (same rationale — the dnf install of the kiosk
  RPM in the Containerfile installs the files), and removed mkosi.postinst
  (the RPM %post scriptlet runs during mkosi's dnf install phase).

* Sat Apr 11 2026 Pau Aliagas <linuxnow@gmail.com> - 0.4.20-1
- Version bump. Planned feature scope tracked as GitHub issues #67-#74
  (zenity first-boot menu, iPXE preseed + best-available-disk, power-mgmt
  + donation fix, debug tarball, drop arexibo, pre-anaconda whiptail TUI,
  USB auto-detect, bats + shellcheck CI). No functional changes in this
  release — rebuilds images with current main-branch state.

* Mon Apr 07 2026 Pau Aliagas <linuxnow@gmail.com> - 0.4.19-1
- Redesign first-boot: normal GNOME session with setup wizard, then kiosk lockdown
- Setup wizard uses native GNOME panels for WiFi, timezone, language, display
- Arexibo CMS config in wizard; Chromium/Electron self-configure
- ISO boot menu with 3 player entries (all players always installed)
- Ctrl+R reconfigure: reset player config or return to full GNOME wizard
- Add xiboplayer-setup.desktop, xibo-activate-kiosk.sh, xibo-deactivate-kiosk.sh
- Add python3-gobject, libadwaita, gnome-control-center as dependencies

* Mon Apr 06 2026 Pau Aliagas <linuxnow@gmail.com> - 0.4.18-1
- Fix QCOW2 boot (KernelCommandLine=root=gpt-auto), image matrix docs, download links

* Sun Apr 05 2026 Pau Aliagas <linuxnow@gmail.com> - 0.4.17-1
- Fix aarch64 mkosi shim, add ARM64 iPXE and netinstall, comprehensive image matrix docs

* Sat Apr 04 2026 Pau Aliagas <linuxnow@gmail.com> - 0.4.16-1
- Security fixes, wizard fixes (localectl, setup-result), grub hidden, disk partitioning, VLC restored, RPM Fusion codecs, mesa-dri for VMs, bootc naming, WiFi reconnect, connectivity health-check, reboot wrappers, arm64 DEB, mirrorlist for netinstall, CI hardening

* Thu Apr 02 2026 Pau Aliagas <linuxnow@gmail.com> - 0.4.15-1
- Fix session holder service detection, zenity fallback, arexibo.service, iPXE boot

* Wed Apr 02 2026 Pau Aliagas <linuxnow@gmail.com> - 0.4.14-1
- Fix: package xiboplayer-setup.py in RPM/DEB (missing — broke netinstall wizard)
- Fix: add python3-gobject + libadwaita to kickstart packages
- Fix: add cdrom install source for offline ISO
- Feat: iPXE network boot menu with install profiles
- Feat: xibo.profile= kernel parameter (full/electron/chromium)

* Thu Apr 02 2026 Pau Aliagas <linuxnow@gmail.com> - 0.4.13-1
- Libadwaita first-boot wizard, fedora-bootc base for smaller atomic images, trimmed offline ISO, GNOME donation popup fix

* Wed Apr 01 2026 Pau Aliagas <linuxnow@gmail.com> - 0.4.12-1
- Player selection first, Electron/Chromium use own setup UI

* Tue Mar 31 2026 Pau Aliagas <linuxnow@gmail.com> - 0.4.11-1
- Everything + netinstall ISOs, aarch64 QCOW2, first-boot guide

* Mon Mar 30 2026 Pau Aliagas <linuxnow@gmail.com> - 0.4.4-3
- Ship keyd COPR repo file so dnf can resolve keyd dependency (fixes #4)

* Sun Feb 23 2026 Pau Aliagas <linuxnow@gmail.com> - 0.4.4-2
- Update homepage URL to https://xiboplayer.org

* Sun Feb 23 2026 Pau Aliagas <linuxnow@gmail.com> - 0.4.4-1
- Rename package from xibo-kiosk to xiboplayer-kiosk
- Update custom domain to dl.xiboplayer.org

* Sat Feb 21 2026 Pau Aliagas <linuxnow@gmail.com> - 0.3.0-1
- Add player selection to setup wizard (Electron, Chromium, Arexibo)
- Add Google Geolocation API key prompt (optional)
- Write player environment file for systemd service
- Add EnvironmentFile directive to xibo-player.service
- Show active player in status (Ctrl+I) and reconfigure (Ctrl+R) dialogs
- Allow alternatives command via doas

* Wed Feb 18 2026 Pau Aliagas <linuxnow@gmail.com> - 1.0.0-1
- Initial standalone xiboplayer-kiosk package
- Separated from arexibo repository for independent versioning
- Player binary managed via alternatives system (/usr/bin/xiboplayer)

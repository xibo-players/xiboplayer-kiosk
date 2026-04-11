Name:           xiboplayer-kiosk
Version:        0.4.20
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
%{_sysconfdir}/keyd/xibo.conf
%{_sysconfdir}/yum.repos.d/copr-keyd.repo
%{_sysconfdir}/skel/.local/bin/gnome-kiosk-script

%changelog
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

Name:           xiboplayer-kiosk
Version:        0.4.4
Release:        2%{?dist}
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
Requires:       (xiboplayer-electron or xiboplayer-chromium or arexibo)
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
install -Dm644 kiosk/xibo-player.service %{buildroot}%{_userunitdir}/xibo-player.service
install -Dm755 kiosk/xibo-keyd-run.sh %{buildroot}%{_datadir}/xiboplayer-kiosk/xibo-keyd-run.sh
install -Dm755 kiosk/xibo-show-ip.sh %{buildroot}%{_datadir}/xiboplayer-kiosk/xibo-show-ip.sh
install -Dm755 kiosk/xibo-show-cms.sh %{buildroot}%{_datadir}/xiboplayer-kiosk/xibo-show-cms.sh
install -Dm644 kiosk/keyd-xibo.conf %{buildroot}%{_sysconfdir}/keyd/xibo.conf

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
%{_userunitdir}/xibo-player.service
%{_sysconfdir}/keyd/xibo.conf
%{_sysconfdir}/skel/.local/bin/gnome-kiosk-script

%changelog
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

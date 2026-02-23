# xiboplayer-kiosk

Kiosk session scripts for running Xibo digital signage players as full-screen displays under GNOME Kiosk.

## Features

- **First-boot registration wizard** — Zenity-based CMS credential collector
- **Session holder** — keeps GNOME Kiosk alive with health monitoring and auto-restart
- **Systemd user service** — manages the player process with resource limits
- **Keyboard shortcuts** — Ctrl+I (show IP/status), Ctrl+R (reconfigure CMS)
- **Dunst notifications** — persistent status overlay for connection state
- **Player-agnostic** — works with any Xibo player via the alternatives system

## Player Selection (alternatives)

The player binary is managed via the Linux alternatives system (`/usr/bin/xiboplayer`). Each player package registers itself with a priority:

```bash
# xiboplayer-electron (priority 30 — highest = default)
sudo alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/xiboplayer-electron 30

# xiboplayer-chromium (priority 20)
sudo alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/xiboplayer-chromium 20

# arexibo (priority 10)
sudo alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/arexibo 10
```

Switch the active player:

```bash
sudo alternatives --config xiboplayer
```

## Installation

### Fedora (RPM)

```bash
sudo dnf config-manager addrepo --from-repofile=https://dnf.xiboplayer.org/rpm/fedora/43/xiboplayer.repo
sudo dnf install xiboplayer-kiosk

# Install a player (pick one)
sudo dnf install xiboplayer-electron  # Electron-based (recommended)
sudo dnf install xiboplayer-chromium  # Chromium kiosk wrapper
sudo dnf install arexibo              # Rust-based native player
```

### Ubuntu/Debian (DEB)

```bash
curl -fsSL https://dnf.xiboplayer.org/deb/DEB-GPG-KEY-xiboplayer.asc | \
  sudo gpg --dearmor -o /usr/share/keyrings/xiboplayer.gpg
echo "deb [signed-by=/usr/share/keyrings/xiboplayer.gpg] https://dnf.xiboplayer.org/deb/ubuntu/24.04 ./" | \
  sudo tee /etc/apt/sources.list.d/xiboplayer.list
sudo apt update && sudo apt install xiboplayer-kiosk
```

### Kickstart (automated install)

Boot from Fedora netinstall and add to kernel command line:

```
inst.ks=https://raw.githubusercontent.com/xibo-players/xiboplayer-kiosk/main/kickstart/xiboplayer-kiosk.ks
```

## Files Installed

| File | Location | Purpose |
|------|----------|---------|
| `gnome-kiosk-script.sh` | `/usr/share/xiboplayer-kiosk/` | Dispatcher (wizard or session holder) |
| `gnome-kiosk-script.xibo.sh` | `/usr/share/xiboplayer-kiosk/` | Session holder with health monitoring |
| `gnome-kiosk-script.xibo-init.sh` | `/usr/share/xiboplayer-kiosk/` | First-boot CMS registration wizard |
| `xibo-player.service` | `~/.config/systemd/user/` | Systemd user service for the player |
| `xibo-keyd-run.sh` | `/usr/share/xiboplayer-kiosk/` | Keyboard shortcut bridge (keyd→user session) |
| `xibo-show-ip.sh` | `/usr/share/xiboplayer-kiosk/` | Ctrl+I: show IP/CMS/status |
| `xibo-show-cms.sh` | `/usr/share/xiboplayer-kiosk/` | Ctrl+R: show CMS info, offer reconfigure |
| `keyd-xibo.conf` | `/etc/keyd/xibo.conf` | Keyboard shortcut definitions |
| `dunstrc` | `/usr/share/xiboplayer-kiosk/` | Notification daemon configuration |
| `gnome-kiosk-script` | `/etc/skel/.local/bin/` | Dispatcher installed for new users |

## For Player Package Maintainers

To make your player work with xiboplayer-kiosk, your package must:

1. Install a binary that accepts `--allow-offline <data-dir>` arguments
2. Register with the alternatives system in your package scripts:

**RPM (`%post` / `%postun`):**
```
%post
alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/yourplayer 20

%postun
if [ $1 -eq 0 ]; then
    alternatives --remove xiboplayer /usr/bin/yourplayer
fi
```

**DEB (`postinst` / `prerm`):**
```
# postinst
update-alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/yourplayer 20

# prerm
update-alternatives --remove xiboplayer /usr/bin/yourplayer
```

## License

AGPLv3+ — see [LICENSE](LICENSE)

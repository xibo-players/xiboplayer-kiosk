# xibo-kiosk

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
sudo dnf config-manager addrepo --from-repofile=https://xibo-players.github.io/xibo-kiosk/rpm/fedora/43/xibo-kiosk.repo
sudo dnf install xibo-kiosk

# Install a player (pick one)
sudo dnf install xiboplayer-electron  # Electron-based (recommended)
sudo dnf install xiboplayer-chromium  # Chromium kiosk wrapper
sudo dnf install arexibo              # Rust-based native player
```

### Ubuntu/Debian (DEB)

```bash
curl -fsSL https://xibo-players.github.io/xibo-kiosk/deb/DEB-GPG-KEY-xibo-kiosk.asc | \
  sudo gpg --dearmor -o /usr/share/keyrings/xibo-kiosk.gpg
echo "deb [signed-by=/usr/share/keyrings/xibo-kiosk.gpg] https://xibo-players.github.io/xibo-kiosk/deb/ubuntu/24.04 ./" | \
  sudo tee /etc/apt/sources.list.d/xibo-kiosk.list
sudo apt update && sudo apt install xibo-kiosk
```

### Kickstart (automated install)

Boot from Fedora netinstall and add to kernel command line:

```
inst.ks=https://raw.githubusercontent.com/xibo-players/xibo-kiosk/main/kickstart/xibo-kiosk.ks
```

## Files Installed

| File | Location | Purpose |
|------|----------|---------|
| `gnome-kiosk-script.sh` | `/usr/share/xibo-kiosk/` | Dispatcher (wizard or session holder) |
| `gnome-kiosk-script.xibo.sh` | `/usr/share/xibo-kiosk/` | Session holder with health monitoring |
| `gnome-kiosk-script.xibo-init.sh` | `/usr/share/xibo-kiosk/` | First-boot CMS registration wizard |
| `xibo-player.service` | `~/.config/systemd/user/` | Systemd user service for the player |
| `xibo-keyd-run.sh` | `/usr/share/xibo-kiosk/` | Keyboard shortcut bridge (keyd→user session) |
| `xibo-show-ip.sh` | `/usr/share/xibo-kiosk/` | Ctrl+I: show IP/CMS/status |
| `xibo-show-cms.sh` | `/usr/share/xibo-kiosk/` | Ctrl+R: show CMS info, offer reconfigure |
| `keyd-xibo.conf` | `/etc/keyd/xibo.conf` | Keyboard shortcut definitions |
| `dunstrc` | `/usr/share/xibo-kiosk/` | Notification daemon configuration |
| `gnome-kiosk-script` | `/etc/skel/.local/bin/` | Dispatcher installed for new users |

## For Player Package Maintainers

To make your player work with xibo-kiosk, your package must:

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

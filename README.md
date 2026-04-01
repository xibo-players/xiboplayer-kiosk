# xiboplayer-kiosk

Turn any PC or Raspberry Pi into a digital signage kiosk. Download a ready-made image, flash it to a USB stick or SD card, boot and connect to your Xibo CMS.

**[Download kiosk images](https://github.com/xibo-players/xiboplayer-kiosk/releases/latest)** | **[Installation guide](https://www.xiboplayer.org/downloads/)** | **[First-boot guide](https://www.xiboplayer.org/guide/first-boot)**

### Available images

| Image | Hardware | Description |
|-------|----------|-------------|
| **Everything ISO** | PC / laptop | Self-contained offline installer — flash to USB and boot |
| **Netinstall ISO** | PC / laptop | Lightweight ISO — downloads packages during install |
| **Raw disk** | Raspberry Pi, NUC | Flash directly to SD card or SSD |
| **QCOW2** | Virtual machines | Ready-to-boot VM for GNOME Boxes, virt-manager or QEMU |
| **Atomic ISO** | Any | Immutable Fedora Silverblue with automatic updates and rollback |

### Quick start

```bash
# Option 1: Flash a ready-made image (recommended)
# Download from https://github.com/xibo-players/xiboplayer-kiosk/releases/latest

# Option 2: Install on existing Fedora
sudo dnf install https://dl.xiboplayer.org/rpm/fedora/43/noarch/xiboplayer-release-43-7.fc43.noarch.rpm
sudo dnf install xiboplayer-kiosk xiboplayer-electron

# Option 3: Install on Ubuntu / Debian
# See https://www.xiboplayer.org/downloads/
```

Default login: `xibo` / `xibo` — change your password after first boot.

---

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
sudo dnf install \
  https://dl.xiboplayer.org/rpm/fedora/43/noarch/xiboplayer-release-43-7.fc43.noarch.rpm
sudo dnf install xiboplayer-kiosk

# Install a player (pick one)
sudo dnf install xiboplayer-electron  # Electron-based (recommended)
sudo dnf install xiboplayer-chromium  # Chromium kiosk wrapper
sudo dnf install arexibo              # Rust-based native player
```

### Ubuntu/Debian (DEB)

```bash
curl -fsSL https://dl.xiboplayer.org/deb/DEB-GPG-KEY-xiboplayer.asc | \
  sudo gpg --dearmor -o /usr/share/keyrings/xiboplayer.gpg
echo "deb [signed-by=/usr/share/keyrings/xiboplayer.gpg] https://dl.xiboplayer.org/deb/ubuntu/24.04 ./" | \
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

## FPS monitoring

Both Electron and Chromium support an optional Chrome DevTools Protocol port for monitoring FPS, memory and renderer performance. Not enabled by default.

**Enable:**
```bash
# Chromium (port 9222)
systemctl --user set-environment XIBOPLAYER_DEBUG_PORT=9222
systemctl --user restart xiboplayer-chromium

# Electron (port 9223)
systemctl --user set-environment XIBOPLAYER_DEBUG_PORT=9223
systemctl --user restart xiboplayer-electron
```

**Disable:**
```bash
systemctl --user unset-environment XIBOPLAYER_DEBUG_PORT
systemctl --user restart xiboplayer-chromium  # or xiboplayer-electron
```

The port binds to `127.0.0.1` only — not accessible from the network. Query via `http://localhost:9222/json` for targets and `Performance.getMetrics` for FPS, heap size and layout counts.

## License

AGPLv3+ — see [LICENSE](LICENSE)

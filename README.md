# xiboplayer-kiosk

Turn any PC or Raspberry Pi into a digital signage kiosk. Download a ready-made image, flash it to a USB stick or SD card, boot and connect to your Xibo CMS.

**[Download kiosk images](https://github.com/xibo-players/xiboplayer-kiosk/releases/latest)** | **[Installation guide](https://www.xiboplayer.org/downloads/)** | **[First-boot guide](https://www.xiboplayer.org/guide/first-boot)**

### Images

| Image | Arch | Size | Download | Use case |
|-------|------|------|----------|----------|
| **Kickstart (traditional installer)** | | | | |
| Everything ISO | x86_64 | 1.1GB | [xiboplayer-kiosk-everything_x86_64.iso](https://github.com/xibo-players/xiboplayer-kiosk/releases/latest/download/xiboplayer-kiosk-everything_0.4.17_x86_64.iso) | Offline install on PCs, NUCs, signage boxes. No internet needed — all packages bundled. Flash to USB, boot, walk away. |
| Everything ISO | aarch64 | 1.2GB | [xiboplayer-kiosk-everything_aarch64.iso](https://github.com/xibo-players/xiboplayer-kiosk/releases/latest/download/xiboplayer-kiosk-everything_0.4.17_aarch64.iso) | Offline install on Raspberry Pi 5, ARM servers. |
| Netinstall ISO | x86_64 | 1.1GB | [xiboplayer-kiosk-netinstall_x86_64.iso](https://github.com/xibo-players/xiboplayer-kiosk/releases/latest/download/xiboplayer-kiosk-netinstall_0.4.17_x86_64.iso) | Lightweight installer, downloads from Fedora mirrors. Always gets latest packages. |
| Netinstall ISO | aarch64 | 1.1GB | [xiboplayer-kiosk-netinstall_aarch64.iso](https://github.com/xibo-players/xiboplayer-kiosk/releases/latest/download/xiboplayer-kiosk-netinstall_0.4.17_aarch64.iso) | Same for ARM64. Raspberry Pi 5 network install. |
| **Disk images (ready to boot, no installer)** | | | | |
| QCOW2 | x86_64 | 1.7GB | [xiboplayer-kiosk_x86_64.qcow2](https://github.com/xibo-players/xiboplayer-kiosk/releases/latest/download/xiboplayer-kiosk_0.4.17_x86_64.qcow2) | Virtual machines (QEMU/KVM, Proxmox, Gnome Boxes). Import and boot — no installation step. |
| QCOW2 | aarch64 | ~1.7GB | [xiboplayer-kiosk_aarch64.qcow2](https://github.com/xibo-players/xiboplayer-kiosk/releases/latest/download/xiboplayer-kiosk_0.4.17_aarch64.qcow2) | ARM64 virtual machines. |
| Raw disk | x86_64 | 1.1GB | [xiboplayer-kiosk_x86_64.raw.xz](https://github.com/xibo-players/xiboplayer-kiosk/releases/latest/download/xiboplayer-kiosk_0.4.17_x86_64.raw.xz) | Write to SSD/eMMC: `xz -d *.raw.xz && dd if=*.raw of=/dev/sdX`. Industrial/embedded. |
| Raw disk | aarch64 | ~1.1GB | [xiboplayer-kiosk_aarch64.raw.xz](https://github.com/xibo-players/xiboplayer-kiosk/releases/latest/download/xiboplayer-kiosk_0.4.17_aarch64.raw.xz) | **Raspberry Pi 5 SD card**: `xz -d *.raw.xz && sudo dd if=*.raw of=/dev/mmcblkX bs=4M status=progress`. |
| **Atomic (immutable OS, container-native updates)** | | | | |
| Atomic ISO | x86_64 | ~1.5GB | [Latest Atomic release](https://github.com/xibo-players/xiboplayer-kiosk/releases?q=atomic) | Immutable Fedora bootc kiosk. `bootc upgrade` with instant rollback. Best for fleet deployments. |
| Atomic ISO | aarch64 | ~1.5GB | [Latest Atomic release](https://github.com/xibo-players/xiboplayer-kiosk/releases?q=atomic) | Same for ARM64. RPi5 fleets, ARM kiosks. |
| OCI Container | multi-arch | — | `ghcr.io/xibo-players/xiboplayer-kiosk:43` | Pull with podman/docker. Base for custom images or `bootc switch` from existing Fedora. |
| **Network boot (no USB/SD card needed)** | | | | |
| iPXE BIOS | x86 | 400KB | [xiboplayer-ipxe-bios.img](https://dl.xiboplayer.org/ipxe/xiboplayer-ipxe-bios.img) | Legacy BIOS PCs. Flash to USB or embed in PXE ROM. Boots from network, shows install menu. |
| iPXE UEFI | x86_64 | 1.1MB | [xiboplayer-ipxe-uefi-x86_64.img](https://dl.xiboplayer.org/ipxe/xiboplayer-ipxe-uefi-x86_64.img) | Modern UEFI PCs. Chainload from existing PXE or flash to USB. |
| iPXE UEFI | aarch64 | 1.1MB | [xiboplayer-ipxe-uefi-aarch64.img](https://dl.xiboplayer.org/ipxe/xiboplayer-ipxe-uefi-aarch64.img) | RPi5 with UEFI firmware, ARM servers. |
| iPXE script | any | 5KB | [boot.ipxe](https://dl.xiboplayer.org/ipxe/boot.ipxe) | Boot menu script. Auto-detects arch. `chain https://dl.xiboplayer.org/ipxe/boot.ipxe` |

### Quick start

| I want to... | Download |
|--------------|----------|
| Install on a PC with USB stick, no internet | [Everything ISO x86_64](https://github.com/xibo-players/xiboplayer-kiosk/releases/latest) |
| Install on Raspberry Pi 5 | [Raw disk aarch64](https://github.com/xibo-players/xiboplayer-kiosk/releases/latest) — dd to SD card |
| Test in a VM quickly | [QCOW2 x86_64](https://github.com/xibo-players/xiboplayer-kiosk/releases/latest) — import into Gnome Boxes |
| Deploy 50 identical kiosks with fleet updates | [Atomic ISO](https://github.com/xibo-players/xiboplayer-kiosk/releases?q=atomic) + `bootc upgrade` |
| Network boot a room of PCs | [iPXE UEFI](https://dl.xiboplayer.org/ipxe/xiboplayer-ipxe-uefi-x86_64.img) + [boot.ipxe](https://dl.xiboplayer.org/ipxe/boot.ipxe) |
| Rebase existing Fedora to kiosk | `bootc switch ghcr.io/xibo-players/xiboplayer-kiosk:43` |
| Install on existing Fedora via RPM | `sudo dnf install xiboplayer-release && sudo dnf install xiboplayer-kiosk xiboplayer-chromium` |
| Install on Ubuntu/Debian | See [downloads page](https://www.xiboplayer.org/downloads/) |

**[Download images](https://github.com/xibo-players/xiboplayer-kiosk/releases/latest)** — Default login: `xibo` / `xibo` — change your password after first boot.

### What's included

All images ship with: xiboplayer-electron + xiboplayer-chromium + arexibo, VLC + mpv + ffmpeg (full codecs) + RPM Fusion plugins, GDM autologin → gnome-kiosk → player selection wizard, VA-API GPU acceleration + mesa-dri fallback, WiFi auto-reconnect + connectivity health-check, Secure Boot chain + GPG-signed packages, iPXE boot profile selection (`xibo.profile=electron|chromium|full`), bootc atomic updates + instant rollback (Atomic images).

---

## Features

- **First-boot registration wizard** — libadwaita GTK4 player selection wizard with zenity fallback
- **Session holder** — keeps GNOME Kiosk alive with health monitoring and auto-restart
- **Systemd user service** — manages the player process with resource limits
- **Keyboard shortcuts** — Ctrl+I (show IP/status), Ctrl+R (reconfigure CMS)
- **Dunst notifications** — persistent status overlay for connection state
- **Player-agnostic** — works with any Xibo player via the alternatives system

## Player Selection (alternatives)

The player binary is managed via the Linux alternatives system (`/usr/bin/xiboplayer`). Each player package registers itself with a priority:

```bash
# xiboplayer-electron (priority 30 — highest = default)
sudo alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/xiboplayer-electron 20

# xiboplayer-chromium (priority 20)
sudo alternatives --install /usr/bin/xiboplayer xiboplayer /usr/bin/xiboplayer-chromium 30

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
sudo dnf install xiboplayer-chromium  # Chromium-based (recommended)
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

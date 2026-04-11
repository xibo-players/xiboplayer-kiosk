# Changelog

## 0.4.23 (2026-04-11)

**Support bundle collector** ([#70](https://github.com/xibo-players/xiboplayer-kiosk/issues/70)).

New `/usr/bin/xibo-debug-dump` command writes a zstd-compressed tarball of kiosk diagnostic state to `$HOME/Downloads/xibo-debug-<hostname>-<timestamp>.tar.zst`. MSP technicians can collect it locally via Ctrl+D, from an SSH session by typing `xibo-debug-dump`, or from the zenity reconfigure menu (#67 will add the menu row).

### What's in the bundle

| File | Content |
|---|---|
| `00-system.txt` | hostname, `/etc/os-release`, `uname -a`, `uptime`, `date` |
| `01-proc-cmdline.txt` | `/proc/cmdline` with `xibo.cms_key=`, `xibo.wifi_psk=`, and basic-auth URL credentials redacted |
| `02-packages.txt` | `rpm -qa` filtered to xibo/arexibo + top 50 of the full list |
| `03-preseed.env.txt` | `/etc/xiboplayer-preseed.env` with secrets redacted |
| `04-<path>.txt` | Player config files with `cmsKey`/`key` redacted |
| `05-systemd-user.txt` | `systemctl --user status` for all xiboplayer services |
| `06-systemd-system.txt` | `systemctl status` for gdm, avahi, keyd, sshd, NetworkManager |
| `07-journal-user.txt` | `journalctl --user -b`, redacted |
| `08-journal-kernel.txt` | `journalctl -b -k` (kernel log) |
| `09-journal-services.txt` | Per-service journalctl for the kiosk's critical services |
| `10-hardware.txt` | `lscpu`, `free`, `df`, `lsblk`, `lspci -nnk`, `lsusb` |
| `11-display.txt` | `loginctl show-user xibo`, `glxinfo -B`, `/sys/class/drm/` |
| `12-network.txt` | `nmcli con/dev/wifi`, `ip addr`, `ip route`, `resolvectl` |
| `13-time-locale.txt` | `timedatectl`, `localectl` |
| `14-kiosk-state.txt` | Firstboot sentinels, alternatives, `no-idle.conf`, `dconf/profile/gdm` |

### Security — what's NOT in the bundle

The script deliberately does **not** collect these, and a post-tar assertion refuses to ship the bundle if any sneak in (deletes tarball + fires a critical `notify-send`):

- `/etc/NetworkManager/system-connections/**` — contains Wi-Fi PSK in cleartext
- `/etc/shadow`, `/etc/gshadow`
- Browser `Cookies*` directories — player session tokens
- `/etc/doas.conf`
- `~/.ssh/id_*` — private keys

### Redaction

An inline `_redact()` helper pipes content through 5 `sed` patterns covering `xibo.cms_key=`, `xibo.wifi_psk=`, `xibo.config_url=user:pass@host`, JSON `"cmsKey"`, and JSON `"key"`. Applied per-file as files are staged — conservative, prefers over-redaction to leaking.

### Triggers

1. **Ctrl+D via keyd** — new `d = command(...)` binding in `kiosk/keyd-xibo.conf`
2. **CLI** — `/usr/bin/xibo-debug-dump` symlink created by RPM spec and DEB build script
3. **Zenity menu row** — wired up by #67
4. **Labeled USB auto-collect** — `xibo-debug-dump --to-usb` looks for a mounted filesystem labeled `XIBO-DEBUG`; the matching udev rule for auto-trigger on plug-in is deferred to a follow-up

## 0.4.22 (2026-04-11)

**iPXE / kernel preseed infrastructure + best-available-disk autodetect** ([#68](https://github.com/xibo-players/xiboplayer-kiosk/issues/68)).

Foundation layer for unattended and partially-attended kiosk deployment. Establishes `/etc/xiboplayer-preseed.env` as the single source of truth for preseeded values, consumed by the zenity first-boot menu (#67), the pre-anaconda whiptail TUI (#72), and the USB auto-detect scanner (#73).

### 4-layer precedence (most specific wins)

```
Layer 0  — baked-in defaults (profile=chromium if nothing given)
Layer 1  — xibo.config_url=https://…/setup.json (curl+jq in %post)
Layer 2  — USB /setup.json (reserved for #73)
Layer 3  — per-field xibo.*= kernel params (this PR, overrides above)
Layer 4  — interactive zenity menu (reserved for #67)
```

### Supported `xibo.*` kernel params

`profile`, `config_url`, `cms_url`, `cms_key`, `display_name`, `timezone`, `locale`, `wifi_ssid`, `wifi_psk`, `ssh_pubkey`.

### New files

- **`kiosk/xibo-set-wifi.sh`** — NetworkManager keyfile writer. Writes `/etc/NetworkManager/system-connections/<SSID>.nmconnection` at `0600 root:root` instead of calling `nmcli dev wifi connect … password …`, closing the brief `/proc/<pid>/cmdline` PSK leak. Shipped by the RPM (`%install` + `%files` entries) and DEB (`install` line in `build-deb.sh`). Permitted via doas for the xibo user in both `mkosi-extra/etc/doas.conf` and the kickstart doas heredoc.
  - Input validation rejects control characters (newline/tab/null) and NM INI section headers in both SSID and PSK — prevents fake `[wifi-security]` section injection via crafted PSK values.
  - SSID filename sanitisation via `tr -c '[:alnum:]._-' '_'` — path traversal attempts become harmless underscore runs.
  - Authoritative source of `_validate_nm_string`: the same function will be copied verbatim into `kickstart/xibo-wifi-tui.sh` when #72 lands. bats test at `tests/unit/set-wifi.bats` (#74) will enforce byte-identical keyfile output between the two copies.

### Kickstart `%post` additions

- Parses every `xibo.*=` token on `/proc/cmdline`, skipping `xibo.config_url` (that's the Layer 1 fetch instruction, not a value to store).
- If `xibo.config_url=` present: `curl --silent --fail --max-time 30` + `jq` with an **inline allowlist regex** (`^[A-Za-z0-9._/@:+=\- ]+$`) that rejects shell metacharacters (`$`, backtick, `;`, `&`, `|`, `>`, `<`, `\`, newline) **before** values are written to `preseed.env`. Keeps the file safe even though it's never `source`d.
- `_preseed_get()` helper extracts values via `grep | cut` — the preseed file is **never** sourced with `.`, closing the shell-parser attack surface.
- Applies system-level values immediately: `timedatectl set-timezone`, `localectl set-locale LANG=…`, `xibo-set-wifi.sh <SSID> <PSK>` (root, no doas needed in %post), and the `xibo.ssh_pubkey=` pubkey → `/home/xibo/.ssh/authorized_keys` + `systemctl enable sshd.service` dance.
- `xibo.ssh_pubkey=` is **URL-encoded** on the kernel cmdline (`%20` for space) to survive quoting. Example: `xibo.ssh_pubkey=ssh-ed25519%20AAAAC3…%20operator@msp`. Decoded back to spaces before writing `authorized_keys`.

### `%pre` — best-available-disk autodetect rewrite

Replaces the previous "first non-removable ≥8 GB" walk with a ranked "largest in best-preferred bus class" heuristic:

1. Preference order: **NVMe > virtio > SATA**. Stops at the first class with any match — doesn't mix candidates across classes.
2. Within the winning class, picks the **largest** qualifying disk.
3. Removable devices (USB sticks, CD-ROMs, SD cards via `usb-storage`) skipped via `/sys/block/*/removable == 1`.
4. Disks < 8 GB skipped (too small for a kiosk image).
5. **Logs every candidate** considered (name + size + rotational + class) to `/tmp/disk-autodetect.log` so the anaconda install log shows the full selection trail. Previous version only logged the winner.
6. Fallback to `DISK=sda` if nothing qualifies — anaconda still gets a valid `/tmp/disk-config` to `%include`.

### Security notes

- `xibo.config_url=` values should use **path-based tokens** (e.g. `https://ops.example.com/k/a8f2c9d1b4e7.json`) rather than inline `user:pass@host` credentials. The full URL is captured in `/proc/cmdline` AND in the anaconda install logs (`/root/anaconda-ks.log`, `/var/log/anaconda/*`) — path-based secrets are rotatable without touching the installed machine; Basic Auth credentials in the URL are not.
- The jq allowlist regex is a defence-in-depth layer: even if a future maintainer accidentally introduces `source /etc/xiboplayer-preseed.env` elsewhere, the values are already free of shell metacharacters thanks to this filter.

### Packages added to kickstart `%packages`

- `jq` — required by the `xibo.config_url=` fetch pipeline and by #73's USB `setup.json` scanner. Lightweight (~1 MB), no weak deps.
- `openssh-server` — installed unconditionally but `sshd.service` is only enabled when `xibo.ssh_pubkey=` is present. Without the pubkey preseed, the kiosk has no inbound SSH surface. Lightweight (~1 MB).

## 0.4.21 (2026-04-11)

**4-layer power management fix + correct GNOME donation popup suppression** ([#69](https://github.com/xibo-players/xiboplayer-kiosk/issues/69)).

Fixes screen blanking observed on 0.4.19 (reported in Singularity 6 #370) and the GNOME donation popup still appearing despite the existing `show-donation-popup` gsetting (the correct key per 0x0's Singularity 4 #374 is `donation-reminder-enabled` on the `housekeeping` plugin).

### Architectural shift: the kiosk RPM is the kiosk definition

Previously the system-level config files that define kiosk behaviour (`/etc/systemd/logind.conf.d/no-idle.conf`, the power/donation overrides, the GDM dconf lock) were shipped only via image overlays — `mkosi-extra/` copytree for mkosi builds, explicit `COPY` lines in `atomic/Containerfile`, and hand-written heredocs in `kickstart/xiboplayer-kiosk.ks` `%post`. The RPM/DEB packages carried only the shell scripts. This left four duplicated copies of the same config drifting independently.

**This release moves all 5 config files into the `xiboplayer-kiosk` RPM and DEB packages.** The RPM/DEB is now the single source of truth for what makes a machine a kiosk. Image builds are just a delivery mechanism — `dnf install xiboplayer-kiosk` (whether inside `mkosi`, `atomic/Containerfile`, or kickstart `%post`) installs the config files AND runs a `%post` scriptlet that compiles the GSchema overrides and refreshes the dconf database. Four install paths, one definition.

Plain `dnf install xiboplayer-kiosk` on any Fedora system now produces the same power/donation behaviour as the official ISO images.

### The 5 new RPM/DEB-owned files

| File | Layer | Purpose |
|---|---|---|
| `/etc/systemd/logind.conf.d/no-idle.conf` | 1 | logind never idles, ignores power/suspend/hibernate keys + all lid-switch variants. Extended this release with `HandlePowerKey`, `HandleSuspendKey`, `HandleHibernateKey`. |
| `/usr/share/glib-2.0/schemas/90_xiboplayer-kiosk.gschema.override` | 2 | System-wide GSettings defaults: `idle-delay=0`, `lock-enabled=false`, `idle-activation-enabled=false`, `idle-dim=false`, `sleep-inactive-*-type='nothing'`, `power-button-action='nothing'`, plus BOTH donation keys (`donation-reminder-enabled=false` on `housekeeping`, `show-donation-popup=false` on `desktop.interface`). |
| `/etc/dconf/profile/gdm` | 4 | **Critical** — Fedora's `gdm` RPM does NOT ship this file; without it `dconf update` compiles a `/etc/dconf/db/gdm` database that GDM never reads, and Layer 4 is silently inert. Standard GNOME system-admin-guide content (`user-db:user` / `system-db:gdm` / `file-db:/usr/share/gdm/greeter-dconf-defaults`). |
| `/etc/dconf/db/gdm.d/00-xiboplayer-kiosk` | 4 | Same keys as the gschema override, in dconf INI format (slashes instead of dots) — applies to the GDM greeter session specifically. |
| `/etc/dconf/db/gdm.d/locks/00-xiboplayer-kiosk` | 4 | Locks every key path so the gdm user cannot override them even if local dconf has stale values. |

### RPM `%post` scriptlet (new)

```
/usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas/ &>/dev/null || :
/usr/bin/dconf update &>/dev/null || :
```

Runs on every `dnf install xiboplayer-kiosk` — including inside mkosi's build chroot, inside atomic/bootc's `RUN dnf install` layer, and inside anaconda's `%post` transaction. `dconf update` is mandatory (no file trigger), `glib-compile-schemas` is belt-and-braces (glib2 has a file trigger that covers this automatically).

New `Requires: dconf`, `Requires: glib2` in the spec to guarantee both binaries are present when the scriptlet runs.

The DEB package mirrors the same setup: `Depends: dconf-cli, libglib2.0-bin` and a matching `DEBIAN/postinst` script.

### Layer 3 — runtime session gsettings (updated)

`kiosk/gnome-kiosk-script.xibo.sh` at line 22–34 still sets the same keys at session start as a belt-and-braces runtime guard. Updated to:

- Add `donation-reminder-enabled=false` alongside the legacy `show-donation-popup=false`
- Add `power-button-action='nothing'` and `idle-activation-enabled=false` which were missing from the runtime set

This is the only config still written outside the RPM-owned files, because it's a **per-session-start** action (not a file on disk) — the kiosk session script must set these via `gsettings set` whenever a new kiosk session starts, as a runtime guard against any user-level dconf value that might drift from the compiled defaults.

### Removed duplication

With the RPM owning the config, the previously-duplicated install paths are simplified:

- `kickstart/xiboplayer-kiosk.ks` `%post` — the `no-idle.conf` heredoc AND the new Layer 2 / Layer 4 heredocs are all **gone**. Replaced with a comment noting the RPM handles it.
- `atomic/Containerfile` — the existing `COPY mkosi-extra/etc/systemd/logind.conf.d/no-idle.conf` line is **gone**. Replaced with a comment noting the RPM handles it. No `RUN glib-compile-schemas && dconf update` needed either — the RPM scriptlet fires during the preceding `RUN dnf install xiboplayer-kiosk` layer.
- `mkosi.postinst` — **deleted** entirely (the whole file). The `PostInstallationScripts=mkosi.postinst` line in `mkosi.conf` is also reverted.
- `mkosi-extra/` still contains the 5 source files, because the RPM spec's `%install` commands read FROM those paths — `install -Dm644 mkosi-extra/etc/systemd/logind.conf.d/no-idle.conf %{buildroot}%{_sysconfdir}/…`. The mkosi `ExtraTrees` copytree still copies them into built images, but that's now a harmless double-copy since the RPM already installed the same content.

## 0.4.20 (2026-04-11)

Version bump. Planned feature scope tracked as GitHub issues for separate implementation:

- **#67** — zenity first-boot menu (XPC/XPE) — direct `nmcli` + `timedatectl`, no GNOME Settings
- **#68** — iPXE / kernel preseed infrastructure + `xibo.config_url=` JSON fetch + best-available-disk autodetect
- **#69** — 4-layer power management + GNOME donation popup correction (S6 #370 + S4 #374)
- **#70** — `xibo-debug-dump` support bundle (Ctrl+D / zenity / labelled USB trigger)
- **#71** — drop arexibo from default image (keep netinstall opt-in via `xibo.profile=arexibo`)
- **#72** — pre-anaconda whiptail WiFi TUI for netinstall / iPXE
- **#73** — USB auto-detect for `setup.json` preseed (2x-USB MSP flow)
- **#74** — bats test suite + shellcheck CI

Authoritative spec for all items: `xiboplayer-memory/public/plan_consolidated-kiosk-plan-singularity-6-horizon-2026-2-release.md` (1334 lines, hardened through 7 review passes + 2 research reports).

No functional changes in this release — rebuilds images with current main-branch state.

## 0.4.18 (2026-04-06)

- Fix QCOW2 boot (KernelCommandLine=root=gpt-auto), image matrix docs, download links

## 0.4.17 (2026-04-05)

- Fix aarch64 mkosi shim, add ARM64 iPXE and netinstall, comprehensive image matrix docs

## 0.4.16 (2026-04-04)

- Security fixes, wizard fixes (localectl, setup-result), grub hidden, disk partitioning, VLC restored, RPM Fusion codecs, mesa-dri for VMs, bootc naming, WiFi reconnect, connectivity health-check, reboot wrappers, arm64 DEB, mirrorlist for netinstall, CI hardening

## 0.4.15 (2026-04-02)

- Fix session holder service detection, zenity fallback, arexibo.service, iPXE boot

## 0.4.14 (2026-04-02)

### Bug Fixes

- **Netinstall wizard fixed** — `xiboplayer-setup.py` was missing from RPM/DEB packages, causing netinstall to skip the first-boot wizard
- **Offline ISO install source** — added `cdrom` directive so Anaconda finds base packages
- **python3-gobject + libadwaita** baked into kickstart `%packages` for the wizard

### Features

- **iPXE network boot** — ~1 MB USB stick boots any machine from the internet with install profile menu (Full/Electron/Chromium)
- **Install profiles** — single kickstart with `xibo.profile=` kernel parameter selects which players to install

## 0.4.13 (2026-04-02)

### Features

- **Libadwaita first-boot wizard** — Replaces Zenity dialogs with a native GTK4/libadwaita setup app matching gnome-initial-setup style. Pages: language, player selection, CMS config (Arexibo only).
- **Language selection on first boot** — Searchable locale list with common languages at top, applied via `localectl`.
- **gnome-initial-setup integration** — vendor.conf skips account/privacy/welcome pages, keeps keyboard/network/timezone/password.

### Image Size Reduction

- **Atomic: switch to fedora-bootc base** — From Silverblue (2.5 GB) to fedora-bootc (1.0 GB). Expected ~1.5 GB smaller images.
- **Offline ISO trimmed** — Removed firefox (~200 MB), VLC (mpv sufficient, ~100 MB), @fonts group replaced with minimal font set (~100 MB), excluded unused GNOME apps (~150 MB).

### Bug Fixes

- **GNOME 48 donation popup disabled** via gsettings in kiosk session.
- **Player service detection** — `xibo-show-ip.sh` and `xibo-show-cms.sh` now check all three player services.
- **Atomic dnf skip** — `xiboplayer-kiosk-update.service` skips on Silverblue/Atomic systems.
- **GPG verification enabled** — mkosi sandbox repo file changed from `gpgcheck=0` to `gpgcheck=1`.
- **Release URL parameterized** — Containerfile uses `ARG RELEASE_VER` instead of hardcoded URL.
- **CI default-version synced** — RPM and DEB both synced to 0.4.12.

### Infrastructure

- **Dependabot** added for GitHub Actions.

## 0.4.12 (2026-03-31)

- docs: add FPS monitoring section (XIBOPLAYER_DEBUG_PORT)
- feat: upload atomic ISOs to R2 instead of GitHub Releases

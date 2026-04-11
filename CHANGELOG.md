# Changelog

## 0.4.27 (2026-04-11)

**USB auto-detect `/setup.json`** ([#73](https://github.com/xibo-players/xiboplayer-kiosk/issues/73)).

Enables 0x0's two-USB MSP deploy pattern (horizon2026 #396): USB1 is the install ISO, USB2 holds per-customer config. New `kiosk/xibo-usb-preseed.sh` scans USB-transport block devices for `/setup.json` at the root of the first filesystem, validates via jq allowlist, merges into `/etc/xiboplayer-preseed.env`.

### Precedence

Sits between Layer 1 (`xibo.config_url=` JSON fetch) and Layer 2 (per-field `xibo.*=` kernel params). Per-field kernel params always win — operator-on-console beats USB beats URL fetch.

### Trust model

- **`--trust` flag**: called from kickstart `%post` with `--trust`. Install-time, operator physically present, no confirmation dialog.
- **No `--trust`**: callable from runtime reconfigure paths. Shows a `zenity --question` dialog with a preview of the first 1000 bytes of `setup.json` before applying. Prevents the evil-maid attack where a visitor plugs a USB + triggers Ctrl+R full-setup to silently rewrite the CMS URL.
- **No zenity + no `--trust`**: fail closed (exit 0 without applying).

### Install target exclusion

Uses `lsblk TRAN=usb` to limit the scan to USB-transport devices, then parses the `--drives=DISK` line from `/tmp/disk-config` (written by the existing `%pre` disk-autodetect) to exclude the install target basename. If `/tmp/disk-config` doesn't exist (e.g. running from a live system without kickstart), no exclusion is applied — safe because the lsblk filter already skips non-USB devices.

### Security

**jq allowlist regex**: `^[A-Za-z0-9._/@:+=\\- ]+$`. Matches alphanumerics, dot, underscore, slash, hyphen, colon, at, plus, equals, space. Rejects `$`, backtick, `;`, `&`, `|`, `>`, `<`, `\`, newlines — the shell metacharacter set. Applied INSIDE the jq expression so bad values are filtered before they ever reach the env file.

**Known limitation**: operators whose WiFi password contains `!`, `#`, or any rejected character must preseed via the `xibo.wifi_psk=` kernel param instead. Documented in the README's `setup.json` schema section.

### Graceful fall-through

Every failure mode exits 0 silently:
- Missing `lsblk`, `jq`, `mount`, `umount` — skip
- No USB devices — skip
- No `/setup.json` on any USB — skip
- Invalid JSON — warn, continue
- User declines confirmation — skip

**The script can never abort an install.**

### `setup.json` schema (documented in README)

```json
{
  "cms_url":      "https://cms.example.com",
  "cms_key":      "ABCDEF...",
  "display_name": "Reception-3",
  "timezone":     "Europe/Madrid",
  "locale":       "en_US.UTF-8",
  "wifi_ssid":    "MyCorpWiFi",
  "wifi_psk":     "password123",
  "profile":      "chromium"
}
```

All fields optional. Keys map 1:1 to the `xibo.*=` kernel param namespace (drop the `xibo.` prefix). Values must pass the allowlist regex.

### Modified files

- **`kiosk/xibo-usb-preseed.sh`** — new ~165-line script
- **`kickstart/xiboplayer-kiosk.ks`** — new `%post` block after the `xibo.config_url=` fetch that invokes `xibo-usb-preseed.sh --trust`
- **`rpm/xiboplayer-kiosk.spec`** — bump to 0.4.27, new `install -Dm755` + `%files` entry, new `%changelog` block
- **`deb/build-deb.sh`** — mirror

## 0.4.26 (2026-04-11)

**Pre-anaconda whiptail Wi-Fi TUI for netinstall / iPXE WiFi-only machines** ([#72](https://github.com/xibo-players/xiboplayer-kiosk/issues/72)).

Closes the "user boots netinstall ISO on a WiFi-only machine and hits anaconda's complex GTK dialog" gap that 0x0 flagged in horizon2026-2. A new `%pre --erroronfail` block at the top of `kickstart/xiboplayer-kiosk.ks` runs BEFORE anaconda's network phase with a simple whiptail picker.

### Entry conditions (all three must be true for the TUI to open)

1. No wired ethernet link up (`nmcli -t -f TYPE,STATE dev status | grep ethernet:connected` is empty)
2. `xibo.wifi_ssid=` was NOT preseeded via kernel cmdline
3. Wireless hardware is present

If any of these is false, the block exits 0 silently — the TUI never gets in the way of a wired install or a preseeded install.

### Flow

1. Wait up to 10s for NetworkManager to settle (handles races where NM is still `connecting`/`asleep` in the initrd).
2. `nmcli dev wifi rescan` + 2s sleep for results.
3. Build whiptail menu from `nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list` (dedupe by SSID, sort by signal, filter empties).
4. Add synthetic "(hidden)" row (inputbox for manual SSID entry) and "(skip)" row (falls through to anaconda).
5. Show whiptail menu, wait for user pick (no timeout — this is an interactive install).
6. If the chosen network is secured, show whiptail passwordbox.
7. Validate SSID and PSK via verbatim-copy of `_validate_nm_string` from `kiosk/xibo-set-wifi.sh` (rejects control characters + NM INI section headers — same rules as the runtime helper).
8. Write NM keyfile to `/etc/NetworkManager/system-connections/` in the installer env AND — if `/mnt/sysimage` is already mounted — into the target system. Otherwise stash the credentials in `/tmp/xibo-wifi-preseed` (mode 0600) for `%post` to apply after the target filesystem is mounted.
9. `nmcli connection up "$SSID"` in the installer env so anaconda has network for `%packages`.
10. Show success infobox, sleep 2s, return to anaconda.

### %post stash re-application

A new elif branch in the existing `%post` wifi block detects `/tmp/xibo-wifi-preseed`, sources it, calls `xibo-set-wifi.sh "$SSID" "$PSK" "$KEYMGMT"` against the installed system, then `shred -u`s the stash. Precedence: kernel-cmdline `xibo.wifi_ssid=` ALWAYS wins (Layer 2 / per-field params beat TUI input per the plan's preseed precedence).

### Security

- **`_validate_nm_string` copied verbatim** from `kiosk/xibo-set-wifi.sh`. A bats test in #74 will diff the two copies to catch drift. The kickstart comment block flags the sync requirement explicitly.
- **PSK never touches `/proc/<pid>/cmdline`** — the NM keyfile is written directly; `nmcli connection up "$SSID"` matches by NM connection id, not by PSK.
- **Stash file** (`/tmp/xibo-wifi-preseed`) is mode `0600` and `shred -u`'d after `%post` consumes it. The PSK is in plaintext for the window between `%pre` and `%post`, which is acceptable because the installer env has no untrusted users during that window.
- **Error handling**: every step wraps in `|| true` / `return 0`. If `whiptail` or `nmcli` are missing in the `%pre` environment (older installer), the block exits 0 and anaconda's own network phase handles WiFi. If the user cancels the menu, same fall-through. If validation rejects the SSID/PSK, a msgbox explains and the block exits 0. **The TUI can never abort an install.**

### Modified files

- **`kickstart/xiboplayer-kiosk.ks`** — (1) new `%pre --erroronfail` block (~200 lines) before the existing disk-autodetect `%pre`, containing the whiptail TUI inline (single source of truth — no separate file + sync risk); (2) new elif branch in the `%post` wifi block that re-applies `/tmp/xibo-wifi-preseed` if the TUI stashed credentials; (3) `shred -u` the stash after use.
- **`rpm/xiboplayer-kiosk.spec`** — bump to 0.4.26, new `%changelog` entry.

### Design notes

- **Why inline, not a separate `kickstart/xibo-wifi-tui.sh`?** The plan originally called for a separate file, but a separate file creates a sync problem: the kickstart has no file-include mechanism that works offline in `%pre`, so either the file is `curl`'d at install time (fails for offline installs — the exact case we're fixing) OR the content is duplicated via heredoc (two sources of truth). Inlining keeps the TUI in one place and the sync requirement explicit in the comment header.
- **Why no timeout on the menu?** The plan allowed 120s inactivity → fall-through. I removed this because the `%pre` block is only shown when a human is physically booting an install ISO — no walk-away scenarios like the first-boot menu (which has the 120s timeout). A human at the console either picks a network or hits Cancel; there's no benefit to auto-skipping.
- **Why WPA2 default for hidden networks?** WPA3 on a hidden network is extremely rare and the `nmcli connection up` call reports a clear error if the key-mgmt is wrong, so the user can re-run the menu (via Ctrl+R on the installer console) and retry. Open hidden networks are almost non-existent.

## 0.4.25 (2026-04-11)

**Drop arexibo from the default image + remove Python wizard + drop GTK deps** ([#71](https://github.com/xibo-players/xiboplayer-kiosk/issues/71)).

Consolidated spring cleaning of three overlapping removals that all fell out of the Singularity 6 plan's Item E + deferred items from #67:

1. **Arexibo → netinstall opt-in**. The arexibo package is no longer baked into the default ISO (mkosi.conf, atomic/Containerfile, kickstart `%packages`). It's pulled on demand by the kickstart `%post` when `xibo.profile=arexibo` was passed on the kernel cmdline. The runtime kiosk scripts still handle `arexibo.service` (`gnome-kiosk-script.xibo.sh`, `xibo-show-cms.sh`, `xibo-zenity-lib.sh`) so netinstall users who chose `xibo.profile=arexibo` get a working kiosk — what's gone is the default-image presence + the grub/isolinux/iPXE menu entries.

2. **Python wizard deleted**. `kiosk/xiboplayer-setup.py` (347 lines) and `kiosk/xiboplayer-setup.desktop` are gone, along with their `install -Dm755` / `%files` entries in the RPM spec and the `install` lines in `deb/build-deb.sh`. The kickstart `%post --erroronfail` autostart block at lines 419-424 is also deleted — it copied `xiboplayer-setup.desktop` into `/home/xibo/.config/autostart/` and would have failed on every install after the source file was removed. Superseded by the zenity first-boot menu (#67, landed in 0.4.24).

3. **GTK deps dropped**. `python3-gobject`, `libadwaita`, and `gnome-control-center` removed from `Requires:` (spec), `Packages=` (mkosi.conf), `dnf install` (atomic/Containerfile), and `%packages` (kickstart). Per user directive 2026-04-11 "avoid at all cost to use gnome-settings": removing `gnome-control-center` from the image means any future maintainer who tries to shell out to `gnome-control-center wifi` hits a build-time ENOENT and is forced to use the validated `nmcli`/`timedatectl` helper scripts we already ship. Combined with the arexibo removal, default ISO shrinks by ~400 MB.

### Modified files

- **`mkosi.conf`** — removed `arexibo`, `python3-gobject`, `libadwaita` from `Packages=`.
- **`atomic/Containerfile`** — removed `python3-gobject libadwaita gnome-control-center` from the gnome RUN block and `arexibo` from the xiboplayer RUN block. Updated comment block documenting the "no gnome-settings" directive so future maintainers see the rationale at the point of change.
- **`kickstart/xiboplayer-kiosk.ks`** — (1) removed `python3-gobject` + `libadwaita` from `%packages`; (2) removed `arexibo` from the default `dnf install` line; (3) removed the `alternatives --install arexibo` line from the default registration; (4) rewrote the `arexibo)` profile-switch case to `dnf install -y arexibo` on-demand with alternatives registration inside the case + fall-back-to-chromium on install failure (better UX than leaving the kiosk broken); (5) deleted the `%post --erroronfail` autostart block that copied `xiboplayer-setup.desktop` (would have aborted every install after the source file was deleted).
- **`kickstart/grub.cfg`** — dropped the Arexibo `menuentry`, renamed both remaining `menuentry` labels to include the explicit "ERASES ALL DATA ON DISK" warning per Phase 6-sexies safety review.
- **`kickstart/isolinux.cfg`** — same (dropped `label arexibo`, renamed both remaining labels). BYTE-IDENTICAL warning text to grub.cfg.
- **`ipxe/boot.ipxe`** — dropped the `item arexibo` line and the `:arexibo` kernel-line block. Rewrote the file header comment to document every `xibo.*` kernel param the kickstart `%post` consumes (profile/config_url/cms_*/timezone/locale/wifi_*/ssh_pubkey) — MSPs baking custom USBs now have a single-file reference.
- **`rpm/xiboplayer-kiosk.spec`** — (1) removed `Requires: python3-gobject` / `Requires: libadwaita` / `Requires: gnome-control-center` / `Suggests: arexibo`; (2) removed the `install -Dm755 kiosk/xiboplayer-setup.py` + `install -Dm644 kiosk/xiboplayer-setup.desktop` lines; (3) removed the matching `%files` entries; (4) rewrote `%description` to describe the zenity menu + document arexibo as a netinstall opt-in; (5) bumped Version to 0.4.25.
- **`deb/build-deb.sh`** — removed `install` lines for the Python wizard + desktop file; removed `arexibo` from `Depends:` (the `| xiboplayer-chromium | arexibo` alternative becomes just `| xiboplayer-chromium`).
- **`kiosk/xibo-show-cms.sh`** — refactored the Ctrl+R `full-setup)` branch (lines 94-109) to stop referencing the deleted `xiboplayer-setup.desktop`. New behaviour: stop all players, clear `~/.local/share/xibo/first-boot-done`, invoke `xibo-first-boot.sh` in-session, restart the active player service read from `setup-result.json`. Never leaves the kiosk session — no more `doas xibo-deactivate-kiosk.sh` + `pkill gnome-kiosk-script` dance.

### Deleted files

- **`kiosk/xiboplayer-setup.py`** — 347-line libadwaita/GTK4 first-boot wizard. Rejected by 0x0 in Singularity 6 #313-378, superseded by `kiosk/xibo-first-boot.sh` (#67).
- **`kiosk/xiboplayer-setup.desktop`** — the autostart desktop file for the above.

### Security

The `permit nopass xibo cmd localectl` and `permit nopass xibo cmd timedatectl` permits were already replaced with narrower script-specific permits in 0.4.24. This release completes the cleanup by removing the unused `xiboplayer-setup.py` script that could potentially have been tricked into writing arbitrary values via the full-setup reconfigure path.

### Notes

Arexibo is NOT deprecated — it's an opt-in profile for users who want the Rust native player. Mass-deploy path: MSP bakes an iPXE boot.ipxe (or edits the GRUB/isolinux kernel line at boot) with `xibo.profile=arexibo`, the kickstart `%post` pulls `arexibo` from the package repo on install, and alternatives are set accordingly. The failure mode is explicit: if the on-demand `dnf install -y arexibo` fails (no network, package missing from the configured repo), the kickstart logs a warning and falls back to chromium. The install still produces a working kiosk — never a booted-but-broken machine.

## 0.4.24 (2026-04-11)

**Zenity first-boot menu for XPC/XPE on x86_64** ([#67](https://github.com/xibo-players/xiboplayer-kiosk/issues/67)).

0x0's direct ask in horizon2026-2 #1 ("Could you maybe try to patch zenity main menu for XPC/XPE on ISO x86_64 so we can finish concept"). A zenity main menu that runs inside the kiosk session, BEFORE the player starts, with Wi-Fi / Timezone / CMS / Debug / Done rows and a live status column.

### New files

- **`kiosk/xibo-zenity-lib.sh`** — shared helper library. Contains `_preseed_get` (reads `/etc/xiboplayer-preseed.env` via `grep | cut`, never `source`), `zlib_notify` (notify-send wrapper), `zlib_status_wifi` / `zlib_status_tz` / `zlib_status_cms` (live status strings for the menu column), `zlib_cms_form` (zenity `--forms` for URL/key/name with preseed defaults), `zlib_write_chromium_config` / `zlib_write_electron_config` / `zlib_write_arexibo_cms_json` (player-specific config writers), `zlib_write_player_config` (dispatcher based on the active alternative).
- **`kiosk/xibo-first-boot.sh`** — the menu itself. Main loop re-displays the menu after each row action, so operators can configure multiple things in one sitting. Two-minute inactivity timeout (exit code 5) falls through to "start player" automatically to prevent walkaway lockout.
- **`kiosk/xibo-set-timezone.sh`** — validated doas helper. Checks the argument against `timedatectl list-timezones` before invoking the real command. Narrower than the blanket `timedatectl` permit — closes the "set clock backwards to bypass TLS cert validity" attack surface (Phase 6-quinquies security hardening).
- **`kiosk/xibo-set-locale.sh`** — parallel helper for locale, validated against `localectl list-locales`.

### Row handlers

| Row | Behaviour |
|---|---|
| Wi-Fi | `nmcli dev wifi rescan` + `list` + `zenity --list` picker + `zenity --password` (secured only) + `doas xibo-set-wifi.sh`. Connectivity check via `detectportal.firefox.com` catches captive portals and warns the operator before they think they're connected. |
| Timezone | **Two-stage filter** — `zenity --entry` for a substring, then `zenity --list` filtered by `grep -i`. Avoids the 593-row IANA scroll; operators know "Madrid" but not "Europe/Madrid". |
| CMS | `zenity --forms` with URL/key/display-name, pre-filled from preseed.env. Post-save `zenity --info` explains "display is pending in CMS admin panel" — prevents the "why is the screen blank" confusion on every first deployment. |
| Debug | Calls `xibo-debug-dump.sh` (#70). |
| Done | Writes the sentinel and returns. |

### Session-holder integration

`kiosk/gnome-kiosk-script.xibo.sh` gains a first-boot gate: after the gsettings block (Layer 3 power management) and **before** the `systemctl --user start "$PLAYER_SERVICE"` line, if `~/.local/share/xibo/first-boot-done` is absent AND `/usr/share/xiboplayer-kiosk/xibo-first-boot.sh` is executable, run the menu and then `touch` the sentinel. Errors are swallowed with `|| true` so the kiosk never stalls on first boot — if the menu crashes or the operator closes the window, the player still starts.

### Sentinel location

`~/.local/share/xibo/first-boot-done` — user-scoped, wipes on a fresh ISO install (blank `/home/xibo`), matches the existing `XIBO_DATA_DIR` convention. Can be deleted manually (or by a future Ctrl+R "full-setup") to re-trigger the wizard.

### doas permits

`mkosi-extra/etc/doas.conf` AND the kickstart `%post` doas heredoc both gain the two new helper permits (`xibo-set-timezone.sh`, `xibo-set-locale.sh`) alongside the `xibo-set-wifi.sh` permit carried over from #68. The blanket `timedatectl` and `localectl` permits remain for now — removing them is a separate hardening pass (would break existing consumers).

### What's NOT in this PR (deferred)

- **Deleting `xiboplayer-setup.py` + `.desktop`** — the old Python/GTK wizard. Still in the tree but no longer autostarted once the xibo-first-boot.sh flow is proven. Cleanup moves to #71's "drop arexibo" commit or a dedicated chore commit.
- **Dropping `python3-gobject` + `libadwaita` + `gnome-control-center` from `mkosi.conf` and `atomic/Containerfile`** — they're no longer needed now that the new zenity flow exists, but the deletion is coupled to the Python wizard removal.
- **Refactoring `xibo-show-cms.sh`** (Ctrl+R reconfigure) **to source `xibo-zenity-lib.sh`** — the existing script still works standalone; the refactor is a follow-up.
- **Retargeting `mkosi-extra/usr/local/bin/xiboplayer-kiosk-firstboot.sh`** — still copies `xiboplayer-setup.desktop` as an autostart, which is now a dead pointer. Fix is part of the Python wizard removal.

All four items ship in a follow-up PR or as part of #71 when arexibo removal triggers the broader cleanup.

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

# xiboplayer-kiosk v0.5.x — bug-fix test plan

Tracks the bugs flagged during v0.5.0 testing (Singularity 7 thread, 2026-04-13) and their fix/verification status. Each row gets ticked off when the fix lands AND has been verified on a fresh test image by a human operator.

**Rules**:

- A bug is "fixed" when a PR is merged. A bug is "verified" only after a QEMU walkthrough succeeds on a freshly-built ISO containing the fix.
- Verification is per-environment. Re-check on UEFI **and** BIOS (Advanced → basic-graphics-mode).
- Every test image URL is logged in the matrix at the bottom so we can always reproduce.

---

## Environment

| Setting | Value |
|---|---|
| Host | Fedora 43 laptop |
| Hypervisor | QEMU-KVM via virt-manager |
| Guest | 4 GB RAM · 2 CPUs · 20 GB qcow2 · virtio disk · virtio-gpu |
| Firmware | UEFI (OVMF) for primary; secondary round on SeaBIOS for BIOS regression |
| ISO prefix | `https://images.xiboplayer.org/xiboplayer-kiosk/test/<sha>/` |
| QEMU disk | `~/vms/kiosk-0.5.x.qcow2` — fresh per test, do not reuse |

```bash
# Fresh disk per test round
qemu-img create -f qcow2 ~/vms/kiosk-0.5.x.qcow2 20G

# Boot the ISO (UEFI default)
qemu-system-x86_64 -enable-kvm -m 4G -smp 2 -cpu host -machine q35 \
  -bios /usr/share/edk2/ovmf/OVMF_CODE.fd \
  -drive file=~/vms/kiosk-0.5.x.qcow2,if=virtio,format=qcow2 \
  -cdrom ~/Downloads/xiboplayer-kiosk-netinstall_0.5.x_x86_64.iso \
  -boot d -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  -vga virtio -display gtk,gl=on -serial mon:stdio
```

---

## Test stages

Each stage is pass/fail. A stage "passes" only when ALL its checkpoints tick.

### Stage A — Install (unattended)

- [ ] GRUB menu appears with the xiboplayer branded menu (not "Install Fedora 43")
- [ ] Both the main entry and Advanced submenu entries boot without "cannot find command linuxefi" or similar
- [ ] Text-mode anaconda proceeds automatically (no hub-and-spoke prompts, no Software Selection warning)
- [ ] Package install completes; no "Cannot download …" errors for xiboplayer-kiosk or any RPM Fusion package
- [ ] VM reboots cleanly (ISO ejects, kernel boots from the installed disk)

### Stage B — First boot into the kiosk session

- [ ] GDM autologin lands in the `gnome-kiosk-script-wayland` session (black background visible)
- [ ] Python first-boot wizard window opens within ~15 s
- [ ] Welcome/status pane shows the xiboplayer logo (from the branding PNG, not a generic icon)
- [ ] Sidebar shows 7 rows: Language / Keyboard / Wi-Fi / Timezone / Player / CMS / Settings
- [ ] Each row displays a live status subtitle (Timezone = detected TZ, Wi-Fi = SSID or `(wired)` / `(not connected)`, Player = Chromium, etc.)

### Stage C — First-boot pickers

- [ ] Click Language → picker opens, focus in search field, typing "en" filters to matching locales
- [ ] Press Esc → picker closes, returns to sidebar
- [ ] Click Timezone → picker opens with "UTC, New_York, London, Tokyo" placeholder
- [ ] Click Keyboard → picker opens
- [ ] Click Wi-Fi → either the SSID list appears (if WiFi hardware) or an info panel ("No wireless hardware, use a wired connection")
- [ ] Pickers apply via `doas xibo-set-*.sh`; after apply, sidebar status subtitle updates live

### Stage D — CMS registration

- [ ] Click CMS → three-field form (URL / Key / Display Name)
- [ ] Save → writes `~/.config/xiboplayer/chromium/config.json` (or `electron/` if switched) with the URL normalised to trailing slash
- [ ] Sidebar CMS row status updates to the entered URL
- [ ] `notify-send` toast shows "CMS configured: https://…"

### Stage E — Player startup (CRITICAL — currently failing v0.5.0)

- [ ] Click "Start player" → wizard window closes
- [ ] Within ~10 s, the player process starts — `systemctl --user is-active xiboplayer-chromium.service` returns `active`
- [ ] Player UI fills the screen (not black); CMS registration page appears OR the player plays the authorized layout
- [ ] Journalctl shows no "service failed to start" or "No such file" errors for the player service

### Stage F — Reconfigure (Ctrl+R)

- [ ] Press `Ctrl+R` → reconfigure wizard opens (same window chrome as first-boot)
- [ ] Categories "Reconfigure CMS / Full setup / Open Settings / Close" visible
- [ ] Close returns to the running player

### Stage G — Settings sub-actions

- [ ] Settings → GNOME Settings launches gnome-control-center with window decorations visible (not a black orphan)
- [ ] Settings → Open terminal launches ptyxis with decorations
- [ ] Settings → Collect debug bundle produces `~/Downloads/xibo-debug-*.tar.zst`

### Stage H — Regression / BIOS boot

- [ ] Boot same ISO under SeaBIOS instead of UEFI — install still completes, kiosk still reachable

---

## Bug tracker

| # | Bug | Source | Fix status | Verified |
|---|---|---|---|---|
| 1 | Player fails to start after CMS auth (Stage E blocker) | [#145](https://github.com/xiboplayer/xiboplayer-kiosk/issues/145) + Sing7 #70, #94, #96 | ⏳ open | |
| 2 | xorriso GRUB overlay breaks VM kernel auto-detect on some VM configs | [#146](https://github.com/xiboplayer/xiboplayer-kiosk/issues/146) + Sing7 #98 | ⏳ open | |
| 3 | Raspberry Pi 4 install can't find bootable partition | [#57](https://github.com/xiboplayer/xiboplayer-kiosk/issues/57) (Yunus1903) | ⏳ open | |
| 4 | anaconda --device-link error | [#58](https://github.com/xiboplayer/xiboplayer-kiosk/issues/58) (0x0-0xf) | ⏳ open | |

## Enhancement tracker (not release-blockers)

| # | Request | Source | Status |
|---|---|---|---|
| E1 | "Locality" unified menu — Lang + Keyboard + Timezone in one category | [#147](https://github.com/xiboplayer/xiboplayer-kiosk/issues/147) + Sing7 #76, #80 | design pending |
| E2 | Reconfigure window visual polish | [#148](https://github.com/xiboplayer/xiboplayer-kiosk/issues/148) + Sing7 #98 | design pending |
| E3 | Headless first-boot via captive portal (DNSMASQ + Apache) | horizon2026 (0x0) | memory tracked |
| E4 | Plymouth branding (6-slide carousel + anaconda sidebar) | PR4 blueprint | blueprint ready |
| E5 | Drop deprecated shell scripts (xibo-first-boot.sh etc.) | PR3 blueprint | ready for 0.5.1 |

## Verification matrix

One row per test round. Each cell is ✅ (all checks pass), ❌ (one or more checks fail), or 🟦 (not tested).

| Version | Built | ISO URL | A install | B first-boot | C pickers | D CMS | E player | F Ctrl+R | G settings | H BIOS |
|---|---|---|---|---|---|---|---|---|---|---|
| 0.5.0 | 2026-04-13 | `test/a3b2b5a.../` and release `/0.5.0/` | ✅ | ✅ | ✅ | ✅ | ❌ bug #1 | 🟦 | 🟦 | ❌ bug #2 |

Append a new row whenever a fix ISO is built; copy the previous row's verified cells, re-test failed stages.

## How to use this document

1. A new bug gets a row in the bug tracker with status ⏳ open.
2. A PR fixes it → flip to ✅ fixed (not yet verified).
3. A human boots a test ISO containing the fix and walks through the affected stage → flip to ✅ verified with the ISO sha.
4. When every v0.5.x bug row is verified, we tag 0.5.x as "stable" and announce to Sing7.
5. Until then, 0.5.0 is **not promoted** to `latest/` on the CDN (per 0x0's post #96 / #104: "dont bump 0.50, lets try fix it this week").

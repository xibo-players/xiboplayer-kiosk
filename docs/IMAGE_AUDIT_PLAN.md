# Image Audit Plan

## Goals

1. Verify all images include the latest packages and scripts
2. Compare images to understand size differences
3. Identify opportunities to reduce image size
4. Ensure no unnecessary packages are included
5. Document the expected contents of each image type

---

## Phase 1: Size Analysis

### Current sizes (v0.4.15)

| Image | Size | Expected | Issue |
|-------|------|----------|-------|
| Everything ISO x86_64 | 1118 MB | ~1500 MB | Uses Fedora netinst as base (~1100 MB), local repo adds ~20 MB |
| Netinstall ISO x86_64 | 1118 MB | ~700 MB | **Same base as Everything** — should use a smaller base |
| QCOW2 x86_64 (mkosi) | 1767 MB | ~2000 MB | Full installed system, reasonable |
| Raw disk x86_64 | 1172 MB | ~1200 MB | xz compressed, reasonable |
| QCOW2 aarch64 | 1671 MB | ~1800 MB | Smaller (no Intel GPU drivers) |
| iPXE BIOS | 400 KB | ~400 KB | Correct — minimal bootloader |
| iPXE UEFI | 1140 KB | ~1 MB | Correct — EFI binary is larger |

### Key finding: Netinstall ≈ Everything

Both use `Fedora-Everything-netinst-x86_64-43-1.6.iso` as base (~1.1 GB).
The "Everything" adds a local-repo overlay via mkksiso (~20 MB of RPMs).
**They are effectively the same image** — the local repo barely adds anything.

### Action items

- [ ] **Netinstall**: Use `Fedora-Server-netinst` (~700 MB) or `Fedora-Boot` (~600 MB) instead of `Fedora-Everything-netinst`
- [ ] **Everything**: Consider using Fedora Server DVD or building a custom repo with ALL deps pre-resolved
- [ ] **Or**: Drop netinstall entirely — iPXE serves the same purpose (network install) at 400 KB

---

## Phase 2: Package Audit

### Method

For each image type, extract the package list and compare:

```bash
# From QCOW2 (mount and inspect)
guestfish -a disk.qcow2 -i : rpm -qa > qcow2-packages.txt

# From Atomic OCI (inspect container)
podman run --rm ghcr.io/xiboplayer/xiboplayer-kiosk:43 rpm -qa > atomic-packages.txt

# From kickstart (parse %packages + %post dnf commands)
grep -v '^#\|^-\|^%' <(sed -n '/%packages/,/%end/p' kickstart/xiboplayer-kiosk.ks) > kickstart-packages.txt
```

### Compare

```bash
diff <(sort qcow2-packages.txt) <(sort atomic-packages.txt)
```

### Check items

- [ ] All images have `xiboplayer-kiosk >= 0.4.15`
- [ ] All images have `xiboplayer-electron`, `xiboplayer-chromium`, `arexibo`
- [ ] All images have `python3-gobject`, `libadwaita` (setup wizard deps)
- [ ] All images have `mesa-dri-drivers` (software rendering for VMs)
- [ ] No images have `gnome-initial-setup` (removed)
- [ ] Atomic image has `xiboplayer-release` (GPG key)
- [ ] Scripts exist: `gnome-kiosk-script`, `xiboplayer-setup.py`, `firstboot.sh`

---

## Phase 3: RPM Group Analysis

### Current package sources

**Kickstart `%packages`**:
- `@core` — Fedora base (~400 packages, ~500 MB installed)
- `@hardware-support` — firmware, drivers (~200 packages, ~300 MB installed)

**mkosi.conf Packages**:
- `@core` — same as kickstart
- `kernel-core` — just the kernel, not full `kernel` package
- Individual packages listed explicitly

**Containerfile**:
- No groups — everything listed individually

### Potential savings

| Group/Package | Installed size | Can remove? | Savings |
|---------------|---------------|-------------|---------|
| `@hardware-support` | ~300 MB | Replace with targeted drivers | ~200 MB |
| `linux-firmware` (full) | ~800 MB | Already trimmed in Containerfile | ~400 MB already saved |
| `@core` | ~500 MB | Replace with minimal list | ~200 MB |
| `firefox` (in mkosi) | ~200 MB | Remove — kiosk doesn't need it | ~200 MB |
| `vlc` (in mkosi) | ~50 MB | Keep for media playback | — |
| `qt6-qtwebengine` | ~150 MB | Required by arexibo | — |
| Locales (full) | ~200 MB | Already trimmed in Containerfile | ~150 MB already saved |
| Docs/man pages | ~100 MB | Already trimmed in Containerfile | ~80 MB already saved |

### Action items

- [ ] Remove `firefox` from mkosi.conf (leftover, not needed for kiosk)
- [ ] Replace `@core` with explicit minimal package list in mkosi.conf
- [ ] Replace `@hardware-support` with targeted packages in kickstart
- [ ] Add `glibc-minimal-langpack` and remove full langpacks
- [ ] Add `--setopt=install_weak_deps=False` to kickstart `%packages`
- [ ] Compare Containerfile (optimized) vs mkosi.conf (not optimized) packages

---

## Phase 4: Script Verification

### Files that must exist in every image

| File | Source | Purpose |
|------|--------|---------|
| `/usr/share/xiboplayer-kiosk/gnome-kiosk-script.sh` | RPM | Dispatcher |
| `/usr/share/xiboplayer-kiosk/gnome-kiosk-script.xibo.sh` | RPM | Session holder |
| `/usr/share/xiboplayer-kiosk/gnome-kiosk-script.xibo-init.sh` | RPM | First-boot init |
| `/usr/share/xiboplayer-kiosk/xiboplayer-setup.py` | RPM | Player selection wizard |
| `/usr/share/xiboplayer-kiosk/xibo-show-ip.sh` | RPM | Ctrl+I status |
| `/usr/share/xiboplayer-kiosk/xibo-show-cms.sh` | RPM | Ctrl+R reconfigure |
| `/etc/skel/.local/bin/gnome-kiosk-script` | RPM | Dispatcher (skel) |
| `/etc/gdm/custom.conf` | mkosi-extra / Containerfile | GDM autologin |
| `/etc/doas.conf` | mkosi-extra / Containerfile | reboot/shutdown perms |
| `/var/lib/AccountsService/users/xibo` | mkosi-extra / Containerfile | Kiosk session |
| `/usr/local/bin/xiboplayer-kiosk-firstboot.sh` | mkosi-extra / Containerfile | Password + linger |
| `/usr/lib/sysusers.d/xiboplayer-kiosk.conf` | mkosi-extra / Containerfile | User creation |
| `/usr/lib/tmpfiles.d/xiboplayer-kiosk.conf` | mkosi-extra / Containerfile | Home dir population |
| `/usr/lib/systemd/system-preset/80-xiboplayer-kiosk.preset` | mkosi-extra / Containerfile | Service enablement |

### Method

```bash
# For QCOW2/raw
guestfish -a disk.qcow2 -i : find / | grep -E "gnome-kiosk-script|xiboplayer-setup|firstboot|sysusers|tmpfiles|doas.conf|AccountsService"

# For Atomic OCI
podman run --rm ghcr.io/xiboplayer/xiboplayer-kiosk:43 find / -name "gnome-kiosk-script*" -o -name "xiboplayer-setup*" -o -name "*firstboot*" -o -name "doas.conf" 2>/dev/null
```

---

## Phase 5: Image Comparison Matrix

### Build method comparison

| Feature | Kickstart (ISO) | mkosi (QCOW2) | Containerfile (Atomic/bootc) |
|---------|----------------|---------------|------------------------------|
| Package source | Fedora repos + local repo | Fedora repos | Fedora repos |
| Service enablement | kickstart `%post` | preset file + symlink | `systemctl enable` in RUN |
| User creation | kickstart `%post` useradd | sysusers.d | sysusers.d |
| Home dir setup | kickstart `%post` | tmpfiles.d | tmpfiles.d + firstboot |
| GDM config | kickstart `%post` cat | mkosi-extra file | COPY |
| Default target | kickstart `%post` | symlink in mkosi-extra | `systemctl set-default` |
| GPG key | kickstart `%post` install release RPM | from repo | COPY + rpm --import |
| First boot | kickstart + firstboot service | firstboot service | firstboot service |
| Immutable | No | No | Yes (OSTree) |
| Updates | dnf update | dnf update | bootc upgrade |
| Image size | ~1.1 GB (ISO) | ~1.7 GB (QCOW2) | ~1.5 GB (QCOW2) |

---

## Phase 6: Size Optimization Targets

### Target sizes

| Image | Current | Target | Method |
|-------|---------|--------|--------|
| Everything ISO | 1118 MB | 1200 MB | Use Server DVD base (~800 MB) + larger local repo |
| Netinstall ISO | 1118 MB | 700 MB | Use Server-netinst or Boot ISO base |
| QCOW2 (mkosi) | 1767 MB | 1200 MB | Remove firefox, @core → minimal, weak deps off |
| QCOW2 (bootc) | ~1500 MB | 1000 MB | Already optimized in Containerfile |
| Raw disk | 1172 MB | 800 MB | Same optimizations as QCOW2 |
| iPXE | 400 KB | 400 KB | Already minimal |

### Quick wins (no risk)

1. Remove `firefox` from mkosi.conf — saves ~200 MB
2. Add `--setopt=install_weak_deps=False` to kickstart — saves ~100 MB
3. Use `Fedora-Server-netinst` for netinstall ISO — saves ~400 MB
4. Add `glibc-minimal-langpack` — saves ~50 MB

---

## Execution

### CI workflow for audit

Create a `audit-images.yml` workflow that:
1. Downloads each image type
2. Mounts/inspects with guestfish
3. Extracts `rpm -qa`, file list, service list
4. Compares across image types
5. Reports anomalies (missing packages, extra packages, size outliers)

### Manual audit steps

```bash
# 1. Download all images
gh run download --name qcow2-bootc --dir /tmp/audit/

# 2. Mount and inspect
sudo guestfish -a disk.qcow2 -i
> rpm -qa | sort > /tmp/packages.txt
> find /usr/share/xiboplayer-kiosk/ > /tmp/kiosk-files.txt
> cat /etc/systemd/system/default.target > /tmp/default-target.txt
> systemctl list-unit-files --state=enabled > /tmp/enabled-services.txt

# 3. Compare with expected
diff /tmp/packages.txt expected-packages.txt
```

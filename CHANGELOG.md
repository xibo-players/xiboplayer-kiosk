# Changelog

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

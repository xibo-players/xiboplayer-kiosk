# Changelog

## Unreleased

### Bug Fixes

- **Player service detection** — `xibo-show-ip.sh` and `xibo-show-cms.sh` now check all three player services (xibo-player, xiboplayer-electron, xiboplayer-chromium) instead of only xibo-player.
- **Atomic dnf skip** — `xiboplayer-kiosk-update.service` skips on Silverblue/Atomic systems (checks `/run/ostree-booted`). Those use `rpm-ostreed-automatic.timer` instead.
- **GPG verification enabled** — mkosi sandbox repo file changed from `gpgcheck=0` to `gpgcheck=1` with GPG key URL.
- **Release URL parameterized** — Containerfile uses `ARG RELEASE_VER=43-7` instead of hardcoded URL. Kickstart tries GitHub latest redirect first with hardcoded fallback.
- **CI default-version synced** — RPM (was 0.4.9) and DEB (was 0.4.11) both synced to 0.4.12.

### Infrastructure

- **Dependabot** added for GitHub Actions.

## 0.4.12 (2026-03-31)

- docs: add FPS monitoring section (XIBOPLAYER_DEBUG_PORT)
- feat: upload atomic ISOs to R2 instead of GitHub Releases

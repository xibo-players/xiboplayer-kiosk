"""Read-only status probes — never mutate, never call doas.

Each function returns a string suitable for the main-menu status column.
"""

import json
import subprocess
from pathlib import Path


def _run(cmd: list[str]) -> str:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=5, check=False)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:  # noqa: BLE001
        return ""


def wifi_status() -> str:
    """Active Wi-Fi SSID, or '(wired)' / '(not connected)' / '(no wifi hardware)'."""
    have_wifi = _run(["nmcli", "-t", "-f", "DEVICE,TYPE", "dev", "status"])
    if "wifi" not in have_wifi:
        return "(no wifi hardware)"
    active = _run(["nmcli", "-t", "-f", "NAME,TYPE,STATE", "conn", "show", "--active"])
    for line in active.splitlines():
        parts = line.split(":")
        if len(parts) >= 3 and parts[2] == "activated":
            if parts[1] == "802-11-wireless":
                return parts[0]
            if parts[1] == "802-3-ethernet":
                return "(wired)"
    return "(not connected)"


def timezone_status() -> str:
    return _run(["timedatectl", "show", "-p", "Timezone", "--value"]) or "(unknown)"


def locale_status() -> str:
    """Value of /etc/locale.conf LANG, or 'C.UTF-8' if unset."""
    try:
        with Path("/etc/locale.conf").open() as f:
            for line in f:
                line = line.strip()
                if line.startswith("LANG="):
                    return line[5:].strip('"')
    except FileNotFoundError:
        pass
    return _run(["localectl", "status"]).splitlines()[0] if _run(["localectl", "status"]) else "C.UTF-8"


def keyboard_status() -> str:
    """X11 keyboard layout (+variant) from localectl."""
    out = _run(["localectl", "status"])
    layout = variant = ""
    for line in out.splitlines():
        s = line.strip()
        if s.startswith("X11 Layout:"):
            layout = s.split(":", 1)[1].strip()
        elif s.startswith("X11 Variant:"):
            variant = s.split(":", 1)[1].strip()
    if layout and variant:
        return f"{layout} ({variant})"
    return layout or "(unknown)"


def player_status(config_dir: Path) -> tuple[str, str]:
    """Return (player_label, service_name) from setup-result.json.

    Fallback: Chromium (matches xibo.profile=chromium default).
    """
    path = config_dir / "setup-result.json"
    try:
        with path.open() as f:
            data = json.load(f)
        return data.get("player", "Chromium"), data.get("service", "xiboplayer-chromium.service")
    except (FileNotFoundError, json.JSONDecodeError):
        return "Chromium", "xiboplayer-chromium.service"


def cms_status(config_dir: Path, data_dir: Path, player: str) -> str:
    """Return the CMS URL for the active player, or '(not configured)'."""
    if player == "Arexibo":
        path = data_dir / "cms.json"
    elif player == "Electron":
        path = config_dir / "electron" / "config.json"
    else:  # Chromium + any other
        path = config_dir / "chromium" / "config.json"
    try:
        with path.open() as f:
            data = json.load(f)
        # chromium/electron use cmsUrl; arexibo uses address
        return data.get("cmsUrl") or data.get("address") or "(not configured)"
    except (FileNotFoundError, json.JSONDecodeError):
        return "(not configured)"

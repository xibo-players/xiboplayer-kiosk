"""CMS config writers — port of zlib_write_*_config from xibo-zenity-lib.sh.

One function per player. Called after CmsForm dialog collects URL/key/name.
Writes to the player-specific config file; NO doas needed (we write into
$HOME/.config/xiboplayer/<player>/config.json owned by the xibo user).
"""

from __future__ import annotations

import json
import secrets
from pathlib import Path


def _ensure_slash(url: str) -> str:
    return url if url.endswith("/") else url + "/"


def write_chromium(config_dir: Path, url: str, key: str, display_name: str) -> None:
    d = config_dir / "chromium"
    d.mkdir(parents=True, exist_ok=True)
    path = d / "config.json"
    data: dict = {}
    if path.exists():
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError:
            data = {}
    data["cmsUrl"] = _ensure_slash(url)
    data["cmsKey"] = key
    if display_name:
        data["displayName"] = display_name
    path.write_text(json.dumps(data, indent=2))


def write_electron(config_dir: Path, url: str, key: str, display_name: str) -> None:
    d = config_dir / "electron"
    d.mkdir(parents=True, exist_ok=True)
    path = d / "config.json"
    data: dict = {}
    if path.exists():
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError:
            data = {}
    data["cmsUrl"] = _ensure_slash(url)
    data["cmsKey"] = key
    if display_name:
        data["displayName"] = display_name
    path.write_text(json.dumps(data, indent=2))


def write_arexibo(data_dir: Path, url: str, key: str, display_name: str) -> None:
    """Arexibo uses ~/.local/share/xibo/cms.json with a different schema."""
    data_dir.mkdir(parents=True, exist_ok=True)
    hw_key = "xibo-" + secrets.token_hex(6)
    (data_dir / "cms.json").write_text(json.dumps({
        "address": _ensure_slash(url),
        "key": key,
        "displayId": hw_key,
        "displayName": display_name or hw_key,
    }, indent=2))


def write_for_player(
    player: str,
    config_dir: Path,
    data_dir: Path,
    url: str,
    key: str,
    display_name: str,
) -> None:
    """Dispatch on current player. Falls back to Chromium."""
    if player == "Electron":
        write_electron(config_dir, url, key, display_name)
    elif player == "Arexibo":
        write_arexibo(data_dir, url, key, display_name)
    else:
        write_chromium(config_dir, url, key, display_name)

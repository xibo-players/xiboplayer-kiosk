"""Tests for services.cms — player config writers.

These are the functions previously implemented as zlib_write_chromium_config,
zlib_write_electron_config, zlib_write_arexibo_cms_json in xibo-zenity-lib.sh.
Each writer produces a JSON file at a player-specific path; tests verify the
file layout, URL normalisation (trailing slash), and merge-with-existing-json
behaviour.
"""

import json

from xiboplayer_kiosk.services import cms


def test_chromium_writes_expected_keys(tmp_path):
    cms.write_chromium(tmp_path, "https://cms.test", "KEY", "Kiosk-1")
    data = json.loads((tmp_path / "chromium" / "config.json").read_text())
    assert data["cmsUrl"] == "https://cms.test/"
    assert data["cmsKey"] == "KEY"
    assert data["displayName"] == "Kiosk-1"


def test_chromium_adds_trailing_slash_if_missing(tmp_path):
    cms.write_chromium(tmp_path, "https://cms.test", "K", "D")
    data = json.loads((tmp_path / "chromium" / "config.json").read_text())
    assert data["cmsUrl"].endswith("/")


def test_chromium_preserves_trailing_slash(tmp_path):
    cms.write_chromium(tmp_path, "https://cms.test/", "K", "D")
    data = json.loads((tmp_path / "chromium" / "config.json").read_text())
    assert data["cmsUrl"] == "https://cms.test/"


def test_chromium_merges_with_existing_config(tmp_path):
    (tmp_path / "chromium").mkdir()
    (tmp_path / "chromium" / "config.json").write_text(
        json.dumps({"customSetting": "preserved", "cmsUrl": "old"}),
    )
    cms.write_chromium(tmp_path, "https://new/", "K", "D")
    data = json.loads((tmp_path / "chromium" / "config.json").read_text())
    assert data["customSetting"] == "preserved"  # merge preserved non-CMS keys
    assert data["cmsUrl"] == "https://new/"


def test_electron_writes_expected_keys(tmp_path):
    cms.write_electron(tmp_path, "https://cms.test/", "K", "D")
    data = json.loads((tmp_path / "electron" / "config.json").read_text())
    assert data["cmsUrl"] == "https://cms.test/"


def test_arexibo_generates_hwkey(tmp_path):
    cms.write_arexibo(tmp_path, "https://cms.test/", "K", "My-Kiosk")
    data = json.loads((tmp_path / "cms.json").read_text())
    assert data["address"] == "https://cms.test/"
    assert data["displayId"].startswith("xibo-")
    assert len(data["displayId"]) == len("xibo-") + 12  # 6 hex bytes = 12 chars
    assert data["displayName"] == "My-Kiosk"


def test_arexibo_uses_hwkey_as_displayname_when_empty(tmp_path):
    cms.write_arexibo(tmp_path, "https://cms.test/", "K", "")
    data = json.loads((tmp_path / "cms.json").read_text())
    assert data["displayName"] == data["displayId"]


def test_write_for_player_dispatches_chromium(tmp_path):
    cms.write_for_player("Chromium", tmp_path, tmp_path, "https://cms/", "K", "D")
    assert (tmp_path / "chromium" / "config.json").exists()
    assert not (tmp_path / "electron" / "config.json").exists()


def test_write_for_player_dispatches_electron(tmp_path):
    cms.write_for_player("Electron", tmp_path, tmp_path, "https://cms/", "K", "D")
    assert (tmp_path / "electron" / "config.json").exists()


def test_write_for_player_dispatches_arexibo(tmp_path):
    cms.write_for_player("Arexibo", tmp_path, tmp_path, "https://cms/", "K", "D")
    assert (tmp_path / "cms.json").exists()


def test_write_for_player_unknown_falls_back_to_chromium(tmp_path):
    cms.write_for_player("Unknown", tmp_path, tmp_path, "https://cms/", "K", "D")
    assert (tmp_path / "chromium" / "config.json").exists()

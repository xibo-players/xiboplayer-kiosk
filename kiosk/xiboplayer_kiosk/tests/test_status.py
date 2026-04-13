"""Tests for services.status — system probes with subprocess mocked out."""

import json
from unittest.mock import patch

from xiboplayer_kiosk.services import status


class FakeProc:
    def __init__(self, stdout="", returncode=0):
        self.stdout = stdout
        self.returncode = returncode


def test_wifi_status_returns_active_ssid(monkeypatch):
    # First call = dev status list; second = active conn list
    def fake_run(cmd, **kw):
        if "dev" in cmd and "status" in cmd:
            return FakeProc("wlp3s0:wifi\n")
        if "conn" in cmd:
            return FakeProc("HomeWiFi:802-11-wireless:activated\n")
        return FakeProc("")

    with patch("subprocess.run", side_effect=fake_run):
        assert status.wifi_status() == "HomeWiFi"


def test_wifi_status_reports_wired(monkeypatch):
    def fake_run(cmd, **kw):
        if "dev" in cmd and "status" in cmd:
            return FakeProc("wlp3s0:wifi\nenp0s31f6:ethernet\n")
        if "conn" in cmd:
            return FakeProc("EthernetA:802-3-ethernet:activated\n")
        return FakeProc("")

    with patch("subprocess.run", side_effect=fake_run):
        assert status.wifi_status() == "(wired)"


def test_wifi_status_no_hardware(monkeypatch):
    with patch("subprocess.run", return_value=FakeProc("enp0s31f6:ethernet\n")):
        assert status.wifi_status().startswith("(no wifi hardware")


def test_player_status_default_on_missing_file(tmp_path):
    player, service = status.player_status(tmp_path)
    assert player == "Chromium"
    assert service == "xiboplayer-chromium.service"


def test_player_status_reads_json(tmp_path):
    (tmp_path / "setup-result.json").write_text(
        json.dumps({"player": "Electron", "service": "xiboplayer-electron.service"}),
    )
    player, service = status.player_status(tmp_path)
    assert player == "Electron"
    assert service == "xiboplayer-electron.service"


def test_player_status_default_on_bad_json(tmp_path):
    (tmp_path / "setup-result.json").write_text("{not json")
    player, _ = status.player_status(tmp_path)
    assert player == "Chromium"


def test_cms_status_chromium_config(tmp_path):
    d = tmp_path / "chromium"
    d.mkdir()
    (d / "config.json").write_text(json.dumps({"cmsUrl": "https://c/", "cmsKey": "K"}))
    assert status.cms_status(tmp_path, tmp_path, "Chromium") == "https://c/"


def test_cms_status_arexibo_uses_address(tmp_path):
    (tmp_path / "cms.json").write_text(json.dumps({"address": "https://arx/", "key": "K"}))
    assert status.cms_status(tmp_path, tmp_path, "Arexibo") == "https://arx/"


def test_cms_status_unconfigured(tmp_path):
    assert status.cms_status(tmp_path, tmp_path, "Chromium") == "(not configured)"


def test_timezone_status(monkeypatch):
    with patch("subprocess.run", return_value=FakeProc("Europe/Madrid\n")):
        assert status.timezone_status() == "Europe/Madrid"


def test_timezone_status_fallback_on_empty(monkeypatch):
    with patch("subprocess.run", return_value=FakeProc("", returncode=1)):
        assert status.timezone_status() == "(unknown)"

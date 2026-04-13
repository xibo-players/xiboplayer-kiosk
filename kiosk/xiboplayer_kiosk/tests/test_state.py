"""Tests for state.KioskState.

We stub the subprocess-driven refreshes by patching the imported
`status` module functions; state construction + refresh dispatch is
what's tested here, not the underlying system probes.
"""

from pathlib import Path
from unittest.mock import patch

from xiboplayer_kiosk.state import KioskState


def test_load_populates_preseed(tmp_path, monkeypatch):
    preseed_file = tmp_path / "preseed.env"
    preseed_file.write_text("xibo.cms_url=https://cms/\nxibo.display_name=kiosk-7\n")
    monkeypatch.setattr("xiboplayer_kiosk.preseed.PRESEED_PATH", preseed_file)
    with patch("xiboplayer_kiosk.services.status.wifi_status", return_value="(wired)"), \
         patch("xiboplayer_kiosk.services.status.timezone_status", return_value="UTC"), \
         patch("xiboplayer_kiosk.services.status.locale_status", return_value="en_US.UTF-8"), \
         patch("xiboplayer_kiosk.services.status.keyboard_status", return_value="us"), \
         patch("xiboplayer_kiosk.services.status.player_status", return_value=("Chromium", "xiboplayer-chromium.service")), \
         patch("xiboplayer_kiosk.services.status.cms_status", return_value="https://cms/"):
        s = KioskState.load()
    assert s.preseed_vars["xibo.cms_url"] == "https://cms/"
    assert s.preseed_vars["xibo.display_name"] == "kiosk-7"
    assert s.timezone == "UTC"
    assert s.locale == "en_US.UTF-8"
    assert s.player == "Chromium"
    assert s.wifi_ssid == "(wired)"
    assert s.wired_connected is True
    assert s.wifi_hardware_present is True


def test_refresh_wifi_no_hardware():
    s = KioskState()
    with patch("xiboplayer_kiosk.services.status.wifi_status", return_value="(no wifi hardware)"):
        s.refresh_wifi()
    assert s.wifi_hardware_present is False
    assert s.wired_connected is False


def test_refresh_player_sets_service():
    s = KioskState()
    with patch(
        "xiboplayer_kiosk.services.status.player_status",
        return_value=("Electron", "xiboplayer-electron.service"),
    ):
        s.refresh_player()
    assert s.player == "Electron"
    assert s.player_service == "xiboplayer-electron.service"


def test_default_kiosk_dir():
    s = KioskState()
    assert s.kiosk_dir == Path("/usr/share/xiboplayer-kiosk")

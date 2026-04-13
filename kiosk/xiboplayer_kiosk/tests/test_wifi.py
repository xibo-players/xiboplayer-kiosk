"""Tests for services.wifi — nmcli output parsing.

The tricky part is the colon-separated, backslash-escaped nmcli -t format;
we test the split helper + the list_networks() post-processing without
actually shelling out.
"""

from unittest.mock import patch

from xiboplayer_kiosk.services import wifi


def test_split_nmcli_line_plain():
    assert wifi._split_nmcli_line("*:MyWiFi:85:WPA2") == ["*", "MyWiFi", "85", "WPA2"]


def test_split_nmcli_line_handles_escaped_colon():
    # SSID containing a literal ":" — nmcli escapes as \:
    assert wifi._split_nmcli_line(r":net\:work:70:open") == ["", "net:work", "70", "open"]


def test_split_nmcli_line_empty_fields():
    assert wifi._split_nmcli_line(":::" ) == ["", "", "", ""]


class FakeProc:
    def __init__(self, stdout="", returncode=0):
        self.stdout = stdout
        self.returncode = returncode


def test_list_networks_dedupes_by_ssid(monkeypatch):
    stdout = (
        " :NetA:80:WPA2\n"
        " :NetA:70:WPA2\n"  # duplicate, should be dropped
        " :NetB:60:open\n"
    )
    with patch("subprocess.run", return_value=FakeProc(stdout)):
        nets = wifi.list_networks()
    ssids = [n.ssid for n in nets]
    assert ssids == ["NetA", "NetB"]  # sorted by signal desc, deduped


def test_list_networks_maps_empty_security_to_open(monkeypatch):
    stdout = " :NetOpen:65:--\n"
    with patch("subprocess.run", return_value=FakeProc(stdout)):
        nets = wifi.list_networks()
    assert len(nets) == 1
    assert nets[0].security == "open"


def test_list_networks_sorted_by_signal_desc(monkeypatch):
    stdout = (
        " :NetLow:20:open\n"
        " :NetHigh:90:open\n"
        " :NetMid:50:open\n"
    )
    with patch("subprocess.run", return_value=FakeProc(stdout)):
        nets = wifi.list_networks()
    assert [n.ssid for n in nets] == ["NetHigh", "NetMid", "NetLow"]


def test_list_networks_marks_in_use(monkeypatch):
    stdout = (
        "*:HomeWiFi:95:WPA2\n"
        " :Other:50:WPA2\n"
    )
    with patch("subprocess.run", return_value=FakeProc(stdout)):
        nets = wifi.list_networks()
    home = next(n for n in nets if n.ssid == "HomeWiFi")
    assert home.in_use is True
    other = next(n for n in nets if n.ssid == "Other")
    assert other.in_use is False


def test_list_networks_empty_on_nmcli_failure(monkeypatch):
    with patch("subprocess.run", return_value=FakeProc("", returncode=1)):
        assert wifi.list_networks() == []


def test_has_wifi_hardware_true(monkeypatch):
    stdout = "wlp3s0:wifi:connected\nenp0s31f6:ethernet:unavailable\n"
    with patch("subprocess.run", return_value=FakeProc(stdout)):
        assert wifi.has_wifi_hardware() is True


def test_has_wifi_hardware_false_wired_only(monkeypatch):
    stdout = "enp0s31f6:ethernet:connected\n"
    with patch("subprocess.run", return_value=FakeProc(stdout)):
        assert wifi.has_wifi_hardware() is False

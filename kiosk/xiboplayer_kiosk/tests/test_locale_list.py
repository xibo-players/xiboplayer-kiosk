"""Tests for services.locale — list filtering.

The filter strips @variants + non-UTF-8 encodings + C.*/POSIX — same
rules as kiosk/xibo-first-boot.sh handle_language used to apply via
`grep -Ev '@|\\.iso...' | grep -v '^C\\.' | grep -v '^POSIX$'`.
"""

from unittest.mock import patch

from xiboplayer_kiosk.services import locale


class FakeProc:
    def __init__(self, stdout, returncode=0):
        self.stdout = stdout
        self.returncode = returncode


def test_keeps_utf8_locales(monkeypatch):
    stdout = "en_US.UTF-8\nes_ES.UTF-8\nca_ES.UTF-8\nfr_FR.UTF-8\n"
    with patch("subprocess.run", return_value=FakeProc(stdout)):
        got = locale.list_locales()
    assert got == ["en_US.UTF-8", "es_ES.UTF-8", "ca_ES.UTF-8", "fr_FR.UTF-8"]


def test_filters_variant_suffix(monkeypatch):
    stdout = (
        "es_ES.UTF-8\n"
        "es_ES@euro\n"            # @variant — drop
        "es_ES.UTF-8@euro\n"      # @variant — drop
    )
    with patch("subprocess.run", return_value=FakeProc(stdout)):
        got = locale.list_locales()
    assert got == ["es_ES.UTF-8"]


def test_filters_legacy_encodings(monkeypatch):
    stdout = (
        "en_GB.UTF-8\n"
        "en_GB.ISO-8859-1\n"      # iso-8859 — drop
        "en_GB.iso88591\n"        # alt spelling — drop
        "ru_RU.KOI8-R\n"          # koi — drop
    )
    with patch("subprocess.run", return_value=FakeProc(stdout)):
        got = locale.list_locales()
    assert got == ["en_GB.UTF-8"]


def test_filters_c_and_posix(monkeypatch):
    stdout = "C.UTF-8\nPOSIX\nen_US.UTF-8\n"
    with patch("subprocess.run", return_value=FakeProc(stdout)):
        got = locale.list_locales()
    assert got == ["en_US.UTF-8"]


def test_empty_on_failure(monkeypatch):
    with patch("subprocess.run", return_value=FakeProc("", returncode=1)):
        assert locale.list_locales() == []

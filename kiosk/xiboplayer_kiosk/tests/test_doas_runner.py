from pathlib import Path
from unittest.mock import patch

from xiboplayer_kiosk.doas_runner import DoasRunner


def test_run_success(monkeypatch):
    class FakeResult:
        returncode = 0
        stdout = "ok\n"
        stderr = ""

    with patch("subprocess.run", return_value=FakeResult()):
        r = DoasRunner().run("xibo-set-timezone.sh", "Europe/Madrid")
    assert r == (True, "ok\n")


def test_run_failure_captures_stderr(monkeypatch):
    class FakeResult:
        returncode = 1
        stdout = ""
        stderr = "permission denied\n"

    with patch("subprocess.run", return_value=FakeResult()):
        ok, out = DoasRunner().run("xibo-set-wifi.sh", "MyWiFi", "secret")
    assert ok is False
    assert "permission denied" in out


def test_run_timeout_returns_false(monkeypatch):
    import subprocess as sp
    with patch("subprocess.run", side_effect=sp.TimeoutExpired("doas", 30)):
        ok, out = DoasRunner().run("xibo-set-wifi.sh", "SlowNet", timeout=30)
    assert ok is False
    assert "timed out" in out


def test_run_missing_script_returns_false(monkeypatch):
    with patch("subprocess.run", side_effect=FileNotFoundError()):
        ok, out = DoasRunner().run("xibo-set-nonexistent.sh")
    assert ok is False
    assert "not found" in out

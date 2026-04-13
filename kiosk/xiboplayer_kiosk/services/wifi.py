"""Wi-Fi list + scan. Mutation via DoasRunner / xibo-set-wifi.sh."""

import subprocess
from dataclasses import dataclass


@dataclass
class WifiNetwork:
    ssid: str
    signal: int  # 0-100
    security: str  # "open" | "WPA2" | "WPA3" | ...
    in_use: bool


def has_wifi_hardware() -> bool:
    try:
        r = subprocess.run(
            ["nmcli", "-t", "-f", "DEVICE,TYPE", "dev", "status"],
            capture_output=True, text=True, timeout=3, check=False,
        )
    except Exception:  # noqa: BLE001
        return False
    return any(":wifi" in line for line in r.stdout.splitlines())


def rescan() -> None:
    """Fire a WiFi rescan in the background; returns immediately."""
    try:
        subprocess.Popen(
            ["nmcli", "dev", "wifi", "rescan"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except Exception:  # noqa: BLE001
        pass


def list_networks() -> list[WifiNetwork]:
    """Return currently-visible networks sorted by signal, deduped by SSID."""
    try:
        r = subprocess.run(
            ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list"],
            capture_output=True, text=True, timeout=5, check=False,
        )
    except Exception:  # noqa: BLE001
        return []
    if r.returncode != 0:
        return []
    seen: dict[str, WifiNetwork] = {}
    for line in r.stdout.splitlines():
        # nmcli -t escapes embedded colons with a backslash. naïve split
        # is fine for 4 fields where SSID is field 2 (rare edge: SSIDs
        # containing colon — de-escape).
        parts = _split_nmcli_line(line)
        if len(parts) < 4:
            continue
        in_use, ssid, signal_s, security = parts[0], parts[1], parts[2], parts[3]
        if not ssid or ssid in seen:
            continue
        try:
            signal = int(signal_s)
        except ValueError:
            signal = 0
        if not security or security == "--":
            security = "open"
        seen[ssid] = WifiNetwork(
            ssid=ssid, signal=signal, security=security, in_use=(in_use == "*"),
        )
    return sorted(seen.values(), key=lambda n: (-n.signal, n.ssid))


def _split_nmcli_line(line: str) -> list[str]:
    """Split nmcli -t output: `:` separator with `\\:` escape."""
    out: list[str] = []
    buf = ""
    i = 0
    while i < len(line):
        c = line[i]
        if c == "\\" and i + 1 < len(line) and line[i + 1] == ":":
            buf += ":"
            i += 2
            continue
        if c == ":":
            out.append(buf)
            buf = ""
            i += 1
            continue
        buf += c
        i += 1
    out.append(buf)
    return out

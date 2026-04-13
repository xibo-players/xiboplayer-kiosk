"""Keyboard-layout list. Reads from `localectl list-x11-keymap-layouts`."""

import subprocess


def list_layouts() -> list[str]:
    try:
        r = subprocess.run(
            ["localectl", "list-x11-keymap-layouts"],
            capture_output=True, text=True, timeout=5, check=False,
        )
    except Exception:  # noqa: BLE001
        return []
    if r.returncode != 0:
        return []
    return [line.strip() for line in r.stdout.splitlines() if line.strip()]

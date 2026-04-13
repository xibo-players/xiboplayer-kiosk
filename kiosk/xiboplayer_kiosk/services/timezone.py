"""Timezone list. Reads from `timedatectl list-timezones`."""

import subprocess


def list_timezones() -> list[str]:
    try:
        r = subprocess.run(
            ["timedatectl", "list-timezones"],
            capture_output=True, text=True, timeout=5, check=False,
        )
    except Exception:  # noqa: BLE001
        return []
    if r.returncode != 0:
        return []
    return [line.strip() for line in r.stdout.splitlines() if line.strip()]

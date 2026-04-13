"""Desktop notifications — thin wrapper around notify-send."""

import subprocess


def send(msg: str, urgency: str = "normal", replace_id: int = 1) -> None:
    try:
        subprocess.run(
            ["notify-send", "-r", str(replace_id), "-u", urgency, "-t", "0", "Xibo", msg],
            check=False, capture_output=True, timeout=5,
        )
    except Exception:  # noqa: BLE001
        pass

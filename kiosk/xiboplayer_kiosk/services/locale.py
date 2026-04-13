"""Locale read + set. Filter list matches kickstart/xibo-first-boot.sh."""

import re
import subprocess


# Same filter as kiosk/xibo-first-boot.sh handle_language:
# drop @variant, non-UTF-8 encodings, C.*, POSIX
_REJECT = re.compile(r"@|\.(iso|ISO|koi|KOI|gb|GB|euc|EUC|big|BIG)")


def list_locales() -> list[str]:
    """All UTF-8 locales from localectl list-locales, sans @variants + legacy encodings."""
    try:
        r = subprocess.run(
            ["localectl", "list-locales"], capture_output=True, text=True, timeout=5, check=False,
        )
    except Exception:  # noqa: BLE001
        return []
    if r.returncode != 0:
        return []
    out: list[str] = []
    for line in r.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        if _REJECT.search(line):
            continue
        if line.startswith("C.") or line == "POSIX":
            continue
        out.append(line)
    return out

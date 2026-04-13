"""Pure-Python port of _preseed_get from kickstart %post.

/etc/xiboplayer-preseed.env is a KEY=VALUE file written by the installer
%post from kernel-cmdline `xibo.*=` params + `xibo.config_url=` JSON
fetch + USB /setup.json auto-detect. We NEVER `source` it (shell-eval
would let a malicious value run arbitrary code); we parse KEY=VALUE
lines explicitly.
"""

from pathlib import Path

PRESEED_PATH = Path("/etc/xiboplayer-preseed.env")


def read(key: str, path: Path | None = None) -> str:
    """Look up a single key in the preseed environment file.

    Parameters
    ----------
    key
        Full dotted key name, e.g. ``"xibo.cms_url"``.
    path
        File to read. Defaults to ``/etc/xiboplayer-preseed.env`` but is
        injectable for tests.

    Returns
    -------
    str
        The value string with surrounding whitespace stripped, or ``""``
        if the key is absent, the file is missing, or an I/O error occurs.

    Notes
    -----
    We never ``source`` the preseed file. Shell evaluation would let a
    malicious value run arbitrary commands (e.g. via ``xibo.cms_url=$(rm -rf /)``).
    Parsing each line as ``KEY=VALUE`` is safe against every form of
    shell injection.
    """
    if path is None:
        path = PRESEED_PATH
    try:
        with path.open() as f:
            for line in f:
                line = line.strip()
                if line.startswith(key + "="):
                    return line[len(key) + 1:]
    except FileNotFoundError:
        pass
    return ""


def read_all(path: Path | None = None) -> dict[str, str]:
    """Parse every ``KEY=VALUE`` line from the preseed file.

    Parameters
    ----------
    path
        File to read. Defaults to ``/etc/xiboplayer-preseed.env``.

    Returns
    -------
    dict[str, str]
        Mapping of key names to values. Blank lines and lines starting
        with ``#`` are skipped. Empty dict if file missing.
    """
    if path is None:
        path = PRESEED_PATH
    out: dict[str, str] = {}
    try:
        with path.open() as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    continue
                k, _, v = line.partition("=")
                out[k] = v
    except FileNotFoundError:
        pass
    return out

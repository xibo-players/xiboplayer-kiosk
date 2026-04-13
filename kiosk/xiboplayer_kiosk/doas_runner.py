"""DoasRunner — single choke-point for calls to the xibo-set-*.sh helpers.

Every mutator (wifi connect, timezone set, locale set, keyboard set, player
switch) goes through doas to the corresponding shell helper. This wrapper:
- Captures stderr (today's scripts redirect to /dev/null → silent failures)
- Has a timeout (unresponsive nmcli won't freeze the UI forever)
- Never raises — returns (bool, str) so the caller can show ErrorDialog

The boundary: Python never uses sudo/doas on its own commands. Only the
shell helpers can be elevated — they validate arguments and are allowlisted
in /etc/doas.conf.
"""

import subprocess
from pathlib import Path


class DoasRunner:
    """Runs the privileged `xibo-set-*.sh` helpers via `doas`.

    The kiosk wizard is a user-level application, but mutating system
    state (WiFi keyfile, timezone, locale, keyboard layout, player
    alternative) requires root. Rather than giving the Python app any
    elevation, we call pre-validated shell helpers that are allowlisted
    in `/etc/doas.conf` for the xibo user.

    This class centralises the `doas <kiosk_dir>/xibo-set-*.sh ARG...`
    invocation so every mutation goes through the same code path and
    we can (a) capture stderr (shell scripts historically `2>/dev/null`
    their errors, leading to silent failures), (b) enforce a timeout
    (unresponsive `nmcli` must not freeze the UI indefinitely), and (c)
    never raise — errors come back as `(False, message)` so callers can
    surface them in an `ErrorDialog`.
    """

    def __init__(self, kiosk_dir: Path = Path("/usr/share/xiboplayer-kiosk")):
        """
        Parameters
        ----------
        kiosk_dir
            Directory that contains the `xibo-set-*.sh` helper scripts.
            Injectable for tests; defaults to the on-disk install path.
        """
        self.kiosk_dir = kiosk_dir

    def run(self, helper: str, *args: str, timeout: int = 30) -> tuple[bool, str]:
        """Invoke a single `xibo-set-*.sh` helper via `doas`.

        Parameters
        ----------
        helper
            Basename of the helper script, e.g. ``"xibo-set-timezone.sh"``.
            Joined with ``kiosk_dir`` to form the absolute path.
        *args
            Positional arguments forwarded to the helper (already validated
            by the shell script's own argument parser).
        timeout
            Kill the subprocess if it runs longer than this many seconds.

        Returns
        -------
        tuple[bool, str]
            ``(True, combined_output)`` on exit-code 0; otherwise
            ``(False, message)`` where *message* contains captured stderr
            and stdout (suitable for display in an error dialog).

        Notes
        -----
        Never raises — all exception classes are mapped to a
        ``(False, message)`` return so calling code can stay branch-free.
        """
        script = self.kiosk_dir / helper
        cmd = ["doas", str(script), *args]
        try:
            r = subprocess.run(
                cmd, capture_output=True, text=True, timeout=timeout, check=False,
            )
            combined = (r.stderr or "") + (r.stdout or "")
            return r.returncode == 0, combined
        except subprocess.TimeoutExpired:
            return False, f"{helper} timed out after {timeout}s"
        except FileNotFoundError:
            return False, f"{helper} not found at {script}"
        except Exception as e:  # noqa: BLE001 — caller surfaces to UI
            return False, f"{helper} failed: {e}"

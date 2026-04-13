"""Entry-point for `python3 -m xiboplayer_kiosk`.

Parses a single ``--mode`` flag selecting which flow to present:
- ``first-boot`` (default): Welcome splash → Main menu → dispatches to pickers
- ``reconfigure``: Reconfigure menu (Ctrl+R entry after first-boot is done)

The shell wrappers ``/usr/share/xiboplayer-kiosk/xibo-first-boot`` and
``xibo-reconfigure`` invoke this module with the appropriate mode.
"""

import argparse
import sys

from .app import KioskApp


def main() -> int:
    """Build argument parser, run the Adw.Application, return exit code."""
    parser = argparse.ArgumentParser(
        prog="xiboplayer-kiosk-wizard",
        description="xiboplayer kiosk first-boot and reconfigure wizard.",
    )
    parser.add_argument(
        "--mode",
        choices=["first-boot", "reconfigure"],
        default="first-boot",
        help="Which flow to present.",
    )
    args = parser.parse_args()

    app = KioskApp(mode=args.mode)
    return app.run([])


if __name__ == "__main__":
    sys.exit(main())

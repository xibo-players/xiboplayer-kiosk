"""xiboplayer_kiosk — Python package for the first-boot + reconfigure wizard.

Replaces kiosk/xibo-first-boot.sh + xibo-show-cms.sh + xibo-zenity-lib.sh +
xibo-picker.py with a single GTK4+libadwaita application. See the blueprint
in docs/ (or the #PR1-PR4 sequence of PRs) for architecture.
"""

from .branding import BRAND_HEADING_MARKUP, BRAND_XIBO, BRAND_PLAYER, LOGO_PATH  # noqa: F401

__version__ = "0.5.0"

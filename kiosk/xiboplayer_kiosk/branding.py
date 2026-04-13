"""Branding constants — single source of truth for colors, markup, logo."""

from pathlib import Path

# Canonical colors from kiosk/xibo-zenity-lib.sh:167 and reference_xiboplayer_branding
BRAND_XIBO_COLOR = "#0097D8"  # cyan "xibo"
BRAND_PLAYER_COLOR = "#FFFFFF"  # white "player"

BRAND_XIBO = f'<span font_weight="bold" foreground="{BRAND_XIBO_COLOR}">xibo</span>'
BRAND_PLAYER = f'<span font_weight="bold" foreground="{BRAND_PLAYER_COLOR}">player</span>'

# xx-large for the prominent heading slots (welcome splash, main menu title)
BRAND_HEADING_MARKUP = (
    f'<span size="xx-large" font_weight="bold" foreground="{BRAND_XIBO_COLOR}">xibo</span>'
    f'<span size="xx-large" font_weight="bold" foreground="{BRAND_PLAYER_COLOR}">player</span>'
)

# Logo image shipped by the kiosk RPM at /usr/share/xiboplayer-kiosk/
LOGO_PATH = Path("/usr/share/xiboplayer-kiosk/xiboplayer-kiosk-logo.png")


def branded_heading(subtitle: str = "") -> str:
    """Produce Pango markup for a dialog heading.

    Parameters
    ----------
    subtitle
        Small grey text shown below the bold "xiboplayer" line.
        Typical values: ``"Language"``, ``"First boot setup — v0.4.36"``.
        If empty, only the brand name is rendered.

    Returns
    -------
    str
        A single Pango-markup string suitable for ``Adw.AlertDialog.set_heading``
        when ``set_heading_use_markup(True)`` has been called, or for a
        ``Gtk.Label.set_markup`` call in a custom widget.

    Examples
    --------
    >>> markup = branded_heading("Timezone")
    >>> "xibo" in markup and "#0097D8" in markup
    True
    """
    out = BRAND_HEADING_MARKUP
    if subtitle:
        out += "\n" + f'<span size="small">{subtitle}</span>'
    return out

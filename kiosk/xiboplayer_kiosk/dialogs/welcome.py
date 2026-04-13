"""Welcome splash — logo left, branded text right. First-boot only."""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gtk  # noqa: E402

from .. import branding
from .base import BrandedAlertDialog


class WelcomeSplash(BrandedAlertDialog):
    """One-shot info prompt shown BEFORE the main menu on first boot."""

    def __init__(self, version: str = "", build_date: str = ""):
        super().__init__(heading_subtitle="", body="")
        # Custom extra_child with logo LEFT + branded text RIGHT
        self.set_heading("")  # use custom widget instead of heading

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        root.set_size_request(520, -1)

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        row.set_halign(Gtk.Align.CENTER)
        row.set_margin_top(4)
        row.set_margin_bottom(4)

        if branding.LOGO_PATH.exists():
            img = Gtk.Image.new_from_file(str(branding.LOGO_PATH))
            img.set_pixel_size(96)
            img.set_valign(Gtk.Align.CENTER)
            row.append(img)

        text_col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        text_col.set_hexpand(True)
        text_col.set_valign(Gtk.Align.CENTER)

        brand = Gtk.Label()
        brand.set_markup(branding.BRAND_HEADING_MARKUP)
        brand.set_xalign(0)
        text_col.append(brand)

        if version or build_date:
            sub = Gtk.Label()
            sub.set_markup(
                f'<span size="medium">Welcome — v{version}'
                + (f" ({build_date})" if build_date else "")
                + "</span>",
            )
            sub.set_xalign(0)
            sub.set_wrap(True)
            text_col.append(sub)

        row.append(text_col)
        root.append(row)

        body = Gtk.Label()
        body.set_markup(
            "The next screen lets you configure Language, Keyboard, Wi-Fi, "
            "Timezone, Player, and CMS connection. Advanced and diagnostic "
            "actions live under the Settings row. Press Continue when ready.",
        )
        body.set_xalign(0)
        body.set_wrap(True)
        body.set_margin_top(8)
        root.append(body)

        self.set_extra_child(root)

        self.add_suggested("continue", "Continue")
        self.add_cancel("Skip")

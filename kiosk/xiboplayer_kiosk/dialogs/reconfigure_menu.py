"""Reconfigure menu — entered via Ctrl+R after first-boot is already done."""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gtk  # noqa: E402

from ..state import KioskState
from .base import BrandedAlertDialog


class ReconfigureMenu(BrandedAlertDialog):
    def __init__(self, state: KioskState, *, on_pick=None):
        super().__init__(
            heading_subtitle="Reconfigure",
            body=(f"Player:  {state.player}\nCMS:     {state.cms_url}"),
        )
        self.on_pick = on_pick

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        box.set_size_request(520, -1)

        group = Adw.PreferencesGroup()
        for action, title, subtitle in (
            ("cms",    "Reconfigure CMS", "Edit CMS URL / key / display name"),
            ("full",   "Full setup",      "Re-run the first-boot wizard"),
            ("settings","Open Settings",  "Terminal / GNOME Settings / Debug bundle"),
        ):
            row = Adw.ActionRow(title=title, subtitle=subtitle)
            row.set_activatable(True)
            row.connect("activated", self._on_row_activated, action)
            row.add_suffix(Gtk.Image.new_from_icon_name("go-next-symbolic"))
            group.add(row)
        box.append(group)

        self.set_extra_child(box)

        self.add_suggested("close", "Close")
        self.set_close_response("close")

    def _on_row_activated(self, _row, action: str) -> None:
        if callable(self.on_pick):
            self.on_pick(action)

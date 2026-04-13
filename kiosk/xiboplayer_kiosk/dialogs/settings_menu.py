"""Settings sub-menu — Open terminal / GNOME Settings / Debug / Back."""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gtk  # noqa: E402

from .base import BrandedAlertDialog


class SettingsMenu(BrandedAlertDialog):
    def __init__(self, *, on_pick=None):
        super().__init__(heading_subtitle="Settings", body="")
        self.on_pick = on_pick

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        box.set_size_request(480, -1)

        group = Adw.PreferencesGroup()
        for action, title, subtitle in (
            ("terminal", "Open terminal", "ptyxis (Ctrl+S also works)"),
            ("gnome",    "GNOME Settings", "Advanced system tweaks (escape hatch)"),
            ("debug",    "Collect debug bundle", "~/Downloads/xibo-debug-*.tar.zst"),
        ):
            row = Adw.ActionRow(title=title, subtitle=subtitle)
            row.set_activatable(True)
            row.connect("activated", self._on_row_activated, action)
            row.add_suffix(Gtk.Image.new_from_icon_name("go-next-symbolic"))
            group.add(row)
        box.append(group)

        self.set_extra_child(box)
        self.add_suggested("back", "Back")
        self.set_close_response("back")

    def _on_row_activated(self, _row, action: str) -> None:
        if callable(self.on_pick):
            self.on_pick(action)

"""Player picker — 2-row radio selector (Chromium / Electron)."""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gtk  # noqa: E402

from .base import BrandedAlertDialog


class PlayerPicker(BrandedAlertDialog):
    def __init__(self, current: str = "Chromium"):
        super().__init__(
            heading_subtitle="Player",
            body=f"Current player: {current} — choose which runs on next session.",
        )
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_size_request(480, -1)

        group = Adw.PreferencesGroup()
        self._group_leader: Gtk.CheckButton | None = None
        self._checks: dict[str, Gtk.CheckButton] = {}

        for label, subtitle in (
            ("Chromium", "Chromium kiosk (default, lighter)"),
            ("Electron", "Electron wrapper (heavier, more compatible)"),
        ):
            row = Adw.ActionRow(title=label, subtitle=subtitle)
            check = Gtk.CheckButton()
            if self._group_leader is None:
                self._group_leader = check
            else:
                check.set_group(self._group_leader)
            check.set_active(label == current)
            row.add_prefix(check)
            row.set_activatable_widget(check)
            group.add(row)
            self._checks[label] = check

        box.append(group)
        self.set_extra_child(box)

        self.add_cancel()
        self.add_suggested("switch", "Switch")

    def selected_player(self) -> str:
        for name, chk in self._checks.items():
            if chk.get_active():
                return name
        return "Chromium"

"""Main menu — 7 rows with live status column."""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk  # noqa: E402

from ..state import KioskState
from .base import BrandedAlertDialog


class MainMenu(BrandedAlertDialog):
    """First-boot main menu. Status rendered from KioskState. Row activation
    fires a callback the caller wires into the per-row handler."""

    def __init__(self, state: KioskState, *, version: str = "", on_pick=None, on_start=None):
        super().__init__(
            heading_subtitle=(f"First boot setup — v{version}" if version else "First boot setup"),
            body="",
        )
        self.state = state
        self.on_pick = on_pick  # callable(action: str) -> None
        self.on_start = on_start  # callable() -> None

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        box.set_size_request(560, -1)

        self.group = Adw.PreferencesGroup()
        self._rows: dict[str, Adw.ActionRow] = {}
        self._build_rows()
        box.append(self.group)

        self.set_extra_child(box)

        # Only one button — Start. No Cancel (escape = start too).
        self.add_suggested("start", "Start player")
        self.set_close_response("start")

        self.connect("response", self._on_response)

    def _build_rows(self) -> None:
        for action, title, status in self._row_spec():
            row = Adw.ActionRow(title=title, subtitle=status)
            row.set_activatable(True)
            row.connect("activated", self._on_row_activated, action)
            # Right-arrow suffix for visual "this opens a dialog"
            row.add_suffix(Gtk.Image.new_from_icon_name("go-next-symbolic"))
            self.group.add(row)
            self._rows[action] = row

    def _row_spec(self) -> list[tuple[str, str, str]]:
        s = self.state
        return [
            ("language", "Language", s.locale or "(unknown)"),
            ("keyboard", "Keyboard", s.keyboard_layout),
            ("wifi",     "Wi-Fi",    s.wifi_ssid),
            ("timezone", "Timezone", s.timezone),
            ("player",   "Player",   s.player),
            ("cms",      "CMS",      s.cms_url),
            ("settings", "Settings", ""),
        ]

    def refresh_rows(self) -> None:
        """Re-render subtitles from current state (call after any setter)."""
        self.state.refresh_all()
        for action, _title, status in self._row_spec():
            if action in self._rows:
                self._rows[action].set_subtitle(status)

    def _on_row_activated(self, _row, action: str) -> None:
        if callable(self.on_pick):
            self.on_pick(action)

    def _on_response(self, _dlg, response_id: str) -> None:
        if response_id == "start" and callable(self.on_start):
            self.on_start()

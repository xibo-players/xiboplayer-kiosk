"""BrandedAlertDialog — shared ancestor for every kiosk dialog.

Centralises:
- branded heading (blue `xibo` + white `player` + optional subtitle) via
  set_heading_use_markup(True)
- SUGGESTED appearance on primary button
- window icon from branding.LOGO_PATH (AlertDialog itself has no window, but
  when it's its own top-level window the icon applies)
- dark color-scheme preference (kiosk always runs dark)
"""

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk  # noqa: E402

from ..branding import branded_heading


class BrandedAlertDialog(Adw.AlertDialog):
    """Parent for every kiosk dialog. Subclasses fill `extra_child` + responses."""

    def __init__(self, *, heading_subtitle: str = "", body: str = ""):
        super().__init__()
        self.set_heading_use_markup(True)
        self.set_heading(branded_heading(heading_subtitle))
        if body:
            self.set_body(body)
        self._result = None

    def add_suggested(self, response_id: str, label: str) -> None:
        self.add_response(response_id, label)
        self.set_response_appearance(response_id, Adw.ResponseAppearance.SUGGESTED)
        self.set_default_response(response_id)

    def add_destructive(self, response_id: str, label: str) -> None:
        self.add_response(response_id, label)
        self.set_response_appearance(response_id, Adw.ResponseAppearance.DESTRUCTIVE)

    def add_cancel(self, label: str = "Cancel") -> None:
        self.add_response("cancel", label)
        self.set_close_response("cancel")

    @property
    def result(self):
        return self._result

    @result.setter
    def result(self, v) -> None:
        self._result = v

    def focus_after_present(self, widget: Gtk.Widget) -> None:
        """Shift focus to `widget` after presentation. Adw.AlertDialog's
        default-response button steals focus synchronously; we use idle_add
        so our focus grab wins the race."""
        GLib.idle_add(widget.grab_focus)

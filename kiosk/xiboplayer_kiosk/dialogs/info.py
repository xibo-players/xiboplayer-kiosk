"""Info + error helpers — branded replacements for zenity --info/--error."""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw  # noqa: E402

from .base import BrandedAlertDialog


class InfoDialog(BrandedAlertDialog):
    def __init__(self, subtitle: str, body: str, ok_label: str = "OK"):
        super().__init__(heading_subtitle=subtitle, body=body)
        self.add_suggested("ok", ok_label)
        self.set_close_response("ok")


class ErrorDialog(BrandedAlertDialog):
    def __init__(self, subtitle: str, body: str, ok_label: str = "OK"):
        super().__init__(heading_subtitle=subtitle, body=body)
        self.add_response("ok", ok_label)
        self.set_response_appearance("ok", Adw.ResponseAppearance.DEFAULT)
        self.set_default_response("ok")
        self.set_close_response("ok")

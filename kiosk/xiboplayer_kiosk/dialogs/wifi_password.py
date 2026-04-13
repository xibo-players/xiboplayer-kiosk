"""Wi-Fi password dialog — single password entry with reveal eye."""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gtk  # noqa: E402

from .base import BrandedAlertDialog


class WifiPasswordDialog(BrandedAlertDialog):
    def __init__(self, ssid: str):
        super().__init__(
            heading_subtitle="Wi-Fi password",
            body=f"Enter password for {ssid}",
        )
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_size_request(440, -1)
        group = Adw.PreferencesGroup()
        self.pw = Adw.PasswordEntryRow(title="Password")
        group.add(self.pw)
        box.append(group)
        self.set_extra_child(box)

        self.add_cancel()
        self.add_suggested("connect", "Connect")

        self.focus_after_present(self.pw)

    @property
    def password(self) -> str:
        return self.pw.get_text()

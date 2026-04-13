"""CmsForm — URL / Key / Display-name entry form."""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gtk  # noqa: E402

from .base import BrandedAlertDialog


class CmsForm(BrandedAlertDialog):
    def __init__(self, *, cms_url: str = "", cms_key: str = "", display_name: str = ""):
        super().__init__(
            heading_subtitle="CMS",
            body="Enter your Xibo CMS server details",
        )

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_size_request(480, -1)

        group = Adw.PreferencesGroup()

        self.url_row = Adw.EntryRow(title="CMS Server URL")
        self.url_row.set_text(cms_url)
        group.add(self.url_row)

        self.key_row = Adw.PasswordEntryRow(title="CMS Key")
        self.key_row.set_text(cms_key)
        group.add(self.key_row)

        self.name_row = Adw.EntryRow(title="Display Name")
        self.name_row.set_text(display_name)
        group.add(self.name_row)

        box.append(group)
        self.set_extra_child(box)

        self.add_cancel()
        self.add_suggested("save", "Save")

        # Focus first empty row; else Save button
        for row in (self.url_row, self.key_row, self.name_row):
            if not row.get_text():
                self.focus_after_present(row)
                return

    def values(self) -> tuple[str, str, str]:
        url = self.url_row.get_text().strip()
        if url and not url.endswith("/"):
            url += "/"
        return url, self.key_row.get_text().strip(), self.name_row.get_text().strip()

"""Embeddable panel widgets for the right-pane content of KioskWindow.

These mirror the dialogs/* AlertDialog classes but as plain Gtk.Widgets
(no dialog wrapper, no OK/Cancel buttons in chrome). Each panel
fires a callback with the result; the controller (KioskApp) decides
what happens next.

Visual style mirrors the AlertDialog version: Adw.PreferencesGroup with
Adw.EntryRow / Adw.PasswordEntryRow / Adw.ActionRow rows. Action area at
the bottom of each panel for primary action (Apply / Connect / Save).
"""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("Gdk", "4.0")
from gi.repository import Adw, Gdk, GObject, Gio, Gtk, Pango  # noqa: E402


# ───────────────────────────────────────────────────────────────────────
# Picker panel — search entry + filtered ColumnView, embeddable.
# ───────────────────────────────────────────────────────────────────────


class _Row(GObject.Object):
    __gtype_name__ = "XiboPanelRow"

    def __init__(self, values: tuple[str, ...]):
        super().__init__()
        self.values = values
        self._haystack = "\t".join(values).lower()


class PickerPanel(Gtk.Box):
    """Search-as-you-type panel for Language / Timezone / Keyboard / Wi-Fi.

    Parameters
    ----------
    rows : list[tuple[str, ...]]
        Each tuple is a row's column values.
    columns : list[str]
        Column titles. ``len(columns) == arity of each row tuple``.
    print_column : int
        1-indexed column whose value is returned in the ``apply`` callback.
    min_chars : int
        Filter engages once the search entry has this many characters.
    placeholder : str
        EntryRow title (acts as floating placeholder).
    apply_label : str
        Primary button label ("Apply" / "Connect" / etc.).
    on_apply : Callable[[str], None]
        Invoked with the selected value when the primary button fires.
    """

    __gsignals__ = {
        "applied": (GObject.SignalFlags.RUN_FIRST, None, (str,)),
    }

    def __init__(
        self,
        *,
        rows: list[tuple[str, ...]],
        columns: list[str],
        print_column: int = 1,
        min_chars: int = 2,
        placeholder: str = "Type to filter",
        apply_label: str = "Apply",
        on_apply=None,
    ):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.set_margin_top(12)
        self.set_margin_bottom(12)
        self.set_margin_start(18)
        self.set_margin_end(18)
        self._ncols = len(columns)
        self._print_idx = max(0, min(print_column - 1, self._ncols - 1))
        self._min_chars = min_chars
        self._on_apply = on_apply

        # Search entry styled like Adw.EntryRow inside a single PreferencesGroup
        entry_group = Adw.PreferencesGroup()
        self.entry = Adw.EntryRow()
        self.entry.set_title(placeholder)
        entry_group.add(self.entry)
        self.append(entry_group)

        # Data + filter
        self._store = Gio.ListStore.new(_Row)
        for r in rows:
            padded = tuple(list(r) + [""] * (self._ncols - len(r)))
            self._store.append(_Row(padded))

        self._filter = Gtk.CustomFilter.new()
        self._filter.set_filter_func(self._filter_fn)
        self._filter_model = Gtk.FilterListModel.new(self._store, self._filter)

        self._selection = Gtk.SingleSelection.new(self._filter_model)
        self._selection.set_autoselect(False)
        self._selection.set_can_unselect(False)

        self._cv = Gtk.ColumnView.new(self._selection)
        self._cv.set_show_column_separators(False)
        self._cv.set_show_row_separators(False)
        for i, name in enumerate(columns):
            factory = Gtk.SignalListItemFactory.new()
            factory.connect("setup", self._on_setup)
            factory.connect("bind", self._on_bind, i)
            col = Gtk.ColumnViewColumn.new(name or "", factory)
            col.set_expand(i == 0 or self._ncols == 1)
            col.set_resizable(True)
            self._cv.append_column(col)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_hexpand(True)
        scrolled.set_vexpand(True)
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_child(self._cv)
        scrolled.set_has_frame(True)
        scrolled.add_css_class("card")
        self.append(scrolled)

        # Bottom action row
        action_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        action_row.set_halign(Gtk.Align.END)
        self._apply_btn = Gtk.Button(label=apply_label)
        self._apply_btn.add_css_class("suggested-action")
        self._apply_btn.connect("clicked", lambda _b: self._do_apply())
        action_row.append(self._apply_btn)
        self.append(action_row)

        # Wiring
        self.entry.connect("changed", self._on_changed)
        self.entry.connect("entry-activated", lambda _e: self._do_apply())
        self._cv.connect("activate", lambda *_a: self._do_apply())

    def _filter_fn(self, item: _Row) -> bool:
        q = self.entry.get_text().lower()
        if len(q) < self._min_chars:
            return self._min_chars == 0
        return q in item._haystack

    def _on_setup(self, _f, item):
        lbl = Gtk.Label(xalign=0)
        lbl.set_ellipsize(Pango.EllipsizeMode.END)
        lbl.set_margin_start(6)
        lbl.set_margin_end(6)
        lbl.set_margin_top(4)
        lbl.set_margin_bottom(4)
        item.set_child(lbl)

    def _on_bind(self, _f, item, idx: int):
        item.get_child().set_text(item.get_item().values[idx] if idx < len(item.get_item().values) else "")

    def _on_changed(self, _e):
        self._filter.changed(Gtk.FilterChange.DIFFERENT)
        if self._filter_model.get_n_items() > 0:
            self._selection.set_selected(0)

    def _do_apply(self) -> None:
        idx = self._selection.get_selected()
        if idx == Gtk.INVALID_LIST_POSITION:
            return
        item = self._filter_model.get_item(idx)
        if item is None:
            return
        value = item.values[self._print_idx]
        self.emit("applied", value)
        if callable(self._on_apply):
            self._on_apply(value)


# ───────────────────────────────────────────────────────────────────────
# CMS form panel.
# ───────────────────────────────────────────────────────────────────────


class CmsFormPanel(Gtk.Box):
    """Three-row form for CMS URL / key / display name. Embeddable."""

    __gsignals__ = {
        "applied": (GObject.SignalFlags.RUN_FIRST, None, (str, str, str)),
    }

    def __init__(self, *, cms_url: str = "", cms_key: str = "", display_name: str = "", on_apply=None):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.set_margin_top(12)
        self.set_margin_bottom(12)
        self.set_margin_start(18)
        self.set_margin_end(18)
        self._on_apply = on_apply

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
        self.append(group)

        action_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        action_row.set_halign(Gtk.Align.END)
        save_btn = Gtk.Button(label="Save")
        save_btn.add_css_class("suggested-action")
        save_btn.connect("clicked", lambda _b: self._do_apply())
        action_row.append(save_btn)
        self.append(action_row)

    def _do_apply(self) -> None:
        url = self.url_row.get_text().strip()
        if url and not url.endswith("/"):
            url += "/"
        key = self.key_row.get_text().strip()
        name = self.name_row.get_text().strip()
        self.emit("applied", url, key, name)
        if callable(self._on_apply):
            self._on_apply(url, key, name)


# ───────────────────────────────────────────────────────────────────────
# Player picker panel — radio rows.
# ───────────────────────────────────────────────────────────────────────


class PlayerPanel(Gtk.Box):
    """Radio-row picker: Chromium / Electron."""

    __gsignals__ = {
        "applied": (GObject.SignalFlags.RUN_FIRST, None, (str,)),
    }

    def __init__(self, *, current: str = "Chromium", on_apply=None):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.set_margin_top(12)
        self.set_margin_bottom(12)
        self.set_margin_start(18)
        self.set_margin_end(18)
        self._on_apply = on_apply
        self._checks: dict[str, Gtk.CheckButton] = {}

        group = Adw.PreferencesGroup()
        leader: Gtk.CheckButton | None = None
        for label, subtitle in (
            ("Chromium", "Chromium kiosk (default, lighter)"),
            ("Electron", "Electron wrapper (heavier, more compatible)"),
        ):
            row = Adw.ActionRow(title=label, subtitle=subtitle)
            check = Gtk.CheckButton()
            if leader is None:
                leader = check
            else:
                check.set_group(leader)
            check.set_active(label == current)
            row.add_prefix(check)
            row.set_activatable_widget(check)
            group.add(row)
            self._checks[label] = check
        self.append(group)

        action_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        action_row.set_halign(Gtk.Align.END)
        switch_btn = Gtk.Button(label="Switch")
        switch_btn.add_css_class("suggested-action")
        switch_btn.connect("clicked", lambda _b: self._do_apply())
        action_row.append(switch_btn)
        self.append(action_row)

    def _do_apply(self) -> None:
        for name, chk in self._checks.items():
            if chk.get_active():
                self.emit("applied", name)
                if callable(self._on_apply):
                    self._on_apply(name)
                return


# ───────────────────────────────────────────────────────────────────────
# Settings panel — actions list (Open terminal / GNOME Settings / Debug).
# ───────────────────────────────────────────────────────────────────────


class SettingsPanel(Gtk.Box):
    """Sub-actions list: terminal / GNOME settings / debug bundle."""

    __gsignals__ = {
        "picked": (GObject.SignalFlags.RUN_FIRST, None, (str,)),
    }

    def __init__(self, *, on_pick=None):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.set_margin_top(12)
        self.set_margin_bottom(12)
        self.set_margin_start(18)
        self.set_margin_end(18)
        self._on_pick = on_pick

        group = Adw.PreferencesGroup()
        for action_id, title, subtitle in (
            ("terminal", "Open terminal", "ptyxis (Ctrl+S also works)"),
            ("gnome",    "GNOME Settings", "Advanced system tweaks"),
            ("debug",    "Collect debug bundle", "~/Downloads/xibo-debug-*.tar.zst"),
        ):
            row = Adw.ActionRow(title=title, subtitle=subtitle)
            row.set_activatable(True)
            row._action_id = action_id  # type: ignore[attr-defined]
            row.connect("activated", self._on_row_activated)
            row.add_suffix(Gtk.Image.new_from_icon_name("go-next-symbolic"))
            group.add(row)
        self.append(group)

    def _on_row_activated(self, row) -> None:
        action = row._action_id  # type: ignore[attr-defined]
        self.emit("picked", action)
        if callable(self._on_pick):
            self._on_pick(action)

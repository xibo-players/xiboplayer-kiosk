"""Picker — live-filter Gtk.ColumnView. Used for Language / Timezone /
Keyboard / Wi-Fi / (Player uses a simpler radio-row variant)."""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("Gdk", "4.0")
from gi.repository import Adw, Gdk, Gio, GLib, GObject, Gtk, Pango  # noqa: E402

from .base import BrandedAlertDialog


class Row(GObject.Object):
    """GObject wrapper so Gtk.FilterListModel accepts the items."""

    __gtype_name__ = "XiboPickerRow"

    def __init__(self, values: tuple[str, ...]):
        super().__init__()
        self.values = values
        self._haystack = "\t".join(values).lower()


_HEADER_HIDE_CSS = b"""
columnview.hide-columnview-header > header {
    opacity: 0;
    min-height: 0;
    padding: 0;
}
columnview.hide-columnview-header > header > * {
    min-height: 0;
    padding: 0;
}
"""
_css_provider_installed = False


def _install_css_once() -> None:
    global _css_provider_installed
    if _css_provider_installed:
        return
    p = Gtk.CssProvider()
    p.load_from_data(_HEADER_HIDE_CSS)
    Gtk.StyleContext.add_provider_for_display(
        Gdk.Display.get_default(),
        p,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
    )
    _css_provider_installed = True


class Picker(BrandedAlertDialog):
    """Filter-as-you-type picker.

    Parameters
    ----------
    subtitle : str            — heading subtitle under the brand
    body : str                — prompt text ("Type a locale code...")
    rows : list[tuple[str,...]] — source data
    columns : list[str]       — column headers (len = row tuple arity)
    print_column : int        — 1-indexed column to return on confirm
    min_chars : int           — filter engages at N chars (0 = show all)
    hide_header : bool        — hide column-header row via CSS
    placeholder : str         — search entry placeholder
    """

    def __init__(
        self,
        *,
        subtitle: str,
        body: str,
        rows: list[tuple[str, ...]],
        columns: list[str],
        print_column: int = 1,
        min_chars: int = 2,
        hide_header: bool = False,
        placeholder: str = "",
    ):
        # Body becomes the SearchEntry placeholder — folding the prompt
        # into the entry kills the "disconnected prompt above entry"
        # feel and lets the dialog shrink vertically.
        combined_placeholder = placeholder or body or (
            f"Type at least {min_chars} characters to filter" if min_chars > 0 else "Type to filter"
        )
        super().__init__(heading_subtitle=subtitle, body="")
        self._rows = rows
        self._ncols = len(columns)
        self._print_idx = max(0, min(print_column - 1, self._ncols - 1))
        self._min_chars = min_chars

        # Compact size — list has only as much room as it needs; the
        # ScrolledWindow handles overflow. ~10 visible rows.
        extra = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        extra.set_size_request(460, 300)

        # Adw.EntryRow gives the same visual style as the CmsForm fields
        # (libadwaita preferences row: floating title, padded, large hit
        # area, matching font/size). Wrap in a single-row PreferencesGroup
        # so it gets the rounded boxed-list border.
        entry_group = Adw.PreferencesGroup()
        self.entry = Adw.EntryRow()
        self.entry.set_title(combined_placeholder)
        entry_group.add(self.entry)
        extra.append(entry_group)

        # Data model
        self._store = Gio.ListStore.new(Row)
        for r in rows:
            padded = tuple(list(r) + [""] * (self._ncols - len(r)))
            self._store.append(Row(padded))

        self._filter = Gtk.CustomFilter.new()
        self._filter.set_filter_func(self._filter_fn)
        self._filter_model = Gtk.FilterListModel.new(self._store, self._filter)

        self._selection = Gtk.SingleSelection.new(self._filter_model)
        self._selection.set_autoselect(False)
        self._selection.set_can_unselect(False)

        self._cv = Gtk.ColumnView.new(self._selection)
        self._cv.set_show_column_separators(False)
        self._cv.set_show_row_separators(False)
        self._cv.set_reorderable(False)

        for i, name in enumerate(columns):
            factory = Gtk.SignalListItemFactory.new()
            factory.connect("setup", self._on_setup)
            factory.connect("bind", self._on_bind, i)
            col = Gtk.ColumnViewColumn.new(name or "", factory)
            col.set_expand(i == 0 or self._ncols == 1)
            col.set_resizable(True)
            self._cv.append_column(col)

        if hide_header or self._ncols == 1:
            _install_css_once()
            self._cv.add_css_class("hide-columnview-header")

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_hexpand(True)
        scrolled.set_vexpand(True)
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_child(self._cv)
        scrolled.set_has_frame(True)
        # Match the EntryRow's rounded-border look so entry + list read
        # as a vertically-stacked pair of cards (same idiom as
        # PreferencesGroup → PreferencesGroup in GNOME Settings).
        scrolled.add_css_class("card")
        extra.append(scrolled)

        self.set_extra_child(extra)

        self.add_cancel()
        self.add_suggested("ok", "OK")

        # Wire filter-as-you-type. Adw.EntryRow exposes Gtk.Editable's
        # standard "changed" signal (not GtkSearchEntry's "search-changed").
        # "entry-activated" is the libadwaita-specific Enter-press signal.
        self.entry.connect("changed", self._on_search_changed)
        self.entry.connect("entry-activated", self._on_entry_activate)
        self._cv.connect("activate", lambda *a: self.emit("response", "ok"))

        # Key controller — must be on the ENTRY (the focused widget),
        # not the dialog. Adw.EntryRow's default key handler eats
        # Escape to clear text; a dialog-level controller in any
        # propagation phase doesn't run before the entry's own bound
        # action, because Adw.EntryRow installs its Escape handler at
        # the widget action level (not as an event controller). The
        # only reliable way to override is to attach a CAPTURE-phase
        # controller directly on the entry widget itself, which sees
        # the keystroke before the entry's action class processes it.
        ec_entry = Gtk.EventControllerKey.new()
        ec_entry.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        ec_entry.connect("key-pressed", self._on_key)
        self.entry.add_controller(ec_entry)
        # Also at the dialog level for when focus moves to the list/buttons.
        ec_dialog = Gtk.EventControllerKey.new()
        ec_dialog.connect("key-pressed", self._on_key)
        self.add_controller(ec_dialog)

        self.focus_after_present(self.entry)

    def _filter_fn(self, item: Row) -> bool:
        q = self.entry.get_text().lower()
        if len(q) < self._min_chars:
            return self._min_chars == 0
        return q in item._haystack

    def _on_setup(self, _factory, item):
        lbl = Gtk.Label(xalign=0)
        lbl.set_ellipsize(Pango.EllipsizeMode.END)
        lbl.set_margin_start(6)
        lbl.set_margin_end(6)
        lbl.set_margin_top(4)
        lbl.set_margin_bottom(4)
        item.set_child(lbl)

    def _on_bind(self, _factory, item, col_idx: int):
        lbl = item.get_child()
        row = item.get_item()
        lbl.set_text(row.values[col_idx] if col_idx < len(row.values) else "")

    def _auto_select_first(self) -> None:
        if self._filter_model.get_n_items() > 0:
            self._selection.set_selected(0)

    def _on_search_changed(self, _e) -> None:
        self._filter.changed(Gtk.FilterChange.DIFFERENT)
        self._auto_select_first()

    def _on_entry_activate(self, _e) -> None:
        if self._selection.get_selected() == Gtk.INVALID_LIST_POSITION:
            self._auto_select_first()
        self.emit("response", "ok")

    def _on_key(self, _ctl, keyval, _kc, _mods) -> bool:
        if keyval == Gdk.KEY_Escape:
            self.emit("response", "cancel")
            return True
        if keyval == Gdk.KEY_Down and self.entry.has_focus():
            self._cv.grab_focus()
            self._auto_select_first()
            return True
        return False

    def selected_value(self) -> str | None:
        idx = self._selection.get_selected()
        if idx == Gtk.INVALID_LIST_POSITION:
            return None
        item = self._filter_model.get_item(idx)
        if item is None:
            return None
        return item.values[self._print_idx]

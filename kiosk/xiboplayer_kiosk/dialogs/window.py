"""KioskWindow — single window with sidebar + content (Adw.NavigationSplitView).

Replaces the dialog-per-screen flow with a GNOME Settings / Control Center
style layout: persistent sidebar on the left listing categories (Language,
Keyboard, Wi-Fi, Timezone, Player, CMS), with the selected category's UI
rendered inline in the content pane on the right. No new windows for
sub-screens — the user navigates by clicking sidebar rows, no back-stack
popups, no dialog churn.

Sub-screens (Picker, CmsForm, PlayerPicker) are reused as **embedded
widgets**, swapped into the content area's child slot. They keep the same
visual style — Adw.PreferencesGroup + Adw.EntryRow — but no AlertDialog
wrapper, no OK/Cancel chrome (sidebar handles navigation; each panel has
its own action area).
"""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("Gdk", "4.0")
from gi.repository import Adw, Gdk, Gtk  # noqa: E402

from .. import branding


_CATEGORIES = [
    ("language", "Language"),
    ("keyboard", "Keyboard"),
    ("wifi",     "Wi-Fi"),
    ("timezone", "Timezone"),
    ("player",   "Player"),
    ("cms",      "CMS"),
    ("settings", "Settings"),
]


class KioskWindow(Adw.ApplicationWindow):
    """Top-level window. Holds the split view + handles category selection.

    Parameters
    ----------
    app
        The Adw.Application this window belongs to. Used for lifecycle
        (app.release() when the user clicks "Start player" or closes).
    state
        Shared KioskState used to render sidebar status subtitles AND
        passed to whatever panel is currently shown.
    on_pick
        Callable taking ``(category_id: str)`` invoked when the user
        clicks a sidebar row. Implementor swaps the content panel.
    on_start
        Callable invoked when the user clicks the "Start player" button
        in the header. Caller normally calls app.release() here.
    version
        Version string for the sidebar title subtitle.
    """

    def __init__(self, app, state, *, on_pick=None, on_start=None, version: str = ""):
        super().__init__(application=app)
        self.state = state
        self.on_pick = on_pick
        self.on_start = on_start
        self.set_title("xiboplayer")
        self.set_default_size(820, 520)

        self._split = Adw.NavigationSplitView()
        self._split.set_min_sidebar_width(240)
        self._split.set_max_sidebar_width(280)
        self._split.set_sidebar_width_fraction(0.35)

        self._sidebar_page = self._build_sidebar(version)
        self._content_page = self._build_content_placeholder()
        self._split.set_sidebar(self._sidebar_page)
        self._split.set_content(self._content_page)

        self.set_content(self._split)

    # ── sidebar ─────────────────────────────────────────────────────────

    def _build_sidebar(self, version: str) -> Adw.NavigationPage:
        """One Adw.NavigationPage hosting a HeaderBar + ListBox of categories."""
        toolbar = Adw.ToolbarView()

        header = Adw.HeaderBar()
        title_widget = Gtk.Label()
        title_widget.set_markup(branding.BRAND_HEADING_MARKUP)
        title_widget.set_use_markup(True)
        header.set_title_widget(title_widget)
        toolbar.add_top_bar(header)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_hexpand(True)
        scrolled.set_vexpand(True)
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        self._listbox = Gtk.ListBox()
        self._listbox.add_css_class("navigation-sidebar")
        self._listbox.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._listbox.connect("row-activated", self._on_sidebar_row_activated)
        self._sidebar_rows: dict[str, Adw.ActionRow] = {}
        for category_id, title in _CATEGORIES:
            row = Adw.ActionRow(title=title)
            row.set_subtitle(self._sidebar_subtitle(category_id))
            row.set_activatable(True)
            row._category_id = category_id  # type: ignore[attr-defined]
            self._listbox.append(row)
            self._sidebar_rows[category_id] = row
        scrolled.set_child(self._listbox)

        # "Start player" goes at the BOTTOM of the sidebar — always
        # reachable, can't be lost in a sub-page.
        bottom_bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        bottom_bar.set_margin_top(6)
        bottom_bar.set_margin_bottom(8)
        bottom_bar.set_margin_start(8)
        bottom_bar.set_margin_end(8)
        start_btn = Gtk.Button(label="Start player")
        start_btn.add_css_class("suggested-action")
        start_btn.set_hexpand(True)
        start_btn.connect("clicked", lambda _b: self.on_start() if callable(self.on_start) else None)
        bottom_bar.append(start_btn)

        sidebar_root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        sidebar_root.append(scrolled)
        sidebar_root.append(bottom_bar)
        toolbar.set_content(sidebar_root)

        page = Adw.NavigationPage()
        page.set_title("xiboplayer")
        page.set_child(toolbar)
        return page

    def _build_content_placeholder(self) -> Adw.NavigationPage:
        """Initial right-pane content. Replaced on the first sidebar click.

        Uses a tight custom layout instead of Adw.StatusPage because the
        latter vertically centers content with large padding — that
        looked like "wasted middle space". This version pins the logo +
        text near the top with compact spacing.
        """
        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(Adw.HeaderBar())

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_top(36)
        box.set_margin_bottom(24)
        box.set_margin_start(24)
        box.set_margin_end(24)
        box.set_halign(Gtk.Align.CENTER)
        box.set_valign(Gtk.Align.START)

        if branding.LOGO_PATH.exists():
            try:
                pic = Gtk.Picture.new_for_filename(str(branding.LOGO_PATH))
                pic.set_size_request(160, 160)
                pic.set_can_shrink(True)
                pic.set_content_fit(Gtk.ContentFit.CONTAIN)
                box.append(pic)
            except Exception:  # noqa: BLE001
                pass

        title = Gtk.Label()
        title.set_markup('<span size="x-large" weight="bold">xiboplayer first boot</span>')
        title.set_xalign(0.5)
        box.append(title)

        desc = Gtk.Label(
            label="Select a category from the left to configure it.\n"
                  "Press Start player when ready.",
        )
        desc.set_justify(Gtk.Justification.CENTER)
        desc.set_xalign(0.5)
        desc.add_css_class("dim-label")
        box.append(desc)

        toolbar.set_content(box)
        page = Adw.NavigationPage()
        page.set_title("xiboplayer")
        page.set_child(toolbar)
        return page

    # ── public API for the controller ───────────────────────────────────

    def set_content_panel(self, title: str, widget: Gtk.Widget) -> None:
        """Replace the right-pane content with `widget` under `title`."""
        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        header.set_title_widget(Adw.WindowTitle.new(title, ""))
        toolbar.add_top_bar(header)
        toolbar.set_content(widget)
        page = Adw.NavigationPage()
        page.set_title(title)
        page.set_child(toolbar)
        self._split.set_content(page)
        self._content_page = page

    def refresh_sidebar(self) -> None:
        """Re-render every sidebar row's status subtitle from KioskState."""
        self.state.refresh_all()
        for category_id, row in self._sidebar_rows.items():
            row.set_subtitle(self._sidebar_subtitle(category_id))

    # ── private helpers ─────────────────────────────────────────────────

    def _sidebar_subtitle(self, category_id: str) -> str:
        s = self.state
        return {
            "language": s.locale or "(unknown)",
            "keyboard": s.keyboard_layout,
            "wifi":     s.wifi_ssid,
            "timezone": s.timezone,
            "player":   s.player,
            "cms":      s.cms_url,
            "settings": "Terminal · GNOME Settings · Debug",
        }.get(category_id, "")

    def _on_sidebar_row_activated(self, _box, row) -> None:
        if callable(self.on_pick):
            self.on_pick(row._category_id)  # type: ignore[attr-defined]

#!/usr/bin/env python3
"""
xibo-picker.py — live-filter picker built on Adw.AlertDialog.

We use Adw.AlertDialog (libadwaita 1.5+, non-deprecated replacement
for Adw.MessageDialog) so our dialog inherits zenity 4.2's exact look
for free — zenity itself is built on the same stack:

  - Rounded dark floating dialog (no OS title bar)
  - Bold centered heading + smaller body text
  - BIG wide response-area buttons (Cancel + OK equal-width at bottom)
  - Suggested-action blue fill on the default button

All we add on top is the xiboplayer-branded header (blue "xibo" +
white "player") and the filter entry + column view that zenity's
--list doesn't have.

Reads items from stdin (one per line, or TSV for multi-column) and
prints the selected row's --print-column to stdout. Exit code 0 on
pick, 1 on cancel.

Key flags (mirror zenity where possible):
    --title=TITLE            window title (shown by WM, usually hidden)
    --heading=TEXT           bold heading at top (Adw.AlertDialog heading)
    --brand-header=SUBTITLE  render branded xiboplayer + SUBTITLE as the
                             heading area (colored Pango markup). Takes
                             precedence over --heading.
    --text=TEXT              body subtitle (Pango markup ok)
    --column=NAME            repeatable; column headers (and count)
    --tsv                    stdin is TAB-separated
    --hide-header            hide column headers
    --hide-column=N          hide column N (1-indexed)
    --print-column=N         column to print on OK (1-indexed)
    --min-chars=N            filter engages at N chars (default 2)
    --width=N --height=N     dialog size (default 520x520)
    --window-icon=PATH       window icon file
    --ok-label=STR           OK button label (default "OK")
    --cancel-label=STR       Cancel button label (default "Cancel")
    --placeholder=TEXT       entry placeholder

Exit codes:
    0 — user picked a row (printed to stdout)
    1 — user cancelled / closed / pressed Escape
"""

import argparse
import sys
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Gdk, GLib, Gio, Adw, Pango, GObject


BRAND_XIBO_MARKUP = (
    '<span size="xx-large" font_weight="bold" foreground="#0097D8">xibo</span>'
    '<span size="xx-large" font_weight="bold" foreground="#FFFFFF">player</span>'
)


def parse_args():
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument('--title', default='xiboplayer')
    p.add_argument('--heading', default=None)
    p.add_argument('--brand-header', default=None)
    p.add_argument('--text', default='')
    # --welcome: info-splash mode (no list, no entry). Shows a horizontal
    # header with the xiboplayer logo on the left and the branded brand
    # + subtitle text on the right, followed by an OK button. Used by
    # the first-boot welcome screen.
    p.add_argument('--welcome', action='store_true')
    p.add_argument('--logo', default='')
    p.add_argument('--column', action='append', default=[])
    p.add_argument('--tsv', action='store_true')
    p.add_argument('--hide-header', action='store_true')
    p.add_argument('--hide-column', type=int, default=0)
    p.add_argument('--print-column', type=int, default=1)
    p.add_argument('--min-chars', type=int, default=2)
    p.add_argument('--width', type=int, default=520)
    p.add_argument('--height', type=int, default=520)
    p.add_argument('--window-icon', default='')
    p.add_argument('--ok-label', default='OK')
    p.add_argument('--cancel-label', default='Cancel')
    p.add_argument('--placeholder', default='')
    return p.parse_args()


class Row(GObject.Object):
    """GObject wrapper — Gtk.FilterListModel needs GObject items."""
    __gtype_name__ = 'XiboPickerRow'

    def __init__(self, values):
        super().__init__()
        self.values = tuple(values)
        self._haystack = '\t'.join(values).lower()


def build_column_view(columns, filter_model, hide_header, hide_column):
    selection = Gtk.SingleSelection.new(filter_model)
    selection.set_autoselect(False)
    selection.set_can_unselect(False)

    cv = Gtk.ColumnView.new(selection)
    cv.set_show_column_separators(False)
    cv.set_show_row_separators(False)
    cv.set_reorderable(False)

    ncols = len(columns)
    for i, name in enumerate(columns):
        if hide_column == i + 1:
            continue

        factory = Gtk.SignalListItemFactory.new()

        def on_setup(_factory, item):
            lbl = Gtk.Label(xalign=0)
            lbl.set_ellipsize(Pango.EllipsizeMode.END)
            lbl.set_margin_start(6)
            lbl.set_margin_end(6)
            lbl.set_margin_top(4)
            lbl.set_margin_bottom(4)
            item.set_child(lbl)
        factory.connect('setup', on_setup)

        def on_bind(_factory, item, idx=i):
            lbl = item.get_child()
            row = item.get_item()
            lbl.set_text(row.values[idx] if idx < len(row.values) else '')
        factory.connect('bind', on_bind)

        col = Gtk.ColumnViewColumn.new(name or '', factory)
        col.set_expand(i == 0 or ncols == 1)
        col.set_resizable(True)
        cv.append_column(col)

    if hide_header or ncols == 1:
        # Gtk.ColumnView has no public hide-header API in GTK 4.x.
        # The header row is a child widget with node-name "header" —
        # we hide it via a CSS provider scoped to this ColumnView
        # instance (style class "hide-columnview-header" gate).
        cv.add_css_class('hide-columnview-header')
        css = Gtk.CssProvider()
        css.load_from_data(
            b'columnview.hide-columnview-header > header { '
            b'  opacity: 0; min-height: 0; padding: 0; '
            b'} '
            b'columnview.hide-columnview-header > header > * { '
            b'  min-height: 0; padding: 0; '
            b'}'
        )
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

    return cv, selection


class PickerApp(Adw.Application):
    def __init__(self, args, rows):
        super().__init__(application_id='org.xiboplayer.Picker',
                         flags=Gio.ApplicationFlags.NON_UNIQUE)
        self._args = args
        self._rows = rows
        self._result = None

    def do_activate(self):
        args = self._args
        self.hold()

        if args.welcome:
            self._do_welcome()
        else:
            self._do_picker()

    def _do_welcome(self):
        """Welcome-splash mode: logo left, branded text right, OK button.

        Used by xibo-first-boot.sh's welcome_splash() at the top of the
        first-boot flow. No list, no entry — just an info dialog with
        a prominent logo.
        """
        args = self._args
        dlg = Adw.AlertDialog(heading='', body='')

        # Horizontal box: logo on the left, text on the right.
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        row.set_margin_top(4)
        row.set_margin_bottom(4)
        if args.logo:
            try:
                img = Gtk.Image.new_from_file(args.logo)
                img.set_pixel_size(96)
                img.set_valign(Gtk.Align.CENTER)
                row.append(img)
            except Exception:
                pass

        text_col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        text_col.set_hexpand(True)
        text_col.set_valign(Gtk.Align.CENTER)

        brand = Gtk.Label()
        brand.set_markup(BRAND_XIBO_MARKUP)
        brand.set_xalign(0)
        text_col.append(brand)

        if args.brand_header:
            sub = Gtk.Label()
            sub.set_markup('<span size="medium">' + args.brand_header + '</span>')
            sub.set_xalign(0)
            sub.set_wrap(True)
            text_col.append(sub)

        row.append(text_col)

        wrapper = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        wrapper.set_size_request(max(args.width - 40, 420), -1)
        wrapper.append(row)

        if args.text:
            body = Gtk.Label()
            body.set_markup(args.text)
            body.set_xalign(0)
            body.set_wrap(True)
            body.set_margin_top(8)
            wrapper.append(body)

        dlg.set_extra_child(wrapper)

        dlg.add_response('ok', args.ok_label)
        dlg.set_response_appearance('ok', Adw.ResponseAppearance.SUGGESTED)
        dlg.set_default_response('ok')
        dlg.set_close_response('ok')

        def on_response(_dlg, _response_id):
            self._result = 'ok'  # any non-None → exit 0
            self.release()
        dlg.connect('response', on_response)
        dlg.connect('closed', lambda _d: self.release())

        dlg.present(None)

    def _do_picker(self):
        args = self._args
        columns = args.column or ['']
        ncols = len(columns)

        # Adw.AlertDialog (libadwaita 1.5+) — the non-deprecated
        # replacement for Adw.MessageDialog. Same libadwaita look:
        # rounded floating dark dialog, bold heading, big wide buttons.
        heading_text = args.heading if args.heading is not None else args.title
        dlg = Adw.AlertDialog(heading=heading_text or '', body='')
        if args.brand_header is not None:
            # Blue "xibo" + white "player". AlertDialog supports Pango
            # markup directly on `heading` via heading-use-markup.
            markup = BRAND_XIBO_MARKUP
            if args.brand_header:
                markup += '\n<span size="small">' + args.brand_header + '</span>'
            dlg.set_heading_use_markup(True)
            dlg.set_heading(markup)
            if args.text:
                dlg.set_body(args.text)
        elif args.text:
            dlg.set_body(args.text)

        # Extra child = entry + scrolled column view.
        extra = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        extra.set_size_request(max(args.width - 40, 360), max(args.height - 180, 280))

        entry = Gtk.SearchEntry()
        entry.set_placeholder_text(
            args.placeholder or f'Type at least {args.min_chars} characters to filter'
        )
        extra.append(entry)

        # Data model.
        gstore = Gio.ListStore.new(Row)
        for r in self._rows:
            padded = list(r) + [''] * (ncols - len(r))
            gstore.append(Row(padded[:ncols]))

        custom_filter = Gtk.CustomFilter.new()

        def filter_fn(item):
            q = entry.get_text().lower()
            if len(q) < args.min_chars:
                return False
            return q in item._haystack
        custom_filter.set_filter_func(filter_fn)
        filter_model = Gtk.FilterListModel.new(gstore, custom_filter)

        cv, selection = build_column_view(columns, filter_model, args.hide_header, args.hide_column)
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_hexpand(True)
        scrolled.set_vexpand(True)
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_child(cv)
        scrolled.set_has_frame(True)
        extra.append(scrolled)

        dlg.set_extra_child(extra)

        # Responses: Adw.AlertDialog renders them as full-width buttons
        # in the response-area with libadwaita's native big-button styling.
        dlg.add_response('cancel', args.cancel_label)
        dlg.add_response('ok', args.ok_label)
        dlg.set_response_appearance('ok', Adw.ResponseAppearance.SUGGESTED)
        dlg.set_default_response('ok')
        dlg.set_close_response('cancel')

        # Behavior ------------------------------------------------------

        def auto_select_first():
            if filter_model.get_n_items() > 0:
                selection.set_selected(0)

        def confirm():
            idx = selection.get_selected()
            if idx == Gtk.INVALID_LIST_POSITION:
                return
            item = filter_model.get_item(idx)
            if item is None:
                return
            col_idx = max(0, min(args.print_column - 1, ncols - 1))
            self._result = item.values[col_idx]
            dlg.response('ok')

        def on_search_changed(_e):
            custom_filter.changed(Gtk.FilterChange.DIFFERENT)
            auto_select_first()
        entry.connect('search-changed', on_search_changed)
        entry.connect('activate', lambda _: confirm())
        cv.connect('activate', lambda *_: confirm())

        def on_response(_dlg, response_id):
            if response_id == 'ok':
                confirm()
            # Release the hold so Adw.Application can quit cleanly.
            self.release()
        dlg.connect('response', on_response)
        dlg.connect('closed', lambda _d: self.release())

        key_ctl = Gtk.EventControllerKey.new()

        def on_key(_ctl, keyval, _kc, _mods):
            if keyval == Gdk.KEY_Escape:
                dlg.response('cancel')
                return True
            if keyval == Gdk.KEY_Down and entry.has_focus():
                cv.grab_focus()
                auto_select_first()
                return True
            return False
        key_ctl.connect('key-pressed', on_key)
        dlg.add_controller(key_ctl)

        # Present with parent=None — the dialog becomes its own top-
        # level window without needing a phantom parent window.
        dlg.present(None)
        # Grab focus AFTER present via idle_add, otherwise AdwAlertDialog's
        # default-response button (the blue "OK") steals focus away from
        # the entry and the operator has to click the entry before they
        # can type. idle_add runs on the next GLib main-loop iteration,
        # by which time the dialog's internal focus grab has completed.
        GLib.idle_add(entry.grab_focus)


def main():
    args = parse_args()
    columns = args.column or ['']
    ncols = len(columns)

    rows = []
    for line in sys.stdin:
        line = line.rstrip('\n\r')
        if not line:
            continue
        parts = line.split('\t') if args.tsv else [line]
        while len(parts) < ncols:
            parts.append('')
        rows.append(parts[:ncols])
    if not rows:
        print('xibo-picker: no input rows', file=sys.stderr)
        sys.exit(1)

    app = PickerApp(args, rows)
    app.run([])
    if app._result is not None:
        print(app._result)
        sys.exit(0)
    sys.exit(1)


if __name__ == '__main__':
    main()

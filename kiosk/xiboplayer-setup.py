#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Pau Aliagas <linuxnow@gmail.com>
"""
Xibo Player Setup — follows gnome-initial-setup style exactly.

Uses AdwStatusPage + AdwPreferencesGroup — same widget pattern as
gnome-initial-setup language/timezone/account pages.
"""

import locale
import subprocess
import hashlib
import json
import os
import socket
import time

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw, GLib

XIBO_DATA_DIR = os.path.expanduser('~/.local/share/xibo')

# Common locales shown at the top of the language list.
# Full list is loaded from localectl and searchable.
COMMON_LOCALES = [
    ('English (US)', 'en_US.UTF-8'),
    ('English (UK)', 'en_GB.UTF-8'),
    ('Español (España)', 'es_ES.UTF-8'),
    ('Català', 'ca_ES.UTF-8'),
    ('Français', 'fr_FR.UTF-8'),
    ('Deutsch', 'de_DE.UTF-8'),
    ('Italiano', 'it_IT.UTF-8'),
    ('Português (Brasil)', 'pt_BR.UTF-8'),
    ('Português (Portugal)', 'pt_PT.UTF-8'),
    ('Nederlands', 'nl_NL.UTF-8'),
    ('Polski', 'pl_PL.UTF-8'),
    ('日本語', 'ja_JP.UTF-8'),
    ('中文 (简体)', 'zh_CN.UTF-8'),
    ('中文 (繁體)', 'zh_TW.UTF-8'),
    ('한국어', 'ko_KR.UTF-8'),
    ('العربية', 'ar_SA.UTF-8'),
    ('Türkçe', 'tr_TR.UTF-8'),
    ('Русский', 'ru_RU.UTF-8'),
]

PLAYERS = [
    ('Electron', '/usr/bin/xiboplayer-electron', 'xiboplayer-electron.service',
     'Web-based player with built-in setup UI (recommended)', True),
    ('Chromium', '/usr/bin/xiboplayer-chromium', 'xiboplayer-chromium.service',
     'Chromium kiosk player with built-in setup UI', False),
    ('Arexibo', '/usr/bin/arexibo', 'arexibo.service',
     'Native Rust player — requires CMS credentials', False),
]


# ── Pages ─────────────────────────────────────────────────────

def get_available_locales():
    """Get all available locales from localectl."""
    try:
        result = subprocess.run(
            ['localectl', 'list-locales'],
            capture_output=True, text=True, timeout=5,
        )
        return [l.strip() for l in result.stdout.splitlines() if l.strip()]
    except Exception:
        return [loc for _, loc in COMMON_LOCALES]


def get_current_locale():
    """Get the current system locale."""
    try:
        result = subprocess.run(
            ['localectl', 'status'],
            capture_output=True, text=True, timeout=5,
        )
        for line in result.stdout.splitlines():
            if 'LANG=' in line:
                return line.split('LANG=')[-1].strip()
    except Exception:
        pass
    return os.environ.get('LANG', 'en_US.UTF-8')


def make_language_page():
    """Language selection — searchable list like gnome-initial-setup language page."""
    page = Adw.StatusPage(
        title='Language',
        description='Select the language for this device.',
    )
    page.selected_locale = get_current_locale()

    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)

    # Search entry
    search = Gtk.SearchEntry(placeholder_text='Search languages…')
    search.set_margin_start(24)
    search.set_margin_end(24)
    box.append(search)

    # Scrollable list of locales
    scrolled = Gtk.ScrolledWindow(
        vexpand=True,
        min_content_height=300,
        margin_start=24,
        margin_end=24,
    )

    listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
    listbox.add_css_class('boxed-list')
    listbox.set_filter_func(lambda row: True)

    # Build locale → display name map from common locales
    locale_names = {loc: name for name, loc in COMMON_LOCALES}
    all_locales = get_available_locales()

    # Common locales first, then the rest
    common_codes = {loc for _, loc in COMMON_LOCALES}
    ordered = [loc for _, loc in COMMON_LOCALES if loc in all_locales]
    ordered += sorted(loc for loc in all_locales if loc not in common_codes)

    rows = []
    first_selected = None
    for loc in ordered:
        display = locale_names.get(loc, loc)
        row = Adw.ActionRow(title=display, subtitle=loc)
        row._locale = loc
        row._search_text = f'{display} {loc}'.lower()
        listbox.append(row)
        rows.append(row)

        if loc == page.selected_locale and first_selected is None:
            first_selected = row

    if first_selected:
        listbox.select_row(first_selected)

    def on_row_selected(lb, row):
        if row:
            page.selected_locale = row._locale

    listbox.connect('row-selected', on_row_selected)

    # Search filtering
    def on_search_changed(entry):
        text = entry.get_text().lower()
        listbox.set_filter_func(
            lambda row: not text or text in row._search_text
        )

    search.connect('search-changed', on_search_changed)

    scrolled.set_child(listbox)
    box.append(scrolled)

    page.set_child(box)
    return page


def make_display_page():
    """Display config — launches GNOME Settings display panel."""
    page = Adw.StatusPage(
        title='Display',
        description='Optionally configure resolution, orientation and layout.\nClick Done to skip.',
    )

    group = Adw.PreferencesGroup()

    # Button to open GNOME display settings
    row = Adw.ActionRow(
        title='Open Display Settings',
        subtitle='Arrange displays, set resolution, rotation and scaling',
    )
    row.set_activatable(True)

    icon = Gtk.Image.new_from_icon_name('go-next-symbolic')
    row.add_suffix(icon)

    def on_activated(_row):
        try:
            subprocess.Popen(
                ['gnome-control-center', 'display'],
                start_new_session=True,
            )
        except Exception:
            pass

    row.connect('activated', on_activated)
    group.add(row)

    # Hint for CLI users
    hint = Adw.ActionRow(
        title='Command line',
        subtitle='gdctl set --logical-monitor --monitor HDMI-1 --transform 90 --persistent',
    )
    hint.add_css_class('property')
    group.add(hint)

    page.set_child(group)
    return page


def make_player_page():
    """Player selection — same layout as gnome-initial-setup account page."""
    page = Adw.StatusPage(
        title='Player',
        description='Select the digital signage player for this device.',
    )
    page.selected = None
    page.service = None

    group = Adw.PreferencesGroup()
    first_check = None

    def on_toggled(check, name, service):
        if check.get_active():
            page.selected = name
            page.service = service

    for name, binary, service, desc, default in PLAYERS:
        if not os.path.isfile(binary):
            continue

        row = Adw.ActionRow(title=name, subtitle=desc)

        check = Gtk.CheckButton()
        if first_check is None:
            first_check = check
            if default:
                check.set_active(True)
                page.selected = name
                page.service = service
        else:
            check.set_group(first_check)

        check.connect('toggled', on_toggled, name, service)
        row.add_prefix(check)
        row.set_activatable_widget(check)
        group.add(row)

    if page.selected is None and first_check is not None:
        first_check.set_active(True)

    page.set_child(group)
    return page


def make_cms_page():
    """CMS configuration — same layout as gnome-initial-setup network page."""
    page = Adw.StatusPage(
        title='CMS Connection',
        description='Enter your Xibo CMS server details.',
    )

    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)

    group = Adw.PreferencesGroup()

    page.url_row = Adw.EntryRow(title='CMS Server URL')
    page.url_row.set_text('https://')
    group.add(page.url_row)

    page.key_row = Adw.EntryRow(title='CMS Key')
    group.add(page.key_row)

    page.name_row = Adw.EntryRow(title='Display Name')
    page.name_row.set_text(socket.gethostname())
    group.add(page.name_row)

    box.append(group)

    page.error_banner = Adw.Banner(revealed=False)
    box.append(page.error_banner)

    page.set_child(box)
    return page


def validate_cms(page):
    url = page.url_row.get_text().strip()
    key = page.key_row.get_text().strip()

    if not url or url == 'https://':
        page.error_banner.set_title('CMS Server URL is required.')
        page.error_banner.set_revealed(True)
        return False
    if not key:
        page.error_banner.set_title('CMS Key is required.')
        page.error_banner.set_revealed(True)
        return False

    page.error_banner.set_revealed(False)
    return True


def get_cms_config(page):
    url = page.url_row.get_text().strip()
    if not url.endswith('/'):
        url += '/'
    key = page.key_row.get_text().strip()
    name = page.name_row.get_text().strip() or socket.gethostname()

    machine_id = ''
    try:
        with open('/etc/machine-id') as f:
            machine_id = f.read().strip()
    except OSError:
        pass

    raw = f'{machine_id}{int(time.time())}{key}'
    display_id = hashlib.sha256(raw.encode()).hexdigest()[:12]

    return {
        'address': url,
        'key': key,
        'display_id': f'xibo-{display_id}',
        'display_name': name,
        'proxy': None,
    }


# ── Window ────────────────────────────────────────────────────

class SetupWindow(Adw.ApplicationWindow):
    """Matches gnome-initial-setup window: header bar + content + nav buttons."""

    def __init__(self, app):
        super().__init__(
            application=app,
            default_width=600,
            default_height=500,
        )

        toolbar = Adw.ToolbarView()

        # Header bar
        header = Adw.HeaderBar()
        header.set_title_widget(Gtk.Label(label='Xibo Player Setup'))

        self.back_btn = Gtk.Button(label='Previous')
        self.back_btn.connect('clicked', self._on_back)
        self.back_btn.set_visible(False)
        header.pack_start(self.back_btn)

        self.next_btn = Gtk.Button(label='Next')
        self.next_btn.add_css_class('suggested-action')
        self.next_btn.connect('clicked', self._on_next)
        header.pack_end(self.next_btn)

        toolbar.add_top_bar(header)

        # Stack for pages (matches gnome-initial-setup's GtkStack with crossfade)
        self.stack = Gtk.Stack(
            transition_type=Gtk.StackTransitionType.CROSSFADE,
            transition_duration=300,
        )

        self.language_page = make_language_page()
        self.player_page = make_player_page()
        self.cms_page = make_cms_page()
        self.display_page = make_display_page()

        self.stack.add_named(self.language_page, 'language')
        self.stack.add_named(self.player_page, 'player')
        self.stack.add_named(self.cms_page, 'cms')
        self.stack.add_named(self.display_page, 'display')

        # Page order for navigation
        self.pages = ['language', 'player', 'cms', 'display']

        toolbar.set_content(self.stack)
        self.set_content(toolbar)
        self._update_buttons()

    def _current(self):
        return self.stack.get_visible_child_name()

    def _is_last(self):
        return self._current() == 'display'

    def _update_buttons(self):
        current = self._current()
        self.back_btn.set_visible(current != 'language')
        self.next_btn.set_label('Done' if self._is_last() else 'Next')

    def _go(self, name):
        self.stack.set_visible_child_name(name)
        self._update_buttons()

    def _on_back(self, _btn):
        current = self._current()
        idx = self.pages.index(current)
        if idx > 0:
            self._go(self.pages[idx - 1])

    def _on_next(self, _btn):
        current = self._current()

        if current == 'language':
            import threading
            threading.Thread(target=self._apply_locale, daemon=True).start()
            self._go('player')
            return

        if current == 'player':
            if self.player_page.selected == 'Arexibo':
                self._go('cms')
            else:
                self._go('display')
            return

        if current == 'cms':
            if not validate_cms(self.cms_page):
                return
            self._go('display')
            return

        if current == 'display':
            self._finish()

    def _apply_locale(self):
        loc = self.language_page.selected_locale
        try:
            subprocess.run(
                ['doas', 'localectl', 'set-locale', f'LANG={loc}'],
                capture_output=True, timeout=5,
            )
        except Exception:
            pass  # non-fatal on dev machines without doas

    def _finish(self):
        player = self.player_page.selected
        service = self.player_page.service

        binary_map = {
            'Electron': '/usr/bin/xiboplayer-electron',
            'Chromium': '/usr/bin/xiboplayer-chromium',
            'Arexibo': '/usr/bin/arexibo',
        }
        binary = binary_map.get(player)
        if binary:
            subprocess.run(
                ['doas', 'alternatives', '--set', 'xiboplayer', binary],
                capture_output=True,
            )

        if player == 'Arexibo':
            config = get_cms_config(self.cms_page)
            os.makedirs(XIBO_DATA_DIR, exist_ok=True)
            with open(os.path.join(XIBO_DATA_DIR, 'cms.json'), 'w') as f:
                json.dump(config, f, indent=4)

        if service:
            subprocess.run(
                ['systemctl', '--user', 'enable', '--now', service],
                capture_output=True,
            )

        os.makedirs(XIBO_DATA_DIR, exist_ok=True)
        with open(os.path.join(XIBO_DATA_DIR, 'setup-result.json'), 'w') as f:
            json.dump({'player': player, 'service': service}, f)

        self.close()


# ── Application ───────────────────────────────────────────────

class SetupApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id='org.xiboplayer.setup')

    def do_activate(self):
        win = SetupWindow(self)
        win.present()


if __name__ == '__main__':
    SetupApp().run([])

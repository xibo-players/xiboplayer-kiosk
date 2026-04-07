#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Pau Aliagas <linuxnow@gmail.com>
"""
xiboplayer first-boot setup wizard.

Runs as autostart in a normal GNOME session on first boot.
Page 1: recommends opening System Settings to configure WiFi, timezone,
language and display. Page 2 (Arexibo only): CMS connection fields.

On finish, activates kiosk mode via AccountsService and logs out.
Subsequent boots go directly to gnome-kiosk with the selected player.
"""

import hashlib
import json
import os
import socket
import subprocess
import time

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw, GLib

XIBO_DATA_DIR = os.path.expanduser('~/.local/share/xibo')
SETUP_RESULT = os.path.join(XIBO_DATA_DIR, 'setup-result.json')
KIOSK_DIR = '/usr/share/xiboplayer-kiosk'
AUTOSTART_FILE = os.path.expanduser('~/.config/autostart/xiboplayer-setup.desktop')


def read_setup_result():
    """Read the player selection written by kickstart."""
    try:
        with open(SETUP_RESULT) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return {'player': 'Chromium', 'service': 'xiboplayer-chromium.service'}


def get_wifi_status():
    """Get current WiFi SSID or connection status."""
    try:
        result = subprocess.run(
            ['nmcli', '-t', '-f', 'NAME,TYPE', 'connection', 'show', '--active'],
            capture_output=True, text=True, timeout=5,
        )
        for line in result.stdout.splitlines():
            parts = line.split(':')
            if len(parts) >= 2 and 'wireless' in parts[-1]:
                return parts[0]
        for line in result.stdout.splitlines():
            parts = line.split(':')
            if len(parts) >= 2 and 'ethernet' in parts[-1]:
                return f'{parts[0]} (wired)'
    except Exception:
        pass
    return 'Not connected'


def get_timezone():
    """Get current system timezone."""
    try:
        result = subprocess.run(
            ['timedatectl', 'show', '-p', 'Timezone', '--value'],
            capture_output=True, text=True, timeout=5,
        )
        return result.stdout.strip()
    except Exception:
        return 'Unknown'


def get_locale():
    """Get current system locale."""
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


def generate_display_id(key):
    """Generate a unique display ID from machine-id + timestamp + key."""
    machine_id = ''
    try:
        with open('/etc/machine-id') as f:
            machine_id = f.read().strip()
    except OSError:
        pass
    raw = f'{machine_id}{int(time.time())}{key}'
    return f'xibo-{hashlib.sha256(raw.encode()).hexdigest()[:12]}'


# ── Pages ─────────────────────────────────────────────────────


def make_system_page():
    """System configuration — recommend opening GNOME Settings."""
    page = Adw.StatusPage(
        title='System Setup',
        description=(
            'Before starting the kiosk, open System Settings to configure:\n'
            '• WiFi or network connection\n'
            '• Date, time and timezone\n'
            '• Language and region\n'
            '• Display resolution and rotation\n\n'
            'Click Done when ready — the system will reboot into kiosk mode.'
        ),
        icon_name='preferences-system-symbolic',
    )

    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)

    # Open Settings button
    settings_btn = Gtk.Button(label='Open System Settings')
    settings_btn.add_css_class('suggested-action')
    settings_btn.add_css_class('pill')
    settings_btn.set_halign(Gtk.Align.CENTER)
    settings_btn.connect('clicked', lambda _: subprocess.Popen(
        ['gnome-control-center'], start_new_session=True))
    box.append(settings_btn)

    # Current status summary
    status_group = Adw.PreferencesGroup(title='Current status')

    page.net_row = Adw.ActionRow(title='Network', subtitle=get_wifi_status())
    page.net_row.add_prefix(Gtk.Image.new_from_icon_name('network-wireless-symbolic'))
    status_group.add(page.net_row)

    page.tz_row = Adw.ActionRow(title='Timezone', subtitle=get_timezone())
    page.tz_row.add_prefix(Gtk.Image.new_from_icon_name('preferences-system-time-symbolic'))
    status_group.add(page.tz_row)

    page.lang_row = Adw.ActionRow(title='Language', subtitle=get_locale())
    page.lang_row.add_prefix(Gtk.Image.new_from_icon_name('preferences-desktop-locale-symbolic'))
    status_group.add(page.lang_row)

    box.append(status_group)

    page.set_child(box)
    return page


def make_cms_page():
    """CMS configuration for Arexibo — URL, key, display name."""
    page = Adw.StatusPage(
        title='CMS Connection',
        description=(
            'Enter your Xibo CMS server details.\n\n'
            'After clicking Done, this device will restart in kiosk mode\n'
            'and connect to the CMS. Log in to your CMS admin panel\n'
            'and authorise the display to start showing content.'
        ),
        icon_name='network-server-symbolic',
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
    """Validate CMS fields. Returns True if valid."""
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


# ── Window ────────────────────────────────────────────────────


class SetupWindow(Adw.ApplicationWindow):
    """First-boot setup wizard."""

    def __init__(self, app):
        super().__init__(
            application=app,
            default_width=350,
            default_height=550,
        )

        self.player_info = read_setup_result()
        self.needs_cms = self.player_info.get('player') == 'Arexibo'

        toolbar = Adw.ToolbarView()

        # Header bar
        header = Adw.HeaderBar()
        header.set_title_widget(Gtk.Label(label='xiboplayer setup'))

        self.back_btn = Gtk.Button(label='Previous')
        self.back_btn.connect('clicked', self._on_back)
        self.back_btn.set_visible(False)
        header.pack_start(self.back_btn)

        self.next_btn = Gtk.Button(label='Reboot into kiosk' if not self.needs_cms else 'Next')
        self.next_btn.add_css_class('suggested-action')
        self.next_btn.connect('clicked', self._on_next)
        header.pack_end(self.next_btn)

        toolbar.add_top_bar(header)

        # Pages
        self.stack = Gtk.Stack(
            transition_type=Gtk.StackTransitionType.CROSSFADE,
            transition_duration=300,
        )

        self.system_page = make_system_page()
        self.stack.add_named(self.system_page, 'system')

        if self.needs_cms:
            self.cms_page = make_cms_page()
            self.stack.add_named(self.cms_page, 'cms')

        toolbar.set_content(self.stack)
        self.set_content(toolbar)

    def _on_back(self, _btn):
        if self.stack.get_visible_child_name() == 'cms':
            self.stack.set_visible_child_name('system')
            self.back_btn.set_visible(False)
            self.next_btn.set_label('Next')

    def _on_next(self, _btn):
        current = self.stack.get_visible_child_name()

        if current == 'system':
            # Refresh status before moving on
            self.system_page.net_row.set_subtitle(get_wifi_status())
            self.system_page.tz_row.set_subtitle(get_timezone())
            self.system_page.lang_row.set_subtitle(get_locale())

            if self.needs_cms:
                self.stack.set_visible_child_name('cms')
                self.back_btn.set_visible(True)
                self.next_btn.set_label('Reboot into kiosk')
            else:
                self._finish()
            return

        if current == 'cms':
            if not validate_cms(self.cms_page):
                return
            self._write_cms_config()
            self._finish()

    def _write_cms_config(self):
        """Write Arexibo cms.json."""
        url = self.cms_page.url_row.get_text().strip()
        if not url.endswith('/'):
            url += '/'
        key = self.cms_page.key_row.get_text().strip()
        name = self.cms_page.name_row.get_text().strip() or socket.gethostname()

        config = {
            'address': url,
            'key': key,
            'display_id': generate_display_id(key),
            'display_name': name,
            'proxy': None,
        }

        os.makedirs(XIBO_DATA_DIR, exist_ok=True)
        with open(os.path.join(XIBO_DATA_DIR, 'cms.json'), 'w') as f:
            json.dump(config, f, indent=4)

    def _finish(self):
        """Activate kiosk mode and log out."""
        # Activate kiosk session for all future logins
        subprocess.run(
            ['doas', os.path.join(KIOSK_DIR, 'xibo-activate-kiosk.sh')],
            capture_output=True,
        )

        # Remove autostart so wizard doesn't run again
        try:
            os.remove(AUTOSTART_FILE)
        except OSError:
            pass

        # Mark gnome-initial-setup as done (belt and suspenders)
        os.makedirs(os.path.expanduser('~/.config'), exist_ok=True)
        open(os.path.expanduser('~/.config/gnome-initial-setup-done'), 'a').close()

        self.close()

        # Reboot — next boot will use kiosk session
        GLib.timeout_add(500, self._reboot)

    def _reboot(self):
        subprocess.run(['doas', 'reboot'], capture_output=True)
        return False


# ── Application ───────────────────────────────────────────────


class SetupApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id='org.xiboplayer.setup')

    def do_activate(self):
        win = SetupWindow(self)
        win.present()


if __name__ == '__main__':
    SetupApp().run([])

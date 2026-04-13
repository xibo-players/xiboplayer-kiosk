"""KioskApp — lifecycle owner for the first-boot + reconfigure wizards."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, GLib  # noqa: E402

from . import branding
from .doas_runner import DoasRunner
from .services import cms as cms_svc
from .services import keyboard as kb_svc
from .services import locale as locale_svc
from .services import notify
from .services import timezone as tz_svc
from .services import wifi as wifi_svc
from .state import KioskState
from .dialogs.cms_form import CmsForm
from .dialogs.info import ErrorDialog, InfoDialog
from .dialogs.main_menu import MainMenu
from .dialogs.picker import Picker
from .dialogs.player_picker import PlayerPicker
from .dialogs.reconfigure_menu import ReconfigureMenu
from .dialogs.settings_menu import SettingsMenu
from .dialogs.welcome import WelcomeSplash
from .dialogs.wifi_password import WifiPasswordDialog


def _apply_dark_theme() -> None:
    """Mirror zenity: honour GNOME color-scheme preference."""
    try:
        s = Gio.Settings.new("org.gnome.desktop.interface")
        cs = s.get_string("color-scheme") if "color-scheme" in s.list_keys() else ""
        prefer_dark = (cs == "prefer-dark")
        from gi.repository import Gtk
        Gtk.Settings.get_default().set_property(
            "gtk-application-prefer-dark-theme", prefer_dark,
        )
    except Exception:  # noqa: BLE001
        pass


class KioskApp(Adw.Application):
    def __init__(self, mode: str):
        super().__init__(
            application_id="org.xiboplayer.Kiosk",
            flags=Gio.ApplicationFlags.NON_UNIQUE,
        )
        self.mode = mode
        self.state: KioskState | None = None
        self.doas = DoasRunner()
        self._main_menu: MainMenu | None = None

    def do_activate(self):  # noqa: D401, N802
        self.hold()
        _apply_dark_theme()
        self.state = KioskState.load()
        if self.mode == "reconfigure":
            self._present_reconfigure()
        else:
            self._present_welcome()

    # ── Welcome → Main flow ─────────────────────────────────────────────

    def _present_welcome(self) -> None:
        version = self._version()
        build_date = self._build_date()
        dlg = WelcomeSplash(version=version, build_date=build_date)
        dlg.connect("response", self._on_welcome_response)
        dlg.present(None)

    def _on_welcome_response(self, _dlg, response_id: str) -> None:
        if response_id == "continue":
            self._present_main_menu()
        else:
            self._finish()

    def _present_main_menu(self) -> None:
        assert self.state is not None
        self._main_menu = MainMenu(
            self.state,
            version=self._version(),
            on_pick=self._on_main_pick,
            on_start=self._finish,
        )
        self._main_menu.connect("response", lambda _d, rid: self._finish() if rid == "start" else None)
        self._main_menu.present(None)

    def _on_main_pick(self, action: str) -> None:
        dispatch = {
            "language": self._pick_language,
            "keyboard": self._pick_keyboard,
            "wifi":     self._pick_wifi,
            "timezone": self._pick_timezone,
            "player":   self._pick_player,
            "cms":      self._form_cms,
            "settings": self._open_settings,
        }
        fn = dispatch.get(action)
        if fn:
            fn()

    # ── Pickers ─────────────────────────────────────────────────────────

    def _pick_language(self) -> None:
        rows = [(loc,) for loc in locale_svc.list_locales()]
        p = Picker(
            subtitle="Language",
            body="Type a locale code (e.g. en, en_GB, ca, es, fr, de):",
            rows=rows, columns=["Locale"], min_chars=2, hide_header=True,
        )
        p.connect("response", self._on_picker_response, "locale")
        p._picker_obj = p  # keep reference; GObject holds itself but be safe
        p.present(None)

    def _pick_keyboard(self) -> None:
        rows = [(x,) for x in kb_svc.list_layouts()]
        p = Picker(
            subtitle="Keyboard layout",
            body="Type a layout code or country (e.g. us, es, fr, gb):",
            rows=rows, columns=["Layout"], min_chars=2, hide_header=True,
        )
        p.connect("response", self._on_picker_response, "keyboard")
        p.present(None)

    def _pick_timezone(self) -> None:
        rows = [(z,) for z in tz_svc.list_timezones()]
        p = Picker(
            subtitle="Timezone",
            body="Type a city or region (e.g. Madrid, Europe, UTC):",
            rows=rows, columns=["IANA timezone"], min_chars=2, hide_header=True,
        )
        p.connect("response", self._on_picker_response, "timezone")
        p.present(None)

    def _pick_wifi(self) -> None:
        if not wifi_svc.has_wifi_hardware():
            dlg = InfoDialog(subtitle="Wi-Fi", body="No wireless hardware detected. Use a wired connection instead.")
            dlg.present(None)
            return
        wifi_svc.rescan()
        GLib.timeout_add_seconds(2, self._pick_wifi_after_scan)

    def _pick_wifi_after_scan(self) -> bool:
        nets = wifi_svc.list_networks()
        if not nets:
            dlg = InfoDialog(subtitle="Wi-Fi", body="No Wi-Fi networks found. Try again or use wired.")
            dlg.present(None)
            return False
        rows: list[tuple[str, ...]] = []
        for n in nets:
            name = ("* " if n.in_use else "") + n.ssid
            rows.append((name, f"{n.signal}%", n.security))
        p = Picker(
            subtitle="Wi-Fi",
            body="Select a network",
            rows=rows, columns=["SSID", "Signal", "Security"],
            min_chars=0, hide_header=False, print_column=1,
        )
        p.connect("response", self._on_wifi_picker_response)
        p.present(None)
        return False

    def _on_wifi_picker_response(self, dlg, response_id: str) -> None:
        if response_id != "ok":
            return
        ssid_with_marker = dlg.selected_value() or ""
        ssid = ssid_with_marker[2:] if ssid_with_marker.startswith("* ") else ssid_with_marker
        if not ssid:
            return
        # Look up security
        security = next((n.security for n in wifi_svc.list_networks() if n.ssid == ssid), "open")
        if security == "open":
            self._connect_wifi(ssid, "")
            return
        pw_dlg = WifiPasswordDialog(ssid)
        pw_dlg.connect("response", self._on_wifi_password_response, ssid)
        pw_dlg.present(None)

    def _on_wifi_password_response(self, dlg, response_id: str, ssid: str) -> None:
        if response_id != "connect":
            return
        self._connect_wifi(ssid, dlg.password)

    def _connect_wifi(self, ssid: str, psk: str) -> None:
        notify.send(f"Connecting to {ssid}...")
        ok, err = self.doas.run("xibo-set-wifi.sh", ssid, psk)
        if ok:
            notify.send(f"Wi-Fi connected to {ssid}")
        else:
            ErrorDialog(subtitle="Wi-Fi", body=f"Failed to connect to {ssid}.\n\n{err}").present(None)
        if self._main_menu:
            self._main_menu.refresh_rows()

    def _pick_player(self) -> None:
        assert self.state is not None
        p = PlayerPicker(current=self.state.player)
        p.connect("response", self._on_player_response)
        p.present(None)

    def _on_player_response(self, dlg, response_id: str) -> None:
        if response_id != "switch":
            return
        choice = dlg.selected_player()
        arg = "electron" if choice == "Electron" else "chromium"
        ok, err = self.doas.run("xibo-set-player.sh", arg)
        if ok:
            InfoDialog(
                subtitle="Player",
                body=f"Player switched to {choice}.\n\nReboot the kiosk (or log out and back in) to start the new player.",
            ).present(None)
        else:
            ErrorDialog(subtitle="Player", body=f"Failed to switch player.\n\n{err}").present(None)
        if self._main_menu:
            self._main_menu.refresh_rows()

    def _on_picker_response(self, dlg, response_id: str, kind: str) -> None:
        if response_id != "ok":
            return
        value = dlg.selected_value()
        if not value:
            return
        helper = {
            "locale": "xibo-set-locale.sh",
            "keyboard": "xibo-set-keyboard.sh",
            "timezone": "xibo-set-timezone.sh",
        }[kind]
        notify.send(f"Setting {kind} to {value}...")
        ok, err = self.doas.run(helper, value)
        if ok:
            notify.send(f"{kind.capitalize()}: {value}")
        else:
            ErrorDialog(subtitle=kind.capitalize(), body=f"Failed to set {kind} to {value}.\n\n{err}").present(None)
        if self._main_menu:
            self._main_menu.refresh_rows()

    # ── CMS form ────────────────────────────────────────────────────────

    def _form_cms(self) -> None:
        assert self.state is not None
        s = self.state
        dlg = CmsForm(
            cms_url=s.cms_url if s.cms_url != "(not configured)" else s.preseed_vars.get("xibo.cms_url", ""),
            cms_key=s.preseed_vars.get("xibo.cms_key", ""),
            display_name=s.preseed_vars.get("xibo.display_name", ""),
        )
        dlg.connect("response", self._on_cms_response)
        dlg.present(None)

    def _on_cms_response(self, dlg, response_id: str) -> None:
        if response_id != "save":
            return
        url, key, name = dlg.values()
        assert self.state is not None
        try:
            cms_svc.write_for_player(
                self.state.player, self.state.config_dir, self.state.data_dir, url, key, name,
            )
            notify.send(f"CMS configured: {url}")
        except Exception as e:  # noqa: BLE001
            ErrorDialog(subtitle="CMS", body=f"Failed to write CMS config:\n\n{e}").present(None)
        if self._main_menu:
            self._main_menu.refresh_rows()

    # ── Settings ────────────────────────────────────────────────────────

    def _open_settings(self) -> None:
        dlg = SettingsMenu(on_pick=self._on_settings_pick)
        dlg.present(None)

    def _on_settings_pick(self, action: str) -> None:
        if action == "terminal":
            for cand in ("ptyxis", "kgx", "gnome-terminal", "xterm"):
                try:
                    subprocess.Popen([cand], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    notify.send(f"Opened {cand}")
                    return
                except FileNotFoundError:
                    continue
            ErrorDialog(subtitle="Terminal", body="No terminal emulator found (tried ptyxis / kgx / gnome-terminal / xterm).").present(None)
        elif action == "gnome":
            try:
                subprocess.Popen(["gnome-control-center"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                notify.send("Opened GNOME Settings")
            except FileNotFoundError:
                ErrorDialog(subtitle="GNOME Settings", body="gnome-control-center is not installed.").present(None)
        elif action == "debug":
            for cand in (self.state.kiosk_dir / "xibo-debug-dump.sh", Path("/usr/bin/xibo-debug-dump")):
                if cand.exists():
                    subprocess.Popen([str(cand)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    return
            ErrorDialog(subtitle="Debug", body="xibo-debug-dump not found.").present(None)

    # ── Reconfigure flow (Ctrl+R entry) ─────────────────────────────────

    def _present_reconfigure(self) -> None:
        assert self.state is not None
        dlg = ReconfigureMenu(self.state, on_pick=self._on_reconfigure_pick)
        dlg.connect("response", lambda _d, rid: self._finish() if rid == "close" else None)
        dlg.present(None)

    def _on_reconfigure_pick(self, action: str) -> None:
        if action == "cms":
            self._form_cms()
        elif action == "full":
            # Reset first-boot sentinel + re-enter main menu
            sentinel = self.state.data_dir / "first-boot-done"
            try:
                sentinel.unlink()
            except FileNotFoundError:
                pass
            self._present_main_menu()
        elif action == "settings":
            self._open_settings()

    # ── Lifecycle helpers ───────────────────────────────────────────────

    def _finish(self) -> None:
        self.release()

    def _version(self) -> str:
        try:
            from . import __version__
            return __version__
        except Exception:  # noqa: BLE001
            return ""

    def _build_date(self) -> str:
        return os.environ.get("XIBO_KIOSK_BUILD_DATE", "")

"""KioskApp — single-window controller (Adw.NavigationSplitView).

Replaces the dialog-stacking model with a sidebar-and-content layout
inspired by GNOME Settings / Control Center. The sidebar lists every
configurable category (Language, Keyboard, Wi-Fi, Timezone, Player,
CMS, Settings); the right pane swaps to the corresponding panel when
the operator clicks a row. No dialogs pop for sub-screens — everything
lives in one window.

Modal exceptions:
- Wi-Fi password (Adw.AlertDialog, because it's a transient secret prompt)
- Info / Error feedback after each action (Adw.AlertDialog)
"""

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
from .dialogs.info import ErrorDialog, InfoDialog
from .dialogs.panels import CmsFormPanel, LocalityPanel, PickerPanel, PlayerPanel, SettingsPanel
from .dialogs.window import KioskWindow
from .dialogs.wifi_password import WifiPasswordDialog


def _apply_dark_theme() -> None:
    """Honour GNOME color-scheme preference via Adw.StyleManager."""
    try:
        s = Gio.Settings.new("org.gnome.desktop.interface")
        cs = s.get_string("color-scheme") if "color-scheme" in s.list_keys() else ""
        mgr = Adw.StyleManager.get_default()
        if cs == "prefer-dark":
            mgr.set_color_scheme(Adw.ColorScheme.FORCE_DARK)
        elif cs == "prefer-light":
            mgr.set_color_scheme(Adw.ColorScheme.FORCE_LIGHT)
        else:
            mgr.set_color_scheme(Adw.ColorScheme.PREFER_DARK)
    except Exception:  # noqa: BLE001
        pass


class KioskApp(Adw.Application):
    """Adw.Application that owns the KioskWindow + per-category panels."""

    def __init__(self, mode: str):
        super().__init__(
            application_id="org.xiboplayer.Kiosk",
            flags=Gio.ApplicationFlags.NON_UNIQUE,
        )
        self.mode = mode
        self.state: KioskState | None = None
        self.doas = DoasRunner()
        self._window: KioskWindow | None = None

    def do_activate(self):  # noqa: D401, N802
        """Build state, create the window, present it."""
        _apply_dark_theme()
        self.state = KioskState.load()
        self._window = KioskWindow(
            self,
            self.state,
            on_pick=self._on_category,
            on_start=self._finish,
            version=self._version(),
        )
        self._window.present()

    # ── category dispatch ───────────────────────────────────────────────

    def _on_category(self, category: str) -> None:
        """User clicked a sidebar row — swap the content panel.

        Top-level sidebar has only three rows: Locality, CMS, Settings.
        Locality contains Language/Keyboard/Timezone sub-rows; Settings
        contains Wi-Fi/Player plus the ops actions.
        """
        dispatch = {
            "locality": self._show_locality,
            "cms":      self._show_cms,
            "settings": self._show_settings,
        }
        fn = dispatch.get(category)
        if fn:
            fn()

    # ── Locality overview + sub-picker dispatch ─────────────────────────

    def _show_locality(self) -> None:
        """Locality overview — shows current Language/Keyboard/Timezone.

        Clicking a row opens the corresponding picker; after a successful
        apply, the picker's apply callback navigates back here so the
        operator sees the new value in the row subtitle.
        """
        s = self.state
        panel = LocalityPanel(
            locale=s.locale,
            keyboard=s.keyboard_layout,
            timezone=s.timezone,
            on_pick=self._locality_pick,
        )
        self._window.set_content_panel("Locality", panel)

    def _locality_pick(self, action: str) -> None:
        if action == "language":
            self._show_language()
        elif action == "keyboard":
            self._show_keyboard()
        elif action == "timezone":
            self._show_timezone()

    # ── content panels ──────────────────────────────────────────────────

    def _show_language(self) -> None:
        rows = [(loc,) for loc in locale_svc.list_locales()]
        panel = PickerPanel(
            rows=rows,
            columns=["Locale"],
            min_chars=2,
            placeholder="Type a locale code (e.g. en, en_GB, ca, es, fr, de)",
            apply_label="Set language",
            on_apply=lambda v: self._apply_via_doas(
                "xibo-set-locale.sh", v, "Language", back_to=self._show_locality,
            ),
        )
        self._window.set_content_panel("Language", panel)

    def _show_keyboard(self) -> None:
        rows = [(x,) for x in kb_svc.list_layouts()]
        panel = PickerPanel(
            rows=rows,
            columns=["Layout"],
            min_chars=2,
            placeholder="Type a layout code or country (e.g. us, es, fr, gb)",
            apply_label="Set keyboard",
            on_apply=lambda v: self._apply_via_doas(
                "xibo-set-keyboard.sh", v, "Keyboard", back_to=self._show_locality,
            ),
        )
        self._window.set_content_panel("Keyboard", panel)

    def _show_timezone(self) -> None:
        rows = [(z,) for z in tz_svc.list_timezones()]
        panel = PickerPanel(
            rows=rows,
            columns=[""],  # blank column header — IANA is jargon for the operator
            min_chars=2,
            placeholder="Type UTC or a city (e.g. UTC, New_York, London, Tokyo)",
            apply_label="Set timezone",
            on_apply=lambda v: self._apply_via_doas(
                "xibo-set-timezone.sh", v, "Timezone", back_to=self._show_locality,
            ),
        )
        self._window.set_content_panel("Timezone", panel)

    def _show_wifi(self) -> None:
        if not wifi_svc.has_wifi_hardware():
            self._window.set_content_panel(
                "Wi-Fi",
                self._info_status_widget(
                    icon="network-wireless-disabled-symbolic",
                    title="No wireless hardware",
                    body="This kiosk has no Wi-Fi adapter. Use a wired connection.",
                ),
            )
            return
        wifi_svc.rescan()
        # Wait briefly for scan results before populating.
        GLib.timeout_add_seconds(2, self._wifi_panel_populate)

    def _wifi_panel_populate(self) -> bool:
        nets = wifi_svc.list_networks()
        if not nets:
            self._window.set_content_panel(
                "Wi-Fi",
                self._info_status_widget(
                    icon="network-wireless-symbolic",
                    title="No networks found",
                    body="Try again in a moment, or use a wired connection.",
                ),
            )
            return False
        rows: list[tuple[str, ...]] = []
        for n in nets:
            name = ("* " if n.in_use else "") + n.ssid
            rows.append((name, f"{n.signal}%", n.security))
        panel = PickerPanel(
            rows=rows,
            columns=["SSID", "Signal", "Security"],
            min_chars=0,
            placeholder="Filter networks",
            apply_label="Connect",
            on_apply=self._wifi_apply,
        )
        self._window.set_content_panel("Wi-Fi", panel)
        return False

    def _wifi_apply(self, ssid_with_marker: str) -> None:
        ssid = ssid_with_marker[2:] if ssid_with_marker.startswith("* ") else ssid_with_marker
        security = next((n.security for n in wifi_svc.list_networks() if n.ssid == ssid), "open")
        if security == "open":
            self._connect_wifi(ssid, "")
            return
        # Password is sensitive — keep as a transient AlertDialog.
        pw = WifiPasswordDialog(ssid)
        pw.connect("response", lambda _d, rid: self._connect_wifi(ssid, pw.password) if rid == "connect" else None)
        pw.present(self._window)

    def _connect_wifi(self, ssid: str, psk: str) -> None:
        notify.send(f"Connecting to {ssid}...")
        ok, err = self.doas.run("xibo-set-wifi.sh", ssid, psk)
        if ok:
            notify.send(f"Wi-Fi connected to {ssid}")
        else:
            ErrorDialog(subtitle="Wi-Fi", body=f"Failed to connect to {ssid}.\n\n{err}").present(self._window)
        self._window.refresh_sidebar()
        # Back to the Settings overview (same parent as Wi-Fi sub-picker).
        self._show_settings()

    def _show_player(self) -> None:
        panel = PlayerPanel(
            current=self.state.player,
            on_apply=self._player_apply,
        )
        self._window.set_content_panel("Player", panel)

    def _player_apply(self, choice: str) -> None:
        arg = "electron" if choice == "Electron" else "chromium"
        ok, err = self.doas.run("xibo-set-player.sh", arg)
        if ok:
            InfoDialog(
                subtitle="Player",
                body=f"Player switched to {choice}. Reboot (or log out + back in) to apply.",
            ).present(self._window)
        else:
            ErrorDialog(subtitle="Player", body=f"Failed to switch player.\n\n{err}").present(self._window)
        self._window.refresh_sidebar()
        # Back to Settings overview (Player sub-picker's parent).
        self._show_settings()

    def _show_cms(self) -> None:
        s = self.state
        panel = CmsFormPanel(
            cms_url=s.cms_url if s.cms_url != "(not configured)" else s.preseed_vars.get("xibo.cms_url", ""),
            cms_key=s.preseed_vars.get("xibo.cms_key", ""),
            display_name=s.preseed_vars.get("xibo.display_name", ""),
            on_apply=self._cms_apply,
        )
        self._window.set_content_panel("CMS", panel)

    def _cms_apply(self, url: str, key: str, name: str) -> None:
        try:
            cms_svc.write_for_player(self.state.player, self.state.config_dir, self.state.data_dir, url, key, name)
            notify.send(f"CMS configured: {url}")
        except Exception as e:  # noqa: BLE001
            ErrorDialog(subtitle="CMS", body=f"Failed to write CMS config:\n\n{e}").present(self._window)
        self._window.refresh_sidebar()

    def _show_settings(self) -> None:
        s = self.state
        wifi_sub = s.wifi_ssid if s.wifi_ssid else (
            "(not connected)" if s.wifi_hardware_present else "(no wireless hardware)"
        )
        panel = SettingsPanel(
            wifi_subtitle=wifi_sub,
            player_subtitle=s.player or "(unknown)",
            on_pick=self._settings_pick,
        )
        self._window.set_content_panel("Settings", panel)

    def _settings_pick(self, action: str) -> None:
        # Wi-Fi + Player are "sub-pickers": clicking them opens a picker
        # panel in the content pane (not a modal), same pattern as
        # Locality sub-rows. After apply the callback navigates back to
        # the Settings overview so the new value is visible.
        if action == "wifi":
            self._show_wifi()
            return
        if action == "player":
            self._show_player()
            return
        if action == "terminal":
            for cand in ("ptyxis", "kgx", "gnome-terminal", "xterm"):
                try:
                    subprocess.Popen([cand], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    notify.send(f"Opened {cand}")
                    return
                except FileNotFoundError:
                    continue
            ErrorDialog(subtitle="Terminal", body="No terminal emulator installed.").present(self._window)
        elif action == "gnome":
            try:
                subprocess.Popen(["gnome-control-center"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                notify.send("Opened GNOME Settings")
            except FileNotFoundError:
                ErrorDialog(subtitle="GNOME Settings", body="gnome-control-center is not installed.").present(self._window)
        elif action == "debug":
            for cand in (self.state.kiosk_dir / "xibo-debug-dump.sh", Path("/usr/bin/xibo-debug-dump")):
                if cand.exists():
                    subprocess.Popen([str(cand)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    notify.send("Debug bundle generation started")
                    return
            ErrorDialog(subtitle="Debug", body="xibo-debug-dump not found.").present(self._window)

    # ── helpers ─────────────────────────────────────────────────────────

    def _apply_via_doas(self, helper: str, value: str, label: str, *, back_to=None) -> None:
        notify.send(f"Setting {label.lower()} to {value}...")
        ok, err = self.doas.run(helper, value)
        if ok:
            notify.send(f"{label}: {value}")
        else:
            ErrorDialog(subtitle=label, body=f"Failed to set {label} to {value}.\n\n{err}").present(self._window)
        self._window.refresh_sidebar()
        # After apply, navigate back to the parent overview panel so the
        # operator sees the new value in the row subtitle and doesn't
        # stare at a stale picker wondering if anything happened.
        if callable(back_to):
            back_to()

    def _info_status_widget(self, *, icon: str, title: str, body: str) -> Adw.StatusPage:
        sp = Adw.StatusPage()
        sp.set_icon_name(icon)
        sp.set_title(title)
        sp.set_description(body)
        return sp

    def _finish(self) -> None:
        if self._window is not None:
            self._window.close()

    def _version(self) -> str:
        try:
            from . import __version__
            return __version__
        except Exception:  # noqa: BLE001
            return ""

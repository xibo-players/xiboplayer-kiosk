"""KioskState — single source of truth for UI status.

Loaded once at startup via KioskState.load(). Dialog refresh_* methods are
called after each successful setter to keep the UI live without re-shelling
on every paint.
"""

from dataclasses import dataclass, field
from pathlib import Path

from . import preseed
from .services import status


@dataclass
class KioskState:
    wifi_ssid: str = ""
    wifi_hardware_present: bool = False
    wired_connected: bool = False
    timezone: str = ""
    locale: str = ""
    keyboard_layout: str = ""
    player: str = "Chromium"
    player_service: str = "xiboplayer-chromium.service"
    cms_url: str = ""
    cms_key: str = ""
    display_name: str = ""
    preseed_vars: dict[str, str] = field(default_factory=dict)
    kiosk_dir: Path = Path("/usr/share/xiboplayer-kiosk")
    config_dir: Path = Path.home() / ".config" / "xiboplayer"
    data_dir: Path = Path.home() / ".local" / "share" / "xibo"

    @classmethod
    def load(cls) -> "KioskState":
        s = cls()
        s.preseed_vars = preseed.read_all()
        s.refresh_all()
        return s

    def refresh_all(self) -> None:
        self.refresh_wifi()
        self.refresh_timezone()
        self.refresh_locale()
        self.refresh_keyboard()
        self.refresh_player()
        self.refresh_cms()

    def refresh_wifi(self) -> None:
        self.wifi_ssid = status.wifi_status()
        self.wifi_hardware_present = not self.wifi_ssid.startswith("(no wifi hardware")
        self.wired_connected = self.wifi_ssid == "(wired)"

    def refresh_timezone(self) -> None:
        self.timezone = status.timezone_status()

    def refresh_locale(self) -> None:
        self.locale = status.locale_status()

    def refresh_keyboard(self) -> None:
        self.keyboard_layout = status.keyboard_status()

    def refresh_player(self) -> None:
        self.player, self.player_service = status.player_status(self.config_dir)

    def refresh_cms(self) -> None:
        self.cms_url = status.cms_status(self.config_dir, self.data_dir, self.player)

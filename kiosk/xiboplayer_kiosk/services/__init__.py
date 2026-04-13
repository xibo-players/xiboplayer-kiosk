"""Per-domain read/write service modules.

Each module exposes `list_*()` read functions (no doas needed) and `set_*(state, doas, ...)`
mutators that call DoasRunner and then update KioskState.
"""

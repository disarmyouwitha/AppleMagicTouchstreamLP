# GlassToKey.Linux

Minimal Linux app host.

Planned responsibilities:

- process entry point
- settings/config under XDG paths
- Linux runtime startup/shutdown
- device selection UI or CLI
- wiring `GlassToKey.Core` to `GlassToKey.Platform.Linux`
- packaging-facing permission guidance such as generated `udev` rules

Current CLI/runtime features:

- `show-config` prints the resolved XDG-backed host settings, selected trackpads, preset, and keymap path
- `init-config` writes default Linux host settings using detected stable IDs
- `print-udev-rules` emits a packaging-oriented rule template for the currently detected Apple trackpads and `/dev/uinput`
- `run-engine` now consumes the resolved settings so stable-id selection, preset choice, and optional keymap override are part of the live runtime path
- the Linux host now ships its own bundled `GLASSTOKEY_DEFAULT_KEYMAP.json`, so Linux defaults can diverge from Windows while keeping the shared schema

This project should remain thin. Most logic belongs in the shared core or the Linux platform backend.

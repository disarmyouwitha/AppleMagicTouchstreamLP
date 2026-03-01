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
- `doctor` checks XDG config health, bundled keymap presence, live evdev bindings, and `/dev/uinput` readiness
- `print-udev-rules` emits a packaging-oriented rule template for the currently detected Apple trackpads and `/dev/uinput`
- `selftest` validates the bundled Linux keymap import path, rejects stray Windows-only bundled labels, and verifies semantic-to-evdev coverage for the current Linux action surface
- `capture-atpcap` writes Linux `.atpcap` version 3 normalized frame captures for offline analysis
- `summarize-atpcap` prints a quick summary of a Linux `.atpcap` capture
- `replay-atpcap` replays a Linux `.atpcap` capture through the shared engine path and can emit a replay trace JSON
- `write-atpcap-fixture` writes a replay expectation fixture from an existing Linux `.atpcap` capture
- `check-atpcap-fixture` replays a Linux `.atpcap` capture and validates it against an expectation fixture
- `run-engine` now consumes the resolved settings so stable-id selection, preset choice, and optional keymap override are part of the live runtime path
- the Linux host now ships its own bundled `GLASSTOKEY_DEFAULT_KEYMAP.json`, and the embedded bundled keymap payload has been translated away from Windows-only defaults like `EMOJI`, `LWin`, and `Win+H`
- `VOL_UP`, `VOL_DOWN`, `BRIGHT_UP`, and `BRIGHT_DOWN` now resolve through semantic codes and Linux evdev output mappings instead of relying on Windows VK fallback
- checked-in publish profiles now cover:
  - framework-dependent `linux-x64`
  - self-contained single-file `linux-x64`

Current phase:

- early Phase 4 usable alpha
- the live Linux typing path is working on the tested Ubuntu 24.04 host
- packaging, doctor, and offline `.atpcap` diagnostics are now started, but GUI, polished install flow, and packaged end-user distribution are still in progress

Publish commands:

- framework-dependent:
  - `dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxFrameworkDependent`
- self-contained single-file:
  - `dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxSelfContained`

Packaging notes:

- framework-dependent publish still expects the target machine to have `.NET 10` runtime installed
- self-contained publish avoids the runtime prerequisite, but device permissions still need a targeted `udev` rule for `/dev/input/event*` and `/dev/uinput`
- `print-udev-rules` is the current packaging scaffold for those permissions
- run overlapping `dotnet build` / `dotnet publish` commands for the same project graph sequentially; parallel publishes can collide in shared output paths
- `packaging/linux/install.sh` and `packaging/linux/90-glasstokey.rules` are the checked-in install artifacts
- `packaging/linux/install.sh` now supports wrapper-vs-service install decisions and prints explicit post-install commands for `doctor`, `init-config`, `show-config`, and `run-engine`

Current diagnostics status:

- Linux `.atpcap` version 3 capture now preserves normalized contact frames and physical click state for replay, summary, and trace analysis
- `summarize-atpcap` now reports button-pressed and button-edge counts
- fixture generation/check commands now make Linux `.atpcap` captures useful for regression checking, not just manual replay

This project should remain thin. Most logic belongs in the shared core or the Linux platform backend.

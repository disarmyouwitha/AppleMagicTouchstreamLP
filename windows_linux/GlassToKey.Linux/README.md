# GlassToKey.Linux

Minimal Linux app host.

For the canonical Linux status, validated host findings, and remaining-work checklist, use `../LINUX_GOLD.md`.

Responsibilities:

- process entry point
- settings/config under XDG paths via the shared `GlassToKey.Linux.Host` library
- Linux runtime startup/shutdown
- device selection UI or CLI
- wiring `GlassToKey.Core` to `GlassToKey.Platform.Linux`
- packaging-facing permission guidance such as generated `udev` rules

Current CLI/runtime features:

- `show-config` opens the config GUI in graphical sessions when available, and `show-config --print` prints the resolved XDG-backed host settings, selected trackpads, preset, and keymap path
- `init-config` writes default Linux host settings using detected stable IDs
- `doctor` checks XDG config health, bundled keymap presence, live evdev bindings, and `/dev/uinput` readiness
- `print-udev-rules` emits a packaging-oriented rule template for the currently detected Apple trackpads and `/dev/uinput`
- `bind-left`, `bind-right`, and `swap-sides` manage explicit left/right assignment without editing settings by hand
- `load-keymap` imports a full GlassToKey profile bundle when present (`Version` + `Settings` + `KeymapJson`), while still accepting raw keymap JSON as a fallback
- `selftest` validates the bundled Linux keymap import path, rejects stray Windows-only bundled labels, and verifies semantic-to-evdev coverage for the current Linux action surface
- `capture-atpcap` writes Linux `.atpcap` version 3 normalized frame captures for offline analysis
- `summarize-atpcap` prints a quick summary of a Linux `.atpcap` capture
- `replay-atpcap` replays a Linux `.atpcap` capture through the shared engine path and can emit a replay trace JSON
- `write-atpcap-fixture` writes a replay expectation fixture from an existing Linux `.atpcap` capture
- `check-atpcap-fixture` replays a Linux `.atpcap` capture and validates it against an expectation fixture
- `start` launches the headless runtime in the background and returns the shell prompt
- `stop` stops that background runtime
- `run-engine` now consumes the resolved settings so stable-id selection, preset choice, and optional keymap override are part of the live runtime path
- `watch-runtime`, `capture-atpcap`, and `run-engine` now report binding-state transitions so disconnect/rebind churn is visible during live Linux runs
- the Linux host now ships its own bundled `GLASSTOKEY_DEFAULT_KEYMAP.json`, and the embedded bundled keymap payload has been translated away from Windows-only defaults like `EMOJI`, `LWin`, and `Win+H`
- `VOL_UP`, `VOL_DOWN`, `BRIGHT_UP`, and `BRIGHT_DOWN` now resolve through semantic codes and Linux evdev output mappings instead of relying on Windows VK fallback
- Linux semantic coverage now also includes mute/media transport, lock keys, print/pause/menu, and F13-F24
- the CLI now consumes the shared `GlassToKey.Linux.Host` library instead of carrying its own private copy of the Linux settings/runtime layer
- the generated/installable Linux `udev` rules now prefer a dedicated `glasstokey` access group plus `0660` device modes, with `uaccess` left as an additive hint instead of the primary trust model
- checked-in publish profiles now cover:
  - framework-dependent `linux-x64`
  - self-contained single-file `linux-x64`

Current phase:

- early usable alpha
- the live Linux typing path is working on the tested Ubuntu 24.04 host
- tray-desktop packaging is the default user story
- direct headless CLI operation remains supported through `glasstokey start` / `glasstokey stop`
- local Arch `PKGBUILD` scaffolding now exists under `packaging/linux/arch`; real Arch packaging/install validation is the next distro-expansion checkpoint

Quick start:

- source run:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- doctor`
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- init-config`
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- show-config --print`
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- load-keymap /path/to/keymap.json`
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- start`
- installed wrapper run:
  - `glasstokey doctor`
  - `glasstokey init-config`
  - `glasstokey show-config`
  - `glasstokey load-keymap /path/to/keymap.json`
  - `glasstokey start`
- stop the background CLI runtime with `glasstokey stop`
- the documented default desktop path is `glasstokey-gui`; the tray app owns the runtime in normal desktop use
- profile import/export is now shared with Windows: both sides use the same `Version` + `Settings` + `KeymapJson` bundle shape
- if you want a bounded foreground smoke test instead of a background session, use `run-engine 10`
- if you installed the optional headless user service, control it with:
  - `systemctl --user start glasstokey.service`
  - `systemctl --user stop glasstokey.service`
  - `systemctl --user restart glasstokey.service`
  - `journalctl --user -u glasstokey.service -f`

Publish commands:

- framework-dependent:
  - `dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxFrameworkDependent`
- self-contained single-file:
  - `dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxSelfContained`

Packaging notes:

- framework-dependent publish still expects the target machine to have `.NET 10` runtime installed
- self-contained publish avoids the runtime prerequisite, but device permissions still need a targeted `udev` rule for `/dev/input/event*` and `/dev/uinput`
- on the current Ubuntu host, `uaccess` tags alone were not sufficient to guarantee user ACLs on recreated Bluetooth trackpad nodes, so the packaged permission strategy now prefers the dedicated `glasstokey` group model
- `print-udev-rules` is the current packaging scaffold for those permissions
- run overlapping `dotnet build` / `dotnet publish` commands for the same project graph sequentially; parallel publishes can collide in shared output paths
- `packaging/linux/install.sh` and `packaging/linux/90-glasstokey.rules` are the checked-in install artifacts
- `packaging/linux/deb/build-deb.sh` now produces a first Debian package skeleton from the current publish outputs
- `packaging/linux/install.sh` now supports wrapper-vs-service install decisions and prints explicit post-install commands for `doctor`, `init-config`, `show-config`, `load-keymap`, `start`, `stop`, and `run-engine`

Current diagnostics status:

- Linux `.atpcap` version 3 capture now preserves normalized contact frames and physical click state for replay, summary, and trace analysis
- `summarize-atpcap` now reports button-pressed and button-edge counts
- fixture generation/check commands now make Linux `.atpcap` captures useful for regression checking, not just manual replay
- rich diagnostics remain primarily CLI/operator tooling; the GUI should stay focused on config, live preview, and lightweight doctor visibility

This project should remain thin. Most logic belongs in the shared core or the Linux platform backend.

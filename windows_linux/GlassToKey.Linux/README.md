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

- bare `glasstokey` is the graphical entrypoint; in a graphical session it opens the tray host and config window
- when bare `glasstokey` is used while a detached headless runtime or user service is active, GlassToKey now stops that headless runtime first and launches the full tray host so pointer input is not left suppressed underneath the GUI
- `init-config` writes default Linux host settings using detected stable IDs
- `doctor` checks XDG config health, bundled keymap presence, live evdev bindings, `/dev/uinput` readiness, and Linux actuator-hidraw haptics access when available
- `list-devices` and runtime binding only target authoritative Apple Magic Trackpad multitouch nodes; wrong evdev nodes should be fixed by rebinding, not by Linux-side fallback logic
- `pulse-haptics` sends direct actuator pulses to the configured left/right USB trackpad for bring-up and permission validation
- `print-udev-rules` emits a packaging-oriented rule template for the currently detected Apple trackpads, any validated actuator hidraw interfaces, and `/dev/uinput`
- `bind-left`, `bind-right`, and `swap-sides` manage explicit left/right assignment without editing settings by hand
- `load-keymap` imports a full GlassToKey profile bundle when present (`Version` + `Settings` + `KeymapJson`), while still accepting raw keymap JSON as a fallback
- `print-keymap` prints the saved Linux device bindings plus a text-mode ASCII view of the current layer-0 keymap
- `selftest` validates the bundled Linux keymap import path, rejects stray Windows-only bundled labels, and verifies semantic-to-evdev coverage for the current Linux action surface
- `capture-atpcap` writes Linux `.atpcap` version 3 normalized frame captures for offline analysis
- `summarize-atpcap` prints a quick summary of a Linux `.atpcap` capture
- `replay-atpcap` replays a Linux `.atpcap` capture through the shared engine path and can emit a replay trace JSON
- `write-atpcap-fixture` writes a replay expectation fixture from an existing Linux `.atpcap` capture
- `check-atpcap-fixture` replays a Linux `.atpcap` capture and validates it against an expectation fixture
- `start` launches the headless runtime in the background and returns the shell prompt
- `stop` stops the detached background runtime, any running tray host, and matching user `systemd` services such as `glasstokey.service`
- `run-engine` now consumes the resolved settings so stable-id selection, preset choice, and optional keymap override are part of the live runtime path
- `start`, detached `__background-run`, and `run-engine` now all use the headless pure-keyboard runtime policy
- headless only auto-selects trackpads when no saved left/right bindings exist; it does not persist those temporary choices
- headless now also disables pointer-intent takeover in core, so the pure-keyboard runtime never transitions into mouse intent
- headless evdev grab is now policy-driven: in a graphical session it grabs exclusively by default, in proven no-pointer environments it skips grab, and `start --no-grab` / `run-engine --no-grab` explicitly opt out
- `watch-runtime`, `capture-atpcap`, and `run-engine` now report binding-state transitions so disconnect/rebind churn is visible during live Linux runs
- the Linux host now ships its own bundled `GLASSTOKEY_DEFAULT_KEYMAP.json`, and the embedded bundled keymap payload has been translated away from Windows-only defaults like `EMOJI`, `LWin`, and `Win+H`
- `VOL_UP`, `VOL_DOWN`, `BRIGHT_UP`, and `BRIGHT_DOWN` now resolve through semantic codes and Linux evdev output mappings instead of relying on Windows VK fallback
- Linux brightness handling is intentionally split: `BRIGHT_UP` / `BRIGHT_DOWN` stay on the native evdev brightness-key path only, while `BRI_SCRIPT_UP` / `BRI_SCRIPT_DOWN` stay on the `xrandr` fallback path only
- Linux semantic coverage now also includes mute/media transport, lock keys, print/pause/menu, and F13-F24
- Linux now also triggers Magic Trackpad haptics through the validated actuator hidraw interface when the device exposes that interface and permissions allow write access
- On the current Ubuntu 24.04 host, live runtime haptics has now been validated end-to-end on both tested USB trackpads:
  - older Magic Trackpad (`0x05ac/0x0265`) actuator node `/dev/hidraw11`
  - newer Magic Trackpad (`0x05ac/0x0324`) actuator node `/dev/hidraw15`
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
- local Arch `PKGBUILD` scaffolding now exists under `GlassToKey.Linux/packaging/arch`; real Arch packaging/install validation is the next distro-expansion checkpoint

Quick start:

- source run:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- doctor`
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- init-config`
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- load-keymap /path/to/keymap.json`
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- start`
- installed wrapper run:
  - `glasstokey doctor`
  - `glasstokey init-config`
  - `glasstokey print-keymap`
  - `glasstokey`
  - `glasstokey load-keymap /path/to/keymap.json`
  - `glasstokey start`
- stop the background CLI runtime, tray host, or optional user service with `glasstokey stop`
- the documented default desktop path is `glasstokey-gui`; it starts the tray host in background, and `glasstokey-gui --show` opens the config window on demand
- profile import/export is now shared with Windows: both sides use the same `Version` + `Settings` + `KeymapJson` bundle shape
- if you want a bounded foreground headless smoke test instead of a background session, use `run-engine 10`
- for direct haptics bring-up, use `pulse-haptics left 5` or `pulse-haptics right 5`
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
- self-contained publish avoids the runtime prerequisite, but device permissions still need a targeted `udev` rule for `/dev/input/event*`, validated actuator `/dev/hidraw*` nodes, and `/dev/uinput`
- on the current Ubuntu host, `uaccess` tags alone were not sufficient to guarantee user ACLs on recreated Bluetooth trackpad nodes, so the packaged permission strategy now prefers the dedicated `glasstokey` group model
- the checked-in packaging rules now include Magic Trackpad actuator hidraw access for both validated USB product ids: `0x0265` and `0x0324`
- `print-udev-rules` is the current packaging scaffold for those permissions
- run overlapping `dotnet build` / `dotnet publish` commands for the same project graph sequentially; parallel publishes can collide in shared output paths
- `GlassToKey.Linux/packaging/90-glasstokey.rules` plus package-manager installs (`.deb` and Arch package) are the supported install artifacts
- `GlassToKey.Linux/packaging/deb/build-deb.sh` now produces a first Debian package skeleton from the current publish outputs

Current diagnostics status:

- Linux `.atpcap` version 3 capture now preserves normalized contact frames and physical click state for replay, summary, and trace analysis
- `summarize-atpcap` now reports button-pressed and button-edge counts
- fixture generation/check commands now make Linux `.atpcap` captures useful for regression checking, not just manual replay
- rich diagnostics remain primarily CLI/operator tooling; the GUI should stay focused on config, live preview, and lightweight doctor visibility

This project should remain thin. Most logic belongs in the shared core or the Linux platform backend.

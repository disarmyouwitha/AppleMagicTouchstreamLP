# Linux Gold

This is the canonical Linux source of truth for the `windows_linux/` repo.

It replaces the old split planning/status docs and should be kept aligned with:

- `AGENTS.md`
- `GlassToKey.Linux/README.md`
- `GlassToKey.Platform.Linux/README.md`
- `GlassToKey.Linux.Gui/README.md`
- `packaging/linux/README.md`

## Goal

Deliver a usable Linux GlassToKey build on modern Ubuntu by reusing the shared C# engine and data model while keeping Linux input, output, configuration, packaging, and GUI work platform-specific.

Current target assumptions:

- Ubuntu 24.04+
- Wayland-first desktop reality
- Apple Magic Trackpad family validated on the current host
- one or two trackpads
- evdev input plus `uinput` output

## Repo Shape

### Windows host

- `GlassToKey/`
- remains the feature-complete Windows app today
- still owns WPF, WinForms, Raw Input, `SendInput`, click suppression, Windows haptics, and tray/startup UI

### Shared core

- `GlassToKey.Core/`
- current shared seam/library project for Linux-facing reuse
- currently exposes the shared frame-target seam and `TouchProcessorRuntimeHost`
- should remain free of WPF, WinForms, Raw Input, `SendInput`, `evdev`, `uinput`, and UI shell code

### Linux backend

- `GlassToKey.Platform.Linux/`
- owns Linux device enumeration, stable identity, evdev frame assembly, reconnect supervision, `uinput` dispatch, and Linux-specific permission probing

### Linux host/config

- `GlassToKey.Linux.Host/`
- owns XDG-backed settings/config/runtime composition and the shared Linux `doctor` surface used by both CLI and GUI

### Linux CLI

- `GlassToKey.Linux/`
- minimal operator-facing host
- current command surface includes device enumeration, axis probing, `doctor`, config init/show/bind, `.atpcap` diagnostics, runtime watch, and live `run-engine`

### Linux GUI

- `GlassToKey.Linux.Gui/`
- early Avalonia control shell
- current scope is settings, bindings, preset/keymap path selection, in-app `doctor`, and a first tray/top-bar path

### Packaging

- `packaging/linux/`
- checked-in `udev` rule template, install script, and Debian package skeleton

## Architectural Boundaries

- Keep Windows-only code in `GlassToKey/`.
- Keep shared engine/runtime seams in `GlassToKey.Core/`.
- Keep Linux gesture ingestion and `uinput` output in `GlassToKey.Platform.Linux/`.
- Keep Linux settings/runtime composition in `GlassToKey.Linux.Host/`.
- Keep Linux CLI/GUI hosts thin.
- Prefer platform-neutral semantic actions over Windows-VK assumptions in any shared flow.
- Treat touch processing as latency-sensitive: no avoidable allocations, logging, or file I/O on hot paths.

## Validated Host Findings

- Apple trackpads can expose Type B multitouch slots and parallel legacy absolute fields on the same evdev node.
- Prefer the Apple `if01` `-event-mouse` node when multiple event nodes represent one physical trackpad.
- Real `EVIOCGABS` probing works on the host and should be used instead of hardcoded Windows ranges.
- The tested host reported:
  - slot `0..15`
  - X `-3678..3934`
  - Y `-2478..2587`
  - pressure `0..253`
- Linux normalization should subtract axis minima and pass spans `MaxX=7612` and `MaxY=5065`.
- Over Bluetooth on the tested host, `/dev/input/by-id` was absent; stable identity fell back to device `uniq`.
- The same normalized frame path was validated over both USB and Bluetooth on the tested Apple trackpads.
- `run-engine` has been validated end-to-end on the host: evdev input -> shared engine/runtime host -> dispatch pump -> `uinput` output into a real focused app.
- Packaging validation changed the permission direction:
  - `uaccess` alone was not reliable for recreated Bluetooth nodes in the tested Ubuntu session
  - checked-in packaging now prefers a dedicated `glasstokey` group with `0660` modes
  - `TAG+="uaccess"` remains only an additive desktop-session hint
- Sandbox caveat:
  - `EVIOCGABS` can fail inside the coding sandbox even when it works on the real host
  - treat that as an environment validation issue first, not product-side evidence that fallback logic is required

## Current Implemented Status

### Shared/core path

- [x] `GlassToKey.Core` project exists and builds on Linux
- [x] shared frame-target seam exists via `TrackpadFrameEnvelope` and `ITrackpadFrameTarget`
- [x] `TouchProcessorRuntimeHost` is public and usable from Linux hosts
- [x] shared dispatch model carries `DispatchSemanticAction`
- [x] Linux runtime can drive the shared engine/layout/keymap path through the shared host surface

### Linux backend

- [x] Apple trackpad enumeration exists
- [x] preferred `if01` device selection exists
- [x] real `EVIOCGABS` axis/range probing exists
- [x] raw evdev event capture exists
- [x] evdev-to-`InputFrame` assembly exists
- [x] normalized coordinate path validated on host
- [x] legacy absolute fallback path is accounted for
- [x] runtime-side stable-id rebind/reconnect supervision exists
- [x] `LinuxUinputDispatcher` exists
- [x] semantic-first Linux mapping resolves semantic codes before Windows-VK fallback
- [x] Linux semantic coverage includes media, brightness, mute, transport, lock keys, print/pause/menu, and F13-F24

### Linux host and operator tooling

- [x] XDG-backed settings/config path exists
- [x] stable-id device selection exists
- [x] CLI supports `list-devices`
- [x] CLI supports `probe-axes`
- [x] CLI supports `probe-uinput`
- [x] CLI supports `doctor`
- [x] CLI supports `show-config`
- [x] CLI supports `init-config`
- [x] CLI supports `bind-left`, `bind-right`, and `swap-sides`
- [x] CLI supports `print-udev-rules`
- [x] CLI supports `selftest`
- [x] CLI supports `read-events`
- [x] CLI supports `read-frames`
- [x] CLI supports `uinput-smoke`
- [x] CLI supports `watch-runtime`
- [x] CLI supports `run-engine`

### Linux diagnostics and replay

- [x] Linux `.atpcap` capture exists
- [x] Linux `.atpcap` summary exists
- [x] Linux `.atpcap` replay exists
- [x] Linux fixture generation exists
- [x] Linux fixture checking exists
- [x] normalized version 3 Linux captures preserve physical click state in frame-header flags
- [x] `doctor` checks XDG config, bundled keymap presence, live bindings, evdev accessibility, and `/dev/uinput` readiness

### Bundled Linux defaults

- [x] Linux ships its own bundled `GLASSTOKEY_DEFAULT_KEYMAP.json`
- [x] Linux bundled defaults no longer ship Windows-only labels like `EMOJI`, `LWin`, or `Win+H`
- [x] Linux self-test validates bundled keymap import and semantic-to-evdev coverage

### Packaging and distribution

- [x] checked-in framework-dependent Linux publish profile exists
- [x] checked-in self-contained Linux publish profile exists
- [x] checked-in framework-dependent GUI publish profile exists
- [x] checked-in self-contained GUI publish profile exists
- [x] checked-in `udev` rules template exists
- [x] checked-in install script exists
- [x] install script supports wrapper-vs-service decisions
- [x] Debian package skeleton exists
- [x] Debian package build script can produce a `.deb` from current publish outputs

### GUI

- [x] Avalonia GUI shell exists
- [x] GUI can enumerate candidates and assign left/right devices
- [x] GUI can select layout preset
- [x] GUI can browse, set, and clear a custom keymap path
- [x] GUI can run and display `doctor`
- [x] GUI has a first tray/top-bar shell via Avalonia `TrayIcon`
- [x] GUI publishes self-contained cleanly

## Remaining Work

### 1. Packaging and permission closure

These are the highest-priority productization tasks because they determine whether the current Linux runtime can be installed and operated reliably outside the dev shell.

- [ ] Validate the dedicated `glasstokey` group flow end-to-end from a fresh install on the target Ubuntu session
- [ ] Confirm reconnect behavior for packaged Bluetooth trackpads after node churn, not just in a dev shell
- [ ] Confirm packaged `/dev/uinput` access and evdev access both survive reboot/login/logout cycles
- [ ] Validate the checked-in `90-glasstokey.rules` against the currently supported Apple vendor/product pairs on the host and in packaged installs
- [ ] Validate wrapper-only install flow from `packaging/linux/install.sh`
- [ ] Validate user-service install flow from `packaging/linux/install.sh`
- [ ] Validate `.deb` install, upgrade, and uninstall behavior
- [ ] Decide whether wrapper mode, user service mode, or both should be the documented default for first users
- [ ] Tighten post-install guidance once the real packaged flow is proven on host

### 2. GUI/product surface

The GUI exists, but it is still a control shell rather than the finished Linux product surface.

- [ ] Manually validate the tray/top-bar path on the target Ubuntu desktop
- [ ] Add explicit runtime start/stop/status control in the GUI
- [ ] Surface current binding state and reconnect status in the GUI
- [ ] Decide how much runtime diagnostics should live in the GUI versus remain CLI-only
- [ ] Decide whether keymap editing is in-scope for the GUI or whether file-based custom keymaps remain the v1 story
- [ ] Polish the packaged GUI launcher path and desktop entry behavior

### 3. Runtime validation and regression depth

The live path works. The next gap is broader validation under the ways users will actually run it.

- [ ] Add more Linux replay fixtures from real host captures covering both tested trackpad families and both USB/Bluetooth transport paths
- [ ] Validate unplug/replug churn while `run-engine` is active for longer sessions
- [ ] Validate the same churn under packaged wrapper/service execution, not just ad hoc runs
- [ ] Decide whether optional dispatch tracing should be added as targeted diagnostics for runtime misbehavior
- [ ] Keep `.atpcap` as the primary long-form offline diagnostic artifact

### 4. Shared-core and semantic cleanup

The Linux path works, but shared extraction is still only partially complete in repo structure and shared semantics still coexist with Windows-VK compatibility.

- [ ] Continue moving shared engine/layout/keymap/runtime pieces toward `GlassToKey.Core`
- [ ] Keep `GlassToKey.Core` dependency-clean and Linux/Windows consumable
- [ ] Reduce remaining shared-flow dependence on Windows virtual-key compatibility where semantic actions should be authoritative
- [ ] Decide how much replay/self-test infrastructure should live directly in `GlassToKey.Core` versus remain host-owned
- [ ] Keep Windows behavior unchanged while that cleanup proceeds

### 5. Linux v1 parity decisions still deferred

These are intentionally not blocking the current packaging/productization push, but they remain open product decisions.

- [ ] Decide whether Linux v1 ships mixed-mode only or also attempts keyboard-mode suppression
- [ ] If keyboard-mode suppression is pursued, prototype `EVIOCGRAB` with strict crash/exit safety and clear operator expectations
- [ ] Decide whether Linux force-click parity remains disabled or whether a Linux-specific calibrated pressure path is worth building later
- [ ] Investigate Magic Trackpad haptics only after the typing/runtime path is productized

## Recommended Immediate Work Order

1. Close packaged permission validation around the `glasstokey` group model.
2. Validate the install script and `.deb` flow end-to-end on the target Ubuntu desktop.
3. Manually validate the GUI tray/runtime control shell on the host.
4. Add a small set of real capture fixtures covering the current tested hardware and reconnect churn.
5. Only then return to deeper shared-core cleanup or deferred parity work.

## Build Commands

Run overlapping builds/publishes for the same project graph sequentially.

### Shared/Linux builds

- `dotnet build GlassToKey.Core/GlassToKey.Core.csproj -c Release`
- `dotnet build GlassToKey.Platform.Linux/GlassToKey.Platform.Linux.csproj -c Release`
- `dotnet build GlassToKey.Linux.Host/GlassToKey.Linux.Host.csproj -c Release`
- `dotnet build GlassToKey.Linux/GlassToKey.Linux.csproj -c Release`
- `dotnet build GlassToKey.Linux.Gui/GlassToKey.Linux.Gui.csproj -c Release`

### Linux publish

- `dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxFrameworkDependent`
- `dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxSelfContained`
- `dotnet publish GlassToKey.Linux.Gui/GlassToKey.Linux.Gui.csproj -c Release -p:PublishProfile=LinuxGuiFrameworkDependent`
- `dotnet publish GlassToKey.Linux.Gui/GlassToKey.Linux.Gui.csproj -c Release -p:PublishProfile=LinuxGuiSelfContained`

### Linux package build

- `bash packaging/linux/deb/build-deb.sh --version 0.1.0-dev --output-dir /tmp/glasstokey-deb-out`

## Doc Rule

If Linux scope, status, or packaging reality changes:

- update this file first
- then update `AGENTS.md`
- keep project/package READMEs short and local to their project surface

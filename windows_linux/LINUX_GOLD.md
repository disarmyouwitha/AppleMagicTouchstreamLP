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

- `GlassToKey.Windows/`
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

## Target Final Architecture

This section describes the intended end state after the migration and cleanup work is complete.

The important distinction is:

- the current repo is still in a transitional state
- the target architecture is the shape we should be steering changes toward

### Design principles

- Shared product behavior lives once in a platform-neutral core.
- Platform-specific input/output/device code lives in platform layers.
- Host/runtime composition lives in host layers.
- Shipped apps stay thin and mostly provide entry points, packaging, and UI shells.
- A shared gesture or layout change should affect every platform that consumes the shared core unless a platform layer intentionally diverges.
- When Linux uncovers missing shared behavior or settings/layout/runtime plumbing, prefer moving that logic into `GlassToKey.Core` when the dependency boundary allows it rather than building a second Linux-only implementation.
- Reimplementation in Linux host/platform layers is the fallback only when the code is genuinely platform-specific or extracting it would force platform dependencies into `Core`.

### Target layers

#### 1. Shared core

- `GlassToKey.Core`
- owns:
  - touch engine
  - gesture logic
  - input/contact/frame model
  - layout generation
  - keymap model and parsing
  - dispatch model
  - platform-neutral semantic actions
  - replay/test logic that is truly platform-neutral
  - shared runtime seam used by all platforms
- must not depend on:
  - WPF
  - WinForms
  - Avalonia
  - Raw Input
  - `SendInput`
  - `evdev`
  - `uinput`
  - XDG/platform settings
  - tray/startup/service code

#### 2. Windows platform layer

- target shape: `GlassToKey.Platform.Windows`
- owns:
  - Raw Input ingestion
  - Windows-native output injection such as `SendInput`
  - click suppression / keyboard-mode plumbing
  - Windows haptics
  - Windows-only device/runtime glue
- must not own:
  - gesture behavior
  - layout rules
  - keymap semantics
  - app shell/tray/startup configuration policy

#### 3. Linux platform layer

- `GlassToKey.Platform.Linux`
- owns:
  - evdev enumeration and identity
  - frame assembly
  - reconnect supervision
  - `uinput` output
  - Linux-native permission probing
  - Linux-only device/runtime glue
- must not own:
  - gesture behavior
  - layout rules
  - keymap semantics
  - host/UI policy

#### 4. Windows host layer

- target shape: `GlassToKey.Windows.Host`
- owns:
  - Windows runtime composition
  - Windows settings/config composition
  - tray/startup behavior
  - diagnostics wiring
  - host-side policy around runtime lifecycle
- depends on:
  - `GlassToKey.Core`
  - `GlassToKey.Platform.Windows`

#### 5. Linux host layer

- `GlassToKey.Linux.Host`
- owns:
  - XDG-backed settings/config composition
  - Linux runtime composition
  - doctor/host-side diagnostics
  - host-side policy around runtime lifecycle
- depends on:
  - `GlassToKey.Core`
  - `GlassToKey.Platform.Linux`

#### 6. Thin shipped apps

- Windows desktop app:
  - `GlassToKey.Windows`
- Linux runtime app:
  - `GlassToKey.Linux`
- Linux GUI app:
  - `GlassToKey.Linux.Gui` if it remains a separately shipped executable

These top-level apps should stay thin:

- parse startup arguments
- bootstrap the relevant host layer
- provide platform UI shell entry points
- package/publish the final app

### Target Linux product model

The intended Linux user-facing shape is:

- a long-running tray app that owns the runtime on the hotpath
- an on-demand config window opened from that tray app
- a reusable CLI/service path kept for diagnostics, packaging validation, and headless experiments

Linux should support both final operator-facing modes:

1. desktop:
   tray-owned runtime for normal workstation use
2. headless:
   CLI/service runtime for server, kiosk, minimal-shell, or GUI-free use

This is a product requirement, not just an engineering convenience:

- a Linux build that cannot run headless is the wrong product shape
- desktop tray mode is the primary UX
- headless runtime mode remains a supported final product mode
- what changes between modes is the host shell, not the runtime path
- both modes should use the same `GlassToKey.Core` logic and the same Linux platform/runtime path

#### Tray-owned runtime app

- owns the live evdev -> engine -> `uinput` path
- owns reconnect supervision
- owns the tray/top-bar surface
- opens and closes the config window on demand
- should be the primary day-to-day Linux product shape
- should mirror the existing Windows and macOS product model as closely as practical
- must keep the runtime work off the UI thread even though the tray app owns the process

#### Config window

- edits settings and keymap selection
- surfaces binding state and live runtime state
- runs diagnostics
- should read runtime state directly from the tray-owned runtime instead of relying on a second preview/runtime split where possible
- should not be required to stay alive for typing to keep working

#### CLI/service path

- remains useful for `doctor`, capture/replay, fixture work, packaging validation, and headless testing
- remains a valid engineering/runtime harness
- is not the primary Linux desktop product shape
- remains a required final product mode for headless operation
- should stay reusable and headless even if the tray app becomes the normal operator-facing runtime

Current repo note:

- the service/controller split remains an engineering and headless path, not the primary desktop architecture
- the default desktop source path now runs as a tray-owned runtime app with the config window opened on demand
- the tray-owned desktop path now exposes live typing state and live preview from the same in-process runtime stream instead of polling a separate service/runtime-state path
- the remaining implementation work is now mostly productization:
  - validate and polish the tray-owned desktop host on the real Ubuntu session
  - keep CLI/service flows supported for headless and packaging use
  - make the packaged desktop path line up with the new source-level desktop architecture

### Recorded design decision

The shared-code migration direction is now explicitly decided:

- shared code should be physically moved into `GlassToKey.Core`
- `GlassToKey.Core` should become the canonical source location for shared engine/layout/keymap/runtime code
- linked-source references back into the Windows app project are transitional debt, not an acceptable end state
- Windows can remain the source of truth during the Linux/shared-core buildout, but shared code should still be moved into `GlassToKey.Core` as it is extracted
- Linux work should not solve shared problems by pointing back into `GlassToKey.Windows/` or by creating new Linux-only duplicates when the logic belongs in `Core`

### Target dependency direction

The desired dependency graph is:

```text
GlassToKey.Core
  ^
  |
GlassToKey.Platform.Windows      GlassToKey.Platform.Linux
  ^                              ^
  |                              |
GlassToKey.Windows.Host          GlassToKey.Linux.Host
  ^                              ^              ^
  |                              |              |
GlassToKey.Windows               GlassToKey.Linux  GlassToKey.Linux.Gui
```

Rules:

- `GlassToKey.Core` is the only shared logic layer.
- `GlassToKey.Core` should own shared source files directly rather than linking back to `GlassToKey.Windows/` as a permanent architecture.
- Platform layers depend on `Core`, never on each other.
- Host layers depend on `Core` plus one platform layer.
- Top-level apps depend on host layers, not on deep internals.
- Windows and Linux should consume the same shared engine path through `Core`.

### Target build model

Once the architecture is in the intended final state, daily builds should be simple:

- Windows app build:
  - build the Windows top-level app project
- Linux runtime build:
  - build the Linux top-level app project
- Linux GUI build:
  - build the Linux GUI top-level app project only if that GUI remains a separate shipped binary

Internal dependency projects should build automatically through project references.

That means:

- developers should not need to manually build `Core`, `Platform.Windows`, `Platform.Linux`, `Windows.Host`, or `Linux.Host` as part of normal app workflows
- those projects exist for code organization, reuse, and testability, not as the primary operator-facing build targets

### Migration implication

The current Windows project is still more monolithic than the target shape.

The architecture is not considered complete until:

- shared source files live in `GlassToKey.Core`
- Windows consumes the shared engine path through `GlassToKey.Core` via a real project reference
- Windows-specific runtime/device code is split cleanly into a Windows platform layer
- Windows host/runtime composition is separated from pure platform plumbing
- a shared gesture change in `GlassToKey.Core` is automatically picked up by both Windows and Linux builds

## Architectural Boundaries

- Keep Windows-only code in `GlassToKey.Windows/`.
- Keep shared engine/runtime seams in `GlassToKey.Core/`.
- Prefer physically moving shared layout, keymap, touch-config, and runtime-profile logic into `GlassToKey.Core/` instead of rebuilding similar logic separately in Linux host, GUI, or platform code.
- Do not treat linked source files back into `GlassToKey.Windows/` as an acceptable steady state for shared code.
- Keep Linux gesture ingestion and `uinput` output in `GlassToKey.Platform.Linux/`.
- Keep Linux settings/runtime composition in `GlassToKey.Linux.Host/`.
- Keep Linux CLI/GUI hosts thin.
- Prefer platform-neutral semantic actions over Windows-VK assumptions in any shared flow.
- Treat touch processing as latency-sensitive: no avoidable allocations, logging, or file I/O on hot paths.

## Validated Host Findings

- Apple trackpads can expose Type B multitouch slots and parallel legacy absolute fields on the same evdev node, but the product path now treats the MT slot stream as authoritative and ignores the legacy compatibility fields.
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
- The `glasstokey` group flow has now been validated through a real install/relogin cycle on the host:
  - `/dev/uinput` and matched `/dev/input/event*` nodes came up as `root:glasstokey`
  - `doctor` reported `Summary: ok` after session refresh
  - stable-id bindings survived event-node renumbering across reboot/reconnect
- The checked-in package-manager install flow and user-service flow were validated on the host.
- The Linux user service now runs `run-engine` until interrupted rather than timing out after 10 seconds.
- Packaged reconnect validation is now proven on the host for both:
  - Bluetooth power off/on churn
  - USB unplug/replug churn
- A reconnect bug was fixed in the runtime supervision path:
  - a dropped engine frame no longer causes a fake evdev disconnect/rebind loop
- Real Linux `.atpcap` fixtures now exist under `GlassToKey.Linux/fixtures/linux/` for:
  - `bluetooth-trackpad`
  - `bluetooth-reconnect`
  - `usb-trackpad`
- Sandbox caveat:
  - `EVIOCGABS` can fail inside the coding sandbox even when it works on the real host
  - treat that as an environment validation issue first, not product-side evidence that fallback logic is required or should be reintroduced

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
- [x] legacy absolute fallback path removed; MT slot stream is authoritative
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
- [x] CLI supports `load-keymap`
- [x] CLI supports `selftest`
- [x] CLI supports `read-events`
- [x] CLI supports `read-frames`
- [x] CLI supports `uinput-smoke`
- [x] CLI supports `watch-runtime`
- [x] CLI supports `start` and `stop` for background runtime ownership
- [x] CLI supports `run-engine`

### Linux diagnostics and replay

- [x] Linux `.atpcap` capture exists
- [x] Linux `.atpcap` summary exists
- [x] Linux `.atpcap` replay exists
- [x] Linux fixture generation exists
- [x] Linux fixture checking exists
- [x] normalized version 3 Linux captures preserve physical click state in frame-header flags
- [x] `doctor` checks XDG config, bundled keymap presence, live bindings, evdev accessibility, and `/dev/uinput` readiness
- [x] checked-in real Linux fixture coverage now exists for:
  - Bluetooth normal typing
  - Bluetooth reconnect churn
  - USB normal typing

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
- [x] Debian package skeleton exists
- [x] Arch local `PKGBUILD` skeleton exists
- [x] Debian package build script can produce a `.deb` from current publish outputs
- [x] package-manager install flow validated on the host
- [x] user-service flow validated on the host
- [x] packaged `glasstokey` / `glasstokey-gui` launcher flow validated on the host
- [x] dedicated `glasstokey` group permission flow validated on the host after relogin
- [x] packaged runtime survives reboot/session refresh with working evdev + `uinput` access

### GUI

- [x] Avalonia GUI shell exists
- [x] GUI can enumerate candidates and assign left/right devices
- [x] GUI can select layout preset
- [x] GUI can import/export the shared GlassToKey profile bundle shape (`Version` + `Settings` + `KeymapJson`)
- [x] GUI can run and display `doctor`
- [x] GUI has a first tray/top-bar shell via Avalonia `TrayIcon`
- [x] Tray-owned runtime lifecycle is separate from the config window
- [x] Normal config changes now flow through the XDG settings file and are reloaded in-process by the runtime owner
- [x] GUI now has a live input preview fed from the same tray-owned runtime stream used for typing
- [x] Tray now exposes `.atpcap` capture, replay, and summarize actions for desktop debugging, and replay now opens in the config visualizer with time-based playback controls
- [x] desktop source builds now default to an in-process tray-owned runtime instead of a GUI-controlled user service
- [x] GUI publishes self-contained cleanly
- [x] packaged `glasstokey-gui` launcher path now reopens the config UI cleanly from an existing tray-owned instance

## Remaining Work

### 1. Packaging and permission closure

These are the highest-priority productization tasks because they determine whether the current Linux runtime can be installed and operated reliably outside the dev shell.

- [x] Validate the dedicated `glasstokey` group flow end-to-end from a fresh install on the target Ubuntu session
- [x] Confirm reconnect behavior for packaged Bluetooth trackpads after node churn, not just in a dev shell
- [x] Confirm packaged `/dev/uinput` access and evdev access both survive reboot/login/logout cycles
- [x] Validate the checked-in `90-glasstokey.rules` against the currently supported Apple vendor/product pairs on the host and in packaged installs
- [x] Validate package-manager install flow (`.deb`) including user-service availability
- [x] Validate package-manager install flow (Arch package skeleton) including user-service availability
- [x] Validate `.deb` install, upgrade, and uninstall behavior
- [x] Decide the documented default install story: tray desktop by default, with `glasstokey start` / `glasstokey stop` as the documented headless path
- [x] Tighten post-install guidance once the real packaged flow is proven on host
- [x] Keep a documented and validated headless launch path as part of the final packaged Linux story
- [ ] Validate the checked-in Arch `PKGBUILD` install/runtime story on a real Arch test environment

### 2. GUI/product surface

The current GUI/service split proved useful for validation, but it is no longer the target desktop shape. The next work is to pivot Linux toward the Windows/macOS model where the tray app owns the runtime and opens the config window on demand.

- [x] Manually validate the tray/top-bar path on the target Ubuntu desktop
- [x] Implement the runtime-owner/config-UI split for the user-service path as an engineering checkpoint
- [x] Keep the config UI off the hotpath while still surfacing current settings and service state
- [x] Make normal config changes propagate through the runtime owner without restarting `systemd`
- [x] Add a first live trackpad visualizer so host debugging can distinguish input ingest from output/dispatch faults
- [x] Decide that Linux should pivot toward the Windows/macOS product model: tray app owns runtime, config opens on demand, CLI/service stays secondary
- [x] Move runtime ownership from the service/controller split into the Linux tray app by default
- [x] Replace the current second-reader preview/status hacks with direct runtime state exposed from the tray-owned runtime where practical
- [x] Keep the config window off the hotpath even when the tray app owns the runtime process
- [x] Preserve the reusable CLI/service runtime host as a supported headless mode while the tray app becomes the default desktop host
- [x] Keep rich runtime diagnostics CLI-first; the GUI should stay focused on settings, live preview, lightweight doctor visibility, and operator-facing actions
- [x] Put keymap editing in-scope for the Linux GUI now rather than deferring it out of v1
- [x] Polish the packaged GUI launcher path and desktop entry behavior enough for the current desktop packaging story
- [ ] Keep packaged GUI validation aligned with current source behavior during iteration

### 3. Runtime validation and regression depth

The live path works. The next gap is broader validation under the ways users will actually run it.

- [x] Add more Linux replay fixtures from real host captures covering both tested trackpad families and both USB/Bluetooth transport paths
- [x] Validate unplug/replug churn while `run-engine` is active for longer sessions
- [x] Validate the same churn under packaged wrapper/service execution, not just ad hoc runs
- [ ] Decide whether optional dispatch tracing is still worth adding as narrow CLI diagnostics for runtime misbehavior
- [x] Keep `.atpcap` as the primary long-form offline diagnostic artifact

### 4. Shared-core and semantic cleanup

The Linux path works, but shared extraction is still only partially complete in repo structure and shared semantics still coexist with Windows-VK compatibility.

Recommended first extraction slice:

- physically move the public layout/config/model files that are already shared in practice and do not require Windows-only host wiring:
  - `GridKeyPosition`
  - `KeyLayout`
  - `LayoutBuilder`
  - `TrackpadLayoutPreset`
  - `ColumnLayoutSettings`
  - `RuntimeConfigurationFactory`
  - `TrackpadDecoderProfile`
  - `UserSettings`
  - `KeymapStore`
  - `PtpReport`
  - `InputFrame`
  - `ForceNormalizer`
  - `ButtonEdgeTracker`
- then update Windows to reference those types from `GlassToKey.Core` instead of compiling the same files locally
- defer the internal engine/dispatch actor layer until after that first slice is stable:
  - `TouchProcessorFactory`
  - `TouchProcessorCore`
  - `DispatchEventQueue`
  - `DispatchEventPump`
  - related internal engine/dispatch helpers
- reason:
  - Windows still calls parts of the internal engine layer directly today, while the public layout/config/keymap/model layer is the lower-risk slice to move first

- [x] Continue moving shared engine/layout/keymap/runtime pieces toward `GlassToKey.Core`
- [x] Remove the linked-source bridge from the Windows app into `GlassToKey.Core` for shared code
- [ ] Keep `GlassToKey.Core` dependency-clean and Linux/Windows consumable
- [ ] Reduce remaining shared-flow dependence on Windows virtual-key compatibility where semantic actions should be authoritative
- [ ] Decide how much replay/self-test infrastructure should live directly in `GlassToKey.Core` versus remain host-owned
- [ ] Keep Windows behavior unchanged while that cleanup proceeds
- [x] Windows now consumes `GlassToKey.Core` as the canonical shared implementation through a project reference
- [x] Keep Windows as the single `GlassToKey.Windows` app project for now; do not split into `GlassToKey.Platform.Windows` or `GlassToKey.Windows.Host` unless a future need justifies it

### 5. Linux v1 parity decisions still deferred

These are intentionally not blocking the current packaging/productization push, but they remain open product decisions.

- [ ] Decide whether Linux v1 ships mixed-mode only or also attempts keyboard-mode suppression
- [ ] If keyboard-mode suppression is pursued, prototype `EVIOCGRAB` with strict crash/exit safety and clear operator expectations
- [ ] Decide whether Linux force-click parity remains disabled or whether a Linux-specific calibrated pressure path is worth building later
- [ ] Investigate Magic Trackpad haptics only after the typing/runtime path is productized

## Next Milestone Checklist

### Milestone A: desktop product validation

- [x] Manually validate the tray/top-bar desktop path on the target Ubuntu session
- [x] Confirm the packaged GUI launcher and desktop entry behave the same way as the current source-level tray runtime
- [x] Keep rich runtime diagnostics in the CLI; leave the GUI focused on config, live preview, doctor visibility, and operator-facing actions
- [x] Confirm keymap editing is in-scope for the GUI now

Exit criteria:

- the tray-owned desktop runtime is the clearly documented default Linux desktop story
- packaged GUI behavior matches current source behavior closely enough to stop treating it as provisional

### Milestone B: packaging closure

- [x] Validate `.deb` install, upgrade, and uninstall behavior
- [x] Decide the documented default install mode for first users: tray desktop by default, with CLI `start` / `stop` documented for headless runs
- [x] Tighten post-install guidance around `doctor`, `init-config`, `show-config`, `load-keymap`, `start`, `stop`, direct `run-engine` smoke tests, and optional service enablement
- [x] Keep a documented and validated headless launch path as part of the final packaged Linux story
- [ ] Validate and document the first Arch install/package flow from `packaging/linux/arch/`

Exit criteria:

- a fresh install path is documented and validated for both desktop and headless use
- the `.deb` flow is proven, not just the raw install script

### Milestone C: cleanup after product closure

- [ ] Keep extending the Linux fixture set as regression coverage
- [x] Continue moving shared engine/layout/keymap/runtime pieces into `GlassToKey.Core`
- [x] Remove the linked-source bridge from the Windows app into `GlassToKey.Core`
- [ ] Reduce remaining shared-flow dependence on Windows virtual-key compatibility where semantic actions should be authoritative
- [x] Keep Windows as one top-level `GlassToKey.Windows` app project; do not split further unless a future need justifies it
- [ ] Only then return to deferred Linux parity work like keyboard suppression, force-click parity, or haptics

## README Follow-Ups

- `packaging/linux/README.md`: keep desktop packaging guidance centered on the tray-owned GUI runtime, with the user service described as the optional headless/background path and `glasstokey start` / `stop` documented as the direct headless path
- `GlassToKey.Linux/README.md`: keep a short direct-run section covering `doctor`, `init-config`, `show-config`, `load-keymap`, `start`, `stop`, and `run-engine`
- `GlassToKey.Linux.Gui/README.md`: keep the current scope aligned with the tray-owned desktop runtime, GUI keymap editing being in scope, and rich diagnostics remaining CLI-first
- `GlassToKey.Core/README.md`: update when the linked-source bridge starts shrinking materially, not just when Linux adds features
- `AGENTS.md`: update after Linux packaging defaults or desktop/headless workflow expectations change

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

### Arch local package build

- `sudo pacman -S --needed base-devel dotnet-sdk`
- `cd packaging/linux/arch`
- `makepkg -f`

## Doc Rule

If Linux scope, status, or packaging reality changes:

- update this file first
- then update `AGENTS.md`
- keep project/package READMEs short and local to their project surface

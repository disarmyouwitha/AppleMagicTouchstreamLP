# AGENTS

## Scope
- This file is for the `windows_linux/` working folder only.
- When Codex is opened from `windows_linux/`, default to this folder's build targets and source tree.
- Do not treat sibling folders such as `../mac/` as in-scope unless the user explicitly asks.

## Default Targets
- Primary production target: `GlassToKey/GlassToKey.csproj`
- Migration targets: `GlassToKey.Core/GlassToKey.Core.csproj`, `GlassToKey.Platform.Linux/GlassToKey.Platform.Linux.csproj`, `GlassToKey.Linux.Host/GlassToKey.Linux.Host.csproj`, `GlassToKey.Linux/GlassToKey.Linux.csproj`
- Current reality: the Windows app in `GlassToKey/` is the only feature-complete implementation here today.

## Current State
- `GlassToKey/` is the active Windows host. It targets `net10.0-windows` with WPF and WinForms enabled.
- `GlassToKey.Core/` now includes shared input/dispatch primitives, the extracted engine/layout/keymap path, a shared `TrackpadFrameEnvelope` / `ITrackpadFrameTarget` seam, and `TouchProcessorRuntimeHost` as a public wrapper around the internal actor/dispatch pipeline.
- `GlassToKey.Platform.Linux/` now has preferred Apple `if01` device selection, raw evdev capture, real `EVIOCGABS` axis/range probing, an evdev-to-`InputFrame` assembler, a runtime service that can stream directly into a shared frame target, runtime-side stable-id rebind/reconnect supervision for unplug/replug churn, a `LinuxUinputDispatcher`, and a semantics-first Linux key mapper that resolves semantic codes to evdev output before falling back to Windows VK compatibility.
- `GlassToKey.Linux.Host/` now carries the reusable Linux XDG settings/config/runtime layer plus the `doctor` runner so the CLI and GUI can share one host surface without the GUI referencing the CLI executable project.
- `GlassToKey.Linux/` is now a minimal CLI host. `Program.cs` supports `list-devices`, `probe-axes`, `probe-uinput`, `doctor`, `show-config`, `init-config`, `print-udev-rules`, `selftest`, `capture-atpcap`, `replay-atpcap`, `summarize-atpcap`, `write-atpcap-fixture`, `check-atpcap-fixture`, `uinput-smoke`, `read-events`, `read-frames`, `watch-runtime`, and `run-engine`. It now uses an XDG-backed settings file for stable-id device selection, layout preset selection, and optional keymap-path override through `GlassToKey.Linux.Host`. The Linux host also now ships its own bundled `GLASSTOKEY_DEFAULT_KEYMAP.json` instead of copying the Windows default, and the embedded bundled `KeymapJson` has been translated so Linux no longer ships Windows-only `EMOJI`, `LWin`, or `Win+H` defaults by accident. `run-engine` has been validated end-to-end on the current Ubuntu 24.04 host with both tested Apple Magic Trackpads. Checked-in publish profiles now cover framework-dependent and self-contained `linux-x64` publishes, and the checked-in install script now supports wrapper-vs-service install decisions with better post-install guidance.
- `GlassToKey.Linux.Gui/` now exists as an early Avalonia control shell on top of the same XDG-backed Linux host settings used by the CLI. It now supports device assignment, preset selection, keymap browse/clear, and an in-app `doctor` report. GUI publish now works both framework-dependent and self-contained.

## What To Build
- For Windows app work, target `GlassToKey/GlassToKey.csproj`.
- For shared extraction work, target `GlassToKey.Core/GlassToKey.Core.csproj`.
- For Linux backend work, target `GlassToKey.Platform.Linux/GlassToKey.Platform.Linux.csproj` and `GlassToKey.Linux/GlassToKey.Linux.csproj`. There is now runnable Linux behavior, but it is still an engineering host rather than a packaged end-user app.

## Build Commands
- Windows app build:
  - `dotnet build GlassToKey/GlassToKey.csproj -c Release`
- Windows app self-test:
  - `dotnet run --project GlassToKey/GlassToKey.csproj -c Release -- --selftest`
- Shared/Linux builds:
  - `dotnet build GlassToKey.Core/GlassToKey.Core.csproj -c Release`
  - `dotnet build GlassToKey.Platform.Linux/GlassToKey.Platform.Linux.csproj -c Release`
  - `dotnet build GlassToKey.Linux.Host/GlassToKey.Linux.Host.csproj -c Release`
  - `dotnet build GlassToKey.Linux/GlassToKey.Linux.csproj -c Release`
  - `dotnet build GlassToKey.Linux.Gui/GlassToKey.Linux.Gui.csproj -c Release`
- Linux device probe:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- list-devices`
- Linux raw evdev probe:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- read-events /dev/input/eventN 10 120`
- Linux frame probe:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- read-frames /dev/input/eventN 10 24`
- Linux axis/range probe:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- probe-axes /dev/input/eventN`
- Linux uinput readiness probe:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- probe-uinput`
- Linux doctor:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- doctor`
- Linux host config display:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- show-config`
- Linux host config init:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- init-config`
- Linux packaged permission rule output:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- print-udev-rules`
- Linux host self-test:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- selftest`
- Linux `.atpcap` capture:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- capture-atpcap /tmp/capture.atpcap 10`
- Linux `.atpcap` replay:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- replay-atpcap /tmp/capture.atpcap /tmp/replay-trace.json`
- Linux `.atpcap` summary:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- summarize-atpcap /tmp/capture.atpcap`
- Linux `.atpcap` fixture write:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- write-atpcap-fixture /tmp/capture.atpcap /tmp/capture.fixture.json`
- Linux `.atpcap` fixture check:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- check-atpcap-fixture /tmp/capture.atpcap /tmp/capture.fixture.json /tmp/replay-trace.json`
- Linux uinput smoke test:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- uinput-smoke A B Enter`
- Linux runtime watch:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- watch-runtime 10`
- Linux engine runtime:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- run-engine 10`
- Linux framework-dependent publish:
  - `dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxFrameworkDependent`
- Linux self-contained publish:
  - `dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxSelfContained`
- Linux GUI framework-dependent publish:
  - `dotnet publish GlassToKey.Linux.Gui/GlassToKey.Linux.Gui.csproj -c Release -p:PublishProfile=LinuxGuiFrameworkDependent`
- Linux GUI self-contained publish:
  - `dotnet publish GlassToKey.Linux.Gui/GlassToKey.Linux.Gui.csproj -c Release -p:PublishProfile=LinuxGuiSelfContained`
- Linux Debian skeleton build:
  - `bash packaging/linux/deb/build-deb.sh --version 0.1.0-dev --output-dir /tmp/glasstokey-deb-out`
- In the current Ubuntu 24.04 shell, the three Linux-targeted build commands above were verified.
- Run overlapping `dotnet build` / `dotnet publish` commands for the same project graph sequentially. Parallel publishes can collide in shared `bin/` / `obj/` paths.

## Directory Map
- `GlassToKey/`: Windows runtime, WPF UI, Raw Input, dispatch, replay, diagnostics, tray behavior.
- `GlassToKey/Core/Engine/`: best first candidates for shared extraction.
- `GlassToKey/Core/Dispatch/`: shared model seams plus Windows-specific `SendInput` implementation.
- `GlassToKey/Core/Diagnostics/`: replay, capture, raw analysis, and self-test infrastructure.
- `GlassToKey.Core/`: future platform-neutral engine/library.
- `GlassToKey.Platform.Linux/`: Linux device enumeration, evdev/uinput backend in progress.
- `GlassToKey.Linux.Host/`: shared Linux host/config/runtime and doctor layer used by both CLI and GUI.
- `GlassToKey.Linux/`: Linux CLI host and early packaging/publish surface.
- `GlassToKey.Linux.Gui/`: early Linux GUI control shell for device binding, keymap selection, and diagnostics.
- `LINUX_PROJECT_SKELETON.md`, `LINUX_VERSION.md`, `LINUX_EVDEV_MAPPING.md`: planning docs for the migration.

## Important Boundaries
- Keep Windows-only code in `GlassToKey/`: WPF, WinForms, Raw Input, `SendInput`, click suppression, tray/startup UI, Windows haptics.
- Keep `GlassToKey.Core/` free of WPF, WinForms, Raw Input, `SendInput`, `evdev`, and `uinput`.
- Linux work should consume platform-neutral models or semantics, not Windows virtual-key assumptions.
- `DispatchKeyResolver.cs` is a known split point because Linux needs semantic actions or evdev key codes rather than Windows VK mappings. The current engine/dispatch path now carries `DispatchSemanticAction` metadata alongside Windows VK fields, so new Linux output work should build on that semantic payload instead of adding more VK-only assumptions.
- For hot paths, prefer precomputed code tables and fixed-size state arrays. The Linux `uinput` dispatcher now resolves semantic codes to evdev codes first and tracks repeat/modifier state by resolved Linux key code in the pump loop.
- Linux evdev reality on the current Ubuntu hardware: Apple trackpads can expose Type B multitouch slot events and parallel legacy absolute events on the same node. Do not assume slot-only traffic.
- `EVIOCGABS` works on the real device and currently reports `slot 0..15`, `X -3678..3934`, `Y -2478..2587`, and pressure `0..253` on both tested trackpad families here. Linux code should normalize coordinates by subtracting axis minima, yielding the expected spans `MaxX=7612` and `MaxY=5065`. It may still fail inside the sandboxed coding environment even when normal event reads succeed. Treat that as a sandbox artifact first, not immediately as a driver limitation.
- When Apple exposes multiple event interfaces for one physical trackpad, prefer the `-if01-event-mouse` node. On the tested Lightning trackpad, `event22` (`if01`) carried the real multitouch stream while `event21` was inactive during touch capture.
- Over Bluetooth, `/dev/input/by-id` is not present for the tested Apple trackpads. Use the device `uniq` value as the stable-id fallback there.
- The tested Bluetooth nodes were `/dev/input/event10` (older trackpad) and `/dev/input/event13` (USB-C trackpad). Both validated with the same `EVIOCGABS` ranges and the same normalized frame path as USB.
- The Linux host now uses an XDG-backed settings file for stable-id device selection. `show-config` was validated with `XDG_CONFIG_HOME=/tmp/...` and resolved the Bluetooth trackpads by `uniq`.
- Linux and Windows are now allowed to ship different bundled default keymaps as long as they keep the shared keymap schema and action vocabulary intact. `GlassToKey.Linux/GLASSTOKEY_DEFAULT_KEYMAP.json` is now the Linux host default.
- The Linux bundled default now resolves `VOL_UP`, `VOL_DOWN`, `BRIGHT_UP`, and `BRIGHT_DOWN` through semantic codes and Linux evdev mappings instead of depending on Windows-VK fallback.
- The Linux `run-engine` command has now been validated end-to-end on the host: evdev input -> shared engine host -> dispatch pump -> `uinput` output into a real focused app.
- `print-udev-rules` now emits a targeted packaging template for the currently detected Apple trackpad vendor/product pairs plus `/dev/uinput`.
- `GlassToKey.Linux selftest` now validates the bundled Linux keymap import path, rejects stray Windows-only bundled labels, and checks semantic-to-evdev coverage for the current Linux action surface.
- The repo now carries checked-in Linux publish profiles for framework-dependent and self-contained `linux-x64` publishes, plus a first Debian package skeleton.
- The repo now also carries self-contained GUI publish support and a reusable `GlassToKey.Linux.Host` library so CLI and GUI share one Linux host/config surface.
- `packaging/linux/` now contains checked-in Linux install artifacts, plus a first Debian package skeleton under `packaging/linux/deb/`.
- Linux now has a first `.atpcap` capture/replay path based on version 3 normalized frame captures, plus a `doctor` command for post-install evdev/`uinput`/config health checks.
- Linux `.atpcap` version 3 capture now preserves physical click state in the frame header flags while staying in the shared normalized v3 payload shape.
- Linux now also has fixture generation and fixture checking commands so `.atpcap` captures can be regression-checked, not just replayed.
- The Linux runtime now supervises bindings by stable ID and can re-open a trackpad stream after device-node churn while the process stays alive.
- Dispatch tracing for `run-engine` is optional diagnostic tooling, not a product requirement. It can help debug bindings or timing issues, but future `.atpcap` capture remains the better long-form artifact for deeper offline analysis.

## Key Files
- `GlassToKey/TouchRuntimeService.cs`: current Windows hot path and runtime host.
- `GlassToKey/RawInputInterop.cs`: Windows input ingestion.
- `GlassToKey/Core/Dispatch/SendInputDispatcher.cs`: Windows output injection.
- `GlassToKey/Core/Engine/TouchProcessorCore.cs`: likely shared extraction target.
- `GlassToKey/Core/Diagnostics/SelfTestRunner.cs`: local deterministic Windows-side self-tests.
- `GlassToKey/KeymapStore.cs`, `GlassToKey/LayoutBuilder.cs`, `GlassToKey/KeyLayout.cs`: likely shared-model candidates.

## Working Rules
- Preserve current Windows behavior while extracting shared code.
- Be explicit about implemented code versus design docs. The Linux markdown files describe the intended shape, not a finished port.
- Treat touch processing as latency-sensitive. Avoid allocations, logging, and file I/O on hot paths.
- If device probing needs an unsandboxed `ioctl` or other direct host access to resolve Linux behavior, request escalation instead of assuming the kernel or driver is broken.
- The current sandbox can still block `EVIOCGABS` during live `watch-runtime` validation even when the same command works on the host. Treat that as an environment validation issue, not a product requirement for fallback logic.
- The user has stated they will approve out-of-sandbox access when needed for Linux device validation. Still request escalation normally so the action is explicit.
- If the user asks to "build" from this folder without more detail, prefer the target most relevant to the touched code:
  - `GlassToKey/GlassToKey.csproj` for current app behavior
  - one of the Linux/shared projects if the change is confined there
- Keep this file aligned with `GlassToKey/AGENTS.md` when Windows workflows or architecture shift.

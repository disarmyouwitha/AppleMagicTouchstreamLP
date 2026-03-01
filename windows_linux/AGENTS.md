# AGENTS

## Scope
- This file is for the `windows_linux/` working folder only.
- When Codex is opened from `windows_linux/`, default to this folder's build targets and source tree.
- Do not treat sibling folders such as `../mac/` as in-scope unless the user explicitly asks.

## Default Targets
- Primary production target: `GlassToKey/GlassToKey.csproj`
- Migration targets: `GlassToKey.Core/GlassToKey.Core.csproj`, `GlassToKey.Platform.Linux/GlassToKey.Platform.Linux.csproj`, `GlassToKey.Linux/GlassToKey.Linux.csproj`
- Current reality: the Windows app in `GlassToKey/` is the only feature-complete implementation here today.

## Current State
- `GlassToKey/` is the active Windows host. It targets `net10.0-windows` with WPF and WinForms enabled.
- `GlassToKey.Core/` has started shared extraction for input/dispatch primitives and now exposes a shared `TrackpadFrameEnvelope` / `ITrackpadFrameTarget` seam for posting normalized frames toward the engine path.
- `GlassToKey.Platform.Linux/` now has preferred Apple `if01` device selection, raw evdev capture, real `EVIOCGABS` axis/range probing, an initial evdev-to-`InputFrame` assembler, a runtime service that can stream directly into a shared frame target, and a first `uinput` readiness probe. Real `uinput` injection is not implemented yet.
- `GlassToKey.Linux/` is now a minimal CLI host. `Program.cs` supports `list-devices`, `probe-axes`, `probe-uinput`, `read-events`, `read-frames`, and `watch-runtime`, and shared project references are enabled by default.

## What To Build
- For Windows app work, target `GlassToKey/GlassToKey.csproj`.
- For shared extraction work, target `GlassToKey.Core/GlassToKey.Core.csproj`.
- For Linux backend work, target `GlassToKey.Platform.Linux/GlassToKey.Platform.Linux.csproj` and `GlassToKey.Linux/GlassToKey.Linux.csproj`, but do not assume there is runnable Linux behavior yet.

## Build Commands
- Windows app build:
  - `dotnet build GlassToKey/GlassToKey.csproj -c Release`
- Windows app self-test:
  - `dotnet run --project GlassToKey/GlassToKey.csproj -c Release -- --selftest`
- Shared/Linux builds:
  - `dotnet build GlassToKey.Core/GlassToKey.Core.csproj -c Release`
  - `dotnet build GlassToKey.Platform.Linux/GlassToKey.Platform.Linux.csproj -c Release`
  - `dotnet build GlassToKey.Linux/GlassToKey.Linux.csproj -c Release`
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
- Linux runtime watch:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- watch-runtime 10`
- In the current Ubuntu 24.04 shell, the three Linux-targeted build commands above were verified.

## Directory Map
- `GlassToKey/`: Windows runtime, WPF UI, Raw Input, dispatch, replay, diagnostics, tray behavior.
- `GlassToKey/Core/Engine/`: best first candidates for shared extraction.
- `GlassToKey/Core/Dispatch/`: shared model seams plus Windows-specific `SendInput` implementation.
- `GlassToKey/Core/Diagnostics/`: replay, capture, raw analysis, and self-test infrastructure.
- `GlassToKey.Core/`: future platform-neutral engine/library.
- `GlassToKey.Platform.Linux/`: Linux device enumeration, evdev/uinput backend in progress.
- `GlassToKey.Linux/`: Linux CLI host in progress.
- `LINUX_PROJECT_SKELETON.md`, `LINUX_VERSION.md`, `LINUX_EVDEV_MAPPING.md`: planning docs for the migration.

## Important Boundaries
- Keep Windows-only code in `GlassToKey/`: WPF, WinForms, Raw Input, `SendInput`, click suppression, tray/startup UI, Windows haptics.
- Keep `GlassToKey.Core/` free of WPF, WinForms, Raw Input, `SendInput`, `evdev`, and `uinput`.
- Linux work should consume platform-neutral models or semantics, not Windows virtual-key assumptions.
- `DispatchKeyResolver.cs` is a known split point because Linux needs semantic actions or evdev key codes rather than Windows VK mappings. The current engine/dispatch path now carries `DispatchSemanticAction` metadata alongside Windows VK fields, so new Linux output work should build on that semantic payload instead of adding more VK-only assumptions.
- Linux evdev reality on the current Ubuntu hardware: Apple trackpads can expose Type B multitouch slot events and parallel legacy absolute events on the same node. Do not assume slot-only traffic.
- `EVIOCGABS` works on the real device and currently reports `slot 0..15`, `X -3678..3934`, `Y -2478..2587`, and pressure `0..253` on both tested trackpad families here. Linux code should normalize coordinates by subtracting axis minima, yielding the expected spans `MaxX=7612` and `MaxY=5065`. It may still fail inside the sandboxed coding environment even when normal event reads succeed. Treat that as a sandbox artifact first, not immediately as a driver limitation.
- When Apple exposes multiple event interfaces for one physical trackpad, prefer the `-if01-event-mouse` node. On the tested Lightning trackpad, `event22` (`if01`) carried the real multitouch stream while `event21` was inactive during touch capture.
- Over Bluetooth, `/dev/input/by-id` is not present for the tested Apple trackpads. Use the device `uniq` value as the stable-id fallback there.
- The tested Bluetooth nodes were `/dev/input/event10` (older trackpad) and `/dev/input/event13` (USB-C trackpad). Both validated with the same `EVIOCGABS` ranges and the same normalized frame path as USB.

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

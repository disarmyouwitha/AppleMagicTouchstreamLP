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
- `GlassToKey.Core/` has started shared extraction for low-dependency input/dispatch primitives. Engine extraction has not started yet.
- `GlassToKey.Platform.Linux/` now has candidate device enumeration and an initial evdev slot-to-`InputFrame` assembler. Live event reads and `uinput` output are not implemented yet.
- `GlassToKey.Linux/` is now a minimal CLI host. `Program.cs` supports `list-devices`, and shared project references are enabled by default.

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
- `DispatchKeyResolver.cs` is a known split point because Linux needs semantic actions or evdev key codes rather than Windows VK mappings.

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
- If the user asks to "build" from this folder without more detail, prefer the target most relevant to the touched code:
  - `GlassToKey/GlassToKey.csproj` for current app behavior
  - one of the Linux/shared projects if the change is confined there
- Keep this file aligned with `GlassToKey/AGENTS.md` when Windows workflows or architecture shift.

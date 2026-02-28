# AGENTS

## Project Summary
- This directory is the transition workspace for moving GlassToKey from a Windows-only app into a shared `windows_linux` layout.
- The active, feature-complete product still lives in `GlassToKey/`.
- `GlassToKey.Core/`, `GlassToKey.Platform.Linux/`, and `GlassToKey.Linux/` are present, but they are scaffold-stage projects rather than functional ports.
- Treat the repo as "Windows production code plus shared/Linux migration skeleton", not as a finished dual-platform implementation.

## Current Truth
- `GlassToKey/GlassToKey.csproj` is the real app host today. It targets `net10.0-windows` and enables WPF/WinForms.
- `GlassToKey.Core/CoreProjectMarker.cs` states: `Scaffold only. Shared engine extraction not started.`
- `GlassToKey.Platform.Linux/LinuxPlatformMarker.cs` states: `Scaffold only. Linux backend implementation not started.`
- `GlassToKey.Linux/Program.cs` is a placeholder entry point that prints a scaffold-only message.
- `GlassToKey.Linux/GlassToKey.Linux.csproj` keeps its shared project references behind `EnableSharedPortReferences=false`.

## Repository Map
- `GlassToKey/`: active Windows app, runtime, UI, dispatch, replay, capture, and diagnostics.
- `GlassToKey.Core/`: intended shared engine/library target for extracted platform-neutral logic.
- `GlassToKey.Platform.Linux/`: intended Linux backend for evdev/uinput/device handling.
- `GlassToKey.Linux/`: intended Linux host process and future config/runtime entry point.
- `LINUX_PROJECT_SKELETON.md`: extraction plan and ownership boundaries.
- `LINUX_VERSION.md`: Linux feasibility, architecture, and porting strategy.
- `LINUX_EVDEV_MAPPING.md`: target mapping from Linux evdev frames into the existing input model.
- `MY_KEYMAP.json`, `hi.atpcap`: local sample artifacts for keymap/capture work.

## Ownership Boundaries
- Keep Windows-specific code in `GlassToKey/` for now: WPF, Raw Input, `SendInput`, click suppression, startup registration, tray UI, Windows haptics.
- Move only platform-neutral behavior into `GlassToKey.Core/`: engine logic, frame/contact models, layout math, keymap model, replay/test logic, semantic actions.
- Put Linux-only systems work in `GlassToKey.Platform.Linux/`: evdev ingestion, device identity, reconnect handling, permissions, `uinput` output.
- Keep `GlassToKey.Linux/` thin. It should host startup, settings, device selection, diagnostics surfacing, and wiring only.
- Do not let Linux code depend on Windows virtual-key assumptions. `DispatchKeyResolver.cs` is a known split point because Linux needs semantic actions or evdev key codes instead of Windows VKs.

## Important Files
- `GlassToKey/TouchRuntimeService.cs`: current Windows hot-path runtime host.
- `GlassToKey/RawInputInterop.cs`: Windows Raw Input interop layer.
- `GlassToKey/Core/Engine/*`: strongest first candidates for shared extraction.
- `GlassToKey/Core/Dispatch/DispatchModels.cs`: dispatch model that should become shared.
- `GlassToKey/Core/Dispatch/IInputDispatcher.cs`: interface seam for platform output backends.
- `GlassToKey/Core/Dispatch/SendInputDispatcher.cs`: Windows-only output implementation.
- `GlassToKey/Core/Diagnostics/*`: replay/self-test/capture code worth preserving through the migration.
- `GlassToKey/KeymapStore.cs`, `GlassToKey/LayoutBuilder.cs`, `GlassToKey/KeyLayout.cs`: likely shared-model candidates.

## Working Agreements
- Preserve the current Windows app behavior while extracting shared code. Do not break the existing tray/runtime flow just to improve future Linux shape.
- Be explicit about what is implemented versus planned. The Linux docs are design guidance, not proof that the port exists yet.
- Keep hot-path code allocation-conscious. The Windows runtime already treats per-frame processing as latency-sensitive.
- Do not put `WPF`, `WinForms`, Raw Input, `SendInput`, `evdev`, or `uinput` dependencies into `GlassToKey.Core/`.
- When touching migration seams, prefer small extraction steps with unchanged behavior over large reorganizations.
- Update docs when the architecture changes. At minimum, keep this file, `GlassToKey/AGENTS.md`, and the Linux planning docs aligned.

## Build And Test Notes
- There is no `.sln` file in this directory today. Work is project-based.
- Documented Windows build command:
  - `dotnet build GlassToKey/GlassToKey.csproj -c Release`
- Documented Windows self-test command:
  - `dotnet run --project GlassToKey/GlassToKey.csproj -c Release -- --selftest`
- Likely scaffold build commands for shared/Linux projects:
  - `dotnet build GlassToKey.Core/GlassToKey.Core.csproj -c Release`
  - `dotnet build GlassToKey.Platform.Linux/GlassToKey.Platform.Linux.csproj -c Release`
  - `dotnet build GlassToKey.Linux/GlassToKey.Linux.csproj -c Release`
- In this environment, `dotnet` was not installed, so those commands were not verified here.
- Expect the Windows host to require a Windows machine with the .NET 10 SDK; Linux implementation work will additionally need Linux-specific runtime validation once real code exists.

## Runtime And Data Notes
- Windows runtime artifacts are currently documented under `GlassToKey/README.md`:
  - `settings.json` beside the app
  - `%LOCALAPPDATA%\GlassToKey\keymap.json`
  - `%LOCALAPPDATA%\GlassToKey\runtime-errors.log`
- Capture files use the `ATPCAP01` family handled by `GlassToKey/Core/Diagnostics/InputCaptureFile.cs`.
- Replay, fixture generation, and raw analysis are already Windows-side workflows worth preserving during extraction.

## Git And Workspace Notes
- This directory may be part of a larger repo that also contains sibling platform folders such as `../mac/`.
- `git status` run from here can show changes outside `windows_linux/`; do not revert unrelated sibling-platform work.
- When adding migration files, prefer repo-level guidance here and keep host-specific guidance in `GlassToKey/AGENTS.md`.

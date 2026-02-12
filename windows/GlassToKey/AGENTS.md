# AGENTS

## Project Summary
- **GlassToKey app path:** `GlassToKey` is the active app. Live mode runs as a tray/status app that reads touchpad report `0x05` via Raw Input and drives keyboard mapping logic in the background.
- **Core intent:** Keep OS mouse/gesture behavior intact in mixed mode while mapping selected touch intents to keys. In keyboard mode, global mouse clicks are swallowed outside the visualizer process.

## Repository Map
- `GlassToKey/`: WPF visualizer + touch processor engine + diagnostics (capture/replay/self-test).
- `GlassToKey/fixtures/replay/`: deterministic replay smoke capture and fixture JSON.
- `README.md`: project-level workflows and runtime flags for the visualizer.
- `AGENTS.md`: contributor guidance and operational commands.

## Key Files & Responsibilities
- `GlassToKey/PtpReport.cs`: zero-allocation parser for touchpad report payloads.
- `GlassToKey/TouchRuntimeService.cs`: hot-path runtime host (WM_INPUT routing, touch actor, key dispatch, click suppression).
- `GlassToKey/StatusTrayController.cs`: tray icon/menu actions (`Config...`, separator, `Capture`, `Replay`, separator, `Restart`, `Exit`) and config launch flow.
- `GlassToKey/RuntimeObserverContracts.cs`: read-only observer contracts for runtime frame mirroring and tray mode indication.
- `GlassToKey/StartupRegistration.cs`: startup-on-login registration via HKCU Run key.
- `GlassToKey/MainWindow.xaml.cs`: secondary visualizer/config UI (settings, keymap, replay UI).
- `GlassToKey/RuntimeConfigurationFactory.cs`: shared layout/config builders for runtime + config UI.
- `GlassToKey/KeymapStore.cs`: layout-scoped keymap/custom-button persistence (`6x3`, `6x4`, etc.) across layers/sides.
- `GlassToKey/Core/Engine/*`: touch processor state machine and key-binding resolution.
- `GlassToKey/Core/Diagnostics/*`: capture format, replay runner, metrics, and self-tests.

## Working Agreements
- **Build environment:** Visual Studio 2022/2023 + WDK for driver work; .NET 10 SDK for `GlassToKey` (`net10.0-windows`).
- **EFFICIENCY** Always write the most performant and efficient code to turn an Apple Magic Trackpad into a keyboard with an emphasis on running in the background as a status app and instant key detection.
- **Hot-path discipline:** No avoidable allocations, logging spam, or file I/O in per-frame processing paths.
- **Touch policy:** Visualizer intentionally renders tip contacts only (`TipSwitch=true`) to avoid hover artifacts.
- **Documentation:** Keep `README.md` and this file in sync when flags, report formats, workflow commands, or architecture change.

## Common Workflows
1. **Build visualizer (Release):**
   ```powershell
   dotnet build .\tools\GlassToKey\GlassToKey.csproj -c Release
   ```

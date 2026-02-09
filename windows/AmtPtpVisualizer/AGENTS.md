# AGENTS

## Project Summary
- **GlassToKey app path:** `AmtPtpVisualizer` is the active app. Live mode runs as a tray/status app that reads touchpad report `0x05` via Raw Input and drives keyboard mapping logic in the background.
- **Core intent:** Keep OS mouse/gesture behavior intact in mixed mode while mapping selected touch intents to keys. In keyboard mode, global mouse clicks are swallowed outside the visualizer process.

## Repository Map
- `AmtPtpVisualizer/`: WPF visualizer + touch processor engine + diagnostics (capture/replay/self-test).
- `AmtPtpVisualizer/fixtures/replay/`: deterministic replay smoke capture and fixture JSON.
- `README.md`: project-level workflows and runtime flags for the visualizer.
- `AGENTS.md`: contributor guidance and operational commands.

## Key Files & Responsibilities
- `AmtPtpVisualizer/PtpReport.cs`: zero-allocation parser for touchpad report payloads.
- `AmtPtpVisualizer/TouchRuntimeService.cs`: hot-path runtime host (WM_INPUT routing, touch actor, key dispatch, click suppression).
- `AmtPtpVisualizer/StatusTrayController.cs`: tray icon/menu and config window launch flow.
- `AmtPtpVisualizer/RuntimeObserverContracts.cs`: read-only observer contracts for runtime frame mirroring and tray mode indication.
- `AmtPtpVisualizer/StartupRegistration.cs`: startup-on-login registration via HKCU Run key.
- `AmtPtpVisualizer/MainWindow.xaml.cs`: secondary visualizer/config UI (settings, keymap, replay UI).
- `AmtPtpVisualizer/RuntimeConfigurationFactory.cs`: shared layout/config builders for runtime + config UI.
- `AmtPtpVisualizer/KeymapStore.cs`: layout-scoped keymap/custom-button persistence (`6x3`, `6x4`, etc.) across layers/sides.
- `AmtPtpVisualizer/Core/Engine/*`: touch processor state machine and key-binding resolution.
- `AmtPtpVisualizer/Core/Diagnostics/*`: capture format, replay runner, metrics, and self-tests.

## Working Agreements
- **Build environment:** Visual Studio 2022/2023 + WDK for driver work; .NET 6 SDK for `AmtPtpVisualizer` (`net6.0-windows`).
- **EFFICIENCY** Always write the most performant and efficient code to turn an Apple Magic Trackpad into a keyboard with an emphasis on running in the background as a status app and instant key detection.
- **Hot-path discipline:** No avoidable allocations, logging spam, or file I/O in per-frame processing paths.
- **Touch policy:** Visualizer intentionally renders tip contacts only (`TipSwitch=true`) to avoid hover artifacts.
- **Documentation:** Keep `README.md` and this file in sync when flags, report formats, workflow commands, or architecture change.

## Common Workflows
1. **Build visualizer (Release):**
   ```powershell
   dotnet build .\tools\AmtPtpVisualizer\AmtPtpVisualizer.csproj -c Release
   ```

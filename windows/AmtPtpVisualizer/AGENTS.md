# AGENTS

## Project Summary
- **Magic Trackpad 2 driver stack:** `AmtPtpDeviceUsbUm` (UMDF USB driver) and `AmtPtpControlPanel` (WinForms installer/configuration tool) provide precision-touch HID reports on Windows.
- **GlassToKey app path:** `tools/AmtPtpVisualizer` is the active app that reads touchpad report `0x05` via Raw Input, visualizes contacts, and drives keyboard mapping logic.
- **Core intent:** Keep OS mouse/gesture behavior intact while mapping selected touch intents to keys. The kernel driver already emits `PTP_REPORT`, so most iteration is user-mode.

## Repository Map
- `.github/workflows/build.yml`: CI reference for NuGet restore + `msbuild` packaging of driver/control-panel artifacts.
- `AmtPtpDeviceUsbUm/`: C/C++ driver stack, HID descriptor/report definitions, and input parsing.
- `AmtPtpControlPanel/`: .NET 6 WinForms driver installer/replacement utility with ACL/privilege handling.
- `tools/AmtPtpVisualizer/`: WPF visualizer + touch processor engine + diagnostics (capture/replay/self-test).
- `tools/AmtPtpVisualizer/fixtures/replay/`: deterministic replay smoke capture and fixture JSON.
- `README.md`: project-level workflows and runtime flags for the visualizer.
- `AGENTS.md`: contributor guidance and operational commands.

## Key Files & Responsibilities
- `AmtPtpDeviceUsbUm/Device.c` + `AmtPtpDeviceUsbUm/Queue.c`: device interface/queue wiring and HID report read flow.
- `AmtPtpDeviceUsbUm/InputInterrupt.c`: converts USB interrupts into `PTP_REPORT` contact packets.
- `AmtPtpDeviceUsbUm/include/Hid.h`: `PTP_REPORT`/`PTP_CONTACT` structures and report IDs.
- `AmtPtpControlPanel/Main.cs`: driver swap/install path (ownership, ACL, privilege elevation).
- `tools/AmtPtpVisualizer/PtpReport.cs`: zero-allocation parser for touchpad report payloads.
- `tools/AmtPtpVisualizer/MainWindow.xaml.cs`: reader loop, UI orchestration, and left/right device routing.
- `tools/AmtPtpVisualizer/Core/Engine/*`: touch processor state machine and key-binding resolution.
- `tools/AmtPtpVisualizer/Core/Diagnostics/*`: capture format, replay runner, metrics, and self-tests.

## Working Agreements
- **Build environment:** Visual Studio 2022/2023 + WDK for driver work; .NET 6 SDK for `AmtPtpVisualizer` (`net6.0-windows`).
- **Driver caution:** Do not touch the driver or control panel, full stop.
- **EFFICIENCY** Always write the most performant and efficient code to turn an Apple Magic Trackpad into a keyboard with an emphasis on running in the background as a status app and instant key detection.
- **Hot-path discipline:** No avoidable allocations, logging spam, or file I/O in per-frame processing paths.
- **Touch policy:** Visualizer intentionally renders tip contacts only (`TipSwitch=true`) to avoid hover artifacts.
- **Documentation:** Keep `README.md` and this file in sync when flags, report formats, workflow commands, or architecture change.

## Common Workflows
1. **Build visualizer (Release):**
   ```powershell
   dotnet build .\tools\AmtPtpVisualizer\AmtPtpVisualizer.csproj -c Release
   ```

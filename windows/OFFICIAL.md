# Official Apple USB-C Driver Notes (GlassToKey)

## Scope
This document tracks reverse-engineering progress for Magic Trackpad USB-C packets coming through Apple official Windows driver transport (`VID 0x05AC`, `PID 0x0265`, `usage 0x00/0x00`).

## Current Decode Status
- Raw analyzer sees stable packet signature from official driver:
  - `reportId=0x05`, `payloadLength=50`
  - `official-usbc-press2.atpcap`: `records=789`, `decoded=789`
  - `official-usbc-press.atpcap`: `records=1031`, `decoded=1031`
- Runtime no longer hard-crashes on these captures after raw-input fault guards + decoder profile split.
- Contact count decoding is reliable (press capture reports up to 4 contacts).

## Decoder Routing
Decoder profile is resolved per device path, so left/right halves can use different decoder profiles.

- Profile enum and parser: `GlassToKey/TrackpadDecoderProfile.cs`
- Settings persistence map: `GlassToKey/UserSettings.cs`
- Runtime lookup:
  - UI mode: `GlassToKey/MainWindow.xaml.cs`
  - Tray/runtime mode: `GlassToKey/TouchRuntimeService.cs`

Supported values:
- `auto`
- `legacy`
- `official`

`auto` behavior:
- official transport (`usage 0/0`) tries `official` PTP normalization first, then `legacy` fallback.
- legacy transport keeps previous path.

## Official Slot Mapping (Current Best)
Implemented in `GlassToKey/TrackpadReportDecoder.cs` (`NormalizeOfficialTouchFields`).

Per contact slot (`slotOffset = 1 + contactIndex * 9`):
- `X`: little-endian `u16` from `[slot+2..slot+3]`
- `Y`: little-endian `u16` from `[slot+4..slot+5]`
- `Flags`: force tip+confidence on decoded contact (`... | 0x03`)
- `Id`: normalized to slot index (prevents pathological packed IDs from official transport)
- scaling:
  - `X` uses `maxRaw=14720` (empirical fix for ~90% width cap with official USB-C captures)
  - `Y` uses `maxRaw=10240` (empirical fix for ~75% height cap with official USB-C captures)

Why this mapping:
- avoids 10-bit wrap behavior seen with packed interpretation.
- avoids overlapping byte usage between X and Y (reduced X corruption).
- best continuity from available captures.

## Known Remaining Issues
- X channel may still include non-position signal in some gestures.
- pressure is not decoded from official transport yet; UI may show `p:0` depending on probe outcome.
- raw analyzer JSON is currently summary-level only (no per-frame coordinate dump).

## Crash/Diagnostics
Runtime exception log:
- `%LOCALAPPDATA%\GlassToKey\runtime-errors.log`
- code: `GlassToKey/Core/Diagnostics/RuntimeFaultLogger.cs`

## Capture + Analysis Commands
From `windows` folder:

```powershell
dotnet .\GlassToKey\bin\Debug\net6.0-windows\GlassToKey.dll --selftest

dotnet .\GlassToKey\bin\Debug\net6.0-windows\GlassToKey.dll --raw-analyze .\official-usbc-press2.atpcap --raw-analyze-out .\official-usbc-press2.analysis.json
```

If you want a rebuilt release exe:

```powershell
dotnet publish .\GlassToKey\GlassToKey.csproj -c Release -r win-x64 --self-contained false
```

Published output:
- `GlassToKey\bin\Release\net6.0-windows\win-x64\publish\GlassToKey.exe`

## Mixed Driver Setup (Left/Right Different)
Set profile per selected device path in settings JSON:
- `%LOCALAPPDATA%\GlassToKey\settings.json`
- key: `DecoderProfilesByDevicePath`

Example:

```json
"DecoderProfilesByDevicePath": {
  "\\?\\HID#VID_05AC&PID_0265...": "official",
  "\\?\\HID#VID_05AC&PID_0262...": "legacy"
}
```

## Next Recommended Reverse-Engineering Pass
- add optional per-frame raw+decoded CSV output in `RawCaptureAnalyzer` for official profile.
- isolate pressure/tip/confidence bits from bytes near slot `[+1,+7,+8]` while holding position constant.
- validate full-range sweeps to confirm if Y wrap is fully resolved on latest mapping.

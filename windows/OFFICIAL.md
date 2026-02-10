# Official Apple USB-C Driver Notes (GlassToKey)

## Purpose
This is the reverse-engineering handoff for official Apple USB-C driver packets in GlassToKey.

Target transport observed so far:
- `VID 0x05AC`
- `PID 0x0265`
- `usagePage=0x00`, `usage=0x00`
- `reportId=0x05`
- report length `50` bytes

Primary decoder code:
- `GlassToKey/TrackpadReportDecoder.cs`

## What We Changed
These are the key architecture changes made to support official driver data without breaking legacy paths.

- Added profile-aware decode routing (`auto`, `legacy`, `official`).
- Added per-device profile map so left/right can use different decoders.
- Added crash-safe runtime guards around raw input decode path.
- Added raw capture analyzer CLI mode for quick signature and decode health checks.
- Normalized pathological official contact IDs to stable slot IDs.

Related files:
- `GlassToKey/TrackpadReportDecoder.cs`
- `GlassToKey/TrackpadDecoderProfile.cs`
- `GlassToKey/UserSettings.cs`
- `GlassToKey/MainWindow.xaml.cs`
- `GlassToKey/TouchRuntimeService.cs`
- `GlassToKey/Core/Diagnostics/RawCaptureAnalyzer.cs`
- `GlassToKey/Core/Diagnostics/RuntimeFaultLogger.cs`
- `GlassToKey/App.xaml.cs`
- `GlassToKey/ReaderOptions.cs`

## Decoder Profiles
`auto`:
- Try both legacy and official decode candidates, then choose by payload semantics.
- Selection rules (current):
  - If only one candidate has contacts, use that one.
  - If legacy candidate shows any non-zero contact IDs, prefer `legacy`.
  - If official candidate is edge-saturated (`x/y` pinned to bounds), prefer `legacy`.
  - If both have contacts and legacy IDs are all zero, prefer `official`.
  - If ambiguous, bias to `legacy` to protect open-source/standard PTP behavior.
- This avoids metadata-only misclassification when both drivers expose the same VID/PID and usage.
- Runtime latching: once an `auto` device gets a decoded frame with `contactCount > 0`,
  its chosen profile is latched for the rest of the process run (per device path).

`legacy`:
- Standard original PTP path only.

`official`:
- Force official normalization attempt first; keeps legacy fallback.

Per-device persistence key:
- `%LOCALAPPDATA%\GlassToKey\settings.json`
- `DecoderProfilesByDevicePath`

Example:
```json
"DecoderProfilesByDevicePath": {
  "\\?\\HID#VID_05AC&PID_0265...": "official",
  "\\?\\HID#VID_05AC&PID_0262...": "legacy"
}
```

## Packet Layout Findings
Important finding: the official stream does not match standard Windows PTP field semantics even though packet size is 50 bytes.

Current best contact slot model:
- slot size: `9` bytes
- slot base: `slotOffset = 1 + contactIndex * 9`
- decoded contact count still taken from report tail (`ContactCount` from parsed frame)

Current coordinate extraction:
- `X raw = LE u16 [slot+2 .. slot+3]`
- `Y raw = LE u16 [slot+4 .. slot+5]`

Current normalization behavior:
- `Id = contactIndex` (stable, avoids giant packed IDs/jumping)
- `Flags = (flags & 0xFC) | 0x03` (force tip + confidence true)

Why:
- Earlier packed-coordinate interpretation produced severe wrap and jumps.
- Earlier overlapping byte choices contaminated one axis with non-position signals.
- This non-overlapping mapping produced stable, usable motion in live tests.

## Scaling Findings
Axis raw ranges are not symmetric in this stream, so axis-specific maxima are required.

Current constants:
- `OfficialMaxRawX = 14720`
- `OfficialMaxRawY = 10240`

Current scaling function:
- `scaled = clamp(raw, 0..maxRaw) * targetMax / maxRaw` (with rounding)
- target ranges still use runtime defaults (`DefaultMaxX`, `DefaultMaxY`)

Observed behavior that drove these constants:
- Y originally looked like ~75 percent travel because it was scaled as if max raw were ~16383.
- After Y max changed to `10240`, Y reached near full height.
- X was then short by roughly ~10 percent; reducing X max to `14720` corrected width coverage in live test.

## Known Good Outcomes So Far
- No hard crash on official captures after guards were added.
- Contact count is accurate in official press tests.
- ID instability is resolved (no huge jumping IDs).
- X and Y now both track with good stability in current live feedback.

## Known Unknowns
- Pressure is not reliably decoded for official transport yet.
- UI may show `p:0` because pressure probe currently sees no trustworthy pressure signal.
- Some non-position bits likely still exist in nearby slot bytes (`+1`, `+7`, `+8`).
- Raw analyzer JSON is summary-level only; no built-in per-frame XY dump yet.

## Runtime Stability Guardrails
Raw input exception handling now includes:
- structured fault logging to `%LOCALAPPDATA%\GlassToKey\runtime-errors.log`
- contextual packet dump fields (VID/PID/usage/report index/report hex prefix)
- temporary raw-input pause after repeated faults (prevents rapid lockup loops)

Key code:
- `GlassToKey/Core/Diagnostics/RuntimeFaultLogger.cs`
- `GlassToKey/MainWindow.xaml.cs`
- `GlassToKey/TouchRuntimeService.cs`

## Analyzer + Validation Workflow
From `windows` directory:

```powershell
dotnet .\GlassToKey\bin\Debug\net6.0-windows\GlassToKey.dll --selftest
dotnet .\GlassToKey\bin\Debug\net6.0-windows\GlassToKey.dll --raw-analyze .\your-capture.atpcap --raw-analyze-out .\your-capture.analysis.json
dotnet run --project .\GlassToKey\GlassToKey.csproj -c Release -- --decoder-debug
```

Release build:

```powershell
dotnet publish .\GlassToKey\GlassToKey.csproj -c Release -r win-x64 --self-contained false
```

Published exe:
- `GlassToKey\bin\Release\net6.0-windows\win-x64\publish\GlassToKey.exe`

Decoder debug output:
- add `--decoder-debug` to print per-side chosen decode profile and sample contact fields.

## Tuning Procedure (If Scaling Drifts Again)
Use this exact process:

1. Record a one-finger full-width sweep and full-height sweep separately.
2. Compute raw axis min/max from the chosen slot byte pairs.
3. Set axis max slightly above observed max (about 3 to 8 percent headroom).
4. Rebuild and verify full-range visual coverage.
5. Keep X and Y scaling independent.

Practical note:
- If an axis tops out early, `maxRaw` is too high.
- If an axis overshoots/clamps too early at extremes, `maxRaw` is too low.

## Recommended Next Reverse-Engineering Steps
1. Add optional per-frame CSV output in `RawCaptureAnalyzer` with raw slot bytes + decoded XY.
2. Isolate pressure/tip/confidence bits using stationary-finger force ramps.
3. Validate 2-5 finger motion with mixed velocities to confirm slot ordering assumptions.
4. Confirm behavior on both halves when one side is legacy and the other official.

## Quick Context Summary For Next Session
- Official USB-C path is now usable with profile-aware decoding and runtime stability guards.
- Current slot decode and axis scales are empirical but working in live tests.
- Remaining work is mostly pressure/flag semantics and richer diagnostics, not crash triage.

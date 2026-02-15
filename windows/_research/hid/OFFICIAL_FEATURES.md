# Apple Magic Trackpad Windows Feature/Haptics Research

Last updated: 2026-02-14

## Objective
- Find any reliable method to trigger AMT haptics from Windows user space first.
- Keep kernel-driver changes as a second phase if user-space HID writes are blocked.

## Confirmed Cross-Platform Signals
- mac path in this repo already uses `MTActuatorActuate(...)` via private Multitouch APIs:
  - `../mac/Framework/OpenMultitouchSupportXCF/OpenMTInternal.h`
  - `../mac/Framework/OpenMultitouchSupportXCF/OpenMTManager.m`
- Linux fork notes a host-click mode and per-event haptic parameters:
  - `host_click=1` enables host-driven click/haptic behavior.
  - `button_down_param` / `button_up_param` are 4-byte values where first byte is pressure and later bytes map to vibration shaping.
  - Source: `https://github.com/nexustar/linux-hid-magicmouse`
- Windows MT2 fork (`vitoplantamura`) reports added haptic feedback control messages based on previous reverse engineering.
  - Source: `https://github.com/vitoplantamura/MagicTrackpad2ForWindows`

## Windows Strategy (Pragmatic Order)
1. User-space HID research path (now implemented in GlassToKey):
   - Open device handle directly from enumerated HID path.
   - Query report sizes/usage.
   - Send candidate Feature/Output/Write payloads and observe physical haptic response.
2. Packet-capture assisted path:
   - Capture USB traffic while force-clicking in native behavior.
   - Identify non-input host-to-device reports near click transitions.
   - Replay same reports through user-space HID path.
3. Driver path only if needed:
   - If user-space write methods are consistently rejected (`ACCESS_DENIED`, stalled, or ignored), move to lower-level filter/driver experiments.

## New GlassToKey Research CLI
- `--hid-probe`: Open selected AMT HID and print VID/PID, usage, report lengths.
- `--hid-index <n>`: Choose target AMT from enumeration.
- `--hid-feature <hex-bytes>`: Send feature report payload.
- `--hid-output <hex-bytes>`: Send output report payload.
- `--hid-write <hex-bytes>`: Send raw write payload via `WriteFile`.
- `--hid-repeat <n>` and `--hid-interval-ms <ms>`: burst or pulse tests.
- `--hid-auto-probe`: sweep report IDs + safe payload variants and log API responses.
- `--hid-auto-report-max <0..255>`: upper report ID bound for auto sweep (default `15`).
- `--hid-auto-interval-ms <ms>`: delay between auto sweep steps (default `10`).
- `--hid-auto-log <path>`: optional log output path.
- `--hid-actuator-pulse`: send Linux-derived click/release strength-config frames repeatedly (may configure click feel depending on mode/firmware).
- `--hid-actuator-vibrate`: send known "vibrate now" actuator packet repeatedly (confirmed immediate haptics on this host).
- auto-probe tests both `OutputReportByteLength` and `OutputReportByteLength + 1` payload lengths.
- auto-probe runs a second focused phase on any report IDs that return `ok=True`, trying known actuator packet templates (including the 14-byte pattern seen in other reverse-engineering attempts).

## Suggested Test Flow
1. Enumerate and probe:
```powershell
dotnet run --project .\GlassToKey\GlassToKey.csproj -c Release -- --list
dotnet run --project .\GlassToKey\GlassToKey.csproj -c Release -- --hid-probe
```
2. Send candidate report bytes (replace with your current hypothesis):
```powershell
dotnet run --project .\GlassToKey\GlassToKey.csproj -c Release -- --hid-probe --hid-output "01 00 00 00"
```
3. Pulse sequence for tactile detectability:
```powershell
dotnet run --project .\GlassToKey\GlassToKey.csproj -c Release -- --hid-output "01 00 00 00" --hid-repeat 10 --hid-interval-ms 40
```
4. Automated actuator sweep:
```powershell
dotnet run --project .\GlassToKey\GlassToKey.csproj -c Release -- --hid-auto-probe --hid-index 3 --hid-auto-report-max 63 --hid-auto-log .\captures\haptics\auto-probe.log
```

5. Confirmed actuator haptics trigger (vibrate now):
```powershell
dotnet run --project .\GlassToKey\GlassToKey.csproj -c Release -- --hid-index 3 --hid-actuator-vibrate --hid-actuator-count 20 --hid-actuator-interval-ms 60 --hid-actuator-param32 0x00026C15
```

## Local Probe Snapshot (2026-02-14)
- Enumerated multiple AMT HID collections on one host (`COL01`, `COL02`, `COL03`, and additional `MI_02`/`MI_03`).
- `COL01` and `COL02` were locked (`ERROR_ACCESS_DENIED` / `ERROR_SHARING_VIOLATION`) in this environment.
- `MI_02` identifies as **`Product: Actuator`** with caps:
  - `UsagePage=0xFF00`, `Usage=0x000D`
  - `InputReportByteLength=16`
  - `OutputReportByteLength=64`
  - `FeatureReportByteLength=0`
- `MI_03` identifies as **`Product: Accelerometer`**.
- `COL03` opened read/write and responded to `HidD_SetFeature` (`UsagePage=0x000D`, `Usage=0x000E`, `FeatureReportByteLength=2`).
- Initial actuator write probes with all-zero 64/65-byte payloads were rejected by both `HidD_SetOutputReport` and `WriteFile`, so payload format/report ID is still unknown.
- Current actuator sweep responses are consistent `Win32=0x57` (`ERROR_INVALID_PARAMETER`) for tested report IDs and safe payload variants, which strongly suggests packet framing/content is validated by the stack/firmware.
- One observed `COL03` caps snapshot:
  - `UsagePage=0x000D`, `Usage=0x000E`
  - `FeatureReportByteLength=2`
  - `OutputReportByteLength=0`

## Notes
- Report payload format is device/firmware-specific; first byte is often report ID on HID transports.
- Keep AMT plugged over USB-C during first haptics experiments to reduce BLE transport variables.
- Start weak/short pulses before trying stronger repeated bursts.

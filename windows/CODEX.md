# GlassToKey: Apple Magic Trackpad 2 Haptics Research (Windows) Handoff

Last updated: 2026-02-15

This file is the continuity/handoff doc for continuing AMT2 (Magic Trackpad 2) haptics reverse engineering on Windows in this repo.

## Objective

Find a reliable, user-mode (no kernel driver changes) way to trigger/configure haptics on Apple Magic Trackpad 2 on Windows by talking to the HID "Actuator" interface.

Second phase (only if needed): driver / lower-level USB control experiments.

## Repo Layout (Relevant Parts)

- `GlassToKey/OFFICIAL_SPEC.md`
  - Reverse engineering notes for report decoding and device behavior.
- `GlassToKey/OFFICIAL_FEATURES.md`
  - Current research CLI overview and local device snapshot notes.
- `GlassToKey/HidResearchTool.cs`
  - HID enumeration (SetupAPI), probing, payload send helpers, auto-probe scanner, known template probes, actuator pulse test.
- `GlassToKey/ReaderOptions.cs`
  - CLI flags for HID research mode.
- `GlassToKey/App.xaml.cs`
  - Bootstraps "HID research mode": if any `--hid-*` flags are present, runs `HidResearchTool.Run(...)` and exits.

## What We Know So Far (Empirical)

### Device surfaces / collections

One physical AMT2 will enumerate as multiple HID collections/interfaces on Windows. Many collections can be locked (sharing violation/access denied) while at least one "Actuator" interface is openable.

In the last successful local probe (USB only):

- One interface identifies as `Product: Actuator` (often `MI_02`).
- Observed caps on that Actuator interface:
  - `UsagePage=0xFF00`, `Usage=0x000D`
  - `InputReportByteLength=16`
  - `OutputReportByteLength=64`
  - `FeatureReportByteLength=0`

### Report ID 0x53 appears special

Using `--hid-auto-probe`, almost all report IDs fail with Win32 `0x57` (`ERROR_INVALID_PARAMETER`).

One report ID produced `ok=True` API results:

- Report ID: `0x53`
- Some `HidD_SetOutputReport(...)` and `WriteFile(...)` attempts succeeded at the API level for certain payload shapes (e.g. all-zero 64-byte output report).

This strongly suggests that:

- The Actuator output report includes a report ID byte.
- `0x53` is likely the output report ID for actuator control/config.

Important: API success does not guarantee physical haptic output; it only shows the stack/firmware accepted the write.

## External Reverse Engineering Hint (dos1 / Linux issue #28)

From the Linux Magic Trackpad 2 driver issue discussion:

- Bluetooth message is 15 bytes and starts with `0xF2`.
- USB message is the same but without the leading `0xF2` (14 bytes).
- Byte 1 determines event: `0x22` click, `0x23` release.
- Three strength bytes are at positions (in that message) corresponding to indexes 3, 6, 11 in the BT form.

USB body (14 bytes) we are using:

`[eventId] 01 [s1] 78 02 [s2] 24 30 06 01 [s3] 18 48 13`

macOS presets reported there:

- low:
  - click: `s1=15 s2=04 s3=04`
  - release: `s1=10 s2=00 s3=00`
- medium:
  - click: `17 06 06`
  - release: `14 00 00`
- high:
  - click: `1E 08 08`
  - release: `18 02 02`

## Current Implementation State (Windows)

Implemented in `GlassToKey/HidResearchTool.cs`:

### 1. Auto-probe

CLI: `--hid-auto-probe`

- Enumerates candidate interfaces.
- Opens selected interface.
- Sweeps report IDs and payload variants using both:
  - `HidD_SetOutputReport` ("control-like" path)
  - `WriteFile` (raw write path)
- Logs every attempt to a log file (default `%LOCALAPPDATA%\\GlassToKey\\hid-auto-probe-*.log`).
- If any report IDs return `ok=True`, runs a focused Phase 2 against only those IDs using "known templates".

Known templates (Phase 2) currently include:

- A previously seen 14-byte "base" pattern with optional XOR/sum checksums and padding.
- The dos1/Linux issue #28 strength-config bodies for click/release at low/medium/high, with:
  - `rid=0x53` prepended
  - padded to the device's `OutputReportByteLength` (usually 64)

### 2. Explicit actuator pulse test

CLI: `--hid-actuator-pulse`

Purpose: send the dos1/Linux "strength config" frames repeatedly so you can physically feel if anything changes/triggers.

Implementation details:

- Hard-codes report ID `0x53` (based on prior sweep data).
- Builds two frames:
  - click config: `eventId=0x22` with strength bytes from `--hid-actuator-param32`
  - release config: `eventId=0x23` with strength bytes currently hard-coded to `00 00 00`
- Prepends report ID, pads to `OutputReportByteLength`, then for each pulse:
  - tries `HidD_SetOutputReport(...)` OR falls back to `WriteFile(...)`
  - prints `ok=<bool>` and `win32=0x...`

Flags in `GlassToKey/ReaderOptions.cs`:

- `--hid-actuator-pulse`
- `--hid-actuator-count <n>` (default 10)
- `--hid-actuator-interval-ms <ms>` (default 60)
- `--hid-actuator-param32 <hex>` (default `0x00026C15`)
  - low 3 bytes are interpreted as `s1`, `s2`, `s3`:
    - `s1 = param32 & 0xFF`
    - `s2 = (param32 >> 8) & 0xFF`
    - `s3 = (param32 >> 16) & 0xFF`

## How To Run (Recommended Sequence)

All commands are from `C:\\Users\\jholloway\\Documents\\AppleMagicTouchstreamLP\\windows`.

1. Build

```powershell
dotnet build .\GlassToKey\GlassToKey.csproj -c Release
```

2. List all interfaces

```powershell
dotnet run --project .\GlassToKey\GlassToKey.csproj -c Release -- --list
```

Pick the interface that shows `Product: Actuator` and `OutputReportByteLength=64` when probed.

3. Probe the actuator interface (replace `<n>`)

```powershell
dotnet run --project .\GlassToKey\GlassToKey.csproj -c Release -- --hid-probe --hid-index <n>
```

4. Auto-probe (wide sweep, logs responses)

```powershell
dotnet run --project .\GlassToKey\GlassToKey.csproj -c Release -- --hid-auto-probe --hid-index <n> --hid-auto-report-max 255 --hid-auto-interval-ms 5 --hid-auto-log .\captures\haptics\auto-probe.log
```

5. Actuator pulse (start with macOS "high click" strengths)

`high click` strength triple is `1E 08 08` so:

- `param32 = 0x0008081E`

```powershell
dotnet run --project .\GlassToKey\GlassToKey.csproj -c Release -- --hid-probe --hid-index <n> --hid-actuator-pulse --hid-actuator-count 30 --hid-actuator-interval-ms 40 --hid-actuator-param32 0x0008081E
```

Other preset examples:

- low click: `0x00040415`
- medium click: `0x00060617`

## Interpreting Results

### API-level acceptance vs physical haptics

- `ok=True` means Windows accepted the report for that HID handle/path.
- It might still do nothing physically if:
  - the packet only configures future click feedback rather than triggering an immediate actuator event
  - a missing enable/host-click mode gate exists
  - the report requires additional bytes/checksum/state not yet sent

### What “good” looks like

Any of:

- noticeably different click feeling when physically pressing after sending strength configs
- a pulse-like response to repeated config writes (less likely; config-only packets may not vibrate immediately)

## Next Research Steps (Pragmatic)

1. Confirm whether the dos1/Linux strength-config frames change the physical click strength on USB Windows.
   - If yes: we have a working path to control haptic strength, and can iterate toward a true "actuate now" packet.

2. Add options to `--hid-actuator-pulse` for release strengths (currently hardcoded `00 00 00`).
   - Add `--hid-actuator-release-param32` mirroring `--hid-actuator-param32`.

3. Expand Phase 2 templates:
   - include "silent mode" variants (last two strength bytes `00 00`)
   - try different event IDs beyond `0x22/0x23` if found in captures

4. Capture USB traffic while macOS triggers haptics (if possible) and replay host->device control transfers:
   - Wireshark + USBPcap on Windows, or capture from macOS side and replicate.
   - Pay attention to report IDs and any HID class control transfers corresponding to output/feature writes.

5. If user-mode HID paths are blocked (persistent `ACCESS_DENIED` / `SHARING_VIOLATION` on actuator) or ignored:
   - Consider a filter driver or lower-level interface claim, but do this only after exhausting user-mode.

## Notes / Gotchas

- Many "collections" are locked if opened by another consumer. USB-only during tests reduces ambiguity.
- In this environment, Git-for-Windows `nl.exe`/`sed.exe` may fail with Win32 error 5; use PowerShell `Get-Content` for paging.


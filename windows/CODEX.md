# GlassToKey: Apple Magic Trackpad 2 Haptics Research (Windows) Handoff

Last updated: 2026-02-15

This file is the continuity/handoff doc for continuing AMT2 (Magic Trackpad 2) haptics reverse engineering on Windows in this repo.

## Objective

Find a reliable, user-mode (no kernel driver changes) way to trigger/configure haptics on Apple Magic Trackpad 2 on Windows by talking to the HID "Actuator" interface.

Second phase (only if needed): driver / lower-level USB control experiments.

## Repo Layout (Relevant Parts)

- `GlassToKey/OFFICIAL_SPEC.md`
  - Reverse engineering notes for report decoding and device behavior.
- `GlassToKey/Core/Haptics/MagicTrackpadActuatorHaptics.cs`
  - Production haptics helper (user-mode HID Actuator output report, warmup in background, throttled trigger).
- `GlassToKey/Core/Dispatch/SendInputDispatcher.cs`
  - Dispatch pump thread triggers haptics when `DispatchEventFlags.Haptic` is set.
- `GlassToKey/Core/Engine/TouchProcessorCore.cs`
  - Tags key dispatch events with `DispatchEventFlags.Haptic` when enabled.
- `GlassToKey/UserSettings.cs`
  - Persists haptics settings (`HapticsEnabled`, `HapticsStrength`, `HapticsMinIntervalMs`).
- `GlassToKey/MainWindow.xaml` / `GlassToKey/MainWindow.xaml.cs`
  - UI slider: `Haptic Strength` (Off/Low/Med/High).
- `_research/hid/HidResearchTool.cs`
  - Archived HID probing/scanner used during reverse engineering (no longer wired into the production app).

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

Production haptics path:

- `MagicTrackpadActuatorHaptics.TryVibrate()` sends the known-good AMT2 actuator output report (`rid=0x53`, 14-byte body padded to 64).
- `TouchProcessorCore` can tag key dispatch events with `DispatchEventFlags.Haptic`.
- `SendInputDispatcher` triggers haptics on the dispatch pump thread when that flag is present.
- UI controls `UserSettings.HapticsEnabled` and chooses strength via the 4-step `Haptic Strength` slider (Off/Low/Med/High).

## How To Run (Production)

- Launch GlassToKey normally (tray app), then open `Config...`.
- Under `Typing Tuning`, set `Haptic Strength` to `Off/Low/Med/High`.

Notes:

- The old `--hid-*` research CLI was removed from the production app. The historical scanner/prober code lives in `_research/hid/` if you want to revive it in a separate tool.

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

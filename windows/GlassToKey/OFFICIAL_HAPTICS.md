# GlassToKey: Official Magic Trackpad 2 Haptics Notes (Windows)

Last updated: 2026-02-15

This documents the current known-good way to trigger Magic Trackpad 2 (AMT2) haptics on Windows from user mode, plus the routing details needed for multi-trackpad setups.

## What Works

AMT2 exposes a separate HID interface that identifies as an **Actuator** device.

On at least some firmwares, sending a specific **HID output report** to that actuator interface triggers an immediate haptic pulse.

In this repo, the production implementation is `GlassToKey/Core/Haptics/MagicTrackpadActuatorHaptics.cs`.

## HID Interface Identification

The actuator interface has been observed as:

- `UsagePage = 0xFF00`
- `Usage = 0x000D`
- `OutputReportByteLength = 64` (typical)

The touch surface collections (used by Raw Input) are different HID collections and are often locked for open/write access. Do not send actuator packets to the touch collection.

## The "Vibrate Now" Packet

### Report framing

Windows HID output reports typically include a **Report ID** as the first byte of the write buffer. For the actuator report used here:

- Report ID: `0x53`

### Payload format (14 bytes + zero padding)

Byte layout:

- `[0]` `0x53` Report ID
- `[1]` `0x01` Command
- `[2..5]` `strength` as `uint32` little-endian
- `[6..13]` constant tail bytes:
  - `21 2B 06 01 00 16 41 13`

Any bytes beyond 14 should be zero padding out to the device's `OutputReportByteLength` (typically 64).

In code, the payload builder is `BuildPayload(outputReportBytes, strength)`.

### Strength semantics

The `strength` field is a 32-bit value. The device accepts many values, but the perceptual mapping is **not confirmed to be linear** and may be firmware-dependent.

In this repo, the tuning UI supports a slider that sweeps the low byte:

- `amp = 0x00..0x4A` (empirically observed saturation around `0x4A` on the tested device)
- Effective strength: `strength = 0x00026C00 | amp`

If you need exact macOS parity, you should empirically calibrate these values on your device.

## How We Send It (Windows User Mode)

The implementation uses:

- `CreateFileW` on the actuator HID device interface path
- `HidD_SetOutputReport(handle, payload, payload.Length)`

No kernel driver changes are required for this path on the tested firmware.

## Multi-Trackpad Routing (Critical)

If you have two AMT2 devices connected (for example, Left and Right trackpads), you must route haptics to the correct physical device.

Problem symptom:

- Right-hand taps trigger left-hand haptics (because the software always opens the first actuator it finds).

### Correct routing approach

Both the touch collection path (Raw Input selection) and the actuator interface belong to the same physical device. Windows provides a stable way to join them:

- `DEVPKEY_Device_ContainerId` (a GUID)

Strategy:

1. Take the selected touch HID path for Left/Right (`UserSettings.LeftDevicePath`, `UserSettings.RightDevicePath`).
2. Resolve each path to its `ContainerId` via SetupAPI (`SetupDiGetDevicePropertyW` with `DEVPKEY_Device_ContainerId`).
3. Enumerate HID interfaces for the actuator (`UsagePage=0xFF00`, `Usage=0x000D`).
4. For each actuator interface, read its `ContainerId` and match it to the Left/Right ContainerId.
5. Open one actuator handle per side and send the packet to that handle.

In this repo, this is implemented in:

- `MagicTrackpadActuatorHaptics.SetRoutes(leftTouchHidPath, rightTouchHidPath)`
- `MagicTrackpadActuatorHaptics.TryVibrate(TrackpadSide side)`

## Keeping The Hot Path Hot

HID enumeration and actuator handle opening are expensive and can block.

This repo keeps those operations off the hot path:

- `WarmupAsync()` runs initialization on the thread pool.
- The dispatch hot loop only calls `TryVibrate(side)` which:
  - throttles by `HapticsMinIntervalMs`
  - sends the already-prebuilt output report buffer

Haptics are triggered on the dispatch pump thread (not the raw input parsing thread) by tagging dispatch events with `DispatchEventFlags.Haptic`.

Relevant code path:

- `TouchProcessorCore.EnqueueDispatchEvent(...)` adds `DispatchEventFlags.Haptic` to `KeyTap` when enabled.
- `SendInputDispatcher.Dispatch(...)` calls `MagicTrackpadActuatorHaptics.TryVibrate(dispatchEvent.Side)` when the flag is present.

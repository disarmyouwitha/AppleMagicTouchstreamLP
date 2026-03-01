# Linux evdev to InputFrame Mapping

## Purpose

This document defines how the Linux runtime should translate `evdev` multitouch events into the existing `InputFrame` / `ContactFrame` model used by the GlassToKey engine.

The mapping is designed for:

- modern Ubuntu
- Apple Magic Trackpad 2
- mainline Linux `hid-magicmouse`
- userspace ingestion through `evdev` or `libevdev`

## Source event model

Preferred model:

- Type B slot protocol events

Observed on current Ubuntu 24.04 Apple hardware:

- Type B slot protocol events
- parallel legacy absolute fields on the same device node

The important event types for GlassToKey are:

- `EV_ABS`
  - `ABS_X`
  - `ABS_Y`
  - `ABS_PRESSURE`
  - `ABS_MT_SLOT`
  - `ABS_MT_TRACKING_ID`
  - `ABS_MT_TOUCH_MAJOR`
  - `ABS_MT_TOUCH_MINOR`
  - `ABS_MT_POSITION_X`
  - `ABS_MT_POSITION_Y`
  - `ABS_MT_PRESSURE`
  - `ABS_MT_ORIENTATION`
- `EV_KEY`
  - `BTN_LEFT`
  - `BTN_TOUCH`
  - optional `BTN_TOOL_FINGER`
- `EV_SYN`
  - `SYN_REPORT`

The Linux docs describe:

- Type B multitouch slot updates
- `ABS_MT_TRACKING_ID = -1` meaning slot released
- `SYN_REPORT` as the frame boundary

Practical note:

- do not assume every useful Apple trackpad frame will be reconstructable from slots alone
- if slot traffic is absent or incomplete, fall back to a single-contact path using `ABS_X`, `ABS_Y`, `ABS_PRESSURE`, `ABS_MT_TOUCH_MAJOR`, `ABS_MT_TOUCH_MINOR`, `BTN_TOUCH`, and `BTN_TOOL_FINGER`

## Existing GlassToKey frame model

Current engine contract:

```csharp
public struct InputFrame
{
    public long ArrivalQpcTicks;
    public byte ReportId;
    public ushort ScanTime;
    public byte ContactCount;
    public byte IsButtonClicked;
    public ContactFrame Contact0;
    public ContactFrame Contact1;
    public ContactFrame Contact2;
    public ContactFrame Contact3;
    public ContactFrame Contact4;
}
```

And:

```csharp
public readonly record struct ContactFrame(
    uint Id,
    ushort X,
    ushort Y,
    byte Flags,
    byte Pressure = 0,
    byte Phase = 0,
    bool HasForceData = true)
```

Important constraints:

- maximum 5 contacts in `InputFrame`
- engine receives `maxX` and `maxY` separately
- engine keying logic mainly depends on:
  - contact id stability
  - X/Y positions
  - `TipSwitch`
  - button state
  - force data only for force/corner-force gestures

## Mapping rules

## Device identity and side routing

Each selected Linux trackpad should be opened as a separate evdev device.

Use stable identity from:

- `/dev/input/by-id/*` if available
- device `uniq` when `/dev/input/by-id/*` is absent, which was the case for the tested Bluetooth trackpads
- udev properties for vendor/product
- device name plus physical path as fallback

Each open device maps to one `TrackpadSide`:

- left
- right

## Per-device state to maintain

The Linux backend must keep mutable state per device:

- current slot index
- slot table keyed by `ABS_MT_SLOT`
- current button-down state from `BTN_LEFT`
- device abs ranges for X, Y, and pressure
- frame sequence counter

Suggested per-slot state:

```text
slot
trackingId
isActive
xRaw
yRaw
pressureRaw
orientationRaw
touchMajorRaw
touchMinorRaw
dirty
```

## Event handling rules

### `ABS_MT_SLOT`

Meaning:

- subsequent `ABS_MT_*` updates apply to that slot

Action:

- set `currentSlot`

### `ABS_MT_TRACKING_ID`

Meaning:

- `>= 0`: slot becomes active with a stable contact id
- `-1`: slot is released

Action:

- if value is `-1`, mark slot inactive
- clear any per-contact state that should not leak into the next touch
- if value is `>= 0`, mark slot active and store `trackingId`

### `ABS_MT_POSITION_X`

Action:

- update the current slot X position using the raw evdev value

### `ABS_MT_POSITION_Y`

Action:

- update the current slot Y position using the raw evdev value

### `ABS_MT_PRESSURE`

Action:

- store raw pressure for the current slot

Important:

- do not assume Linux pressure is equivalent to the Windows Apple-report force path
- see force handling section below

### `ABS_MT_ORIENTATION`

Action:

- store raw orientation only as extra metadata for future use

Linux orientation is not the same as the current `ContactFrame.Phase` field.

### `BTN_LEFT`

Action:

- store the latest physical click state for the device

This maps to `InputFrame.IsButtonClicked`.

### `SYN_REPORT`

Meaning:

- current slot updates form one complete input frame

Action:

- snapshot all active slots into one `InputFrame`
- enqueue/post that frame into the existing engine pipeline

### Legacy absolute fallback

Meaning:

- some Apple devices expose enough non-slot absolute state to build a useful single-contact frame even when slot reconstruction is unavailable or incomplete

Action:

- track `ABS_X`, `ABS_Y`, and `ABS_PRESSURE`
- treat `BTN_TOUCH` and `BTN_TOOL_FINGER` as activity hints
- optionally use `ABS_MT_TOUCH_MAJOR` and `ABS_MT_TOUCH_MINOR` as additional contact-presence hints
- on `SYN_REPORT`, if no slot-based contacts are active but legacy absolute state indicates an active touch, emit one synthetic contact

## Exact field mapping

## `InputFrame.ArrivalQpcTicks`

Set to:

- `Stopwatch.GetTimestamp()` at `SYN_REPORT` commit time

Reason:

- current engine uses monotonic deltas, not wall-clock time
- .NET `Stopwatch` is the closest cross-platform equivalent to the current Windows timing path

Future refinement:

- capture Linux kernel event timestamps separately for diagnostics/replay metadata

## `InputFrame.ReportId`

Set to:

- a Linux synthetic constant, for example `0xEE`

Reason:

- Linux evdev frames are not PTP HID reports
- do not pretend they are Windows report `0x05`

## `InputFrame.ScanTime`

Set to:

- low 16 bits of elapsed milliseconds since device-open or frame counter modulo `65536`

Reason:

- current engine does not fundamentally rely on native PTP scan-time semantics
- this field is mainly carried through the model

## `InputFrame.ContactCount`

Set to:

- number of active slots emitted into this frame
- clamp to `InputFrame.MaxContacts`

Overflow rule:

- if Linux reports more than 5 active contacts, keep the first 5 after deterministic ordering
- increment a diagnostic overflow counter

## `InputFrame.IsButtonClicked`

Set from:

- current `BTN_LEFT` state on that specific device

Mapping:

- `1` when pressed
- `0` when released

## Contact ordering rule

Order active contacts by:

1. slot number ascending
2. take the first 5

Reason:

- deterministic
- stable under the Linux Type B slot model
- avoids reshuffling contacts between frames
- leaves room for a legacy single-contact fallback when slot data is not usable

## `ContactFrame.Id`

Set from:

- `ABS_MT_TRACKING_ID` when available

Fallback:

- slot number if a driver ever exposes active contacts without a valid tracking id

Reason:

- the engine depends on stable contact identity across frames

## `ContactFrame.X`

Set from:

- raw `ABS_MT_POSITION_X` value

Do not rescale to Windows defaults.

The engine already accepts `maxX` separately, so Linux should pass:

- `X = raw device coordinate`
- `maxX = device abs maximum from `EVIOCGABS(ABS_MT_POSITION_X)``

## `ContactFrame.Y`

Set from:

- raw `ABS_MT_POSITION_Y` value

Pass:

- `Y = raw device coordinate`
- `maxY = device abs maximum from `EVIOCGABS(ABS_MT_POSITION_Y)``

Do not invert Y unless real-device testing proves the Linux coordinate system is reversed relative to the existing layout assumptions.

Current real-device note:

- both connected Apple trackpads on Ubuntu 24.04 produced coherent contact movement from the raw evdev stream
- current tested ranges are `X -3678..3934` and `Y -2478..2587`, so Linux should normalize by subtracting axis minima and pass spans `MaxX=7612` and `MaxY=5065`
- `EVIOCGABS` may still need an escalated validation path when the sandbox blocks the ioctl even though the host kernel supports it
- the same ranges and normalized frame path were validated over both USB and Bluetooth on the tested Apple trackpads
- Bluetooth transport did not provide `/dev/input/by-id` symlinks on this machine, so stable identity fell back to `uniq`

## `ContactFrame.Flags`

Set to:

- `0x03` for active contacts

Meaning:

- confidence bit on
- tip-switch bit on

Reason:

- Linux evdev does not expose a direct Apple-style confidence flag for this device path
- the engine already treats confidence as non-authoritative
- active MT slot with valid tracking id should be treated as a real finger

Released contacts should not be emitted into the frame at all.

## `ContactFrame.Pressure`

Linux v1 rule:

- store scaled 8-bit pressure if `ABS_MT_PRESSURE` exists
- otherwise store `0`

Scaling:

- use the device's pressure abs range from `EVIOCGABS(ABS_MT_PRESSURE)`
- normalize raw pressure into `0..255`

Suggested formula:

```text
scaled = clamp((raw - min) * 255 / max(1, max - min), 0, 255)
```

## `ContactFrame.Phase`

Linux v1 rule:

- set to `0`

Reason:

- Linux evdev orientation is not equivalent to the Apple lifecycle/phase value the current force normalizer expects

## `ContactFrame.HasForceData`

Linux v1 rule:

- set to `false`

This is the safest initial choice.

Reason:

- current `ForceNormalizer` combines Apple-specific `Pressure` and `Phase`
- Linux gives us pressure, but not the same phase/lifecycle stream
- setting `HasForceData = true` with `Phase = 0` would misrepresent Linux pressure as full Apple force data

Consequence:

- force-click gestures should be disabled on Linux v1
- corner-force gestures should also be disabled on Linux v1

Future option:

- introduce a Linux-specific force normalization path
- calibrate thresholds against real evdev pressure ranges

## Frame assembly algorithm

## Recommended algorithm

```text
on device open:
  query abs ranges for X, Y, pressure
  initialize slot table
  currentSlot = 0
  buttonDown = false
  frameSequence = 0

on input_event:
  switch type/code:
    EV_ABS/ABS_MT_SLOT:
      currentSlot = value

    EV_ABS/ABS_MT_TRACKING_ID:
      if value == -1:
        slots[currentSlot].isActive = false
      else:
        slots[currentSlot].isActive = true
        slots[currentSlot].trackingId = value

    EV_ABS/ABS_MT_POSITION_X:
      slots[currentSlot].xRaw = value

    EV_ABS/ABS_MT_POSITION_Y:
      slots[currentSlot].yRaw = value

    EV_ABS/ABS_MT_PRESSURE:
      slots[currentSlot].pressureRaw = value

    EV_ABS/ABS_MT_ORIENTATION:
      slots[currentSlot].orientationRaw = value

    EV_KEY/BTN_LEFT:
      buttonDown = (value != 0)

    EV_SYN/SYN_REPORT:
      emit one InputFrame from active slots
```

## Emit algorithm

At `SYN_REPORT`:

1. collect all active slots
2. sort by slot ascending
3. take first 5
4. build one `InputFrame`
5. set `ContactCount`
6. set `IsButtonClicked` from current `BTN_LEFT`
7. set `ArrivalQpcTicks = Stopwatch.GetTimestamp()`
8. post to `TouchProcessorActor`

## Device range handling

On Linux, do not hardcode:

- `7612`
- `5065`

Instead, query each device:

- `ABS_MT_POSITION_X` min/max
- `ABS_MT_POSITION_Y` min/max

Then pass the runtime values into the engine.

If the device abs minimum is not zero:

- subtract `min` before storing `X`/`Y`
- pass `max - min` as the corresponding axis maximum

This keeps the engine's normalization logic correct.

## Pressure handling recommendation

Because `ForceNormalizer` is Apple-report-shaped today, the safe Linux v1 behavior is:

- preserve scaled pressure for diagnostics/visualization
- set `HasForceData = false`
- disable force-dependent gestures in Linux defaults

Linux v2 can revisit force if real-device calibration proves:

- `ABS_MT_PRESSURE` is stable enough
- thresholds can be made reliable
- a Linux-specific force normalizer is justified

## Things Linux should not fake

Do not synthesize these unless real testing proves they are needed and correct:

- fake Apple report id `0x05`
- fake Apple phase values `1..3`
- fake confidence transitions
- fake contact releases as lingering contacts with `TipSwitch = false`

Released contacts should simply disappear from the emitted frame on the next `SYN_REPORT`.

## Suggested Linux v1 defaults

Disable these actions by default on Linux:

- `ForceClick1Action`
- `ForceClick2Action`
- `ForceClick3Action`
- upper/lower corner click actions if they depend on force

Keep enabled:

- normal typing
- hold gestures
- swipe gestures
- multi-finger hold
- multi-finger button-click gestures based on `BTN_LEFT`

## Diagnostics to add

The Linux backend should log or expose:

- device node
- stable device id
- axis min/max for X/Y/pressure
- whether pressure axis exists
- active slot count
- overflow count when more than 5 contacts are active
- frames emitted
- `BTN_LEFT` transitions

## Acceptance criteria

The mapping is correct if:

- one-finger taps hit the same keys as the Windows engine expects
- contact identity stays stable during movement
- 2/3/4/5-finger gestures are recognized reliably
- physical click gestures map through `BTN_LEFT`
- no force-click behavior is falsely triggered on Linux

## Primary sources

- Linux multitouch protocol:
  - https://docs.kernel.org/input/multi-touch-protocol.html
- Linux input event codes:
  - https://docs.kernel.org/input/event-codes.html
- Linux `uinput` documentation:
  - https://docs.kernel.org/input/uinput.html
- Upstream Linux Magic Trackpad driver:
  - https://raw.githubusercontent.com/torvalds/linux/master/drivers/hid/hid-magicmouse.c

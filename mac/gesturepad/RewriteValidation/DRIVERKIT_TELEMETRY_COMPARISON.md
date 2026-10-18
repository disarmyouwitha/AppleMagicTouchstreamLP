# DriverKit telemetry comparison — 2026-10-18

**Superseded conversion details:** [Native Compact V7 parity checkpoint](COMPACT_V7_TELEMETRY_PARITY.md) recovers nonlinear geometry/pressure/total/density, Hand ID and quantized velocity. The initial comparison below records the earlier linear adapter and its limits.

Read-only comparison of `captures/BEFORE_takeover.atpcap` and
`captures/AFTER_takeover.atpcap`, recorded on the right USB pad with the same
requested action. These are separate runs, not synchronized identical sensor
samples; differences do not establish pressure or finger-label calibration.
Original files were not transcoded or modified.

| Field | Before (Apple OMS) | After (initial DriverKit adapter) |
| --- | --- | --- |
| Frames / contact observations | 534 / 623 | 504 / 584 |
| Device numeric ID | 216172782451425280 | 216172782451425280 |
| Median major axis | 7.76 | 85 |
| Median minor axis | 7.18 | 102 |
| Median angle | 1.5708 radians | 0 (raw orientation offset) |
| Median pressure / range | 50 / 0–76 | 26 / 0–48 |
| Median total | 0.71875 | 18 (raw size byte) |
| Median density | 0.92188 | 0 placeholder |
| Contacts with telemetry | 623 | 0 |
| Contact states observed | starting, making, touching, breaking, lingering, leaving | touching, leaving |

## Root cause and changes

The initial adapter passed unconverted dimension bytes into a renderer whose
ellipse axes are percentages of pad width, and passed a signed Linux orientation
code into a renderer requiring radians. This explains the huge ellipses. It also
omitted a real finger-type bitfield and collapsed three state bits into a binary
contact/lift state. None of those omissions were a DriverKit transport limitation.

Current adapter:

- Retains position, pressure byte and tracking ID. Pressure remains uncalibrated
  sensor data; do not rescale it just to match medians from different runs.
- Converts touch extents to renderer units using `(byte << 2) / 7612 * 100`,
  following Linux's extent scaling and horizontal sensor range. This provides
  a sensor-based display size; exact parity with Apple's processed ellipse
  calibration is not established by these two captures.
- Converts the three-bit angle code to radians (`code × pi/8`).
- Preserves finger type from contact bits26–28, separately from tracking ID bits64–67.
  Enum0=unknown,1=thumb,2=index,3=middle,4=ring,5=pinky,6=palm. These are device labels,
  not proof of anatomical correctness on every frame. Never use the tracking ID
  as an anatomical label.
- Maps full state bits29–31 to the eight OMS states in order0–7. Earlier saved
  original USB reports contain all eight codes, supporting the state mapping.
- Estimates velocity by same-device/same-tracking-ID finite differences of normalized
  positions and original monotonic report timestamps. No estimate for initial
  contacts, gaps/restarts, nonincreasing time, stale frames, lifts or identity loss.
  UI labels these values **derived**, including approximate centered mm coordinates
  and mm/s using the existing160×114.9mm surface dimensions. They are not Apple's
  processed velocity or absolute-coordinate fields.
- Leaves Hand ID and density explicitly unavailable in the UI. Size is labeled
  a raw size byte rather than Apple's normalized total. Internal zero placeholders
  for absent legacy fields must be interpreted with DriverKit provenance.
- Adds optional `telemetry.driverKit` with original nine contact bytes and velocity
  availability, retaining undecoded fields in new captures. Legacy captures decode
  when the optional object is absent. The existing AFTER capture cannot recover
  omitted finger bits: its adapter had already discarded them before recording.

## Primary protocol references

- [Linux hid-magicmouse decoder](https://github.com/torvalds/linux/blob/master/drivers/hid/hid-magicmouse.c): positions, pressure, extent bytes/scaling and transport headers.
- [VoodooInput packed report layout](https://github.com/acidanthera/VoodooInput/blob/master/VoodooInput/VoodooInputSimulator/VoodooInputSimulatorDevice.hpp): nine-byte bitfield, finger and full state bits.
- [VoodooInput finger enum](https://github.com/acidanthera/VoodooInput/blob/master/VoodooInput/VoodooInputMultitouch/VoodooInputTransducer.h): finger-type mapping.
- [VoodooInput report construction](https://github.com/acidanthera/VoodooInput/blob/master/VoodooInput/VoodooInputSimulator/VoodooInputSimulatorDevice.cpp): orientation4 corresponds to pi/2.

These are reverse-engineered implementations, not a published Apple guarantee.
Earlier original full USB capture has finger codes0,2,3,4 and state codes0–7;
this corroborates field layout, but does not replace a per-finger labeled trial.

## Verification

GesturePad build and61 automated tests passed, including signed coordinates,
independent finger/tracking IDs, all state codes, geometry/orientation conversion,
velocity reset behavior, raw-byte JSON round-trip and legacy telemetry decoding.
The visual result, reported labels and derived velocity still need a live check.
Driver and ownership machinery are unchanged; no activation performed during this fix.

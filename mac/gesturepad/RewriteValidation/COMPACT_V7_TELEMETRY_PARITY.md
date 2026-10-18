# Native telemetry parity checkpoint — 2026-10-18

## Outcome

The DriverKit decoder now reconstructs **all telemetry fields exposed by GesturePad's
OMS contact model**, using the installed Apple Compact V7 unpacker and contact filler
as an independent reference. Build and 68 tests pass. A fresh right USB takeover
recording passed all 1,686 contacts across 18 compared fields with zero mismatches.
See TELEMETRY_PARITY_LIVE_RESULT.json for capture hash, errors and scope.
A matching live Bluetooth recording remains to be checked.

This supersedes the initial Linux-based linear geometry conversion and the earlier
claim that total/density/Hand ID were unavailable. They are recoverable native
conversions/defaults. Existing before/after recordings are retained unchanged.

## Recovered contract

| Field | Reconstructed behavior |
| --- | --- |
| Tracking ID | Contact byte8 bits0–3, independent of finger classification |
| Finger type | Byte3 bits2–4; native maps7→12; other codes unchanged |
| Hand ID | Native Compact V7 path supplies1; not a recovered anatomical hand classifier |
| State | Byte3 bits5–7, all eight OMS states; native immediate0-after-active transition handled |
| X/Y | Signed13-bit values, native2× conversion and Y+5000; native clipping and normalization using device bounds |
| Absolute position | Native signed position /100, with native clipping |
| Major/minor | Native piecewise integer quadratic/linear unpacking, followed by /100 |
| Angle | Native angle code ×4096, then ×pi/32768 (equivalent code×pi/8) |
| Total | Native nonlinear size-byte conversion, then /256 |
| Pressure | Native nonlinear pressure-byte conversion; not simply the raw byte |
| Density | Native integer formula with family0x81 parameters600/430, then /256 |
| Absolute velocity | Sensor-timestamp delta, native float subtraction,1/8 quantization, signed16 saturation and native zero-vector sentinel handling |
| Normalized velocity | Native operation order and surface bounds, reconstructed from quantized velocity |
| Source time | Unwrapped21-bit millisecond compact-header clock; rollover handling |
| Source frame | Receiver-session sequence, retained separately from app capture sequence; origin can differ from old OMS listener |

Density formula in native integer units:
`400*total / (max(600, floor(sqrt(max(600,major)*max(600,minor)))) - 430)`.

As an independent check against the existing real BEFORE recording, all623
contacts fit these normalized/absolute coordinate bounds to float precision,
and all reported Hand ID1. This corroborates calibration; it is not a same-packet
comparison with the older AFTER recording.

Measured Sensor Surface Descriptor on both known pads:
`f03c0000202b000044e352ffbd1ee426`.
Native bounds: Xmax7869/Xmin−7356, Ymax9956/Ymin−174; surface15600×11040.
GesturePad checks the selected service descriptor **before** takeover and refuses
an unknown calibration instead of silently applying these values to another pad.

## Independent verification

Apple framework8440.5, UUIDB172DB85-9E88-3A4E-AB6E-B458FD373A58, macOS15.7.4/24G517:

- All256 possible values for **each** major/minor/size/pressure byte match the native
  unpacker (1,024 scalar comparisons).
-576 independent density input cases match the native integer density routine.
-256 full native-filled contacts match the Swift adapter on **both** USB and Bluetooth
  wrappers, including clipping, code7→12, states, position, hand, axes, total,
  pressure, density and angle.
-96 two-frame native-reference cases match reconstructed velocity and state,
  including all states, the extra/sentinel bit, zero motion, negative motion and
  sensor-edge clipping. Native current-position velocity uses **unclipped** input
  against the prior clipped output; this distinction is preserved.
- Tests cover source-clock wrap, per-pad isolation, raw byte preservation, optional
  metadata compatibility, and legacy captures without DriverKit provenance.

The oracle uses only the current process's mapped framework, synthetic structs and
local calibration state. No kernel tracing or SIP changes. GesturePad itself uses
portable Swift conversions, not private offsets or copied Apple machine code.
See [tools and reproducible commands](../Tools/TelemetryParity/README.md).

## Capture fidelity

New contacts retain optional `telemetry.driverKit`:
- `conversionVersion:2`
- Original nine contact bytes and full enclosing report bytes
- Compact sensor tick value
- Velocity availability/reset status

Converted fields are recorded alongside the bytes. Earlier raw9-byte captures can
be reinterpreted for scalar recovery; captures made before bytes were retained
cannot recover discarded bits. The old AFTER_takeover capture lacks them.
The normal app capture/replay model remains unchanged except optional metadata.

## Remaining human dependency

The right USB capture `telemetry_parity_takeover.atpcap.atpcap` passed on 2026-10-18.
It includes starting, making, touching, breaking, leaving and terminal notTouching
records. The final notTouching record was retained in the display indefinitely;
render conversion now excludes that state while retaining the original capture
record and bytes. A regression covers active→notTouching for both transport forms.

Remaining: record the same short hold/slide/pressure/roll/lift/two-finger sequence
on the left Bluetooth pad after enabling takeover. Check both displays clear on
lift in the updated build, then confirm Release Trackpads and Control–Option–R
restore normal native input. The currently installed driver was active during this
fix; only the build product was updated, without interrupting or reactivating it.

## Limits kept explicit

- This is parity with the **contact callback contract**, not raw electrode images
  or the whole Apple gesture/classification pipeline.
- The native parser's hand1 constant and finger12 category retain their native
  values without asserting anatomical meaning.
- Session counter origins differ. Absolute original native callback timestamps from
  before takeover cannot be reconstructed merely by matching counter numbers.
- First-frame/gap/stale-frame velocity resets are intentional safety boundaries;
  reference checks identify those cases rather than fabricating continuity.
- Missing-contact cleanup and any upstream Apple binary filters need live recording
  evidence. Synthetic decoder parity does not prove those delivery behaviors.
- Continuous DriverKit ownership is unchanged; explicit release and lifecycle
  safeguards remain. No automatic hardware activation occurred during this work.

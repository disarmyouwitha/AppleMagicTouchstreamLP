# Apple Magic Trackpad contact HID layout

Recovered contract for the
model `05ac:0324` Compact V7 reports we decoded and compared with Apple's native
MultitouchSupport parser. It is not a specification for every Apple trackpad.

The production app receives parsed native `MTTouch` callbacks through FLTR.
This report specification preserves the independent decoding research.

## Report framing

Offsets below include the report ID as byte zero. A transport API that supplies
the report ID separately must normalize its buffer before applying these offsets.

| Transport | Report ID | First contact offset | Header |
| --- | --- | --- | --- |
| Bluetooth | `0x31` | 4 | Four-byte Compact header. |
| USB | `0x02` | 12 | Eight-byte wrapper followed by a four-byte Compact header. |

Each contact is **9 bytes**. For the decoder we implemented:

```text
offset = report[0] == 0x31 ? 4 : report[0] == 0x02 ? 12 : reject
require length >= offset
require (length - offset) % 9 == 0
contactCount = (length - offset) / 9
require contactCount <= 15
```

The maximum of 15 contacts was our decoder's bound, not an independently proven
hardware maximum. Zero-contact packets are valid. There is no contact-count field
used by this decoder: count comes from the payload length.

The decoder extracted button bits as `report[1] & 0x03`. It did not use the
remaining header/wrapper bits for contact conversion. Do not infer meanings for
unused bits from this implementation.

The Compact header begins at `h = offset - 4`. Its **21-bit millisecond sensor
clock** is:

```text
ticks = (report[h+1] >> 3)
      | (report[h+2] << 5)
      | (report[h+3] << 13)
```

The epoch wraps at `0x200000` milliseconds (2,097.152 seconds). Maintain the unwrap
state per device, including empty packets. The original implementation added one
epoch whenever a new tick value was less than the previous value, so session,
gap and discontinuity resets are necessary; a decreasing tick alone does not
prove a wrap rather than a reset or out-of-order delivery.

## Nine-byte contact record

Let `c[0]...c[8]` be one contact. Bit numbers are least-significant-bit first.

| Byte | Bits | Decoded meaning |
| --- | --- | --- |
| 0 | 0–7 | X bits 0–7. |
| 1 | 0–4 | X bits 8–12. |
| 1 | 5–7 | Y bits 0–2. |
| 2 | 0–7 | Y bits 3–10. |
| 3 | 0–1 | Y bits 11–12. |
| 3 | 2–4 | Native finger/category code. |
| 3 | 5–7 | Native contact state. |
| 4 | 0–7 | Encoded major-axis scalar. |
| 5 | 0–7 | Encoded minor-axis scalar. |
| 6 | 0–7 | Encoded size/total scalar. |
| 7 | 0–7 | Encoded pressure scalar. |
| 8 | 0–3 | Tracking ID, 0–15. |
| 8 | 4 | Extra/sentinel bit; reconstructed velocity is suppressed when set. Broader meaning unestablished. |
| 8 | 5–7 | Angle code, 0–7. |

Both coordinates are signed 13-bit two's-complement values:

```text
x13 = c[0] | ((c[1] & 0x1f) << 8)
y13 = (c[1] >> 5) | (c[2] << 3) | ((c[3] & 0x03) << 11)
signed13(v) = (v & 0x1000) != 0 ? v - 0x2000 : v
```

| State code (`c[3] >> 5`) | Native callback state |
| --- | --- |
| 0 | notTouching |
| 1 | starting |
| 2 | hovering |
| 3 | making |
| 4 | touching |
| 5 | breaking |
| 6 | lingering |
| 7 | leaving |

Finger/category is `(c[3] >> 2) & 7`, with native remapping **7 → 12**;
other values are preserved. Tracking ID is independent of this classification.
The Compact V7 filler supplies **handID = 1**; we did not decode anatomical
left/right hand identity from these nine bytes. Do not turn tracking IDs or
category 12 into invented anatomical labels.

## Position calibration

Both tested pads exposed Sensor Surface Descriptor:

```text
f03c0000202b000044e352ffbd1ee426
```

Recovered native bounds were X `[-7356, 7869]`, Y `[-174, 9956]`, with reported
surface `15600 × 11040`. The callback conversion was:

```text
ax = clamp(signed13(x13) * 2,        -7356, 7869)
ay = clamp(signed13(y13) * 2 + 5000,  -174, 9956)
normalizedX = Float(ax + 7356) / 15225
normalizedY = Float(ay + 174) / 10130
absoluteX = Float(ax) / 100
absoluteY = Float(ay) / 100
```

These are the measured native coordinate units. Do not substitute the UI's
physical dimensions or assume these bounds for another sensor calibration.
The old takeover implementation checked the descriptor before applying them.

## Scalar conversions

The bytes for axes, total and pressure are compressed native scalars. Simple
linear Linux-style geometry scaling did not reproduce Apple's callback contract.
The recovered integer routines are preserved in the appendix below, including
unsigned wrapping, truncation and shift order.

After unpacking:

```text
majorAxis = Float(majorInteger) / 100
minorAxis = Float(minorInteger) / 100
total = Float(totalInteger) / 256
pressure = Float(pressureInteger)
angle = Float(c[8] >> 5) * Float.pi / 8
```

Pressure here reproduces the native callback value; no independent force-in-grams
calibration was established by this work.

Density uses family `0x81` parameters 600/430, measured in initialized native state:

```text
root = max(600, floor(sqrt(max(600, majorInteger) * max(600, minorInteger))))
densityInteger = Int16(truncatingIfNeeded: totalInteger * 400 / (root - 430))
density = Float(UInt16(truncatingIfNeeded: densityInteger)) / 256
```

The signed narrowing and subsequent unsigned interpretation are intentional parts
of the recorded implementation, even for synthetic outlying scalar inputs.

## Velocity and transition reconstruction

Velocity was reconstructed across packets, rather than extracted from a velocity
field in these nine bytes. State is keyed by **device and tracking ID**.

- Use unwrapped sensor milliseconds for `dt` in seconds. Arrival time is not the
  velocity denominator when sensor ticks are available.
- Require a previous sample, `0 < dt < 0.15`, state touching/breaking/lingering,
  and contact byte 8 bit 4 clear. Otherwise mark velocity unavailable and emit zero.
- Current position for the velocity difference is **unclipped**:
  `Float(signedX * 2) / 100`, `Float(signedY * 2 + 5000) / 100`.
  The previous position is the **clipped** callback position.
- Per axis, compute `q = truncTowardZero(Double(Float(delta * 8)) / dt)`,
  saturating to signed 16-bit `[-32768, 32767]`. `delta` subtraction occurs in Float.
- When both valid quantized components are zero, change X to 1: this matches the
  native zero-vector sentinel avoidance observed by the oracle.
- Absolute velocity is `Float(q) * 0.125`.
- Preserve native Float → Double → Float ordering for normalized velocity:
  X `Float(Double(Float(qx * 2) / 160) * 1000 / 15225)`;
  Y `Float(Double(Float(qy * 2) / 160) * 1000 / 10130)`.
- A state-zero packet immediately following making/touching becomes leaving when
  `0 <= dt < 0.04`. Do not retain notTouching/leaving as the next active sample.
- Reset prior-contact and clock state on session/discontinuity boundaries.

Source-frame values in the removed receiver were session sequence numbers, not a
recovered counter bit field in the contact bytes. Their origin can differ from
ordinary native callback frame counters.

Terminal notTouching records were kept in captures but excluded from the visible
contact snapshot. Original nine-byte records, enclosing reports, tick values,
conversion version 2 and velocity-availability flags were retained as optional
`telemetry.driverKit` provenance. Those serialized types remain for compatibility
with existing captures even after the executable DriverKit path is removed.

## Evidence and scope

Reference: installed MultitouchSupport **8440.5**, framework UUID
`B172DB85-9E88-3A4E-AB6E-B458FD373A58`, macOS **15.7.4 / 24G517**, Intel.
Read-only inspection and a native framework oracle were used; the app did not
embed Apple machine code or call oracle functions by pinned addresses.

The historical decoder tests covered all 256 input values for each scalar,
576 density cases, 256 filled contacts through both report wrappers, and 96
velocity/state cases. They also covered clock wrap and per-device isolation.
The saved native reference vectors remain in
[CompactV7NativeReference.json](Tests/ProductionEngineTests/Fixtures/CompactV7NativeReference.json).
See [preserved research](../RESEARCH_ARCHIVE.md) for native USB parity results
and their measurement limits.

This establishes the contact callback reconstruction for the tested sensor family,
not raw electrode images, all Apple gesture processing, universal firmware support,
or a complete interpretation of the USB wrapper and unused report bits.

## Exact scalar arithmetic retained from the decoder

The following is a documentation snapshot of the portable Swift conversions that
passed the reference comparisons. It is not linked into the production native callback path.

```swift
struct CompactV7Scalars {
    private static func square(_ value: Int64) -> Int64 { value * value }
    private static func smallRadius(_ value: Int64, bias: UInt32) -> Int {
        let squared = UInt64(square(value * 1024 - 76800)) >> 10
        // Preserve the native36-bit coefficient and narrowing/shift order.
        let curved = UInt32(truncatingIfNeeded: (squared &* 0xfffffffd8) >> 10)
        return Int((curved &+ bias) >> 10)
    }
    static func major(_ byte: UInt8) -> Int {
        let v = Int64(byte)
        if v == 0 { return 0 }
        if v < 50 { return smallRadius(v, bias: 0xb5400) }
        if v <= 169 { return Int((UInt32(truncatingIfNeeded: v << 21) &+ 0x25800000) >> 20) }
        let curved = UInt32(truncatingIfNeeded: square(v * 1024 - 0x29800) >> 12)
        return Int((curved &+ 0xea000) >> 10)
    }
    static func minor(_ byte: UInt8) -> Int {
        let v = Int64(byte)
        if v == 0 { return 0 }
        if v < 50 { return smallRadius(v, bias: 0x9c400) }
        if v <= 149 { return Int((UInt32(truncatingIfNeeded: v << 21) &+ 0x1f400000) >> 20) }
        let curved = UInt32(truncatingIfNeeded: ((square(v * 1024 - 0x228f0) >> 10) * 0x57) >> 10)
        return Int((curved &+ 0xc50f0) >> 10)
    }
    static func total(_ byte: UInt8) -> Int {
        let v = Int64(byte)
        if v == 0 { return 0 }
        if v <= 149 { return Int((v * 0x28f5) >> 10) }
        let curved = UInt32(truncatingIfNeeded: ((square(v * 1024 - 0x1bfee) >> 10) * 0x8a) >> 10)
        return Int((curved &+ 0x14f568) >> 10)
    }
    static func pressure(_ byte: UInt8) -> Int {
        let v = Int64(byte)
        if v < 128 { return Int(v * 2) }
        let curved = UInt32(truncatingIfNeeded: square(v * 1024 - 0x1827b) >> 15)
        return Int((curved &+ 0x3827b) >> 10)
    }
    static func density(total: Int, major: Int, minor: Int) -> Int {
        // Parameters600/430 read from initialized native family0x81 state on both pads.
        let root = max(600, Int(Double(max(600, major) * max(600, minor)).squareRoot()))
        return Int(Int16(truncatingIfNeeded: total * 400 / (root - 430)))
    }
}
```

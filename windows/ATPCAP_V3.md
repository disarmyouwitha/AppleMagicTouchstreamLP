# ATPCAP_V3 Acceptance Spec (Windows)

This document defines the **exact Windows-side changes** required to accept and replay `ATPCAP01` **version 3** captures produced by macOS.

## 1) Why this is required

Windows currently assumes:
- capture header version is exactly `2`.
- every record payload is raw HID bytes decoded via `TrackpadReportDecoder`.

macOS now writes:
- `ATPCAP01` header version `3`.
- same 34-byte record header shape, but payload semantics changed:
  - `deviceIndex == -1` => UTF-8 JSON meta payload.
  - non-meta records => `RFV3` binary frame payload (normalized contacts), not HID report bytes.

Without these changes, Windows rejects v3 files at header parse time and cannot decode payloads.

---

## 2) Canonical ATPCAP v3 layout to support

### File header (20 bytes)
1. `magic` (8 bytes ASCII): `ATPCAP01`
2. `version` (Int32 LE): `3`
3. `tickFrequency` (Int64 LE)

### Record header (34 bytes)
1. `payloadLength` (Int32 LE)
2. `arrivalTicks` (Int64 LE, monotonic capture timeline ticks)
3. `deviceIndex` (Int32 LE)
4. `deviceHash` (UInt32 LE)
5. `vendorId` (UInt32 LE)
6. `productId` (UInt32 LE)
7. `usagePage` (UInt16 LE)
8. `usage` (UInt16 LE)
9. `sideHint` (UInt8: 0 unknown, 1 left, 2 right)
10. `decoderProfile` (UInt8: currently 0 from mac writer)

### Record payloads
- Meta record: `deviceIndex == -1`
  - UTF-8 JSON object:
    - `type: "meta"`
    - `schema: "g2k-replay-v1"`
    - `capturedAt`, `platform`, `source`, `framesCaptured`
- Frame record: `deviceIndex >= 0`
  - Binary payload:
    1. `frameMagic` (UInt32 LE) = `0x33564652` (`RFV3`)
    2. `seq` (UInt64 LE)
    3. `timestampSec` (Float64 LE)
    4. `deviceNumericID` (UInt64 LE)
    5. `contactCount` (UInt16 LE)
    6. `reserved` (UInt16 LE)
    7. repeated contact entries (40 bytes each):
      - `id` (Int32 LE)
      - `x` (Float32 LE)
      - `y` (Float32 LE)
      - `total` (Float32 LE)
      - `pressure` (Float32 LE)
      - `majorAxis` (Float32 LE)
      - `minorAxis` (Float32 LE)
      - `angle` (Float32 LE)
      - `density` (Float32 LE)
      - `state` (UInt8, canonical 0..7)
      - `reserved` (3 bytes)

### Cross-platform interoperability contract (MUST)

For **mac capture <-> windows replay** and **windows capture <-> mac replay**, Windows implementation MUST satisfy all of these:

1. Writer/reader support:
- Reader MUST accept v2 and v3.
- Writer used for cross-platform captures MUST emit v3.

2. Frame payload shape:
- Every v3 frame payload MUST be exactly `32 + contactCount * 40` bytes.
- Windows MUST NOT omit fields it does not naturally produce.
- If Windows lacks values (`total`, `pressure`, `majorAxis`, `minorAxis`, `angle`, `density`), it MUST write `0` for those fields, not shorten payload.

3. Canonical state semantics:
- Windows MUST write canonical `state` code `0..7`.
- Windows replay MUST map canonical states into engine flags consistently (mapping in section B.4).

4. Record header invariants:
- `deviceIndex`, `deviceHash`, `sideHint`, and timing fields MUST be written and preserved in replay path.
- Meta record MUST be written as `deviceIndex == -1` with JSON payload (`type=meta`, `schema=g2k-replay-v1`).

5. Compatibility guarantee:
- Mac parser is v3 frame-structure strict; malformed/short v3 payloads will be rejected.
- Therefore, zero-fill is required for unavailable fields to maintain compatibility.

6. Replay timing contract:
- Replay timing MUST be derived from `arrivalTicks` + file `tickFrequency`.
- `timestampSec` in RFV3 payload is informational/debug and MUST NOT drive replay timing.
- `arrivalTicks` MUST be monotonic non-decreasing for frame records. Non-monotonic captures are invalid and should fail parse/replay (no repair path required).
- Writers SHOULD source `arrivalTicks` from a host-monotonic clock taken at capture ingest time.

---

## 3) Required code changes (file-by-file)

## A. `Core/Diagnostics/InputCaptureFile.cs`

1. Accept v3 in reader:
- Replace strict equality check:
  - current: `if (version != InputCaptureFile.CurrentVersion) throw ...`
  - required: accept both versions `2` and `3`.

2. Writer/read constants for cross-compat:
- Add explicit constants:
  - `CurrentWriteVersion = 3` (for cross-platform capture/replay parity)
  - `SupportedReadVersions = { 2, 3 }`
- Optional legacy path may keep v2 writer behind an explicit opt-in flag, but default should be v3.

3. Expose header version on `InputCaptureReader`:
- Add `public int HeaderVersion { get; }`.
- Set it from parsed header to allow downstream branching.

No record-header size changes are required.

---

## B. Add new v3 payload parser module

Add a new file, for example:
- `Core/Diagnostics/AtpCapV3Payload.cs`

Implement:

1. `TryParseMeta(ReadOnlySpan<byte> payload, out AtpCapV3Meta meta)`
- UTF-8 JSON decode.
- Validate `type == "meta"` and schema `g2k-replay-v1`.

2. `TryParseFrame(ReadOnlySpan<byte> payload, out AtpCapV3Frame frame)`
- Validate minimum 32 bytes.
- Validate `RFV3` magic.
- Validate `payload.Length == 32 + contactCount * 40`.

3. `InputFrame ToInputFrame(AtpCapV3Frame frame, long arrivalQpcTicks, ushort maxX, ushort maxY)`
- Convert normalized floats into `InputFrame`:
  - `X = clamp(round(x * maxX), 0..maxX)`
  - `Y = clamp(round(y * maxY), 0..maxY)`
- Set `InputFrame.ReportId` to `0x52` (RFV3 marker low byte), or keep stable chosen constant.
- Set `InputFrame.ScanTime` from `seq & 0xFFFF`.
- Set `InputFrame.ContactCount` from parsed count.
- Set `InputFrame.IsButtonClicked = 0` (v3 payload does not carry click state).

4. State->Flags mapping (required for engine semantics):

Canonical states:
- `0 notTouching`
- `1 starting`
- `2 hovering`
- `3 making`
- `4 touching`
- `5 breaking`
- `6 lingering`
- `7 leaving`

Map to `ContactFrame.Flags`:
- `notTouching(0)` -> `0x00`
- `hovering(2)` -> `0x01` (confidence only)
- `lingering(6)` -> `0x01` (confidence only)
- `leaving(7)` -> `0x01` (confidence only)
- `starting/making/touching/breaking (1/3/4/5)` -> `0x03` (confidence + tip)

Use `Pressure=0`, `Phase=0` unless later extended.

---

## C. `Core/Diagnostics/ReplayRunner.cs`

Inside the replay read loop:

1. Branch by `reader.HeaderVersion`.

2. For v2:
- Keep existing `TrackpadReportDecoder.TryDecode(...)` path unchanged.

3. For v3:
- If `record.DeviceIndex == -1`: parse meta payload and skip dispatch.
- Else parse frame payload with new v3 parser.
- Build `InputFrame` via `ToInputFrame(...)`.
- Dispatch to actor exactly as v2 path does.

4. Timing:
- Keep existing `relativeQpc -> Stopwatch` conversion using `reader.HeaderQpcFrequency`.
- Do not use payload `timestampSec` for replay timing.
- Validate frame-record `arrivalTicks` is monotonic non-decreasing; fail replay if violated.

5. Side resolution:
- Keep using `ReplaySideMapper.Resolve(record.DeviceIndex, record.DeviceHash, record.SideHint)`.
- `sideHint` and `deviceIndex` from mac records remain valid.

6. Fingerprinting:
- Reuse existing `Fingerprint(...)` over `InputFrame` so determinism checks continue unchanged.

---

## D. `Core/Diagnostics/ReplayVisualData.cs`

1. Add same v2/v3 branch as ReplayRunner.
2. For v3:
- parse frame payload to `InputFrame`.
- include in visual frames list.
- meta records are skipped.
3. Device aggregation should still use `(DeviceIndex, DeviceHash)` from record header.

---

## E. `Core/Diagnostics/RawCaptureAnalyzer.cs`

1. Add header version branch.
2. For v2:
- keep existing deep HID/PTP decode analysis unchanged.
3. For v3:
- implement signature analysis over record headers and payload shape:
  - signature fields stay `(vendorId, productId, usagePage, usage, reportId, payloadLength)`.
  - for RFV3 frames: `reportId` can be first payload byte (`0x52`).
- keep `recordsRead`/`recordsDecoded` counters meaningful:
  - decoded = count of successfully parsed RFV3 frame payloads.

4. For `--raw-analyze-contacts-out` in v3 mode:
- emit CSV rows based on parsed RFV3 contacts (not PTP slot bytes).
- do not fabricate slot-byte lifecycle fields; leave them empty or remove in v3 branch output schema.

---

## F. `README.md` + spec notes

Update docs to state:
- replay supports `.atpcap` v2 and v3.
- v3 is normalized frame payload from macOS capture.
- `--raw-analyze-out` supports v3 with reduced/adjusted fields where raw HID-only concepts do not exist.

Also remove stale line:
- "replay expects v2 captures"

---

## G. Self-tests (required)

Add deterministic tests that build a synthetic v3 capture and validate:
1. Reader accepts header version 3.
2. ReplayRunner processes v3 frames with no decode drops.
3. Replay determinism pass1 == pass2 for v3 capture.
4. Raw analyzer returns non-empty signatures and decoded frame counts for v3 capture.

Suggested location:
- `Core/Diagnostics/SelfTestRunner.cs`

---

## H. Capture-only performance note (required guidance)

RFV3 conversion overhead is relevant **only when capture recording is enabled**.  
It is acceptable to prioritize correctness over micro-optimization here, but do not move conversion/file I/O into the live input callback thread.

Minimum recommended approach:
- keep non-capture runtime path unchanged (no extra work when capture is off),
- enqueue capture frames into a bounded queue from callback thread,
- perform RFV3 packing + disk writes on a dedicated writer thread,
- use reusable/preallocated buffers to avoid callback-path allocation spikes.

This keeps capture mode from perturbing live input timing while still enabling cross-platform captures.

---

## 4) Backward compatibility rules

Required behavior:
- v2 replay must remain unchanged.
- v3 replay must be accepted.
- unknown versions must still fail with explicit error.
- v3 capture write must be the default for cross-platform interoperability.

This means **read support broadens**, and **write default moves to v3** (with optional legacy v2 writer only as an explicit non-default fallback).

---

## 5) Exact acceptance criteria

Windows is ATPCAP_V3-ready when all are true:

1. `dotnet run ... --replay <mac_v3_capture.atpcap>` completes without version/decode failure.
2. Replay determinism is true for v3 captures (pass1 == pass2 fingerprints/counters).
3. `dotnet run ... --raw-analyze <mac_v3_capture.atpcap> --raw-analyze-out <out.json>` writes JSON successfully.
4. Existing v2 replay fixtures still pass unchanged.
5. README and spec text no longer claim "v2 only" replay.

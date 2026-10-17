# GlassToKey Capture Format (`.atpcap`)

Canonical replay captures use `.atpcap` (`ATPCAP01`) with a versioned binary layout.

## File Header (20 bytes)

1. `magic` (8 bytes ASCII): `ATPCAP01`
2. `version` (Int32 LE): current macOS writer version is `5`
3. `tickFrequency` (Int64 LE): ticks per second (macOS currently writes `1_000_000_000`)

## Record Header (34 bytes, repeated)

1. `payloadLength` (Int32 LE)
2. `arrivalTicks` (Int64 LE)
3. `deviceIndex` (Int32 LE)
4. `deviceHash` (UInt32 LE)
5. `vendorID` (UInt32 LE)
6. `productID` (UInt32 LE)
7. `usagePage` (UInt16 LE)
8. `usage` (UInt16 LE)
9. `sideHint` (UInt8): `0 unknown`, `1 left`, `2 right`
10. `decoderProfile` (UInt8): reserved on macOS writer (`0`)

## Record Payloads (v5)

- Meta record: `deviceIndex == -1`, payload is UTF-8 JSON:
  - `type: "meta"`
  - `schema: "g2k-replay-v1"`
  - `capturedAt`, `platform`, `source`, `framesCaptured`
- Processed frame record: `deviceIndex == -5`, payload is UTF-8 JSON:
  - `type: "processedFrameRecord"`
  - `record.frame`:
    - `sequence`
    - `timestamp`
    - `deviceNumericID`
    - `deviceIndex`
    - `contacts`
    - `rawTouches`
  - `record.arrivalTicks`
  - `record.dispatchEvents`

The committed replay fixtures use the lean v5 subset:
- no render snapshot payload
- no ingress payload
- no diagnostics payload
- no dispatch events unless the source capture actually had them

## Canonical States

`0 notTouching`, `1 starting`, `2 hovering`, `3 making`, `4 touching`, `5 breaking`, `6 lingering`, `7 leaving`.

## Compatibility

- Capture fixtures are `.atpcap` only.
- Transcript artifacts may remain `.jsonl` for parity/debug output.
- Legacy v3/v4 captures are migrated with `swift run ATPCaptureTranscode`; normal replay parsing is v5-only.

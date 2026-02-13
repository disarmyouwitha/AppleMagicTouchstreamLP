# Official Apple USB-C Driver Notes (GlassToKey)

## Purpose
This is the reverse-engineering handoff for official Apple USB-C driver packets in GlassToKey.

Target transport observed so far:
- `VID 0x05AC`
- `PID 0x0265` and `PID 0x0324`
- `usagePage=0x00`, `usage=0x00`
- `reportId=0x05`
- report length `50` bytes

Primary decoder code:
- `GlassToKey/TrackpadReportDecoder.cs`

## Packet Layout Findings
Important finding: the official stream does not match standard Windows PTP field semantics even though packet size is 50 bytes.

Current best contact  slot model:
- slot size: `9` bytes
- slot base: `slotOffset = 1 + contactIndex * 9`
- decoded contact count still taken from report tail (`ContactCount` from parsed frame)

Current coordinate extraction:
- `X raw = LE u16 [slot+2 .. slot+3]`
- `Y raw = LE u16 [slot+4 .. slot+5]`

Current normalization behavior:
- `Id = contactIndex` (stable, avoids giant packed IDs/jumping)
- `Flags = (flags & 0xFC) | 0x03` (force tip + confidence true)

Why:
- Earlier packed-coordinate interpretation produced severe wrap and jumps.
- Earlier overlapping byte choices contaminated one axis with non-position signals.
- This non-overlapping mapping produced stable, usable motion in live tests.

## Scaling Findings
Axis raw ranges are not symmetric in this stream, so axis-specific maxima are required.

Current constants:
- `OfficialMaxRawX = 14720`
- `OfficialMaxRawY = 10240`

Current scaling function:
- `scaled = clamp(raw, 0..maxRaw) * targetMax / maxRaw` (with rounding)
- target ranges still use runtime defaults (`DefaultMaxX`, `DefaultMaxY`)

Observed behavior that drove these constants:
- Y originally looked like ~75 percent travel because it was scaled as if max raw were ~16383.
- After Y max changed to `10240`, Y reached near full height.
- X was then short by roughly ~10 percent; reducing X max to `14720` corrected width coverage in live test.

## Known Good Outcomes So Far
- No hard crash on official captures after guards were added.
- Contact count is accurate in official press tests.
- ID instability is resolved (no huge jumping IDs).
- X and Y now both track with good stability in current live feedback.

## Known Unknowns
- Some non-position bits likely still exist in nearby slot bytes (`+1`, `+7`, `+8`).
- We still have not isolated true stable contact identity bytes for usage `0/0` official stream.

## Runtime Stability Guardrails
Raw input exception handling now includes:
- structured fault logging to `%LOCALAPPDATA%\GlassToKey\runtime-errors.log`
- contextual packet dump fields (VID/PID/usage/report index/report hex prefix)
- temporary raw-input pause after repeated faults (prevents rapid lockup loops)

## Analyzer + Validation Workflow
Decoder debug output:
- add `--decoder-debug` to print per-side chosen decode profile and sample contact fields.
- `--decoder-debug` now also prints per-contact `rawId -> assignedId` mapping when the frame is PTP-decodable.

Raw analyzer contact trace:
- add `--raw-analyze-contacts-out <path>` to emit per-contact CSV rows with:
  - raw parsed PTP fields (`raw_contact_id`, `raw_flags`, `raw_x`, `raw_y`)
  - decoded assigned fields (`assigned_contact_id`, `assigned_flags`, `decoded_x`, `decoded_y`)
  - slot bytes (`slot_hex`) and `slot_offset` for byte-level reverse-engineering

## Tuning Procedure (If Scaling Drifts Again)
Use this exact process:

1. Record a one-finger full-width sweep and full-height sweep separately.
2. Compute raw axis min/max from the chosen slot byte pairs.
3. Set axis max slightly above observed max (about 3 to 8 percent headroom).
4. Rebuild and verify full-range visual coverage.
5. Keep X and Y scaling independent.

Practical note:
- If an axis tops out early, `maxRaw` is too high.
- If an axis overshoots/clamps too early at extremes, `maxRaw` is too low.

## Recommended Next Reverse-Engineering Steps
1. Use `--raw-analyze-contacts-out` captures to correlate candidate stable-ID bytes (for example slot `+1`, `+7`, `+8`) against `raw_contact_id` drift.
2. Isolate tip/confidence bits using stationary-finger force ramps.

## Quick Context Summary For Next Session
- Official USB-C path is now usable with profile-aware decoding and runtime stability guards.
- Current slot decode and axis scales are empirical but working in live tests.
- Remaining work is mostly flag semantics and richer diagnostics, not crash triage.

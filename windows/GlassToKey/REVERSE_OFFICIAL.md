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
- `Id = slot byte +0` (`payload[slotOffset + 0]`) for usage `0/0` official stream
  - duplicate-safe fallback: first free byte in `0..255` (no fallback to `contactIndex`)
- `Flags = (flags & 0xFC) | 0x03` (force tip + confidence true)

Why:
- Earlier packed-coordinate interpretation produced severe wrap and jumps.
- Earlier overlapping byte choices contaminated one axis with non-position signals.
- This non-overlapping mapping produced stable, usable motion in live tests.

## Empirical Contact-ID Findings (capture.atpcap, analyzed 2026-02-13)
Dataset summary:
- `records=1044`, `decoded=1044`, `usage=0x00/0x00`, `reportId=0x05`, `len=50`
- contact rows in CSV: `2594`
- contact-count distribution by frame (non-zero contact frames): `1 finger=151`, `2 fingers=230`, `3 fingers=661`

Raw ID reality in this stream:
- `raw_contact_id` is exactly `LE u32 [slot+1 .. slot+4]` in every row (`2594/2594`).
- low byte of `raw_contact_id` is always `0x00` (`2594/2594`), so it is not a normal independent finger/session ID field.
- because bytes `+2..+5` are already used by position, `raw_contact_id` drifts with motion.

Byte candidacy results for stable identity:
- `slot+1` (`b1`) is constant `0` in this capture (not useful).
- `slot+7` (`b7`) is constant `0` in this capture (not useful).
- `slot+8` (`b8`) is almost always `3` and briefly `1` on transition moments (`9` rows total), likely state/quality not identity.
- `slot+0` (`b0`) is the strongest candidate:
  - no collisions among simultaneous contacts (0 collision frames in this capture)
  - nearest-neighbor contact continuation stability: `100%` (`2584/2584` matched continuations)
  - remained stable in all observed slot-reassignment events that changed assigned ID

Continuity comparison (nearest-neighbor continuation, threshold 220 decoded units):
- `b0` stability: `100%` (`2584/2584`)
- current assigned ID (`contactIndex`) stability: `99.73%` (`2577/2584`) with `7` continuity breaks
- `raw_contact_id` stability: `41.83%` (`1081/2584`)

Working candidate model (research-only):
- `candidateStableId = payload[slotOffset + 0]` where `slotOffset = 1 + contactIndex * 9`
- implemented in decoder for official usage `0/0` path with duplicate-safe fallback

## Validation Follow-up (capture_new.atpcap, analyzed 2026-02-13)
Dataset summary:
- `records=2596`, `decoded=2596`, `usage=0x00/0x00`, `reportId=0x05`, `len=50`
- contact rows in CSV: `6176`
- contact-count distribution by frame (non-zero contact frames): `1 finger=732`, `2 fingers=577`, `3 fingers=834`, `4 fingers=447`

Stability and collision results:
- same-frame duplicate check: `0` duplicate frames for both `b0` and assigned ID.
- assigned ID matches `b0` in every row (`6176/6176`), so fallback was not needed in this capture.
- nearest-neighbor contact continuation stability (threshold 220 decoded units):
  - `b0`: `100%` (`6129/6129`)
  - assigned ID: `100%` (`6129/6129`)
  - `raw_contact_id`: `33.45%` (`2050/6129`)

Other byte notes:
- `slot+1` remained constant `0`.
- `slot+7` remained constant `0`.
- `slot+8` remained mostly `3` (`6128` rows) with brief `1` transitions (`48` rows), still consistent with a state/quality bit.

## IsButtonClicked Early Mapping (byte 49)
Analyzer support:
- raw summary now reports `button[...]` metrics (pressed frame count, down/up edges, run length, pressed with/without contacts).
- contact CSV now includes both decoded and raw button/tail context fields:
  - `decoded_is_button_clicked`, `raw_is_button_clicked`
  - `decoded_scan_time`, `raw_scan_time`, `raw_contact_count`

From `capture_new.atpcap` (first pass):
- `button[pressedFrames=39, downEdges=2, upEdges=1, maxRunFrames=38, withContacts=39, zeroContacts=0]`
- decoded/raw button fields matched on every row in the CSV (`0` mismatches).
- pressed windows were contiguous runs (`1595-1632` and `2595`), mostly while at least one contact remained active.

From `clicked.atpcap` (click-pattern capture):
- `button[pressedFrames=2576, downEdges=49, upEdges=48, maxRunFrames=766, withContacts=2576, zeroContacts=0]`
- decoded/raw button fields matched on all analyzed rows (`0` mismatches).
- run-length spread includes short and long windows, consistent with mixed short/long click script input.

Current interpretation:
- byte `49` is a strong click/down state signal in this transport.
- down/up edge parity can differ by 1 when a capture ends while still pressed.

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
- Whether `slot+0` (`b0`) remains stable across longer sessions, different hardware revisions, and reconnect/reboot boundaries.
- Exact semantics of `slot+8` toggles (`3 -> 1`) seen around release/transition boundaries.
- Whether a higher-entropy composite (`b0` + another byte) is needed for rare collisions in larger datasets.

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
  - decoded/raw tail/button context (`decoded_is_button_clicked`, `raw_is_button_clicked`, `decoded_scan_time`, `raw_scan_time`, `raw_contact_count`)
- this capture strongly indicates `raw_contact_id` is not a true stable identity field for usage `0/0`.
- raw analysis summary now includes `button[...]` metrics (pressed-frame count, down/up edges, run length, with/without contacts) for `IsButtonClicked` mapping work.

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
1. Validate `slot+0` as candidate stable ID across additional captures:
   - 1->2->3 staggered landings
   - remove/re-add middle finger
   - two-hand independent motion
   - reconnect/reboot sessions
2. Add analyzer-side collision reporting for `slot+0` (same-frame duplicate detection + continuity mismatch counters).
3. Isolate tip/confidence bits using stationary-finger force ramps.

## Quick Context Summary For Next Session
- Official USB-C path is now usable with profile-aware decoding and runtime stability guards.
- Current slot decode and axis scales are empirical but working in live tests.
- Remaining work is mostly flag semantics and richer diagnostics, not crash triage.

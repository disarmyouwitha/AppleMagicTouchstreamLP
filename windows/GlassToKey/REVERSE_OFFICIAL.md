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

## No-Click Tip/Confidence Isolation (tapnoclick*.atpcap, analyzed 2026-02-14)
Goal:
- separate contact-lifecycle and force-like signals from click state.

Datasets:
- `tapnoclick.atpcap`:
  - `records=4092`, `decoded=4092`, usage `0x00/0x00`, `reportId=0x05`, `len=50`
  - two VID signatures were present in this run, both with the same byte-behavior conclusions.
  - `button[pressedFrames=0, downEdges=0, upEdges=0, maxRunFrames=0, withContacts=0, zeroContacts=0]`
- `tapnoclick_RHS.atpcap`:
  - `records=2441`, `decoded=2441`, usage `0x00/0x00`, `reportId=0x05`, `len=50`
  - one accidental click run only:
    - `button[pressedFrames=61, downEdges=1, upEdges=1, maxRunFrames=61, withContacts=61, zeroContacts=0]`
    - pressed frame window was contiguous (`2073..2133`).

Byte-level outcomes:
- `slot+1` remained constant `0` in these no-click datasets.
- `slot+7` remained constant `0` in these no-click datasets.
- `slot+8` now has stronger lifecycle evidence:
  - down events: consistently `0x03`
  - hold events: almost always `0x03`
  - release events: consistently `0x01`
  - hold transition pattern is dominated by `0x03 -> 0x03` with a small `0x03 -> 0x01` edge at release moments.
- accidental click did not alter the `slot+8` release mapping in RHS capture:
  - during click-down frames, `slot+8` remained `0x03`
  - `slot+8 == 0x01` occurred on non-click frames at release transitions.
- `slot+6` is the strongest pressure/force candidate so far:
  - high-entropy, multi-level values while contact is active
  - values were always even in these captures
  - release-phase value collapsed to `0x00` (`releaseTop` for `slot+6` was entirely zero).

## Single-Finger Press-Phase Isolation (press.atpcap, analyzed 2026-02-14)
Goal:
- isolate click-edge behavior from finger-count effects using one contact only.

Dataset summary:
- `records=1673`, `decoded=1673`, usage `0x00/0x00`, `reportId=0x05`, `len=50`
- `contacts[min/avg/max]=0/1.00/1` (single-finger only)
- `button[pressedFrames=539, downEdges=3, upEdges=3, maxRunFrames=213, withContacts=539, zeroContacts=0]`

Key outcomes:
- `slot+8` remained consistent with lifecycle-state behavior:
  - button-down rows still held `slot+8=0x03`
  - `slot+8=0x01` appeared only at release transitions (`2` rows).
- `slot+7` changed only during button-down windows in this one-finger run:
  - button-up rows: `slot+7` stayed `0x00` (`1132/1132`)
  - button-down rows: `slot+7` distributed across `0x00/0x01/0x02/0x03` (`0x03` most common).
- `slot+6` rose sharply during press/click phase:
  - button-up rows: lower range, even-only values (`min/avg/max ~ 0/58/124`)
  - button-down rows: wider/higher range (`min/avg/max ~ 1/163/254`) with odd values present.
- interpretation from this dataset:
  - `slot+7` is unlikely to be a pure finger-count classifier (it varies with one finger present).
  - `slot+7` is likely a click/force phase-class signal.
  - `slot+6` remains the leading analog force/pressure candidate.

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
- Exact final semantic labels for `slot+8` states (`3` active vs `1` release/transition) and whether any rare third state exists in larger datasets.
- Exact mapping from `slot+6` analog-like behavior to force/pressure and/or confidence semantics.
- Exact semantics of `slot+7` state classes (`0..3`) during button-down/click-force windows.
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
- raw analysis summary also includes slot-byte lifecycle stats for `slot+1`, `slot+6`, `slot+7`, `slot+8`:
  - per-byte event counts split by `down`, `hold`, `release`
  - top value histograms per lifecycle phase
  - top hold transitions (`from -> to`) for correlation with contact-state changes
- raw analysis summary now includes button-correlated slot stats for `slot+6/+7/+8`:
  - top values when button is up vs down
  - odd/even and non-zero counters (`slot+6` odd, `slot+7` non-zero, `slot+8==1`) by button state
  - per-contact snapshots on button down/up edge frames.

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
2. Calibrate `slot+6` as force proxy with controlled one-finger ramps:
   - no-click ramps first
   - then identical ramps with deliberate click windows
   - compare `slot+6` trajectories at matched positions.
3. Characterize `slot+7` click-phase states:
   - one-finger click cycles (`down -> click -> unclick` while finger stays planted)
   - compare one-finger vs two/three-finger click/tap-click captures
   - build state-transition map for `slot+7` around button edges.
4. Recover tip/confidence semantics:
   - test edge/partial contacts and rolling/faint touches
   - correlate candidate rules against `slot+8` release marker behavior
   - remove forced `| 0x03` only after stable rule confidence.
5. Add analyzer-side collision reporting for `slot+0` (same-frame duplicate detection + continuity mismatch counters).

## Quick Context Summary For Next Session
- Official USB-C path is now usable with profile-aware decoding and runtime stability guards.
- Current slot decode and axis scales are empirical but working in live tests.
- Strong current byte hypotheses:
  - `slot+8`: contact lifecycle marker (`0x03` active, `0x01` release transition)
  - `slot+6`: analog force/pressure candidate
  - `slot+7`: click/press phase-class signal (observed non-zero only in button-down windows in single-finger press capture)
- Remaining work is mostly final semantic labeling and rule confidence, not crash triage.

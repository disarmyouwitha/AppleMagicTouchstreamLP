# Official USB-C Decoder Spec (Confirmed)

Last updated: 2026-02-14

This document records only confirmed behavior for the official Apple USB-C stream used by GlassToKey. It consolidates:
- implemented decoder behavior (`TrackpadReportDecoder.cs`, `PtpReport.cs`)
- capture-confirmed findings from analyses run on 2026-02-13 and 2026-02-14

## 1. Scope and Stream Signature

Confirmed stream signature:
- Vendor ID: `0x05AC`
- Product IDs observed: `0x0265`, `0x0324`
- Raw Input usage pair: `usagePage=0x00`, `usage=0x00`
- Report ID: `0x05`
- Report length: `50` bytes

## 2. Report Structure (50-byte packet)

Confirmed byte layout for `reportId=0x05` packets:
- Byte `0`: `ReportId`
- Bytes `1..45`: 5 contact slots, each 9 bytes
  - slot `i` base: `slotOffset = 1 + i*9`
- Bytes `46..47`: `ScanTime` (little-endian `u16`)
- Byte `48`: `ContactCount`
- Byte `49`: `IsButtonClicked`

Contact slot byte mapping in the parser:
- `slot+0`: `Flags` byte in raw PTP parse
- `slot+1..4`: `ContactId` (`u32` little-endian) in raw PTP parse
- `slot+5..6`: `X` (`u16` little-endian) in raw PTP parse
- `slot+7..8`: `Y` (`u16` little-endian) in raw PTP parse

## 3. Implemented Official Decode Rules (usage 0/0 path)

For non-native touchpad usage (`usagePage/usage != digitizer/touchpad`), the official profile applies:
- slot stride: `9` bytes, `slotOffset = 1 + i*9`
- assigned contact ID source: `payload[slotOffset + 0]`
- duplicate-safe ID policy:
  - use candidate byte directly when unused
  - on collision, assign first free ID in `0..255`
- coordinate extraction:
  - `rawX = LE u16 [slot+2..3]`
  - `rawY = LE u16 [slot+4..5]`
- force/phase extraction (implemented):
  - `pressureRaw = payload[slotOffset + 6]` (8-bit)
  - `phaseRaw = payload[slotOffset + 7]` (8-bit state-class value; observed set `0..3`)
- flags normalization:
  - `normalizedFlags = (rawFlags & 0xFC) | 0x03`
- this forces tip+confidence bits on output contacts

Locked decoder contract (current):
- `slot+6` is the official-stream source for per-contact pressure signal `p`.
- `slot+7` is the official-stream source for per-contact phase signal `ph`.
- `slot+8` remains lifecycle (`0x03` active/hold, `0x01` release in all analyzed datasets).

## 4. Coordinate Scaling (Implemented)

Confirmed constants:
- `OfficialMaxRawX = 14720`
- `OfficialMaxRawY = 10240`
- target ranges: `RuntimeConfigurationFactory.DefaultMaxX` and `RuntimeConfigurationFactory.DefaultMaxY`

Confirmed scaling function:
- `scaled = clamp(raw, 0..maxRaw) * targetMax / maxRaw` with rounding

## 5. Confirmed Identity Findings From Captures

### `capture.atpcap` (analyzed 2026-02-13)
- rows analyzed: `2594`
- `raw_contact_id` matched `LE u32 [slot+1..4]` in all rows (`2594/2594`)
- low byte of `raw_contact_id` was always `0x00` (`2594/2594`)
- simultaneous-contact collision frames for `slot+0` ID: `0`
- nearest-neighbor continuation stability (threshold 220):
  - `slot+0`: `2584/2584` (`100%`)
  - assigned `contactIndex`: `2577/2584` (`99.73%`)
  - `raw_contact_id`: `1081/2584` (`41.83%`)

### `capture_new.atpcap` (analyzed 2026-02-13)
- rows analyzed: `6176`
- same-frame duplicate check: `0` duplicate frames for `slot+0` and assigned ID
- assigned ID matched `slot+0` in all rows (`6176/6176`)
- nearest-neighbor continuation stability (threshold 220):
  - `slot+0`: `6129/6129` (`100%`)
  - assigned ID: `6129/6129` (`100%`)
  - `raw_contact_id`: `2050/6129` (`33.45%`)

## 6. Confirmed Button Mapping

Byte `49` is confirmed as `IsButtonClicked` in analyzed official captures:
- `capture_new.atpcap`: decoded vs raw button field mismatches = `0`
- `clicked.atpcap`: decoded vs raw button field mismatches = `0`

Observed edge-count property:
- `downEdges` and `upEdges` can differ by `1` when capture ends while still pressed.

## 7. Confirmed Byte-Level Behaviors

From no-click and press-isolation captures (2026-02-14):
- `slot+1` remained constant `0x00` in analyzed datasets.
- `slot+8` observed lifecycle pattern:
  - down/hold states predominantly `0x03`
  - release transitions observed as `0x01`
  - accidental click windows did not change release mapping behavior
- `slot+7` behavior:
  - no-click datasets: near-constant `0x00`
  - one-finger press dataset: non-zero values appear during button-down windows
- `slot+6` behavior:
  - no-click release phase collapsed to `0x00`
  - one-finger press dataset showed higher/wider values during button-down windows, including odd values

Pressure-batch captures in `captures/pressure/analysis` (analyzed 2026-02-14):
- `P00_idle_10s.atpcap`: `records=0`, `decoded=0`, `signatures=0` (no packet rows in this file).
- `P10_noclick_ramp_center_3x.atpcap`:
  - `button[pressedFrames=0, downEdges=0, upEdges=0]`
  - `slot+7` stayed `0x00` for all button-up rows.
- `P11_noclick_hold_levels_center.atpcap`:
  - `button[pressedFrames=0, downEdges=0, upEdges=0]`
  - `slot+7` stayed `0x00` for all button-up rows.
- `P20_clickhold_ramp_center_3x.atpcap`:
  - `button[pressedFrames=665, downEdges=3, upEdges=3]`
  - button-up rows: `slot+7` all `0x00`
  - button-down rows: `slot+7` includes `0x01/0x02/0x03`
- `P21_click_pulses_planted.atpcap`:
  - `button[pressedFrames=246, downEdges=20, upEdges=20]`
  - button-up rows: `slot+7` all `0x00`
  - button-down rows: `slot+7` includes `0x01`

Aggregated pressure-batch evidence (from `P10/P11/P20/P21`):
- `btnSlot rows[up=4808, down=911]`
- `s6Odd[up=0, down=100]` (odd `slot+6` observed only when button is down)
- `s7NonZero[up=0, down=411]` (non-zero `slot+7` observed only when button is down)
- `s8eq1[up=4, down=0]` (`slot+8==0x01` observed on non-click release rows only)

Scan-time behavior in these captures:
- byte pair `[46..47]` (raw/decode `ScanTime`) increments mostly by `110` or `120` counts per frame.

Phase-protocol captures in `captures/pressure/analysis` (analyzed 2026-02-14):
- `phaseA_light_noclick_10s.atpcap`:
  - `button[pressedFrames=0, downEdges=0, upEdges=0]`
  - `slot+7` (`ph`) stayed `0x00`; `slot+6` stayed in no-click range.
- `phaseB_ramp_to_click_10s.atpcap`:
  - `button[pressedFrames=221, downEdges=6, upEdges=6]`
  - `slot+7` (`ph`) remained `0x00` in both button-up and button-down rows.
- `phaseC_post_click_hold_10s.atpcap`:
  - `button[pressedFrames=1022, downEdges=1, upEdges=1]`
  - `slot+7` (`ph`) remained `0x00` in both button-up and button-down rows.
- `phaseD_force-pulse_cycles_10s.atpcap`:
  - `button[pressedFrames=1526, downEdges=3, upEdges=3]`
  - `slot+7` (`ph`) button-down values: `0x00/0x01/0x02/0x03`
  - transition behavior during button-down rows:
    - adjacent step transitions only (`0<->1`, `1<->2`, `2<->3`)
    - no skipped transitions (`|delta| > 1` not observed)
    - both upward and downward transitions observed (not monotonic in one direction)
  - `slot+6` showed wide range (`1..255`) with frequent odd values in button-down rows.

## 8. Force Runtime Exposure (Implemented, Experimental Semantics)

Current runtime/visualizer exposure for official stream contacts:
- per-contact `Pressure8` is sourced from `slot+6`
- per-contact `Phase8` is sourced from `slot+7`
- per-contact `ForceNorm` is currently computed as:
  - `ph=0`: `fn = p` (`0..255`)
  - `ph=1`: `fn = 255 + p` (`255..510`)
  - `ph=2`: `fn = 510 + p` (`510..765`)
  - `ph=3`: `fn = 765 + min(p,220)` (`765..985`)
- shared helper and max constant:
  - `ForceNormalizer.Compute(pressure, phase)`
  - `ForceNormalizer.Max == 985`

Interpretation status:
- extraction and scaling are implemented and validated in live debugging.
- final semantic labels for each phase value remain research-open.

## 9. Runtime Guardrails (Implemented)

Raw-input fault handling includes:
- exception logging to `%LOCALAPPDATA%\GlassToKey\runtime-errors.log`
- contextual raw-input packet metadata in fault logs
- temporary raw-input pause after repeated faults (`3` consecutive faults -> `2` second pause)

## 10. Analyzer Outputs (Implemented)

Analyzer support confirms:
- button summary metrics (`pressedFrames`, `downEdges`, `upEdges`, run-length, with/without contacts)
- per-contact CSV output including:
  - raw parsed fields
  - decoded assigned fields
  - slot bytes and slot offset
  - decoded/raw button and tail context fields
- slot lifecycle and button-correlated stats for `slot+1`, `slot+6`, `slot+7`, `slot+8`

## 11. Not Yet Confirmed

The following are explicitly still open:
- long-session and cross-reconnect stability limits for `slot+0` identity
- final semantic labels for `slot+8` states beyond observed `0x03` active / `0x01` release
- exact physical units and calibration mapping for `slot+6` (`p`) and per-state semantics for `slot+7` (`ph`)
- whether composite identity beyond `slot+0` is required for rare edge cases

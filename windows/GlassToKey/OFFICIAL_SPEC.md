# Official USB-C Decoder Spec (Confirmed)

Last updated: 2026-02-14

This document records only confirmed behavior for the official Apple USB-C stream used by GlassToKey.
- implemented decoder behavior (`TrackpadReportDecoder.cs`, `PtpReport.cs`)

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

Locked scope note:
- `slot+0` is the active per-contact identity key used by decoder/runtime for current-touch tracking.
- long-horizon identity across reconnect/reboot is out of scope for current lock criteria.

## 4. Coordinate Scaling (Implemented)

Confirmed constants:
- `OfficialMaxRawX = 14720`
- `OfficialMaxRawY = 10240`
- target ranges: `RuntimeConfigurationFactory.DefaultMaxX` and `RuntimeConfigurationFactory.DefaultMaxY`

Confirmed scaling function:
- `scaled = clamp(raw, 0..maxRaw) * targetMax / maxRaw` with rounding

## 5. Confirmed Button Mapping

Byte `49` is confirmed as `IsButtonClicked` in analyzed official captures:
- `capture_new.atpcap`: decoded vs raw button field mismatches = `0`
- `clicked.atpcap`: decoded vs raw button field mismatches = `0`

## 6. Confirmed Byte-Level Behaviors

Lock decisions from pressure/phase protocols:
- `slot+6` is locked as the definitive pressure signal byte (`p`).
- `slot+7` is locked as the definitive phase/state signal byte (`ph`).
- `slot+8` is locked for active/release mapping currently observed:
  - `0x03` active/hold
  - `0x01` release
  - `0x02` has not been observed in analyzed datasets to date.

Scan-time behavior in these captures:
- byte pair `[46..47]` (raw/decode `ScanTime`) increments mostly by `110` or `120` counts per frame.

## 7. Force Runtime Exposure (Implemented, Experimental Semantics)

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
- extraction and scaling are implemented and validated in prod.
- final semantic labels for each phase value remain optional research-open, but source bytes are locked.

## 8. Runtime Guardrails (Implemented)

Raw-input fault handling includes:
- exception logging to `%LOCALAPPDATA%\GlassToKey\runtime-errors.log`
- contextual raw-input packet metadata in fault logs
- temporary raw-input pause after repeated faults (`3` consecutive faults -> `2` second pause)

## 9. Analyzer Outputs (Implemented)

Analyzer support confirms:
- button summary metrics (`pressedFrames`, `downEdges`, `upEdges`, run-length, with/without contacts)
- per-contact CSV output including:
  - raw parsed fields
  - decoded assigned fields
  - slot bytes and slot offset
  - decoded/raw button and tail context fields
- slot lifecycle and button-correlated stats for `slot+1`, `slot+6`, `slot+7`, `slot+8`

## 10. Not Yet Confirmed

The following are explicitly still open:
- whether any rare third `slot+8` state (for example `0x02`) exists in larger/edge-case datasets
- optional semantic naming refinements for `slot+7` state values (`0..3`)

## 11. Slot+8 Closure Protocol (Exact Script + Pass/Fail)

Use this only if you want to close the rare-state question (`slot+8==0x02`) before final freeze.

Capture set:
1. `S8A_edge_roll_noclick_20s.atpcap`
   - one finger
   - very light edge/partial contacts, rolling in/out, no click
2. `S8B_two_finger_stagger_release_20s.atpcap`
   - two fingers planted
   - alternate staggered lift/replant cycles, no click
3. `S8C_three_finger_stagger_release_20s.atpcap`
   - three fingers planted
   - remove/re-add middle finger repeatedly, no click
4. `S8D_click_and_force_pulse_20s.atpcap`
   - one finger
   - click-hold with force pulses (deep press cycles)


Analyze command pattern:
```powershell
dotnet run --project .\GlassToKey\GlassToKey.csproj -c Release -- --raw-analyze .\captures\pressure\analysis\<name>.atpcap --raw-analyze-out .\captures\pressure\analysis\<name>.json --raw-analyze-contacts-out .\captures\pressure\analysis\<name>.csv | Tee-Object .\captures\pressure\analysis\<name>.summary.txt
```

Pass/Fail thresholds:
- Pass lock (`slot+8` finalized to two-state active/release):
  - across `S8A..S8D`, `slot+8` unique set is only `{0x03, 0x01}`
  - `slot+8==0x01` occurs only on non-button-down release-side rows
  - no rows with `slot+8==0x02`
- Fail lock (needs update):
  - any reproducible `slot+8==0x02` rows
  - or `slot+8==0x01` frequently appearing during sustained active hold without release transitions

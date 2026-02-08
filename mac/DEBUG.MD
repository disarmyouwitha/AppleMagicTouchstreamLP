# Tap Trace (DEBUG)

## What the JSONL contains
Each line is one event. Key fields:

- `ts_ns`: Monotonic timestamp in nanoseconds (from `DispatchTime.now().uptimeNanoseconds`).
- `frame`: Internal tap-trace frame counter (increments once per processed touch frame).
- `touchKey`: Packed touch identifier: `(deviceIndex << 32) | touchId`.
- `type`: Tap lifecycle event: `created`, `updated`, `dispatched`, `disqualified`, `finalized`, `expired`.
- `keyCell`: Grid coordinates as `"row,col"` when available; `null` when not tied to a key cell.
- `keyCode`: The `CGKeyCode` sent for key actions; `null` if not applicable.
- `keyName`: Human label derived from `keyCode` for common keys; `null` if unknown.
- `char`: Unicode scalar value for single-character labels; `null` when not available.
- `charStr`: The single-character string for `char` when present; `null` otherwise.
- `reason`: Disqualification/expiration reason: e.g. `drag_cancelled`, `intent_mouse`, `timeout`.

## How to read the example
Example line:
```
{"ts_ns":257285439661198,"frame":3997,"touchKey":4294967304,"type":"dispatched","keyCell":"0,1","keyCode":32,"keyName":"U","char":85,"charStr":"U","reason":"none"}
```
Interpretation:
- A key dispatch occurred for touch `4294967304` at frame `3997`.
- It came from grid cell row 0, col 1.
- `keyCode` is the actual key sent (here `kVK_ANSI_U`), and `keyName` is the human label.
- `char`/`charStr` show the label when it’s a single character.

If `char` is `null`, the label likely isn’t a single character (e.g. "Space" or "Return").
In those cases, rely on `keyCode`/`keyName`.

## Reason codes (current)
- `none`
- `timeout`
- `collision`
- `cancelled`
- `disqualified_move`
- `typing_disabled`
- `intent_mouse`
- `drag_cancelled`
- `pending_drag_cancelled`
- `left_continuous_rect`
- `force_cap_exceeded`

## Tips
- Group by `touchKey` to see a complete lifecycle.
- Look for `disqualified` or `expired` without a `dispatched` to spot dropped taps.
- `frame` lets you correlate with other frame-based diagnostics.

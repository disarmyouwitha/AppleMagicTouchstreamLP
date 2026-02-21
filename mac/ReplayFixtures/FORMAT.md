# GlassToKey Replay Fixture Format (`g2k-replay-v1`)

Replay fixtures are newline-delimited JSON (`.jsonl`):

1. First line: `meta` record.
2. Remaining lines: `frame` records in capture order.

## Meta Record

```json
{
  "type": "meta",
  "schema": "g2k-replay-v1",
  "capturedAt": "2026-02-21T00:00:00Z",
  "platform": "macOS",
  "source": "ReplayFixtureCapture",
  "durationSeconds": 3.0,
  "maxFrames": 1200,
  "framesCaptured": 42,
  "selectedDevices": [
    {
      "deviceID": "123456789",
      "deviceNumericID": 123456789,
      "deviceIndex": 0,
      "deviceName": "Magic Trackpad",
      "isBuiltIn": false
    }
  ]
}
```

## Frame Record

```json
{
  "type": "frame",
  "schema": "g2k-replay-v1",
  "seq": 1,
  "timestampSec": 12345.6789,
  "deviceID": "123456789",
  "deviceNumericID": 123456789,
  "deviceIndex": 0,
  "touchCount": 2,
  "contacts": [
    {
      "id": 17,
      "x": 0.42,
      "y": 0.77,
      "total": 0.91,
      "pressure": 0.38,
      "majorAxis": 9.4,
      "minorAxis": 4.1,
      "angle": 0.12,
      "density": 0.56,
      "state": "touching"
    }
  ]
}
```

## Notes

- `schema` is included on every line to simplify streaming validation.
- `seq` is strictly increasing and starts at `1`.
- `timestampSec` is copied directly from the capture callback timestamp.
- Contacts preserve raw callback ordering and values.
- `state` values are: `notTouching`, `starting`, `hovering`, `making`, `touching`, `breaking`, `lingering`, `leaving`.

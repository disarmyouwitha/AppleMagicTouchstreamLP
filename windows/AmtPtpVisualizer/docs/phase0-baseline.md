# Phase 0 Baseline (2026-02-06)

## Scope
- Baseline is measured on offline replay, not live hardware.
- Goal is deterministic parser/routing validation and initial timing/allocation instrumentation.

## Commands
```powershell
dotnet build tools/AmtPtpVisualizer/AmtPtpVisualizer.csproj -c Release
dotnet run --project tools/AmtPtpVisualizer/AmtPtpVisualizer.csproj -c Release -- --selftest
dotnet run --project tools/AmtPtpVisualizer/AmtPtpVisualizer.csproj -c Release -- --replay tools/AmtPtpVisualizer/fixtures/replay/smoke.atpcap --fixture tools/AmtPtpVisualizer/fixtures/replay/smoke.fixture.json
```

## Recorded Replay Summary
- Capture: `tools/AmtPtpVisualizer/fixtures/replay/smoke.atpcap`
- Deterministic: `true` (two-pass fingerprint match)
- Fixture match: `true`
- Fingerprint: `0x14A29BB48FD73897`
- Frames seen: `2`
- Frames parsed: `1`
- Frames dispatched: `1`
- Frames dropped: `1` (expected non-multitouch report)

## Notes
- Live dual-device latency/allocation baseline should be recorded next with `--capture` + `--metrics-out` on target hardware.
- Parser tests currently cover valid decode + malformed short report rejection via `--selftest`.

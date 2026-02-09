# Phase 2-3 Engine Checkpoint (2026-02-06)

## Scope completed
- Added `Core/Engine` scaffolding with:
  - single-consumer `TouchProcessorActor` queue
  - open-addressed `TouchTable<T>`
  - precomputed `BindingIndex` with bucketed hit lookup + snap arrays
  - `EngineKeyAction`/`EngineKeyMapping` model with hold-action support
  - intent state machine modes:
    - `Idle`
    - `KeyCandidate`
    - `TypingCommitted`
    - `MouseCandidate`
    - `MouseActive`
    - `GestureCandidate`
  - layer behavior scaffolding:
    - typing toggle
    - persistent layer set/toggle
    - momentary layer tracking
  - five-finger swipe typing-mode toggle state
  - chordal-shift activity state flags

## Replay integration
- `ReplayRunner` now drives the engine during replay and reports:
  - intent trace fingerprint
  - intent transition count

## Validation commands
```powershell
dotnet build tools/GlassToKey/GlassToKey.csproj -c Release
dotnet run --project tools/GlassToKey/GlassToKey.csproj -c Release -- --selftest
dotnet run --project tools/GlassToKey/GlassToKey.csproj -c Release -- --replay tools/GlassToKey/fixtures/replay/smoke.atpcap --fixture tools/GlassToKey/fixtures/replay/smoke.fixture.json
```

## Notes
- Engine dispatch side effects are intentionally not wired yet (Phase 4).
- Replay fixture now includes expected `intentFingerprint` and `intentTransitions`.

# BUILD_REPLAY Handoff

## Goal
Match `../windows/GlassToKey` replay behavior:
- `Replay...` from GUI loads `.atpcap` and replays visually in-app with playback controls.
- CLI path still supports deterministic headless replay for analysis.

## Current status (2026-02-17)
- GUI replay now renders in the main UI (not just alert-based deterministic verification).
- Header replay controls are wired: play/pause, step back, step forward, seek slider, time/frame labels.
- Tray `Replay...` now opens file picker, loads replay into the GUI, and pauses live listening while replay is active.
- Closing config window ends replay session and resumes live listening if it was active before replay.
- CLI `--replay <file.atpcap>` deterministic 2-pass path is still present.
- Build currently succeeds:
  - `xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Debug -destination 'platform=macOS' build`

## Files changed for this replay work
- `Sources/OpenMultitouchSupport/ATPCaptureReplay.swift`
- `Sources/OpenMultitouchSupport/OMSTouchData.swift`
- `GlassToKey/GlassToKey/ContentViewModel.swift`
- `GlassToKey/GlassToKey/ContentView.swift`
- `GlassToKey/GlassToKey/GlassToKeyApp.swift`

## Architecture summary

### 1) Replay decode / deterministic frame source
`Sources/OpenMultitouchSupport/ATPCaptureReplay.swift`
- Parses `.atpcap` header + records.
- Decodes multitouch HID payloads into `OMSRawTouch` replay frames.
- Normalizes sides to synthetic indices (`left=0`, `right=1`) for deterministic app replay.
- Produces replay stats and a deterministic fingerprint over decoded frame content.

### 2) Deterministic replay engine
`GlassToKey/GlassToKey/ContentViewModel.swift`
- Existing deterministic verification API retained:
  - `runDeterministicReplay(capturePath:)`
  - 2-pass replay + fingerprint/stats comparison.
- Added GUI replay session state + controls:
  - `ReplayUIState`
  - `loadReplayCapture(capturePath:)`
  - `closeReplayCapture()`
  - `toggleReplayPlayback()`
  - `stepReplayForward()` / `stepReplayBackward()`
  - `seekReplay(progress:)`
- Replay frames are applied via `processor.processReplayFrame(...)` so replay uses the same pipeline path as deterministic analysis.
- Replay snapshot publishing now updates only the frame’s side (left/right) and preserves the opposite side; full reset is explicit via `resetReplaySnapshot()`.

### 3) GUI controls
`GlassToKey/GlassToKey/ContentView.swift`
- `HeaderControlsView` accepts replay state and callback closures.
- Replay controls are shown when `replayUIState != nil`.

### 4) App wiring (menu + lifecycle + CLI)
`GlassToKey/GlassToKey/GlassToKeyApp.swift`
- Menu `Replay...`:
  - Opens `.atpcap` picker.
  - Stops live listening (if active), starts replay mode, opens config window, loads capture in view model.
- Window close path:
  - Calls `closeReplayCapture()`.
  - Restores live listening if it was active pre-replay.
- CLI launch mode:
  - `--replay <path>` runs deterministic headless replay and exits with status:
    - `0` if deterministic
    - `1` otherwise or on error

## Important API visibility fix
`Sources/OpenMultitouchSupport/OMSTouchData.swift`
- Added public initializers:
  - `OMSPosition(x:y:)`
  - `OMSAxis(major:minor:)`
  - `OMSTouchData(...)` (already added during replay work)
This was required for replay conversion code in app target.

## Known gaps / follow-ups
1. Replay speed is stored (`speed`) but no UI to change it yet.
2. Seek currently maps slider by frame index, not absolute capture time.
3. Replay controls are in header; Windows parity may want a dedicated timeline panel layout.
4. No automated tests yet for `.atpcap` parse/replay determinism in CI.

## Validation checklist for next Codex instance
1. Build:
   - `xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Debug -destination 'platform=macOS' build`
2. GUI replay manual test:
   - Launch app.
   - Menu bar `Replay...` and select `2finger_hold.atpcap`.
   - Confirm touches animate in GUI and controls work:
     - Play/Pause toggles progression.
     - Step buttons move exactly one frame.
     - Slider seeks and redraws snapshot.
   - Close window and confirm live listening resumes if previously active.
3. CLI deterministic test:
   - Run app binary with `--replay <atpcap-path>`.
   - Confirm summary output reports deterministic true and process exit code is `0`.

## Notes from this environment
- The sample capture file exists at repo root: `2finger_hold.atpcap`.
- In this tool-runner shell, direct app binary replay exits with code `134` (no useful stderr), so headless CLI verification must be re-checked in a normal macOS user session.


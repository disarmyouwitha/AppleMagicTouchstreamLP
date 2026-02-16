## GlassToKey
GlassToKey for Windows.

## Usage
A status bar indicator shows the active mode:
- **Green**: Mixed mode (typing + mouse intent)
- **Purple**: Keyboard mode (full keyboard, no mouse intent)
- **Red**: Mouse-only mode (typing disabled)

Right-clicking the indicator opens tray actions: `Config...`, separator, `Capture`, `Replay`, separator, `Restart`, and `Exit`.

### Pin Tray Icon
- Windows 11:
  - `Settings` -> `Personalization` -> `Taskbar` -> `Other system tray icons` -> turn on `GlassToKey`.
- Windows 10:
  - `Settings` -> `Personalization` -> `Taskbar` -> `Select which icons appear on the taskbar` -> turn on `GlassToKey`.
- You can also drag the icon from the hidden tray (`^`) to the visible tray area.

<img src="screenshots/Screenshot.png" alt="GlassToKey" />


## Typing Tuning
- Hold duration (ms): Time in miliseconds until a tap becomes a hold
- Typing Grace (ms): Time after a key dispatch to keep typing intent active.
- Drag cancel (mm): How far you need to move before tap becomes a drag
- Intent Move (mm): Movement threshold before a touch is treated as mouse intent.
- Intent Velocity (mm/s): Speed threshold before a touch is treated as mouse intent.
- Force Min (f:, 0-255): If `f` is below this value, key dispatch is blocked.
- Force Cap (f:, 0-255): If `f` is above this value, key dispatch is blocked.
  - Key dispatch is allowed only when `f` is within `[Force Min, Force Cap]` (inclusive).
  - Setting `Force Cap` to `0` blocks all key dispatches.
- Gesture Config: 2-finger tap, 3-finger tap, 5-finger swipe L/R, 4-finger hold, and outer/inner corner taps can each be mapped to any action (defaults preserve classic tap-click + typing-toggle behavior).
- Snap Radius: On release during typing intent, off-key taps will snap to the nearest key center if the release point is within this percent of the key’s smaller dimension.
- Keyboard Mode: When enabled, typing-toggle actions switch between **full keyboard** and **mouse-only**. In keyboard mode, mouse down/up events are blocked globally (except inside the GlassToKey config window), and tap gestures only fire when `Tap Click` is enabled. Blocking clicks requires Input Monitoring/Accessibility permission.

## Intent State Machine
GlassToKey runs a simple intent state machine to decide when touches should be interpreted as typing vs mouse input. The UI intent badges use these labels: `idle`, `cand`, `typing`, `mouse`, `gest`.

- **Idle (`idle`)**: No active contacts. Any touch that begins on a key enters `keyCandidate`; otherwise it enters `mouseCandidate`.
- **KeyCandidate (`cand`)**: A short buffer window (fixed at 20ms) watches for mouse-like motion. If the touch stays within thresholds, it becomes `typingCommitted`.
- **TypingCommitted (`typing`)**: Key dispatches are allowed. Typing Grace keeps this state alive for a short window after a key is released.
- **MouseCandidate (`mouse`)**: Short buffer window (fixed at 20ms) watching for mouse-like motion. If motion exceeds thresholds or the buffer elapses, it becomes `mouseActive`.
- **MouseActive (`mouse`)**: Typing is suppressed while mouse intent is active.
- **GestureCandidate (`gest`)**: Multi-finger gesture guard. If 2+ touches begin within the 20ms buffer (or 3+ touches arrive together), typing is suppressed and intent displays as gesture until the contact count drops.

Transitions and notes:
- **Typing Grace** extends `typingCommitted` after a key dispatch, even if all fingers lift.
- **Tap/Drag** immediately disqualifies the touch and forces `mouseActive`.
- **GestureCandidate** enters when 2+ touches start within the key buffer window (or 3+ simultaneous touches) and exits back to `idle` once fewer than two contacts remain.


## Build
```
dotnet build GlassToKey\GlassToKey.csproj -c Release
```


### Optional arguments
- `--maxx <value>` / `--maxy <value>`: Force coordinate scaling.
- `--config`: Open config visualizer on startup (live runtime remains tray-hosted).
- `--list`: Print available trackpad interfaces.
- `--capture <path>`: Write captured reports to binary `.atpcap` format.
- `--replay <capturePath>`: Replay a capture without opening the UI.
- `--replay-ui`: When used with `--replay`, opens UI playback mode (instead of headless replay).
- `--relaunch-tray-on-close`: Internal flag used by tray-initiated capture/replay to relaunch normal tray mode when the window closes.
- `--replay-speed <x>`: Initial replay speed multiplier (for example: `0.5`, `1`, `2`).
- `--fixture <fixturePath>`: Optional expected replay fingerprint/counts JSON (also supports intent fingerprint + transition count).
- `--metrics-out <path>`: Write metrics JSON snapshot.
- `--replay-trace-out <path>`: Write detailed replay trace JSON (intent transitions, dispatch events, diagnostics).
  - Dispatch events/diagnostics include `dispatchLabel` (for example `A`, `TypingToggle`, `Ctrl+C`, `ChordShift`) for direct intent debugging.
  - Diagnostics include `ReleaseDropped` reasons (`drag_cancel`, `off_key_no_snap`, `tap_gesture_active`, `hold_consumed`) when a touch release does not emit a key dispatch.
- `--raw-analyze <capturePath>`: Analyze captured raw HID packets and print report signatures + decode classification, including slot-byte lifecycle stats (`+1/+6/+7/+8`) and button-correlated slot summaries (`+6/+7/+8`, up/down and edge-frame snapshots) for official decoded PTP contacts.
- `--raw-analyze-out <path>`: Write raw analysis JSON output.
- `--raw-analyze-contacts-out <path>`: Write per-contact CSV rows for decoded frames (raw PTP ID/flags/XY alongside assigned decoded ID/flags/XY + slot hex + decoded/raw button/scan/contact-tail fields).
- `--selftest`: Run deterministic local self-tests (parser, replay, intent, dispatch, toggle, chord, tap/click gesture, five-finger swipe) and exit.

### Self-Tests
- Entry point: `Core/Diagnostics/SelfTestRunner.cs` (`dotnet run --project GlassToKey\GlassToKey.csproj -c Release -- --selftest`).
- Coverage includes parser/decoder checks, button-edge tracking, replay determinism + replay-trace validation, intent-mode transitions, dispatch behavior (snap/drag cancel/modifiers/chords), typing-toggle flows, tap/click gesture recognition and suppression, and five-finger swipe toggle behavior.
- Data source is primarily synthetic and deterministic: tests build `InputFrame` sequences in memory and assert emitted snapshots/events.
- Replay self-tests also generate a temporary synthetic `.atpcap` capture on disk, then replay and validate expected fingerprints/counters.
- Recorded captures are still supported for manual or fixture-based replay via `--capture`, `--replay`, and `--fixture`, but they are not required for the built-in self-test pass.

### Generate Replay Fixture From Capture
1. Capture or choose a replay file (`.atpcap`).
2. Generate fixture JSON:
   - `powershell -ExecutionPolicy Bypass -File GlassToKey\fixtures\replay\New-ReplayFixture.ps1 -CapturePath GlassToKey\fixtures\replay\your_capture.atpcap -RelativeCapturePath`
3. Validate replay against the generated fixture:
   - `dotnet run --project GlassToKey\GlassToKey.csproj -c Release -- --replay GlassToKey\fixtures\replay\your_capture.atpcap --fixture GlassToKey\fixtures\replay\your_capture.fixture.json`

Notes:
- If `-FixturePath` is omitted, the script writes `<capture-name>.fixture.json` next to the capture.
- Use `-ProjectPath` if `GlassToKey.csproj` is not at the default relative path.


## Files Created at Runtime
- `%LOCALAPPDATA%\\GlassToKey\\settings.json`: device selections + active layer.
- `%LOCALAPPDATA%\\GlassToKey\\keymap.json`: layered keymap overrides.
- `%LOCALAPPDATA%\\GlassToKey\\runtime-errors.log`: guarded runtime exception log (raw input/device context + stack traces).
- `.atpcap` records embed side hints (`left`/`right`/`unknown`) and decoder profile (`official`/`opensource`) metadata for deterministic replay routing.
- Current capture format version is `2` (`ATPCAP01` + v2 record headers); replay expects v2 captures.
- On first run (no local settings/keymap), defaults are loaded from `GLASSTOKEY_DEFAULT_KEYMAP.json` beside the executable.


## AmtPtpVisualizer
GlassToKey for Windows.

<img src="Screenshot.png">
A minimal WPF visualizer for the Magic Trackpad 2 PTP input reports produced by `AmtPtpDeviceUsbUm`.

## What It Does
- Runs as a status-bar/tray app by default; touch ingest + key dispatch stay active even when the config window is closed.
- Treats the visualizer window as a secondary config surface opened on demand.
- Mirrors live touch contacts from the tray runtime into the config visualizer through a read-only observer channel.
- Uses mode-colored tray icon circles for runtime mode status (`Mouse`, `Mixed`, `Keyboard`).
- Registers for Raw Input (WM_INPUT) and reads multitouch input report `0x05` without opening the HID handle.
- Parses the `PTP_REPORT` payload (5 contacts, scan time, button state) and renders contacts in real time.
- Shows contact IDs for active touch contacts (`TipSwitch=true`) in real time.
- Tags each report with a device index + hash (`[dev N XXXXXXXX]`) so multiple trackpads can be distinguished.
- Supports two trackpads at once (left/right) with a device picker and "None" option.
- Adds a seeded 6x3 keymap starter (Layer 0/1, primary + hold actions) with hit highlighting.
- Adds editable custom buttons per side/layer with action + hold-action mapping and percentage-based `X/Y/Width/Height` tuning.
- Supports capture/replay diagnostics with deterministic fingerprint checks and fixture assertions.
- Supports replay-in-UI playback (`--replay-ui`) with play/pause and speed controls.
- Includes a Windows `TouchProcessor` engine scaffold (single-consumer actor, intent state machine, binding cache, snap accounting).
- In Keyboard mode, swallows global mouse click events outside the visualizer process so accidental trackpad clicks do not leak to other apps.

## How It Works
- **Tray runtime host:** `TouchRuntimeService` owns WM_INPUT ingest, touch processing actor, dispatch pump, and click suppression in normal live mode.
- **Config window:** `MainWindow` updates persisted settings/keymap and pushes config changes into the running tray runtime; it also receives live frame mirrors from runtime for visualization.
- **Device selection:** Uses the in-app dropdowns for left/right. Each can be set to "None".
- **Raw Input path:** Registers for Usage Page `0x0D` (Digitizer), Usage `0x05` (Touch Pad), then parses WM_INPUT payloads.
- **Parsing:** Manual little-endian `TryParse` over `ReadOnlySpan<byte>` into fixed-capacity structs (`PtpReport`, `InputFrame`), with no per-frame contact-array allocations.
- **Rendering:** WPF `FrameworkElement` (`TouchView`) draws a padded surface, grid, and per-contact circles each frame.
- **Tip-only visualization policy:** The visualizer intentionally ignores non-tip (`TipSwitch=false`) near-field/hover contacts to avoid lingering artifacts. Do not reintroduce hover circles unless behavior requirements change.
- **Normalization:** Touches are normalized to a fixed Magic Trackpad 2 aspect ratio using `160.0mm x 114.9mm` for layout. Default logical maxima are `7612 x 5065` unless overridden with `--maxx/--maxy`.
- **Keymap:** Layered mappings and custom buttons live in `keymap.json`, scoped by layout preset (`6x3`, `6x4`, etc.), layer, and side. Labels fall back to layout defaults when missing. Fresh `6x3` setups seed Layer 0/1 mappings plus default thumb buttons, and the header includes `Export Keymap` / `Import Keymap` JSON actions.
- **Diagnostics:** `--capture` writes binary frame captures; `--replay` runs deterministic two-pass replay + optional fixture checks.
- **Keyboard mode click policy:** while typing is enabled and Keyboard mode is on, global click messages are suppressed for external apps; clicks inside the visualizer app remain allowed.
- **Engine replay checks:** replay also computes intent trace fingerprint and transition count from the engine state machine.
- **Replay visual playback:** run with `--replay <file> --replay-ui` to route replayed frames into the left/right visualizer surfaces.

## Build
```
dotnet build AmtPtpVisualizer\AmtPtpVisualizer.csproj -c Release
```

## Run
```
dotnet run --project AmtPtpVisualizer\AmtPtpVisualizer.csproj -c Release
```

- Default live launch starts in tray mode (status app) without opening the visualizer.
- Use the tray icon `Open Config` action or `--config` to open the visualizer immediately.

### Pin Tray Icon
- Windows 11:
  - `Settings` -> `Personalization` -> `Taskbar` -> `Other system tray icons` -> turn on `AmtPtpVisualizer`.
- Windows 10:
  - `Settings` -> `Personalization` -> `Taskbar` -> `Select which icons appear on the taskbar` -> turn on `AmtPtpVisualizer`.
- You can also drag the icon from the hidden tray (`^`) to the visible tray area.

### Optional arguments
- `--maxx <value>` / `--maxy <value>`: Force coordinate scaling.
- `--config`: Open config visualizer on startup (live runtime remains tray-hosted).
- `--list`: Print available HID interfaces.
- `--capture <path>`: Write captured reports to binary `.atpcap` format.
- `--replay <capturePath>`: Replay a capture without opening the UI.
- `--replay-ui`: When used with `--replay`, opens UI playback mode (instead of headless replay).
- `--replay-speed <x>`: Initial replay speed multiplier (for example: `0.5`, `1`, `2`).
- `--fixture <fixturePath>`: Optional expected replay fingerprint/counts JSON (also supports intent fingerprint + transition count).
- `--metrics-out <path>`: Write metrics JSON snapshot.
- `--replay-trace-out <path>`: Write detailed replay trace JSON (intent transitions, dispatch events, diagnostics).
  - Dispatch events/diagnostics include `dispatchLabel` (for example `A`, `TypingToggle`, `Ctrl+C`, `ChordShift`) for direct intent debugging.
  - Diagnostics include `ReleaseDropped` reasons (`drag_cancel`, `off_key_no_snap`, `tap_gesture_active`, `hold_consumed`) when a touch release does not emit a key dispatch.
- `--selftest`: Run parser/replay smoke tests and exit.

## Common Workflows

### 1. Capture a live session
```powershell
dotnet run --project AmtPtpVisualizer/AmtPtpVisualizer.csproj -c Release -- --capture .\touch-session.atpcap --metrics-out .\live-metrics.json --replay-trace-out .\capture-trace.json
```

- Close the app to flush final metrics output.
- If `--replay-trace-out` is provided, closing the app also runs deterministic replay over the just-captured `.atpcap` and writes full trace JSON.

### 2. Validate a capture headlessly (deterministic replay)
```powershell
dotnet run --project AmtPtpVisualizer/AmtPtpVisualizer.csproj -c Release -- --replay .\touch-session.atpcap --metrics-out .\replay-metrics.json --replay-trace-out .\replay-trace.json
```

- This mode does not open WPF UI.
- It prints replay determinism/fingerprint summary to console.

### 3. Replay directly into visualizer UI
```powershell
dotnet run --project AmtPtpVisualizer/AmtPtpVisualizer.csproj -c Release -- --replay .\touch-session.atpcap --replay-ui --replay-speed 1
```

- Uses replay devices populated from capture metadata.
- Left/right device dropdowns still control routing to each pane.
- Replayed frames go through the same touch engine path, so key hit highlighting and key dispatch behavior are active during replay.
- Header replay controls currently support:
  - `Play` / `Pause` / `Resume`
  - Speed: `0.25x`, `0.5x`, `1x`, `2x`, `4x`
  - Step backward / step forward (frame-level stepping)
  - Loop toggle
  - Timeline scrubber slider

## Performance Note
- Default live mode hot path runs in `TouchRuntimeService` independent from config-window lifetime.
- Replay visual playback code paths are only active when `--replay-ui` is set.
- Default live mode (no replay flags) continues to use the normal WM_INPUT ingest path.

### Replay smoke fixture
- Capture: `AmtPtpVisualizer/fixtures/replay/smoke.atpcap`
- Fixture: `AmtPtpVisualizer/fixtures/replay/smoke.fixture.json`
- Run:
  - `dotnet run --project AmtPtpVisualizer/AmtPtpVisualizer.csproj -c Release -- --replay AmtPtpVisualizer/fixtures/replay/smoke.atpcap --fixture AmtPtpVisualizer/fixtures/replay/smoke.fixture.json`

## Files Created at Runtime
- `%LOCALAPPDATA%\\AmtPtpVisualizer\\settings.json`: device selections + active layer.
- `%LOCALAPPDATA%\\AmtPtpVisualizer\\keymap.json`: layered keymap overrides.

## Files
- `App.xaml` / `App.xaml.cs`: App bootstrap + exception dialog.
- `StatusTrayController.cs`: tray icon/menu (`Open Config`, `Exit`).
- `TouchRuntimeService.cs`: background runtime host for WM_INPUT + engine + dispatch.
- `RuntimeObserverContracts.cs`: runtime mode + frame observer contracts for live visualization mirroring.
- `RuntimeConfigurationFactory.cs`: shared settings-to-layout/config builders for UI/runtime parity.
- `StartupRegistration.cs`: Windows startup (`HKCU\\...\\Run`) registration helper.
- `MainWindow.xaml` / `MainWindow.xaml.cs`: secondary config/visualizer UI (plus replay UI path).
- `RawInputInterop.cs`: Raw Input registration + device enumeration.
- `PtpReport.cs`: zero-allocation report parsing.
- `Core/Input/InputFrame.cs`: fixed-capacity frame/contact structs for engine handoff.
- `Core/Engine/*`: touch table, binding index, action model, `TouchProcessor` core + actor queue.
- `Core/Diagnostics/*`: capture format, replay runner, self-tests, frame metrics.
- `TouchState.cs`: Thread-safe state container.
- `TouchView.cs`: WPF drawing.

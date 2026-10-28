## AppleMagicTouchstream
AppleMagicTouchstream for Windows.

## Usage
The tray and application use the Mac hand silhouette in black. Keyboard typing stays available; configured multi-finger gestures reserve their contact cycles. The former Keyboard/Mouse mode and colored mode indicators are removed. Old mode settings and typing-toggle bindings cannot switch Windows into mouse-only or keyboard-only operation. See [Windows input policy](WINDOWS_INPUT_POLICY.md).

Right-clicking the indicator opens `Config...`, `Release Mouse Takeover (Ctrl+Alt+R)`, `Capture`, `Replay`, `Restart`, and `Exit`.

By default, AppleMagicTouchstream opens the config window on launch. To start tray-only (taskbar icon only), enable `Start in taskbar (tray only)` in `Options`.

### Configuration layout

The top selector presents **Gestures / Keyboard**, with Keyboard selected initially. Device and Mouse Takeover controls span both workspaces. Keyboard contains the two trackpad views, typing test and keyboard settings inspector. Gestures replaces those with three resizable columns: gesture navigation, assignment cards and the Action inspector. The Keyboard inspector and Gesture Action column share their width; resizing either updates both. Selecting a key or custom button returns to Keyboard. Decoder Profiles and the header contact-count pills are hidden. See [current parity and hardware testing](MAC_GOLD_PARITY.md).

### Mouse Takeover

Below the device selectors, enable **Mouse Takeover** to save your opt-in for the next launch, or use the temporary **30sec test**. It blocks physical movement, clicks, and wheel events from all mice while injected AppleMagicTouchstream output passes. **Ctrl+Alt+R** releases globally; the checkbox/status and tray indicator update together. It defaults off on first launch. Unchecking it, tray release and Ctrl+Alt+R save Off; normal quit/restart preserves your choice. Windows shell gestures may need separate settings. See [Mouse Takeover](WINDOWS_MOUSE_TAKEOVER.md).

### Pin Tray Icon
- Windows 11:
  - `Settings` -> `Personalization` -> `Taskbar` -> `Other system tray icons` -> turn on `AppleMagicTouchstream`.
- Windows 10:
  - `Settings` -> `Personalization` -> `Taskbar` -> `Select which icons appear on the taskbar` -> turn on `AppleMagicTouchstream`.
- You can also drag the icon from the hidden tray (`^`) to the visible tray area.

<img src="screenshots/Screenshot.png" alt="AppleMagicTouchstream" />


## Typing Tuning

- **Hold Duration** sets the delay before a key hold commits; the default is 220 ms.
- **Haptic Strength** controls the existing Windows haptic output. **Restore Defaults** restores these two settings.
- Force Instead of Hold remains a per-key/custom-button setting. Windows ignores the old global Force Min/Max gates.
- Snap Radius allows eligible off-key releases to choose a nearby key, bounded to 0–100% of the key's smaller dimension.

Typing Grace, Drag Cancel, Intent Move and Intent Velocity have been removed from the Windows controls. Their saved legacy fields remain readable but cannot select mouse intent or cancel unified Windows typing. Unreserved contacts remain keyboard input. A tap must finish within max(200 ms, Hold Duration) and satisfy its original key/release geometry or snap eligibility; movement distance alone does not cancel it. Committed holds retain ownership through drift.

Established MO/modifier chords and committed key holds keep priority on their pad until all fingers lift. While a gesture is unresolved, keyboard proposals retain their original frames, timestamps and modifier snapshots. A winning or cancelled gesture discards them; a never-activated rollover can resolve to typing. Held gesture shortcuts share keyboard key/modifier ownership and release on lift, cancellation or teardown. See [current parity and hardware testing](MAC_GOLD_PARITY.md) for gesture behavior and remaining platform differences.


## Build

The Mac gold-standard port now includes TouchStream's independently traced sides/reference background, resizable inspectors, searchable gesture actions, Mirror Edit, separate coordinated Both gestures, 2–5-finger holds, four/five-finger taps and directional movement. See [current parity and hardware testing](MAC_GOLD_PARITY.md) for supported behavior and remaining differences.

```
dotnet build AppleMagicTouchstream.Windows\AppleMagicTouchstream.Windows.csproj -c Release
```


### Optional arguments
- `--maxx <value>` / `--maxy <value>`: Force coordinate scaling.
- `--config`: Open config visualizer on startup (live runtime remains tray-hosted).
- `--tray-only`: Internal flag used for restarts that should come back tray-only without reopening Config.
- `--list`: Print available trackpad interfaces.
- `--capture <path>`: Write captured reports to binary `.atpcap` format.
- `--replay <capturePath>`: Replay a capture without opening the UI.
- `--replay-ui`: When used with `--replay`, opens UI playback mode (instead of headless replay).
  - Capture/replay UI sessions launch maximized for full-screen inspection.
- `--relaunch-tray-on-close`: Internal flag used by tray-initiated capture/replay to relaunch normal tray mode when the window closes.
- `--replay-speed <x>`: Initial replay speed multiplier (for example: `0.5`, `1`, `2`).
- `--fixture <fixturePath>`: Optional expected replay fingerprint/counts JSON (also supports intent fingerprint + transition count).
- `--metrics-out <path>`: Write metrics JSON snapshot.
- `--replay-trace-out <path>`: Write detailed replay trace JSON (intent transitions, dispatch events, diagnostics).
  - Dispatch events/diagnostics include `dispatchLabel` (for example `A`, `TypingToggle`, `Ctrl+C`, `ChordShift`) for direct intent debugging.
  - Diagnostics include `ReleaseDropped` reasons (`drag_cancel`, `off_key_no_snap`, `hold_consumed`) when a touch release does not emit a key dispatch.
- `--raw-analyze <capturePath>`: Analyze captured raw HID packets and print report signatures + decode classification, including slot-byte lifecycle stats (`+1/+6/+7/+8`) and button-correlated slot summaries (`+6/+7/+8`, up/down and edge-frame snapshots) for official decoded PTP contacts.
- `--raw-analyze-out <path>`: Write raw analysis JSON output.
- `--raw-analyze-contacts-out <path>`: Write per-contact CSV rows for decoded frames (raw PTP ID/flags/XY alongside assigned decoded ID/flags/XY + slot hex + decoded/raw button/scan/contact-tail fields).
- `--selftest`: Run deterministic local self-tests (parser, replay, intent, dispatch, toggle, chord, five-finger swipe) and exit.

### Self-Tests
- Entry point: `WindowsDiagnostics/SelfTestRunner.cs` (`dotnet run --project AppleMagicTouchstream.Windows\AppleMagicTouchstream.Windows.csproj -c Release -- --selftest`).
- Coverage includes parser/decoder checks, button-edge tracking, replay determinism + replay-trace validation, intent-mode transitions, dispatch behavior (snap/drag cancel/modifiers/chords), typing-toggle flows, and five-finger swipe toggle behavior.
- Data source is primarily synthetic and deterministic: tests build `InputFrame` sequences in memory and assert emitted snapshots/events.
- Replay self-tests also generate a temporary synthetic `.atpcap` capture on disk, then replay and validate expected fingerprints/counters.
- Recorded captures are still supported for manual or fixture-based replay via `--capture`, `--replay`, and `--fixture`, but they are not required for the built-in self-test pass.

### Generate Replay Fixture From Capture
1. Capture or choose a replay file (`.atpcap`).
2. Generate fixture JSON:
   - `powershell -ExecutionPolicy Bypass -File AppleMagicTouchstream.Windows\fixtures\replay\New-ReplayFixture.ps1 -CapturePath AppleMagicTouchstream.Windows\fixtures\replay\your_capture.atpcap -RelativeCapturePath`
3. Validate replay against the generated fixture:
   - `dotnet run --project AppleMagicTouchstream.Windows\AppleMagicTouchstream.Windows.csproj -c Release -- --replay AppleMagicTouchstream.Windows\fixtures\replay\your_capture.atpcap --fixture AppleMagicTouchstream.Windows\fixtures\replay\your_capture.fixture.json`

Notes:
- If `-FixturePath` is omitted, the script writes `<capture-name>.fixture.json` next to the capture.
- Use `-ProjectPath` if `AppleMagicTouchstream.Windows.csproj` is not at the default relative path.


## Files Created at Runtime
- `<app-folder>\\settings.json`: device selections + active layer.
- `%LOCALAPPDATA%\\AppleMagicTouchstream\\keymap.json`: layered keymap overrides.
- `%LOCALAPPDATA%\\AppleMagicTouchstream\\runtime-errors.log`: guarded runtime exception log (raw input/device context + stack traces).
- `.atpcap` records embed side hints (`left`/`right`/`unknown`) and decoder profile (`official`/`opensource`) metadata for deterministic replay routing.
- Current capture write format version is `2` (`ATPCAP01` + v2 record headers); replay accepts both v2 and v3 captures.
- For macOS v3 captures, replay applies compatibility normalization (OpenMT Y-axis flip + side-hint swap) before dispatch.
- On first run (no local settings/keymap), defaults are loaded from `DEFAULT_KEYMAP.json` beside the executable.

## Renamed application and existing data

The Windows project is `AppleMagicTouchstream.Windows/AppleMagicTouchstream.Windows.csproj`.
Release outputs `bin/Release/net10.0-windows/AppleMagicTouchstream.exe` and
`AppleMagicTouchstream.Core.dll`; bundled defaults are `DEFAULT_KEYMAP.json`.
Existing `settings.json` and exported profiles retain their formats. Keymaps and
Mouse Takeover opt-in are copied once from the previous GlassToKey local-data
folder to AppleMagicTouchstream without overwriting existing data. The old
single-instance identity is retained to prevent two input runtimes running together.
An existing Windows startup registration is updated to the renamed executable on
normal live launch; startup is never newly enabled by migration or offline checks.
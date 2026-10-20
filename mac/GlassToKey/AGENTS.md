# AGENTS

## Scope
- This file is for the `mac/GlassToKey/` working folder only.
- When Codex is opened from `mac/GlassToKey/`, target the macOS app, Swift package, and Objective-C bridge that live in this folder.
- Do not drift into `../../windows_linux/` unless the user explicitly asks for cross-platform comparison or parity work.

## What This Codebase Is
- A macOS menu bar app that turns Apple Magic Trackpads into a typing surface.
- Input comes from the private MultitouchSupport path through the local `OpenMultitouchSupportXCF` bridge and the Swift `OMSManager` wrapper.
- Output is posted with Core Graphics events, plus app-side mouse blocking and haptic hooks where needed.
- Replay/capture tooling is first-class here: this folder contains `.atpcap` fixtures, transcript baselines, analysis tools, and Swift package tests.

## Default Build Targets
- Main app: `GlassToKey/GlassToKey.xcodeproj` with scheme `GlassToKey`
- Swift package root: `Package.swift`
- Bridge framework project: `Framework/OpenMultitouchSupportXCF.xcodeproj`

## Build And Test Commands
- Main app build:
  - `xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Debug -destination 'platform=macOS' build`
- Reproducible app launch outside the Xcode UI (only when explicitly testing live input):
  - `./build.sh`
  - `open build/DerivedData/Build/Products/Debug/GlassToKey.app`
- Swift package tests:
  - `./test.sh`
- Framework rebuild:
  - `./build_framework.sh`
- Replay transcript parity check:
  - `swift run ReplayHarness --fixture ReplayFixtures/production_typing.atpcap --expected-transcript ReplayFixtures/production_typing.engine.transcript.jsonl`
- Raw capture analysis:
  - `swift run RawCaptureAnalyze --raw-analyze ReplayFixtures/macos_first_capture_2026-02-20.atpcap`

## App Architecture
- `GlassToKey/GlassToKey/GlassToKeyApp.swift`
  - launches as an accessory app
  - owns the menu bar item and config window
  - exposes tray actions for `Config...`, `Capture...`, `Replay...`, restart, and quit
  - manages `MouseEventBlocker` and replay/capture menu state
- `GlassToKey/GlassToKey/GlassToKeyController.swift`
  - bootstraps the app from `UserDefaults`
  - loads devices, layout preset, column settings, custom buttons, key mappings, and geometry overrides
  - starts capture/replay sessions through the view model
- `GlassToKey/GlassToKey/ContentViewModel.swift`
  - is the central app model
  - owns device selection, layouts, key mappings, runtime state, gesture labels, and action catalogs
  - defines the action semantics used by the UI and runtime
- `GlassToKey/GlassToKey/Runtime/InputRuntimeService.swift`
  - consumes `OMSManager.rawTouchStream`
  - fans out runtime frames with `AsyncStream`
  - tracks ingestion metrics with unfair-lock protected state
- `GlassToKey/GlassToKey/Engine/TouchProcessorEngine.swift`
  - is the core touch/intent/dispatch engine
  - is confined to a serial queue and uses a custom `TouchTable` implementation to stay hot-path friendly
  - contains intent state, active/pending touches, repeat handling, and runtime diagnostics
- `GlassToKey/GlassToKey/KeyEventDispatcher.swift`
  - is the single Core Graphics key/mouse posting path
- `GlassToKey/GlassToKey/Runtime/ATPCaptureV3Coordinator.swift`
  - handles capture/replay workflow inside the app

## Package And Tooling
- `Sources/OpenMultitouchSupport/`
  - Swift wrapper layer over the XCFramework
- `Sources/ReplayFixtureKit/`
  - fixture parsing, `.atpcap` codec, replay harness, and raw capture analysis
- `Tools/ReplayFixtureCapture/`
  - records live OMS frames into replay fixtures
- `Tools/ReplayHarness/`
  - runs the actual production TouchProcessorEngine with virtual time and recording output; compares recognition/dispatch transcripts to committed baselines
- `Tools/RawCaptureAnalyze/`
  - produces raw analysis summaries and optional JSON/CSV outputs
- `Tests/ProductionEngineTests/`
  - exercises production taps, modifiers, repeat deadlines, gesture suppression, reset, and captured-configuration parity
- `Tests/ReplayFixtureKitTests/`
  - checks fixture parsing, contact-count smoke behavior, and `.atpcap` round-trips

## Data And Persistence
- Most app settings are persisted in `UserDefaults` via `GlassToKeyDefaultsKeys.swift`.
- Key persisted values include:
  - left/right device IDs
  - layout preset and column settings
  - custom buttons
  - key mappings and geometry overrides
  - typing/gesture thresholds
  - autocorrect, keyboard mode, run-at-startup, and gesture action labels
- Bundled defaults come from `GLASSTOKEY_DEFAULT_KEYMAP.json`.
- Replay baselines live in `ReplayFixtures/`, and canonical transcript baselines use the `.engine.transcript.jsonl` suffix.

## Bridge Rules
- Keep Swift API work in `Sources/OpenMultitouchSupport/`.
- Keep Objective-C private-framework bridge work in `Framework/OpenMultitouchSupportXCF/`.
- Treat `OpenMultitouchSupportXCF.xcframework` as generated output.
- If you change the bridge, rebuild the XCFramework; do not hand-edit generated bundle contents.
- `build_framework.sh` uses project-local `build/FrameworkDerivedData` and recreates the local XCFramework without clearing shared Xcode caches.

## Performance Rules
- This app is latency-sensitive. Assume touch ingestion, intent updates, dispatch, and render snapshot production are hot paths.
- Do not add avoidable allocations, logging, or file I/O in `InputRuntimeService`, `TouchProcessorEngine`, `KeyEventDispatcher`, or frame-to-snapshot code.
- Preserve deterministic replay behavior when changing engine logic. If engine behavior changes intentionally, update the committed transcript baseline and explain why.

## UI And Behavior Rules
- The app is menu-bar first. Do not accidentally turn it into a normal dock-style foreground app unless requested.
- Keep the status item behavior intact: config window, capture/replay flows, restart, and quit are part of the expected product shape.
- Gesture action sources must remain unified. Gesture pickers and button action pickers should continue to use the same shared catalog defined in the app model.
- Keyboard mode and click blocking are permission-sensitive. Be careful when changing behavior tied to Accessibility or Input Monitoring.

## Project Hygiene
- If you add app source files, add them to `GlassToKey.xcodeproj` so command-line builds keep working.
- If you add Swift package files, update `Package.swift` when needed.
- Call out when you could not run `xcodebuild` or `swift test`.

## Current project layout
Use `./build.sh` and `./test.sh` from this package, or invoke them by absolute path. `project.env` defines the app identity used by build/release scripts. See `../README.md` for project roles. Legacy runtime symbols, defaults keys, and capture formats remain compatible.


## Native Trackpad Takeover (user-authorized 2026-10-20)

The app now has GesturePad's continuous selected-device FLTR takeover, independent
of custom DriverKit. See TRACKPAD_TAKEOVER.md. Keep exact USB VID05ac/BT VID004c,
PID0324/type4 validation, all-selection preflight, deduplication, own-client checks,
partial-start rollback and release retry. No helper, restricted driver entitlement,
startup/reconnect auto-takeover or separate synthetic pointer output is added.
Preserve native keyboard ingestion and capture/replay, selection/refresh locks,
paused auto-resync, and awaited keyboard reset before filter release. Explicit
Release/menu/Ctrl-Option-R, sleep, replay and Quit release. Config close/reopen and
active Restart retain the same owner process/controller/native clients; inactive
Restart still relaunches. Test with ./test.sh (includes offline native lifecycle
and coordinator tests), rebuild the XCFramework after native edits, and do not
activate live takeover without the user's hardware test request.


## TouchStream LP reference layout (2026-10-20)

User requested a TouchStream keypad image below the sensor grid and a layout
from mac/left_layout.jpeg + mac/full_layout.gif. See TOUCHSTREAM_LAYOUT.md.
Preserve existing preset identities/settings. TouchStream has independent traced
left/right geometry; editor, startup and replay must all use the same geometry
and per-key overrides. The original GIF is a bundled visual-only reference below
grid/contacts, automatically visible only for the TouchStream layout; do not read
source-tree files at runtime.
Unsupported Hand/Caps Lock/PC-only legends remain inactive editable placeholders.
Do not infer proprietary TouchStream gestures from printed legends. No native
bridge changes or automatic live input activation are needed for this layout.

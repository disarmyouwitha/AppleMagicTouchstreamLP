# AppleMagicTouchstream

Scope: this directory only. Build/test with `./build.sh` and `./test.sh`; Xcode project `AppleMagicTouchstream/AppleMagicTouchstream.xcodeproj`, scheme `AppleMagicTouchstream`. Identity is in `project.env`.

This project targets faithful FingerWorks TouchStream emulation. GTK gesture recognizers and product-specific features were deliberately removed. Haptics are the user-authorized exception: keep optional accepted-key feedback and its strength control. Do not restore other removed features or treat the temporary key-landing/3 mm movement classifier as original TouchStream behavior. Original chords, English spelling correction/BackSpace Auto-Correct and variable-speed typematic are future fidelity goals; the removed GTK implementations were not faithful substitutes.

Keep the multitouch bridge, raw telemetry, device selection, capture/replay tools and useful keyboard bootstrap (normal key/modifier/shortcut output, tap/hold, layers, repeat) working while implementing the original interpreter. Menu-bar config, capture/replay, restart and quit are development utilities. Do not launch the app or exercise live HID/input without an explicit test request.

`AppleMagicTouchstream/AppleMagicTouchstream/ContentView.swift` preserves the original GUI. Keep its layout, trackpad IDs, visualizers, test area, keymap/column inspectors and useful tuning. Remove unwanted feature controls in place; do not replace or simplify the interface without explicit user direction. `Engine/TouchProcessorEngine.swift` is the temporary keyboard engine; `Engine/EngineActorBoundary.swift` owns serial execution and production replay. `Runtime/` owns ingestion, telemetry and capture/replay. `Compatibility/LegacyGTKProfile.swift` is decode/serialization compatibility for old captures and saved layouts, not a live gesture implementation. Unsupported GTK action kinds must remain inert through primary, hold and custom-button paths. Preserve existing settings keys/capture formats; changing serialized enums needlessly breaks fixtures.

Keep Swift bridge work in `Sources/OpenMultitouchSupport`, Objective-C work in `Framework/OpenMultitouchSupportXCF`. XCFramework output is generated: rebuild with `./build_framework.sh` after bridge changes, never hand-edit it. Do not add allocation, logging or I/O to hot input paths. Preserve deterministic replay and update baselines only for intentional behavior changes. Register added app files in the Xcode project as well as SwiftPM. Never change sibling projects incidentally.

Haptic settings remain percent in saved profiles and 0...1 in the engine. Route feedback to the selected originating pad, rate-limit per pad, and keep replay recording-only.

Feature audit: keep Auto-resync as device recovery and Hold Repeat as output scaffolding. Keyboard/Mouse and its native mouse-event blocker are removed; do not restore them from legacy profiles. Run at Startup and GTK Typing Grace are removed. Preserve profile decoding without reactivating them; preserve GUI layout when removing controls.


As of 2026-10-19, the user removed the entire custom DriverKit takeover implementation,
helper embedding, decoder, restart transfer, UI, menu and release shortcut from this
project. Native contact capture is the input path. Do not restore DriverKit. The user explicitly authorized the native FLTR feature
port on 2026-10-20; see the current policy below. Preserve
optional legacy telemetry.driverKit serialization for existing captures.


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


## TouchStream layout (2026-10-20)

The user authorized the GlassToKey TouchStream preset/reference port. Preserve
independent traced left/right regions, editable per-key geometry and inert
placeholders for unsupported legends. Editor, startup and replay use
ContentView.makeTouchStreamKeyLayout. Bundle Resources/TouchStreamReference.gif
in Xcode and SwiftPM; the visual-only background follows the selected TouchStream
layout with no separate checkbox. See
TOUCHSTREAM_LAYOUT.md and the offline TouchStreamLayoutTests. Existing hidden
Mobile/Planck presets remain hidden. Do not restore removed gesture features.


## GesturePad takeover and contact display port (2026-10-21)

User explicitly requests GesturePad's takeover behavior and placement, left pane,
always-on contact paths/telemetry, centered pressure without P/F numbers and the
fixed anatomical palette. This supersedes earlier button/locked-selection/no-
startup policies and authorizes the local V2 bridge differential transition port.
Persistent checkbox defaults off; startup/wake/replay exit reconcile selected native
IDs after opt-in. Emergency release disables persistently; sleep/replay/quit preserve
preference. All transitions await keyboard reset, serialize, and commit changed
logical selection only on successful native preparation. Refresh temporarily
suspends/reconciles; auto-resync remains paused during ownership/transition.
Preserve retained filters, rollback/retry and exact ownership validation.
Keep keyboard engine, keymap/reference, haptics and inspectors. No GesturePad
mouse/scroll/action engine is ported. Colors: Unknown black, Thumb orange, Index
blue, Middle green, Ring purple, Pinky pink, Palm gray. Keep #ID/name adjacent,
plain centered pressure, arrows and paths. No legend/display toggles.
Build native framework from source, test offline, build/install and leave closed.


## Configurable GesturePad gestures (2026-10-22; supersedes no-gesture-port policy)

User explicitly requests all currently implemented GesturePad gestures and approves
gestures taking priority over the keymap for the whole touch cycle. Local copies
of session recognition, acceleration, tap/drag, precise scrolling/momentum and
per-hand bindings are authorized. Keep legacy GTK action kinds inert.
GESTURE_ENGINE.md is this app's integration spec; GesturePad spec governs ported
thresholds. Right inspector has Gestures/Keyboard tabs. Persist app-local actions
and gains; takeover opt-in and selected/owned/armed/AX/profile/live-only gates
remain mandatory. Reserve enabled multi-finger candidates before keyboard output,
cancel same-pad pending/held actions, latch until all-up including empty release
frames, and preserve the other pad's typing. Replay never posts gesture output.
Preserve keymap, haptics, capture schema and native ownership lifecycle.
Do not modify siblings or concurrent mac/REWRITE.md/Hand.jpg work. Build/test,
install with stable Developer ID, leave closed for explicit hardware testing.


## Import/Export placement; trace tuning reverted (2026-10-22)

Keep equal-width Import/Export directly under Mode Toggles in the scrolling
Keyboard settings. User reverted the temporary TouchStream column experiment:
keep fixed traced positions, column tuning disabled, and original per-key
geometry behavior. No column offsets/scales/rotations apply to TouchStream.

## Reference alignment and menu icon (2026-10-22)

User authorized realigning all TouchStream key rectangles against the reference
and replacing the menu-bar status circles with a monochrome hand inspired by
mac/Hand.jpg. StatusHand is a vector template asset; let macOS choose its tint.
Do not restore colored mode/layer/disconnect badges or their subscriptions.
Preserve the underlying keyboard/layer state and device recovery behavior.
The key trace changes base position, size and angle only; preserve mapping
identities, saved per-key overrides and disabled column tuning.

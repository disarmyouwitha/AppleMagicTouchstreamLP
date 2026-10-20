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

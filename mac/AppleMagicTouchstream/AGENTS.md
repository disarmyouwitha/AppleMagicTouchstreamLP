# AppleMagicTouchstream

Scope: this directory only. Build/test with `./build.sh` and `./test.sh`; Xcode project `AppleMagicTouchstream/AppleMagicTouchstream.xcodeproj`, scheme `AppleMagicTouchstream`. Identity is in `project.env`.

This project targets faithful FingerWorks TouchStream emulation. GTK gesture recognizers and product-specific features were deliberately removed. Haptics are the user-authorized exception: keep optional accepted-key feedback and its strength control. Do not restore other removed features or treat the temporary key-landing/3 mm movement classifier as original TouchStream behavior. Original chords, English spelling correction/BackSpace Auto-Correct and variable-speed typematic are future fidelity goals; the removed GTK implementations were not faithful substitutes.

Keep the multitouch bridge, raw telemetry, device selection, capture/replay tools and useful keyboard bootstrap (normal key/modifier/shortcut output, tap/hold, layers, repeat) working while implementing the original interpreter. Menu-bar config, capture/replay, restart and quit are development utilities. Do not launch the app or exercise live HID/input without an explicit test request.

`AppleMagicTouchstream/AppleMagicTouchstream/ContentView.swift` preserves the original GUI. Keep its layout, trackpad IDs, visualizers, test area, keymap/column inspectors and useful tuning. Remove unwanted feature controls in place; do not replace or simplify the interface without explicit user direction. `Engine/TouchProcessorEngine.swift` is the temporary keyboard engine; `Engine/EngineActorBoundary.swift` owns serial execution and production replay. `Runtime/` owns ingestion, telemetry and capture/replay. `Compatibility/LegacyGTKProfile.swift` is decode/serialization compatibility for old captures and saved layouts, not a live gesture implementation. Unsupported GTK action kinds must remain inert through primary, hold and custom-button paths. Preserve existing settings keys/capture formats; changing serialized enums needlessly breaks fixtures.

Keep Swift bridge work in `Sources/OpenMultitouchSupport`, Objective-C work in `Framework/OpenMultitouchSupportXCF`. XCFramework output is generated: rebuild with `./build_framework.sh` after bridge changes, never hand-edit it. Do not add allocation, logging or I/O to hot input paths. Preserve deterministic replay and update baselines only for intentional behavior changes. Register added app files in the Xcode project as well as SwiftPM. Never change sibling projects incidentally.

Haptic settings remain percent in saved profiles and 0...1 in the engine. Route feedback to the selected originating pad, rate-limit per pad, and keep replay recording-only.

Feature audit: keep Auto-resync as device recovery and Hold Repeat as output scaffolding. Keyboard/Mouse and its native mouse-event blocker are removed; do not restore them from legacy profiles. Run at Startup and GTK Typing Grace are removed. Preserve profile decoding without reactivating them; preserve GUI layout when removing controls.


DriverKit takeover is ported from GesturePad v22; see DriverKitProbe/README.md.
Keep capture/decoder independent of output. AppleMagicTouchstream consumes contacts
through its keyboard engine, without GesturePad's synthetic pointer consumer or
legacy blackhole experiments. All supported model0324 pads remain captured; selectors
and manual Sync route app input. Preserve exact signed-owner validation, bounded
restart lease/watchdog, driver cancellation drain, release shortcut Control-Option-R,
release on sleep/replay/Exit, background warm restart on Config close, and Refresh
lock through pending ownership/removal. Do not launch or activate hardware tests
without explicit user request. Shared helper/driver identities permit one owning
app at a time. Run the driver Python tests as well as ./test.sh after changes.

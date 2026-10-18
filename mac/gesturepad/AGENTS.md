# GesturePad

## Scope and purpose
This folder is the independent FingerWorks/TouchStream gesture/chord playground. Keep raw-touch inspection, finger/pressure telemetry, traces, device selection and capture/replay. The opt-in control checkbox now filters selected-pad native movement and scrolling through event identity, without HID seizure, and enables experimental two-finger pointer output. Preserve clicks, drag events, unknown sources and other mice. No keyboard, click, scroll, voice, app-launch or haptic output is synthesized. Keep release safeguards and the temporary Test Pointer Sources observer. Historical raw-HID backend/capture schemas remain for diagnostics but have no UI buttons.

## Build and test
- `./build.sh`: app `GesturePad/GesturePad.xcodeproj`, target/scheme `GesturePad`.
- `./test.sh`: Swift package, runtime module `GesturePadRuntime`, replay and HID identity tests.
- `./release.sh --check`: validate app/release metadata without signing/notarization.
- App product: `build/DerivedData/Build/Products/Debug/GesturePad.app`.
- `./build_framework.sh`: bridge/XCFramework rebuild using project-local caches.
Scripts resolve their own directory. Identity is defined in `project.env`.

## Source organization
- `GesturePad/GesturePad/GesturePadApp.swift`: menu bar, config, capture/replay UI.
- `GesturePad/GesturePad/GesturePadController.swift`: device/raw-surface startup and capture/replay forwarding.
- `GesturePad/GesturePad/ContentViewModel.swift`: raw-contact monitoring model.
- `GesturePad/GesturePad/Engine/TouchProcessorEngine.swift`: live/replay contact processing boundary for future FingerWorks recognition.
- `GesturePad/GesturePad/Runtime/HIDBlackholeExperiment.swift`: exclusive HID ownership experiment; preserve release safeguards.
- `GesturePad/GesturePad/Compatibility`: historical capture/profile schemas and decoding, including legacy keyboard-shaped fields. Preserve their serialization and no-op behavior; do not restore keyboard features as incidental fixes.
- `LegacyReference`: saved original settings/screenshots, not app resources.
- `Sources/RewriteProbeKit` and `Sources/RewriteProbe`: offline contact analysis; see RewriteValidation/START_HERE.md.

## Rules
Preserve the menu-bar shape, existing defaults keys/bundle ID, capture formats, and deterministic replay. Keep sources independent of sibling projects. Do not add avoidable allocations, logging, or I/O on touch hot paths. Update the Xcode project when adding sources. Keep Swift bridge APIs in Sources/OpenMultitouchSupport and Objective-C bridge sources in Framework/OpenMultitouchSupportXCF; rebuild XCFramework after bridge changes and never hand-edit generated bundles. Report build/test limitations.

The checkbox enables continuous selected-pad event filtering (no timeout); the separate 30sec test button enables a timed session. Preserve explicit release/global shortcut plus selection-change, config-close, sleep, replay and termination cleanup for both modes.

TwoFingerPointerTracker uses per-device two-contact midpoint deltas; count/identity changes and stale frames reset the baseline. InterpretedTrackpadPointer posts tagged movement only on the live ingestion path while selected-pad control is active and Accessibility is granted. It pauses when mouse buttons are held. Keep replay output-free. Constant gain and recognition are provisional, not recovered TouchStream calibration.

SelectedTrackpadEventPolicy must only suppress positively identified selected-device mouseMoved/scrollWheel events. No last-active-device or click/drag timing guesses. Resolve sender services through current selected interface ancestry, including AppleMultitouchDevice children; never hardcode sender IDs or do registry I/O inside the event tap. Generated pointer events bypass the filter by tag. Stop control if selected services change or the tap disables. Test source observation and control are mutually exclusive.

Selected-pad ordinary movement currently requires experimental cursor correction: dropping CGEvents alone was observed to leave the cursor moving. Only matched selected-pad events may correct position; allowed/unknown/native-drag/tagged synthetic events update the anchor. Never globally dissociate cursor and mouse. Preserve the independent synthetic two-finger toggle, posted-event counter, and read-only OS three-finger-drag indicator. Hardware verification remains necessary for correction smoothness and mixed devices.

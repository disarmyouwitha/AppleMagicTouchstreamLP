# GesturePad

## Scope and purpose
This folder is the independent FingerWorks/TouchStream gesture/chord playground. Keep raw-touch inspection, finger/pressure telemetry, traces, device selection, capture/replay, and the opt-in HID blackhole experiment. It currently generates no keyboard, mouse, voice, app-launch, or haptic output. The separate device-link refresh control stays separate from trackpad refresh.

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

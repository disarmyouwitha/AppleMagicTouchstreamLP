# Gesturepad — TouchStream gesture playground

For the firmware-informed rewrite validation session, start with [RewriteValidation/START_HERE.md](RewriteValidation/START_HERE.md). `swift run RewriteProbe` analyzes saved captures offline and does not change the playground's recognition/output behavior.

FingerWorks gesture/chord playground. Device selection, blank raw-touch surfaces, named finger telemetry/contact paths, per-finger `p:` pressure and per-pad interaction peaks, and capture/replay remain. All GTK gesture recognizers, action configuration/dispatch, keyboard layouts, and layout generation are removed. Nothing generates keyboard, mouse, voice, or haptic actions. Add new FingerWorks logic at `TouchProcessorEngine.processContacts`, shared by live and replay input. Legacy profile commands are compatibility no-ops.

Open `GesturePad/GesturePad.xcodeproj` in Xcode, select the **GesturePad** scheme, and Run. The app is menu-bar based; use **Config...** to select trackpads and test. Run one experiment at a time to avoid both processing the same touches. Each experiment has its own bundle identifier and preferences, separate from the original and from each other. macOS may request Accessibility/Input Monitoring access for each new app.

Build from this directory:

```sh
xcodebuild -project GesturePad/GesturePad.xcodeproj -scheme GesturePad -configuration Debug -destination 'platform=macOS' build
swift test
```

The app product is `GesturePad.app`. The scheme name is `GesturePad`.

Profiles/capture formats retain legacy fields so existing configurations and recordings can still be read. Removed controls do not reactivate removed runtime features when imported. Package tests cover this experiment; inherited fixtures and transcripts are historical references, not parity expectations for the stripped engine.

This is an independent source copy of `../GlassToKey`, without generated build/release output or the SDK reference dump (available in `../sdk`). No source or package dependency points back to the original app. The original project remains unchanged.


## Temporary HID blackhole experiment

In Config, choose the left and right trackpads in the trackpad section. **Blackhole trackpad HID input (30-second test)** applies to both selected physical devices (or the one selected pad). Selecting the same physical trackpad twice opens it once. HID links refresh automatically on selection, trackpad refresh, and enabling the test. If either selected pad cannot be linked unambiguously, the test stays off. Keyboard interfaces are excluded.

Each eligible interface is opened with `IOHIDDeviceOpen(..., kIOHIDOptionsTypeSeizeDevice)`. Successfully opened interfaces register raw input-report callbacks that count reports/bytes/IDs and discard their payloads. Nothing forwards or synthesizes events. There is no CGEvent-tap fallback. Apple documents this as an [exclusive HID link](https://developer.apple.com/documentation/iokit/1588670-iohiddeviceopen); success on one HID interface does not demonstrate control of other input routes.

The separate blackhole-target picker and device-link refresh button are removed. The toggle uses both trackpad selections; **Release Trackpads** releases all seized interfaces. HID interface/report-count and diagnostic-copy controls remain hidden.

The experiment defaults off and auto-releases after **30 seconds**. It also releases on toggle-off, **Release Trackpads** (Command–Escape while Config has focus), target change, Config close, sleep, replay start, and app termination. The system closes HID clients when their process exits.

For each physical trackpad and transport (Bluetooth / USB), test cursor movement, physical click/drag, tap-click, scrolling, and macOS gestures. Record which outputs still occur, the displayed link/open status, and whether the OMS finger display continues updating. Release and confirm native input returns. Repeat with the other device/transport separately. Hidden or unexposed collections/routes are not ruled out by this inventory.

Use `./build.sh` and `./test.sh` for location-independent builds. See [project layout](../README.md). The goal is faithful TouchStream gesture/chord logic for eventual port to AppleMagicTouchstream.

`./release.sh --check` validates Release product identity and paths without signing or notarizing. Copy `release-config.env.template` to `release-config.env` when preparing a signed release.

## Source organization

`GesturePad/GesturePad.xcodeproj`, target and scheme **GesturePad**, produces **GesturePad.app**. The package runtime is **GesturePadRuntime**. The existing bundle ID remains unchanged to preserve settings/permissions.

Keyboard event posting, autocorrect, dictation, key semantic mapping, mobile layout generation, bundled keyboard keymaps, and the old mouse blocker are removed. The menu bar indicates raw-contact monitoring rather than keyboard/mouse modes. There are no microphone or speech permissions.

`GesturePad/GesturePad/Compatibility` contains the legacy data models and portable-profile decoder required by existing captures and offline replay. These types do not enable keyboard layouts, gestures, or output. `Runtime/PassiveOutputBoundary.swift` maintains the capture API without an action-output implementation. Saved settings/screenshots from the original copy are preserved in `LegacyReference` and are not app resources.

## Inline touch workspace

Live contact values flank the paired visualizers: left contacts in the left sidebar, right contacts in the right sidebar. Each sidebar scrolls independently; the workspace scrolls horizontally on narrower displays. Each contact shows its finger name, `p:` pressure, identity/state, normalized position, and available velocity. Expand **Raw measurements** for absolute coordinates, frame/time, axes, total, and density. Per-pad peak pressure and contact paths remain on the visualizers. Contact columns update live, including during replay; use Capture for recorded telemetry. The workspace scrolls vertically when the window cannot fit all contacts; there is no live-values popover.

Inline left/right touch telemetry remains in sidebars flanking the visualizers. The HID test opens the union of interfaces belonging to the selected trackpads and preserves per-interface open/close results.

**Release Trackpads** is directly below Config in the menu. **Control–Option–R** is registered as a global keyboard shortcut and releases the same session even when another app is focused (if the shortcut is available). The Config button and Command–Escape shortcut remain available as well.

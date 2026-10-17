# Gesturepad — TouchStream gesture playground

For the firmware-informed rewrite validation session, start with [RewriteValidation/START_HERE.md](RewriteValidation/START_HERE.md). `swift run RewriteProbe` analyzes saved captures offline and does not change the playground's recognition/output behavior.

FingerWorks gesture/chord playground. Device selection, blank raw-touch surfaces, named finger telemetry/contact paths, per-finger `p:` pressure and per-pad interaction peaks, and capture/replay remain. All GTK gesture recognizers, action configuration/dispatch, keyboard layouts, and layout generation are removed. Nothing generates keyboard, mouse, voice, or haptic actions. Add new FingerWorks logic at `TouchProcessorEngine.processContacts`, shared by live and replay input. Legacy profile commands are compatibility no-ops.

Open `GlassToKey/GlassToKey.xcodeproj` in Xcode, select the **GlassToKey** scheme, and Run. The app is menu-bar based; use **Config...** to select trackpads and test. Run one experiment at a time to avoid both processing the same touches. Each experiment has its own bundle identifier and preferences, separate from the original and from each other. macOS may request Accessibility/Input Monitoring access for each new app.

Build from this directory:

```sh
xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Debug -destination 'platform=macOS' build
swift test
```

The app product is `GlassToKeyGesturePad.app`. The scheme name remains `GlassToKey`.

Profiles/capture formats retain legacy fields so existing configurations and recordings can still be read. Removed controls do not reactivate removed runtime features when imported. Package tests cover this experiment; inherited fixtures and transcripts are historical references, not parity expectations for the stripped engine.

This is an independent source copy of `../GlassToKey`, without generated build/release output or the SDK reference dump (available in `../GlassToKey/sdk`). No source or package dependency points back to the original app. The original project remains unchanged.


## Temporary HID blackhole experiment

In Config, use **HID trackpad** to choose one physical trackpad, then enable **Blackhole trackpad HID input (30-second test)**. This selection is independent of the OMS left/right device selectors: an OMS device ID is not assumed to equal an HID registry ID. Related HID interfaces are grouped by vendor, transport, and serial (location when no usable serial exists); unidentified interfaces are not guessed into a group. Keyboard interfaces are excluded.

Each eligible interface is opened with `IOHIDDeviceOpen(..., kIOHIDOptionsTypeSeizeDevice)`. Successfully opened interfaces register raw input-report callbacks that count reports/bytes/IDs and discard their payloads. Nothing forwards or synthesizes events. There is no CGEvent-tap fallback. Apple documents this as an [exclusive HID link](https://developer.apple.com/documentation/iokit/1588670-iohiddeviceopen); success on one HID interface does not demonstrate control of other input routes.

The interface panel lists every discovered related registry ID, VID/PID, transport, primary usage, exact open/close result, and raw report counts. Partial success remains visible as `N/total`; a successful open is not labeled successful OS suppression. Zero reports after touching means raw-report availability has not been established even if the open succeeded. Open errors may reflect ownership, permissions, or privileges on the actual OS/device; no privileged helper is installed.

The experiment defaults off and auto-releases after **30 seconds**. It also releases on toggle-off, **Release HID now** (Command–Escape while Config has focus), Config close, sleep, replay start, and app termination. The system closes HID clients when their process exits. Final report counts and close results remain available through **Copy diagnostics**.

For each physical trackpad and transport (Bluetooth / USB), test cursor movement, physical click/drag, tap-click, scrolling, and macOS gestures. Record which outputs still occur, which interfaces opened, whether report counts increase, and whether the OMS finger display continues updating. Release and confirm native input returns. Repeat with the other device/transport separately. Hidden or unexposed collections/routes are not ruled out by this inventory.

Use `./build.sh` and `./test.sh` for location-independent builds. See [project layout](../README.md). The goal is faithful TouchStream gesture/chord logic for eventual port to AppleMagicTouchstream.

`./release.sh --check` validates Release product identity and paths without signing or notarizing. Copy `release-config.env.template` to `release-config.env` when preparing a signed release.

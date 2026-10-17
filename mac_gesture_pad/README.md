# GlassToKeyGesturePad

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

This is an independent source copy of `../mac`, without generated build/release output or the SDK reference dump (available in `../mac/sdk`). No source or package dependency points back to the original app. The original project remains unchanged.

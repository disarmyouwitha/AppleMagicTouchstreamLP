# GlassToKeyKeyboard

Keyboard versus mouse detection experiment. Device selection, keyboard layouts/key mapping, touch visualization, and capture/replay remain. Gesture recognizers/actions, drag cancellation, Typing Tuning, autocorrect, snapping, hold recognition/repeat, and typing grace are removed. A key landing is a typing candidate; movement beyond a fixed 3 mm threshold switches to mouse intent until all contacts lift. Native macOS mouse handling remains active; this experiment does not synthesize or suppress cursor movement.

Open `GlassToKey/GlassToKey.xcodeproj` in Xcode, select the **GlassToKey** scheme, and Run. The app is menu-bar based; use **Config...** to select trackpads and test. Run one experiment at a time to avoid both processing the same touches. Each experiment has its own bundle identifier and preferences, separate from the original and from each other. macOS may request Accessibility/Input Monitoring access for each new app.

Build from this directory:

```sh
xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Debug -destination 'platform=macOS' build
swift test
```

The app product is `GlassToKeyKeyboard.app`. The scheme name remains `GlassToKey`.

Profiles/capture formats retain legacy fields so existing configurations and recordings can still be read. Removed controls do not reactivate removed runtime features when imported. Package tests cover this experiment; inherited fixtures and transcripts are historical references, not parity expectations for the stripped engine.

This is an independent source copy of `../mac`, without generated build/release output or the SDK reference dump (available in `../mac/sdk`). No source or package dependency points back to the original app. The original project remains unchanged.

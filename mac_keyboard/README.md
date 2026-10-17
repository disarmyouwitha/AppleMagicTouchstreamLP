# GlassToKey Keyboard — conservative restart

This is a fresh copy of `../mac`. Its original keyboard touch processor, tap/hold actions, force thresholds, repeats, modifiers, layers, haptics, layouts, autocorrect, and configuration UI are retained.

The changes from `mac` are deliberately limited:

- **Gesture recognition** toggle at the top of Config, default **off**. When off, touch gestures, gesture chord recognition, and gesture-generated actions are disabled. Normal keyboard shortcuts, held keys and layers remain available. Enabling it restores GTK gesture recognizers. The preference is saved and included in exported/captured profiles; older profiles default off.
- Keyboard intent uses the earlier `mac_keyboard` classifier: a key landing permits typing, movement beyond **3 mm** selects mouse intent until all contacts lift. The original keyboard dispatch pipeline consumes that decision. Motion on either selected pad counts; unselected devices are ignored.
- **Tap Cadence**, **Drag Cancel**, **Intent Move**, and **Intent Velocity** controls are removed. Their legacy serialized fields remain readable, but their setters cannot change recognition. There is no separate keyboard drag-cancel path; tap-click gestures use a fixed internal cadence when recognition is enabled.

Build/run `GlassToKey/GlassToKey.xcodeproj`, scheme **GlassToKey**. The product remains **GlassToKeyKeyboard.app**, with bundle ID `ink.ranna.glasstokey.keyboard`, so existing keyboard-project preferences remain separate from `mac` and the gesture playground. Run one touch-processing app at a time when testing.

```sh
xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Debug -destination 'platform=macOS' build
swift test
```

The production replay transcript was refreshed for the new intent diagnostics. Its 14 output commands match the original `mac` replay exactly; the recorded capture was not regenerated.

The previous stripped/reworked keyboard source is backed up at `/tmp/glasstokey-keyboard-before-recopy`. `mac` and `mac_gesture_pad` were not changed by this restart.

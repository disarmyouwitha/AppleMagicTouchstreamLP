# AppleMagicTouchstream

This is a fresh copy of `../mac`. Its original keyboard touch processor, tap/hold actions, force thresholds, repeats, modifiers, layers, haptics, layouts, autocorrect, and configuration UI are retained.

The changes from `mac` are deliberately limited:

- **Gesture recognition** toggle at the top of Config, default **off**. When off, touch gestures, gesture chord recognition, and gesture-generated actions are disabled. Normal keyboard shortcuts, held keys and layers remain available. Enabling it restores GTK gesture recognizers. The preference is saved and included in exported/captured profiles; older profiles default off.
- Keyboard intent uses the earlier `mac_keyboard` classifier: a key landing permits typing, movement beyond **3 mm** selects mouse intent until all contacts lift. The original keyboard dispatch pipeline consumes that decision. Motion on either selected pad counts; unselected devices are ignored.
- **Tap Cadence**, **Drag Cancel**, **Intent Move**, and **Intent Velocity** controls are removed. Their legacy serialized fields remain readable, but their setters cannot change recognition. There is no separate keyboard drag-cancel path; tap-click gestures use a fixed internal cadence when recognition is enabled.

Build/run `AppleMagicTouchstream/AppleMagicTouchstream.xcodeproj`, scheme **AppleMagicTouchstream**. The product remains **AppleMagicTouchstream.app**, with bundle ID `ink.ranna.glasstokey.keyboard`, so existing keyboard-project preferences remain separate from `mac` and the gesture playground. Run one touch-processing app at a time when testing.

```sh
xcodebuild -project AppleMagicTouchstream/AppleMagicTouchstream.xcodeproj -scheme AppleMagicTouchstream -configuration Debug -destination 'platform=macOS' build
swift test
```

The production replay transcript was refreshed for the new intent diagnostics. Its 14 output commands match the original `mac` replay exactly; the recorded capture was not regenerated.

The long-term goal is faithful full TouchStream emulation on Apple Magic Trackpads. The current conservative keyboard implementation remains the starting point; this reorganization does not implement that future interpreter. Gesture/chord research lives independently in `../gesturepad`, and the GlassToKey reference is `../GlassToKey`.

Use `./build.sh` and `./test.sh` for location-independent builds with project-local caches. See [project layout](../README.md). Existing bundle ID and settings keys are retained for continuity.

`./release.sh --check` validates Release product identity and paths without signing or notarizing. Copy `release-config.env.template` to `release-config.env` when preparing a signed release.

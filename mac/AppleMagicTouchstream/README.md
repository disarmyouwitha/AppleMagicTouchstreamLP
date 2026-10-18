# AppleMagicTouchstream

A workbench for a faithful recreation of FingerWorks TouchStream on Apple Magic Trackpads. The original interpreter is still to be implemented; the remaining keyboard processor is temporary bootstrap code, not a claim of TouchStream equivalence.

## Current scope

- Local MultitouchSupport bridge, device selection and raw touch telemetry, pressure, contact paths, capture and deterministic replay.
- Temporary keyboard landing/movement classifier: landing on a key permits typing, movement over 3 mm selects mouse intent until all contacts lift.
- Basic key output, held modifiers, tap/hold shortcuts, layers, key repeat and mouse/media action scaffolding. Select a key in the visualizer to edit its tap and hold action. Existing saved layouts and key mappings remain readable.
- Menu-bar config, pause/resume, capture/replay, restart and quit remain development utilities.

GTK recognizers have been removed: count-based gesture taps/holds, heuristic chord-shift, directional swipes, corners, edges, triangles, gesture click/force-click actions, and gesture repeats. There is no gesture-recognition toggle or setting that can restore them. The GTK gesture configuration, mobile keyboard UI, mechanical-keyboard spacing/auto-splay helpers, app launching, voice dictation, macOS dictionary autocorrect/accessibility text replacement, small-step system controls and typing-toggle actions are also removed from the live app.

The original TouchStream **did** provide chords, English spelling correction/BackSpace Auto-Correct and pressure-dependent typematic. Removing GTK implementations does not remove these from the project's goal: faithful versions belong in the future interpreter. Useful normal keyboard shortcuts and modifiers remain.

## Optional haptic feedback

Haptics are the deliberate GTK exception for Apple trackpads. The original Typing Tuning panel retains its Off/Weak/Medium/Strong haptic slider (0/40/60/100%). Accepted keys, modifiers and hold activation pulse the originating trackpad, throttled independently per pad. Repeat ticks do not generate repeated haptics. Existing strength preferences are reused. Profiles store percent; offline replay normalizes this to the engine's 0–1 scale and only records feedback events, without vibrating hardware. Haptics are an Apple-trackpad extension, not a claim about original TouchStream behavior.

## Compatibility boundary

`AppleMagicTouchstream/AppleMagicTouchstream/Compatibility/LegacyGTKProfile.swift` holds historical profile/capture serialization. Old gesture, dictation and GTK tuning fields remain decodable so captures and saved keyboard layouts are not lost. They never configure live recognizers or effects. The engine's small legacy replay setters are inert; imported unsupported action kinds cannot dispatch through either keys or custom buttons. The mobile geometry helper remains only for offline replay of historical captures; live startup falls back to the bootstrap split layout.

The existing `ink.ranna.glasstokey.keyboard` bundle ID and `GlassToKey.*` preferences are retained for continuity. Existing keymap resources are compatibility/bootstrap data. Run only one touch-processing app at a time when testing.

## Build and test

Open `AppleMagicTouchstream/AppleMagicTouchstream.xcodeproj`, scheme **AppleMagicTouchstream**, or run:

```sh
./build.sh
./test.sh
./build_framework.sh
./release.sh --check
```

These scripts work from any current directory. `release.sh --check` validates paths and Release identity without signing/notarizing. See [project layout](../README.md). FingerWorks research is independent in `../gesturepad`; the GlassToKey reference remains in `../GlassToKey`.

## Configuration interface

The original interface is retained: trackpad selectors show device names **and IDs**, with the original visualizers, pressure peaks, touch inspection, test area, layout selector, keymap/shortcut/custom-button editor, column geometry and Typing Tuning. Feature removal is surgical: GTK Gesture Tuning/recognition toggle, autocorrect status/toggle, app-launch builder, snap toggle, macOS three-finger-drag workaround and mechanical-keyboard spacing/auto-splay controls are removed in place. Core layout, modifier/layer/hold mapping and haptics controls remain. Capture/profile compatibility does not reactivate removed recognizers or effects.

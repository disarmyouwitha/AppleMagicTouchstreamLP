# AppleMagicTouchstream

A workbench for a faithful recreation of FingerWorks TouchStream on Apple Magic Trackpads. The original interpreter is still to be implemented; the remaining keyboard processor is temporary bootstrap code, not a claim of TouchStream equivalence.

## Current scope

- Local MultitouchSupport bridge, device selection and raw touch telemetry, pressure, contact paths, capture and deterministic replay.
- Unreserved contacts default to typing; no movement-to-mouse latch, drag cancellation, or global Force Min/Max gate. Per-key Force instead of hold remains available.
- Basic key output, held modifiers, tap/hold shortcuts, layers, key repeat and mouse/media action scaffolding. Select a key in the visualizer to edit its tap and hold action. Existing saved layouts and key mappings remain readable.
- Menu-bar config, pause/resume, capture/replay, restart and quit remain development utilities.

GTK recognizers have been removed: count-based gesture taps/holds, heuristic chord-shift, directional swipes, corners, edges, triangles, gesture click/force-click actions, and gesture repeats. There is no gesture-recognition toggle or setting that can restore them. The GTK gesture configuration, mobile keyboard UI, mechanical-keyboard spacing/auto-splay helpers, app launching, voice dictation, macOS dictionary autocorrect/accessibility text replacement, small-step system controls and typing-toggle actions are also removed from the live app.

The original TouchStream **did** provide chords, English spelling correction/BackSpace Auto-Correct and pressure-dependent typematic. Removing GTK implementations does not remove these from the project's goal: faithful versions belong in the future interpreter. Useful normal keyboard shortcuts and modifiers remain.

## Optional haptic feedback

Haptics are the deliberate GTK exception for Apple trackpads. Typing Tuning has a fine **Haptic Strength** slider (0–2, step 0.01) using fixed waveform 6; zero is off. Accepted keys, modifiers and hold activation pulse the originating trackpad, throttled independently per pad; repeats do not pulse repeatedly. Existing profiles retain level ×100 storage. Replay records feedback without vibrating hardware. Force clicks independently use fixed waveform 6 at level 0.25. See FORCE_CLICK_HAPTICS.md for the native-framework clamp investigation. Haptics are an Apple-trackpad extension, not a claim about original TouchStream behavior.

## Compatibility boundary

`AppleMagicTouchstream/AppleMagicTouchstream/Compatibility/LegacyGTKProfile.swift` holds historical profile/capture serialization. Old gesture, dictation and GTK tuning fields remain decodable so captures and saved keyboard layouts are not lost. They never configure live recognizers or effects. The engine's small legacy replay setters are inert; imported unsupported action kinds cannot dispatch through either keys or custom buttons. The mobile geometry helper remains only for offline replay of historical captures; live startup falls back to the bootstrap split layout.

The permanent bundle ID is `ink.ranna.applemagictouchstream`. On first launch, preferences migrate from the former `ink.ranna.glasstokey.keyboard` domain without overwriting settings in the new domain; `GlassToKey.*` serialized keys remain compatible. Existing keymap resources are compatibility/bootstrap data. Run only one touch-processing app at a time when testing.

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

## Feature audit

- **Keyboard/Mouse removed:** no mode toggle, mouse-event tap/blocker, or permission prompt. Legacy profile fields remain inert. Future native-input suppression will use blackhole technology.
- **Auto-resync retained:** Apple-device recovery outside the recognition engine; useful during disconnect/sleep testing.
- **Run at Startup removed:** no control, registration manager, startup synchronization or imported-profile side effect. Existing OS login-item registration is not changed automatically; remove any previously enabled entry in macOS Login Items.
- **Hold Repeat retained:** testable output scaffolding for future original typematic. Current fixed repeat is not faithful pressure-dependent typematic.
- **Typing Grace removed:** no UI slider, post-key deadline or scheduled expiry. Legacy profile/replay setter is inert; unreserved contacts default to keyboard interpretation.

Keymap Import/Export includes both hands' configurable gesture actions and pointer/
scroll sensitivities in the Mac host extension. Older files without these settings
preserve current gestures. Trackpad Takeover opt-in remains local to this Mac.

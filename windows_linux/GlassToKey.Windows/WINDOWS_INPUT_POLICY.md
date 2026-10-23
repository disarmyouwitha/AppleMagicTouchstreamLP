# Windows keyboard/gesture policy and hand icon

Updated 2026-10-23 at the user's request.

## Removed from Windows

- Keyboard/Mouse checkbox and keyboard-only/mouse-only switching.
- Typing Toggle in the action menu; imported bindings cannot disable typing.
- Separate mode-driven selective click suppression, its device-edge timing heuristic, and the exception for clicks over the config window.
- Mode snapshot timer/events, mode persistence on restart, colored tray icons, and the header's mode/intent dots and badges.

Windows now opts into `TouchProcessorCore.UseUnifiedInputPolicy()`: typing stays enabled, keyboard-only mode stays off, and legacy setters or toggle actions cannot re-enable those modes. Windows normalizes the old profile fields to neutral values when loading/importing settings. The shared fields and legacy policy remain available to Linux and its existing regression tests.

This follows current Mac `TouchProcessorEngine.swift`, where typing is always enabled and `updateKeyboardModeEnabled` is a compatibility no-op. Keyboard intent, keymaps, modifiers, haptics, autocorrect, gesture reservation, and the existing per-pad gesture engine remain in use. Removing the global mode does not remove normal per-contact keyboard recognition.

## Mouse Takeover

`GlobalMouseClickSuppressor.cs` has been replaced by `GlobalMouseInputHook.cs`. The selective click filter is deleted. The hook still observes mouse activity for autocorrect/gesture interference and supports explicit Mouse Takeover and opt-in diagnostic gates.

Only explicit takeover/diagnostic gates suppress physical input. Typing, active layers, and old profile mode flags cannot silently turn click blocking on. Mouse Takeover's checkbox, 30-second test, Ctrl+Alt+R release, lease/watchdog, lifecycle cleanup, and injected-output allowance are retained. The tray tooltip and release menu still indicate takeover state.

## Hand icon

The source outline is copied directly from Mac `Assets.xcassets/StatusHand.imageset/StatusHand.svg`; only its fill changes from white to black. The Mac files are untouched.

Windows assets live in `Assets/`: black vector source, transparent PNG, and a multi-resolution ICO (16, 20, 24, 32, 40, 48, 64, 128 and 256 pixels). `WindowsDiagnostics/Build-HandIcon.ps1` reproduces them using WPF vector rendering.

The same hand is used for the executable, config window/taskbar icon, header and tray. The header places it on a light backplate for contrast against the app's dark background. The tray hand is static, replacing the former mode-colored circles. Left/right contact counters remain available.

## Verification

`UnifiedInputTests` checks old mode values/setters, ordinary keyboard taps, ignored imported typing-toggle actions, preservation of the shared legacy policy, icon loading, black fill and transparency. The existing gesture, tap-capture, fast-motion, modifier, and Mouse Takeover gate tests run as part of the same self-test suite.

The complete Release build in `bin/UnifiedInput` passed with zero warnings/errors, and all self-tests passed. The regular Release output was locked by the active app, which remains available for the user's tap testing; exit that instance before opening the updated build. No driver or Windows input settings were changed, and the user's separate TODO edits were preserved.

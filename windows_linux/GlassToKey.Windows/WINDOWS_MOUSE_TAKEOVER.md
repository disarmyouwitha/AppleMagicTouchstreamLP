# Mouse Takeover — Windows GlassToKey

## Controls

**Mouse Takeover** is below the Left/Right decoder selectors at the top of Config.

- Check it for continuous takeover during this app session; uncheck to release.
- **30sec test** checks it temporarily, displays a countdown, then releases and unchecks it.
- **Ctrl+Alt+R** releases globally and clears the checkbox. This matches Mac's **Control+Option+R** letter shortcut. It is release-only, not a toggle. No function key is required.
- With Config focused, use Alt+M or focus the checkbox and press Space to toggle it. Physical mouse clicks are blocked while takeover is on; the global release shortcut remains available.
- The status beside the checkbox indicates on/off, countdown, or an activation problem. The tray tooltip shows Mouse Takeover ON, and its menu offers Release Mouse Takeover.

The shortcut must register successfully before activation is allowed. If another app owns Ctrl+Alt+R, the checkbox is disabled and shows the reason.

## Scope and lifecycle

This is the accepted **all-physical-mouse** compromise. It blocks hook-visible physical cursor movement, buttons, and vertical/horizontal wheel events from every mouse. Raw trackpad contacts continue to reach the existing GlassToKey engine; injected output passes through. Mouse Takeover itself changes no decoder packing, driver binding, or Windows gesture settings. The new [gesture engine](WINDOWS_GESTURE_ENGINE.md) uses takeover as its output gate and replaces the former Windows gesture assignments.

Windows shell gestures or touchpad interactions outside the mouse-hook delivery path can still run. Configure conflicting Windows gestures separately if needed; keep the Windows Touchpad switch ON. This is not the selected-device FLTR ownership used on Mac.

The control defaults OFF at every app/process startup and is not saved in profiles. Closing/reopening Config retains the active shared tray runtime; Memory Saver does not restart that process while takeover is active. Restart/quit releases it. Sleep, session changes, contact-processing faults, or loss of the selected connected trackpads release it. Replay cannot activate it. There is no automatic reactivation after recovery.

Continuous mode uses a short hook deadline renewed by the UI heartbeat. If UI progress stops, the lease expires instead of keeping physical input blocked indefinitely. The independent watchdog also handles the keyboard release and 30-second limit. Hook timeout/removal remains a Windows reliability limitation; an active status reflects the requested gate state, not proof of exclusive ownership.

## Implementation and verification

`MouseTakeoverController.cs` owns the session state, global shortcut, heartbeat, watchdog, and lifecycle release. Both the shared tray runtime and standalone live/capture Config route use the existing GlobalMouseInputHook. The main Config UI and tray observe that state. Nothing auto-enables on startup.

The earlier Bluetooth hardware test established retained populated contacts and stable sampled cursor position except for injected movement: [measured result](WINDOWS_MOUSE_HOOK_FALLBACK.md#hardware-result-apple-bluetooth-1623-local). The integrated production UI still needs a short user check of checkbox/uncheck, Ctrl+Alt+R, test expiry, and the existing engine's outputs. Native scrolling/clicks/shell gestures and long-running/two-device behavior are separate checks. No takeover was activated during implementation.

Verification: the integrated Windows Release build completed with zero warnings/errors, all self-tests passed (including renewal/expiry/release gate checks), and a temporary host probe successfully registered/unregistered Ctrl+Alt+R without enabling takeover. The integrated build is in `bin/MouseTakeoverIntegrated`; launch its GlassToKey.Windows.exe with `--config --replace-instance` to use the updated real Config UI. No normal-mode takeover was activated by these verification steps. The main-app 30-second test uses existing engine outputs and does not inject the standalone diagnostic's automatic cursor jump.

## Release-build feedback: native gestures appear suppressed

On 2026-10-22, after opening the normal Release build, the user reported that Mouse Takeover felt correct and appeared to catch all Windows gestures they tried. No additional Windows gesture-setting changes were performed by the implementation. Exact gesture names, foreground apps, and an on/off comparison have not yet been recorded, so this is positive user-observed behavior on this setup, not a universal shell-gesture suppression guarantee.

Code comparison explains part of the improvement:

1. The original `--ptp-movement-gate` experiment used `GatePhysicalMovementFor`: it blocked only non-injected WM_MOUSEMOVE. Vertical/horizontal wheel and button events passed through.
2. The later 30-second Mouse Takeover window and the integrated app both use `GatePhysicalMouseFor` and the same ShouldBlock policy: non-injected movement, wheel, and button events are blocked. Injected events pass. This directly covers native scrolling and gesture actions delivered as those mouse events.
3. The integrated app renews a short fail-open lease for continuous checkbox mode and runs the existing real typing/gesture/drag engine. The standalone diagnostic had a fixed 30-second gate and did not run that engine. Whether engine activity contributes to suppressing any higher-level Windows actions has not been isolated.
4. Neither Mouse Takeover version disables PTP, calls the Windows-internal MIT interception APIs, or installs a driver. Preserved contact delivery is therefore consistent with the earlier successful 30-second capture.

The integrated filter was not broadened beyond the later successful Mouse Takeover test. The broadening happened between the original movement-only experiment and that test. Windows shell actions that bypass the mouse hook are still not covered by an explicit implementation contract. Retain the current gesture settings while behavior is satisfactory; a brief checkbox-off/on comparison of Task View, desktop switching, scroll, and pinch would distinguish native actions from GlassToKey's injected output if needed. No code or settings were changed in response to this feedback.

## Confirmed remaining conflict and warning detection

The user subsequently configured a Windows three-finger gesture and confirmed it still fires during Mouse Takeover. Movement, buttons, and scroll remain blocked as observed. The mouse hook does not provide complete shell-gesture suppression. The user explicitly accepts that compromise.

A read-only query of the actual interactive user's `HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad` returned `ThreeFingerSlideEnabled=1`, `ThreeFingerTapEnabled=0`, `FourFingerSlideEnabled=0`, `FourFingerTapEnabled=0`, and `CustomThreeFingerTap=0`. [Saved narrow preference snapshot](WindowsDiagnostics/windows-gesture-preferences-20261022.json). The sandbox runs as a different account and its HKCU lacked this key; the approved host read accessed the real user's preferences. The installed app normally reads its own user hive without administrator privileges. An absent sandbox key was not evidence that the user's bindings were off.

### Proposed read-only warning

The four `Three/FourFinger` `Slide/TapEnabled` DWORDs can serve as a best-effort signal. Do not assume the Enabled suffix means the nonzero value is merely a Boolean: action/preset values need not be decoded to show a conflict warning. Exact action mapping and Windows-version stability have not been validated. These fields are observed implementation details, not a documented complete/per-device query contract.

- If any known field is present and nonzero, warn that Windows multi-finger actions may still fire during takeover.
- If all four are present, valid DWORDs, and zero, report only that no enabled standard three/four-finger bindings were found. Do not certify every driver/custom gesture is disabled.
- Missing, malformed, inaccessible, or unrecognized data is Unknown, not Disabled; Windows may use defaults or another configuration path. Avoid inventing default values.
- Refresh on Config activation and before enabling takeover, or watch the relevant key for changes, so a Settings change does not leave stale UI. No touchpad settings should be written.

Suggested copy: **Windows multi-finger gestures are enabled and may still run during Mouse Takeover. Review Windows touchpad settings.** For Unknown: **Windows gesture settings could not be verified. Three/four-finger actions may still run.**

An action can open `ms-settings:devices-touchpad` for user review; release Mouse Takeover before opening it so physical mouse input works in Settings. This is the touchpad page, not the touchscreen `devices-touch` page. The documented [TOUCHPAD_PARAMETERS_V1](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-touchpad_parameters_v1) exposes pan/zoom/tap settings but no three/four-finger action bindings. Microsoft documents the [Touchpad Settings URI](https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-settings#devices) and [gesture customization UI](https://support.microsoft.com/en-us/windows/hardware/input-devices/touch-gestures-for-windows).

This section records the feasible warning design; no detector, warning UI, or settings change was added in this research step.


The Windows Keyboard/Mouse mode and its separate selective click filter have been removed. The global hook now observes mouse activity and implements only explicitly enabled takeover/diagnostic gates. It does not suppress clicks based on typing, layers, or an imported mode preference. The hand tray icon is static; takeover remains visible in the tooltip, release menu and Config status. See [input policy](WINDOWS_INPUT_POLICY.md).

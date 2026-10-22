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

This is the accepted **all-physical-mouse** compromise. It blocks hook-visible physical cursor movement, buttons, and vertical/horizontal wheel events from every mouse. Raw trackpad contacts continue to reach the existing GlassToKey engine; injected output passes through. It adds no new pointer/gesture engine and changes no decoder packing, typing/haptics settings, driver binding, or Windows gesture settings.

Windows shell gestures or touchpad interactions outside the mouse-hook delivery path can still run. Configure conflicting Windows gestures separately if needed; keep the Windows Touchpad switch ON. This is not the selected-device FLTR ownership used on Mac.

The control defaults OFF at every app/process startup and is not saved in profiles. Closing/reopening Config retains the active shared tray runtime; Memory Saver does not restart that process while takeover is active. Restart/quit releases it. Sleep, session changes, contact-processing faults, or loss of the selected connected trackpads release it. Replay cannot activate it. There is no automatic reactivation after recovery.

Continuous mode uses a short hook deadline renewed by the UI heartbeat. If UI progress stops, the lease expires instead of keeping physical input blocked indefinitely. The independent watchdog also handles the keyboard release and 30-second limit. Hook timeout/removal remains a Windows reliability limitation; an active status reflects the requested gate state, not proof of exclusive ownership.

## Implementation and verification

`MouseTakeoverController.cs` owns the session state, global shortcut, heartbeat, watchdog, and lifecycle release. Both the shared tray runtime and standalone live/capture Config route use the existing GlobalMouseClickSuppressor hook. The main Config UI and tray observe that state. Nothing auto-enables on startup.

The earlier Bluetooth hardware test established retained populated contacts and stable sampled cursor position except for injected movement: [measured result](WINDOWS_MOUSE_HOOK_FALLBACK.md#hardware-result-apple-bluetooth-1623-local). The integrated production UI still needs a short user check of checkbox/uncheck, Ctrl+Alt+R, test expiry, and the existing engine's outputs. Native scrolling/clicks/shell gestures and long-running/two-device behavior are separate checks. No takeover was activated during implementation.

Verification: the integrated Windows Release build completed with zero warnings/errors, all self-tests passed (including renewal/expiry/release gate checks), and a temporary host probe successfully registered/unregistered Ctrl+Alt+R without enabling takeover. The integrated build is in `bin/MouseTakeoverIntegrated`; launch its GlassToKey.Windows.exe with `--config --replace-instance` to use the updated real Config UI. No normal-mode takeover was activated by these verification steps. The main-app 30-second test uses existing engine outputs and does not inject the standalone diagnostic's automatic cursor jump.

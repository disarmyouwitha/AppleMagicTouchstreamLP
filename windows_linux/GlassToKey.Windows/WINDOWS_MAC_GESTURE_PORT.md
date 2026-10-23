# Latest Mac gesture inspector and recognizer port to Windows

Updated: 2026-10-23. This document distinguishes implemented/offline-verified behavior from live behavior still awaiting acceptance.

## Reference reviewed

The reference is the current source tree in `mac/AppleMagicTouchstream`, not a running Mac binary. No Mac files were changed and no app, takeover, HID session or synthetic input was started during verification.

- `GestureInspector.swift`: grouped sidebar, hand scope, anatomical diagrams, disclosure sections, action menus and conditional gain sliders.
- `Runtime/HandGestureSettings.swift`: independent 2–5-finger inward/outward bindings, 1–5-finger force actions, defaults, allowed actions and per-hand gains.
- `Runtime/ScrollGesture.swift`: `PinchSpreadTracker` and router ownership/translation competition.
- `Runtime/TapClick.swift`: force-click count/identity rules and one-shot crossing.
- `Runtime/InterpretedTrackpadPointer.swift`: reservation, force interruption, output gating and haptics.
- `ContentView.swift`: two-column inspector and Import/Export placement.
- `GESTURE_ENGINE.md`: current integration specification.

## Inspector changes

Windows now groups the inspector by 1, 2, 3, 4 and 5 fingers, followed by Thumb + 2 fingers. Each group shows the same schematic anatomical colors and mirrored hand positions as Mac. These are explanatory diagrams, not claims that Windows reports anatomical finger labels.

Left/Right/Both is a segmented selector. Tap and Move, Move and Force Click, Force Click, and Pinch and Spread are collapsible sections. Two-finger Tap and Move starts expanded; expansion choices survive scope/settings refreshes for the current window. Action menus show Mixed plus each hand's assignment when editing differing values.

Pointer, Scroll and Zoom sensitivity sliders appear only in sections that use those actions. Gains range from 0.25× to 2× in 0.01 steps. Natural scrolling appears with Scroll. The accepted Apple reference pointer response remains fixed. Import/Export Settings are equal-width buttons below the Keyboard options, matching the Mac placement rather than occupying the window header. Existing keyboard settings and input policy are preserved.

## Inputs and defaults

| Input | Default | Choices |
| --- | --- | --- |
| 2-finger movement | Move Pointer | None, Pointer, Drag, Scroll |
| 3-finger row movement | Drag / Select | None, Pointer, Drag, Scroll |
| 4-finger movement | Scroll / Pan | None, Pointer, Drag, Scroll |
| 2-finger tap | Primary Click | None, primary, double, secondary click |
| 3-finger tap | Double-Click | Same tap choices |
| Spread thumb + 2 tap | Secondary Click, unavailable on current PTP reports | Same tap choices; saved but inactive without thumb identity |
| 1-finger force click | Primary Click | Tap choices and Windows system actions |
| 2–5-finger force click | None | Tap choices and Windows system actions |
| Each 2–5-finger Pinch | Zoom | None, Zoom, Windows system actions |
| Each 2–5-finger Spread | Zoom | Same, independent of inward assignment |

The new families are recognized only by the existing Windows hand-gesture composition. Linux's legacy input engine and opt-in boundaries are unchanged. Enum values used by existing settings retain their numbers; new bindings use a cloned additional-action map and Zoom gain. Ordinary Windows settings and portable GlassToKey profile export/import retain them. This does not add automatic import of the different Mac profile schema or Mac shell action names.

## Recognition and arbitration

Shape scale is the RMS pairwise contact spacing in physical millimetres. Rigid translation and rotation do not create scale. Pending activation requires spacing between 5 and 200 mm, at least 0.6 mm of spacing change, and spacing change exceeding centroid travel times `3 / contactCount`. The initial sign selects Pinch or Spread. Spacing-dominant pending input defers pointer/drag/scroll activation. The winning trigger and action remain latched through direction reversal and changes in finger count until all-up.

Added/replaced contacts establish a new shape baseline and contribute zero scale on that frame. A lone survivor continues against the previous other contacts' centroid as a virtual anchor. Discontinuities, duplicate IDs, palm labels, invalid values, >=15 mm shape jumps, >=25 mm per-axis physical motion, stale frames and lifecycle reset cancel safely. Zoom is bounded to ±0.25 scale per packet and has no momentum.

Two Windows safeguards are intentionally retained in addition to the Mac reference rules:

1. Three-finger Drag waits 120 ms for a stable chord when four-finger Scroll is assigned. Waiting travel is discarded; an unowned four-finger cycle cannot become three-finger drag as contacts lift.
2. A still-valid assigned two/three-finger tap retains priority over small shape changes. The initial straight port stole one tap from the user's recorded capture (10 instead of 11 taps, while all 14 longer motion activations stayed unchanged). Pinch now waits until the relevant tap recognizer is no longer viable; this preserves the 1 mm tap-slop/500 ms tap-duration rules. With the corresponding tap set to None, this additional guard is absent. This may make very small pinches feel less immediate and requires live acceptance.

Enabled multi-finger candidates reserve keyboard input before output; reservation includes all-up. One-finger force reserves only at an enabled pressure crossing, preserving ordinary one-finger typing before crossing. Reservation cancels same-pad pending/held keyboard work through the existing runtime path. Another pad remains independently usable; output cannot click/zoom through the other pad's held drag.

## Force click: implemented, pressure feel unverified

The port uses the Mac threshold, maximum reported contact pressure P >= 130. It never sums pressures, uses the button bit as pressure, or infers force from legacy PTP flags. `WindowsHandGestures` carries `ContactFrame.Pressure8` only when `HasForceData` is true. [OFFICIAL_PTP_SPEC.md](OFFICIAL_PTP_SPEC.md) documents the official decoder's raw pressure byte; that evidence does not establish that 130 has the same physical feel as Mac pressure.

The current contact count chooses the enabled force binding. Adding fingers before pressing is allowed; lifting or replacing a finger prevents later force activation in that cycle. A successful crossing fires once until all-up, cancels taps/coast/shape output and balances any active drag before the force action. None bindings do not interrupt continuous output. Pressure-free decoders cannot trigger force actions.

Force feedback uses the existing Windows actuator route, originating pad, enabled/strength settings and rate limiter, with an additional 50 ms per-pad force-feedback bound. No new reports or IOCTLs are introduced. Mac's fixed waveform-6/0.25 feedback is not claimed to map to Windows' actuator strength encoding; Windows retains its accepted haptic transport and user strength. Replay remains recording-only and never instantiates the live gesture output worker.

## Windows outputs

| Mac action/family | Windows implementation |
| --- | --- |
| Zoom | Short, balanced Ctrl+wheel packet for each scale delta |
| Notification Center | Win+N, for Windows 11 |
| Mission Control / App Exposé | Task View (Win+Tab), offered once as Task View; no exact App Exposé equivalent claimed |
| Launch Pad | Start Menu (Windows key) |
| Show Desktop | Win+D |

Shortcut plans are value-only data until the live worker executes them. They emit once on activation, with balanced edges and the existing interpreter event tag. Zoom retains fractional wheel units, provisionally at 1200 wheel units per scale unit. The cursor is not moved. Each zoom packet includes Ctrl down/up; no modifier is held between frames. Target apps may use discrete zoom levels or ignore Ctrl+wheel. This is a compatibility transport, not Windows native PTP magnification, and target-app zoom feel remains unverified.

Zoom and shell actions skip output while another Ctrl/Shift/Alt/Windows modifier is already held, rather than releasing keys owned by physical input or the typing engine. Failed/partial keyboard sends queue only their own release keys for retry; the worker retries cleanup before more output and during idle/shutdown. Existing eligibility, generation invalidation, bounded queue, stale-command rejection and emergency release remain in place. No system shortcut preferences or touchpad settings are modified.

Microsoft documents the shell shortcuts in [Keyboard shortcuts in Windows](https://support.microsoft.com/en-gb/accessibility/windows/keyboard-shortcuts-in-windows), and Ctrl state/fine wheel deltas in [WM_MOUSEWHEEL](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-mousewheel). Actual app zoom behavior is not guaranteed by those message semantics.

## Offline verification

Release build completes with no warnings/errors. Full `--selftest` passes, including:

- Both hands and all 2–5-contact pinch/spread directions; reversals and one-shot system bindings.
- 2→5→1 contact continuity, membership rebase, virtual anchor, translation/rotation rejection and stale/disabled cleanup.
- Each force count, exact 129/130 crossing, one-shot action and haptic routing, maximum versus summed pressure, pressure-free decoding, duplicate IDs and partial lifting.
- Force interruption with balanced drag release, and None force allowing Zoom to continue.
- Settings defaults, existing enum numbers, clone isolation and portable profile retention.
- All 19 action menus, gain scoping/Mixed, active slider preservation and expanded-section retention.
- Balanced Windows shortcut plans and correct 32/64-bit INPUT ABI size, without posting any events.
- The entire existing captured tap replay: 11 taps, 574 pointer outputs and the same activation frames for all 14 longer movements.

Off-screen WPF renders check Keyboard, Gestures, compact size and replay controls. They use fixture devices and default settings and do not construct MainWindow's live runtime. The expanded pinch/force sections are also rendered for visual inspection. Images are available under the build's `Preview` folder.

## Live acceptance still required

Exit the running tray app before opening the updated executable. First inspect the GUI without enabling takeover. Then use the existing 30sec test and a blank browser/document surface to check:

1. Existing two-finger taps/movement, deliberate three-finger drag and four-finger scroll still feel right.
2. Two-finger inward/outward zoom in a browser, then in the intended target apps. Try 3–5-finger shapes and added/lifted fingers.
3. One-finger force click at a harmless location. Confirm ordinary typing does not trigger it; test the other counts only after assigning them.
4. Set a single force/pinch binding to Task View, Start Menu or Show Desktop and confirm one action per touch cycle. Native Windows gestures can still conflict independently of Mouse Takeover.
5. Ctrl+Alt+R and the timed expiry still release input immediately. Do not use important folders to evaluate drag/scroll arbitration.

A capture is useful if force fires too easily, pinches feel delayed, or native gestures interfere. No live hardware/input actions were exercised by the agent.

## Build locations

The regular Release build also succeeded with zero warnings/errors:

`GlassToKey.Windows/bin/Release/net10.0-windows/GlassToKey.Windows.exe`

The independently verified staging build and off-screen images remain in `GlassToKey.Windows/bin/MacGesturePort`. Exit the existing tray instance before launching the updated regular executable. Build from `windows_linux` with `dotnet build .\GlassToKey.Windows\GlassToKey.Windows.csproj -c Release`.

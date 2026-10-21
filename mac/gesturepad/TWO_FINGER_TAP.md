# Two-finger tap to click

**Current gesture rules:** [GESTURE_ENGINE.md](GESTURE_ENGINE.md) is the central
behavior specification. This file supplies feature-specific detail and history.

Added 2026-10-20, GesturePad only, at the user's request. A short stationary
**two-finger tap makes a primary/left click when both fingers lift**. The
**2-finger tap to click** checkbox defaults on with Trackpad Takeover, including
restored takeover at startup. Uncheck it independently to disable tap clicks.
Manual overrides survive ordinary selection/sleep/replay restoration in the
same process; fresh explicit takeover enable restores the feature default.

## Recognition and arbitration

`Runtime/TapClick.swift` is a pure per-pad discrete recognizer, separate from
continuous mouse/scroll ownership. Initial test thresholds are:

| Condition | Limit |
| --- | ---: |
| Entire tap, from first contact to all-up | 500 ms |
| Delay before the second finger joins | 80 ms |
| Minimum simultaneous two-finger overlap | 20 ms |
| Delay between the first and last lift | 80 ms |
| Maximum displacement of either finger from its initial position | 1 mm |
| Maximum contact callback gap | 150 ms |

Allow either finger to land/lift first, and tolerate contact ordering changes.
Reject extra fingers, identity replacement, rejoining after lift begins,
invalid/palm input, stale/nonmonotonic timestamps and long holds. One finger
cannot click. A rejected gesture stays rejected until all-up; repeated empty
frames cannot repeat a successful click.

The 0.35 mm mouse / 0.2 mm scroll initiation rules take priority: once the shared
router recognizes movement, that entire touch cycle cannot tap-click. Thus the
1 mm per-finger limit is an outer rejection limit, not a promise that moving
the centroid by 1 mm remains a tap. This prevents a recognized mouse stroke from clicking on lift. The mouse-only
threshold was raised from 0.2 mm using the move–tap capture, allowing more landing
drift without a fixed delay. Opposing finger movement
is checked individually even if its centroid is stationary. Hardware testing
may justify tuning tap slop/arbitration together later.

A touch used to brake momentum is excluded from tap clicking until all-up.
Physical button suppression, disable, selection changes, release, sleep/replay
and other explicit resets cancel pending taps. Idle watchdog cleanup must not
block the next fresh tap: only existing candidates are invalidated on per-pad
reset. A held physical button explicitly blocks that touch cycle.

## Click output

Create both [Core Graphics mouse events](https://developer.apple.com/documentation/coregraphics/cgevent/init(mouseeventsource:mousetype:mousecursorposition:mousebutton:))
before posting either edge. Post left down followed immediately by left up at
the current cursor, under the same serial output lock. No synthesized held
button, drag, delayed mouse-up job, cursor warp or right-click is introduced.
Events carry the existing synthetic input tag and current modifier flags, so
Shift/Command combinations can retain ordinary click behavior.

Click counts use macOS's double-click interval, four-point position tolerance,
and matching modifiers. Rapid stationary taps receive click counts 1, 2, then
3; timeout, pointer travel, modifier change or reset starts a new count. Both
edges carry the same count. This is a generated-click sequence; mixing physical
and tap clicks is not a reconstructed native click-history stream.

Tap eligibility is independent of acceleration profiles: it still requires the
current selected AND owned FLTR pad, successful transition arming, enabled
feature/takeover and Accessibility. Tap-only operation is allowed when mouse or
scroll output is disabled. Missing permission shows a status message. Replay and
automated tests never post clicks.

## Verification and hardware acceptance

`TwoFingerTapTests` covers staggered landing/lift, one-shot completion, rejection
of holds/motion/extra/replaced contacts, stale/invalid input, movement arbitration,
per-pad isolation, reset/braking suppression, idle watchdog behavior and complete
mouse event pairs/counts/flags. Tests create and inspect events without posting.

Test in a harmless document or blank application area:

1. Tap with two fingers: exactly one primary click after lift.
2. Try either finger landing/lifting slightly earlier.
3. Tap twice rapidly: ordinary double-click behavior.
4. Mouse with two and lift: no click. Hold, spread or add extra fingers: no click.
5. Flick-scroll, then touch to brake: no click from that braking cycle.
6. Disable tap, release takeover or use Ctrl-Option-R: no synthetic clicks.

No hardware activation or app launch is performed by automated verification.

## Move–tap capture tuning

The 2026-10-20 recording reproduces six tap rejections caused by mouse initiation,
not the 500 ms tap limit. The new mouse-only initiation threshold is 0.35 mm;
scroll remains 0.2 mm. See [capture analysis and next test](RewriteValidation/TWO_FINGER_TAP_CAPTURE_ANALYSIS.md).

The follow-up `2finger_tap_test2.atpcap` supports retaining 0.35 mm: production
replay accepts all 22 independent tap candidates, while 23 movement cycles have
no predicted clicks. The user reports improved feel. Larger tested initiation
thresholds add no accepted taps; no further behavior change was made.

# AppleMagicTouchstream gesture engine

Ported from GesturePad on 2026-10-22. This independent local implementation keeps
recognition separate from per-hand actions. Numerical models, input thresholds,
geometry, latching, click timing and release safeguards match
[GesturePad's specification](../gesturepad/GESTURE_ENGINE.md). Firmware research
remains in [mac/FINDINGS.md](../FINDINGS.md); these working gestures are not a claim
of complete TouchStream firmware fidelity.

## Inputs and factory actions

| Input | Factory action |
| --- | --- |
| Two-finger movement | Move Pointer, Apple acceleration |
| Two-finger tap | Primary Click |
| Close, aligned three-finger movement | Drag / Select |
| Non-thumb three-finger tap | Double-Click |
| Four-finger movement | Scroll / Pan, precise scroll and momentum |
| Spread thumb + two known fingertips tap | Secondary Click |

Each movement input offers None, Move Pointer, Drag / Select and Scroll / Pan.
Each tap input offers None, Primary Click, Double-Click and Secondary Click.
No keyboard action assignment or legacy GTK gesture reactivation is introduced.
Movement activation remains 0.35 mm for two/three fingers and 0.2 mm for four;
continuous ownership latches through added/lifted fingers until all-up. Shared-ID
motion avoids centroid jumps. Tap duration is 500 ms, landing/lift skew 80 ms,
overlap 20 ms and slop 1 mm. Spread thumb geometry and relabel tolerance match
GesturePad. Pointer/scroll models, fine movement, momentum and held-drag observer,
reserved button-up, queued-position and stale-input cleanup are ported unchanged.

## Configuration and eligibility

The right inspector has Keyboard first (the default) and Gestures second. Import/Export
Keymap appears below the selector only on Keyboard. Gestures contains the colored
chord examples and Left/Right/Both Action menus. Keyboard retains the existing
layout, column, keymap, haptics and tuning controls. Both shows Mixed assignments;
choosing an action applies to both. Factory settings start mirrored.

Bindings and gains persist in app-local UserDefaults under
`AppleMagicTouchstream.handGestureBindings.v1`. Takeover remains a separate,
default-off persistent opt-in; toggling it never overwrites customized actions.
Duplicate physical-pad selections use Left's non-None action, then Right fallback,
and Left sensitivity. Routing uses native numeric device IDs, not compacted slots.

Output requires selected-and-owned native FLTR pads, a successful armed transition,
Accessibility and live input. Pointer/drag requires the selected device's readable
pointer profile; scroll requires its scroll profile. Missing permissions/profiles
pause output rather than silently substituting another model. Failed transitions
disarm output even if native rollback retained ownership. Changing settings or
selection clears active gesture output; lifecycle transitions stop output before
awaiting keyboard cleanup. Emergency release remains Ctrl–Option–R.

## Keyboard arbitration (user-approved)

Configured multi-finger inputs take priority over keymap regions. Reserve a
candidate as soon as its enabled finger-count family appears, before motion/tap
recognition commits. Reserve the entire pad's touch cycle, including surviving or
added fingers and its final release frame. Rejected/invalid candidates do not
fall back to typing. Two fingers reserve when either two-finger input is assigned;
three reserve for any assigned three-finger/T2F input; four reserve for assigned
four-finger movement. None disables that input's reservation.

On claim, cancel pending keys/repeat/holds and balance engaged modifiers on that
pad. Suppress layer toggles/momentary layers and terminal fallback taps. Keep the
other pad's keyboard contacts and intent independent. Empty-frame all-up cleanup
also clears disqualification marks, allowing reused contact IDs to type next cycle.
One-finger keyboard behavior remains available outside reserved cycles. Already
emitted keys before a second finger arrives cannot be undone.

Reservation is kept while an owned, armed gesture's output is paused for missing
Accessibility/profiles, preventing failed gestures from typing instead.
Recognition/output runs only in the live serial ingestion path. Replay and offline
queries never post gesture events; old keyboard replay/capture formats stay valid.
Gesture bindings are app preferences, not added to the existing capture schema;
gesture CGEvents are not recorded as keyboard dispatch events in old captures.

## Verification

Offline coverage includes the ported recognition/acceleration/momentum/tap/drag/
action/routing tests and numeric vectors, plus keyboard priority, balanced modifier
cleanup, other-hand typing and empty-frame recovery tests. Native takeover tests
cover output arming and failed-transition disarming. Universal Release and signing
must pass before installation. Hardware acceptance of this combined keyboard and
gesture app remains separate from GesturePad's accepted behavior.

# Gesture sessions and latching

User-directed rule, 2026-10-20: FingerWorks-style gestures can latch. Their
starting chord identifies the gesture; keeping that exact chord is not a
requirement for its entire lifetime. This captures the requested interaction
without claiming every original FingerWorks gesture behaved identically.

Future recognizers must describe four separate decisions:

1. **Activation:** which contacts and motion start the gesture?
2. **Continuation:** which contact changes preserve that gesture?
3. **Completion:** when has the user finished? All fingers up is the default
   session boundary for a latched gesture.
4. **Cancellation:** which explicit interruption safely abandons ownership?

Do not reclassify each frame from finger count alone. A session belongs to one
physical pad and retains its recognized gesture through allowed contact changes.
Before adding a competing recognizer, define how it interacts with an existing
session; an extra finger must not accidentally activate another gesture. Some
future gestures may need explicit transitions or different completion rules.
Document and test those policies instead of assuming every recognizer shares
the mouse continuation count.

## Initial chord arbitration (four-finger scroll addition)

The live router now waits for 0.2 mm of initial coherent movement before latching
an enabled two-finger mouse or four-finger scroll chord. Contact-count changes
reset pending displacement while the fingers finish landing. Once committed,
any positive count continues that mode; mouse does not turn into scroll merely
because a fourth finger joins. Scroll likewise continues after fingers lift.
The existing per-ID common-displacement rule applies to both. All-up or explicit
cancellation releases recognition ownership. Scroll may continue a separately
owned momentum coast after all-up; new contact cancels that coast before
recognition resumes. Momentum never keeps a gesture latch alive. See [FOUR_FINGER_SCROLL.md](FOUR_FINGER_SCROLL.md)
for acceleration, fine event handling and acceptance checks. The initial threshold
is new and needs hardware acceptance; the accepted pointer curve is unchanged.

## Current mouse behavior

| Situation | Result |
| --- | --- |
| Idle, any count other than two | Remain idle. |
| Idle, exactly two active contacts | Latch mouse mode and anchor motion. |
| Latched, same pair moves | Move from the pair's centroid. |
| Latched, either finger lifts | Keep moving from the survivor immediately. |
| Latched, fingers join | Keep moving from continuing contacts; new fingers establish their own baseline. |
| Latched, three or more contacts | Continue mouse movement; finger count does not pause or reclassify the gesture. |
| All active contacts lift | End the session; a lone new finger cannot resume it. |
| No IDs in common with the preceding frame | End the old session, treating the missing all-up frame as an interruption; only a fresh two-finger chord can re-arm. |

Changing a centroid's membership is not physical pointer movement. Match contacts
by ID across consecutive frames and average only those fingers' displacements.
New fingers participate after their first baseline; lifted fingers contribute
nothing. This preserves real movement during membership changes without adding
landing-position jumps or inserting a motion pause. With stable membership this
equals centroid displacement. Keep independent history per pad; a latch on the
left cannot enable one-finger motion on the right.
The existing definition of active contacts is `making`/`touching`, excluding
hover-only contacts.

Existing explicit resets cancel the session: release/disable, selection changes,
sleep/replay/refresh transitions, mouse-button suppression and process exit.
Invalid/palm data or non-increasing/stale timestamps also cancel; the current
stale threshold is 150 ms. Large motion outliers re-anchor without accumulating
the rejected displacement. These are deliberate cancellation/recovery rules,
not ordinary finger-count reclassification.

## Implementation and verification

`TwoFingerPointerTracker` in `Runtime/HIDBlackholeExperiment.swift` stores the
per-device session and contact baselines in fixed inline storage (up to 16
contacts, exceeding supported pad finger capacity). Duplicate IDs or capacity
overflow safely cancel the session; no per-frame array or set is allocated. `TwoFingerPointerMotionEngine` consumes its
millimetre deltas and applies the unchanged accepted acceleration. The existing
selected-and-owned FLTR and Accessibility gates still control live movement.
Replay uses the same pure motion calculations without posting events.

Regression tests cover either survivor, rejoining contacts, all-up termination,
continuous 2→3→4→1 transitions, contact-order changes, independent pads, stale frames, identity replacement,
explicit reset and continuation through the accelerated engine. Hardware
acceptance: start with two, move continuously while adding a third and fourth,
remove fingers down to one, then lift all and verify a single new finger stays idle.

No new click, drag, scrolling, keyboard or other gesture output is introduced.

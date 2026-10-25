# Gesture engine consistency audit

Source review: 2026-10-25. Scope: current macOS recognition, arbitration and output
lifecycle, using [firmware findings](../FINDINGS.md) and the
[implementation plan](../FINGERWORKS_IMPLEMENTATION_PLAN.md).

## Assessment

The engine has a shared session model rather than a separate hardcoded engine for
each gesture. Recognition/evidence, ownership and configured output are distinct.
The reviewed structure supports adding gestures incrementally without replacing
accepted pointer/drag/scroll behavior.

| Responsibility | Shared implementation |
| --- | --- |
| Continuous ownership through count changes | `GestureSessionEngine` |
| Matched-ID motion and continuity | `GestureContactMotionTracker` |
| Count-specific registration and shape competition | `TrackpadGestureRouter` |
| 2/3/4-contact tap timing | `TwoFingerTapRecognizer`; three-contact classification adds geometry/anatomy |
| 2/3/4-finger direction/turn and timed repeat | `GestureDirectionalStepper`, `GestureDirectionalRepeater` |
| Stationary Hold, including Thumb+2 | `GestureHoldRecognizer` |
| Global button ownership versus per-pad sessions | `PrimaryDragOutput` |
| Keyboard reservation through final release | `GestureKeyboardArbitration` |
| Discrete action expansion | Shared live dispatcher and `GestureTapActionOutput` |
| Exclusive-owner final candidate cleanup | `State.consumeAllUp` |
| Output completion and timer freshness | `GestureOutputLifecycle` |

Both and single-pad corners have separate evidence state machines because a Both
chord combines asynchronous host-timed samples while single-pad corners validate
an atomic frame. Their geometry, settling, timing and ownership contracts agree.
They do not each own separate mouse-event implementations.

## Intentional rules

- A recognized movement continues through changed finger counts until all-up;
  membership changes rebase motion rather than creating centroid jumps.
- Tap completes on all-up. Hold fires once while down. These are deliberately
  different triggers sharing the same no-double-action ownership principle.
- Force is an explicit pressure override of same-pad continuous movement.
- Both can take over independent sessions and releases their outputs on acquisition.
- Established keyboard MO/modifier chords have same-pad priority.
- Independent hands can move a shared cursor while another pad owns its button.
- Candidate rejection keeps keyboard reservation; it must never become typing.
- An unusable pinch geometry sample can cancel magnification output while keeping
  recognition reserved until release. It does not hand the cycle to a mouse or key.

These differences are explicit contracts, not unexplained per-gesture exceptions.

## Corrections made by this audit

1. **Oversized finite motion:** the contact tracker now marks a ≥25 app-mm axis
   jump as a continuity failure before reporting a continued frame. The shared
   session cancels its owner rather than silently retaining it on a rejected sample.
2. **Scroll cancellation:** only an `.ended` all-up frame can use normal scroll
   completion/coasting. A `.cancelled` terminal frame emits cancellation instead.
   Idle empty frames do not brake a coast already released normally. Momentum's
   own freshness checks remain an additional guard.
3. **Stale active scrolling:** ordinary precise-scroll output now uses the shared
   200 ms receipt watchdog alongside active zoom, drag and directions. Lost callbacks
   cancel the active phase rather than waiting indefinitely for another frame.
4. **Repeated terminal cleanup:** Both, corners, keyboard chords, Hold, directions,
   system gestures and zoom now call one all-up cleanup path for Hold/Force/Tap
   candidates. A new tap family needs to be registered there once.
5. **Retired corner Tap:** the single-pad corner recognizer no longer retains a
   dormant tap branch. Early lift ends the reservation without a Tap action.

No activation thresholds, acceleration curves, action defaults, ownership priority
or hardware security settings were changed by these corrections.

## Verification and remaining work

Offline regression checks cover oversized finite jumps on both axes/signs, explicit
normal-release versus cancellation policy, stale output/freshness, per-pad scroll
phase independence, existing latch/handoff cases, retired settings and rendered GUI
examples. The full project wrapper also runs fake-device native takeover checks.
No hardware was activated during this audit.

The main remaining design debt is `InterpretedTrackpadPointer.State` combining live
arbitration with native effects. Pure recognizers and output builders have strong
unit coverage, but complete timer/Force/Hold/Both effect sequences are harder to
exercise without a live adapter. An incremental effect-sink/pure-coordinator seam
would make those integration tests easier. This is a bounded future extraction,
not a prerequisite for another gesture and not a reason for a large rewrite now.

Apple physical-unit calibration, proprietary firmware arrangement scoring and
application event receipt remain separate empirical questions. Preserve hardware
acceptance tests for BT/USB, release/restoration and cross-pad interactions.

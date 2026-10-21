# Gesture engine rules

**Central behavior specification for GesturePad. Updated 2026-10-20.**

Start here when designing, implementing or tuning gestures. This document
records the current agreed behavior and implemented thresholds. Feature-specific
notes hold equations, investigation history and detailed implementation context;
older experimental descriptions do not override these rules. When behavior
changes, update this document, the implementation and relevant regression tests
together. Report a source/specification mismatch rather than silently treating
one as approval to change the other.

## 1. Gesture inventory

| Gesture | Activation | Continuation | Normal completion | Output |
| --- | --- | --- | --- | --- |
| Two-finger mouse | Exactly two active fingers and initial net movement of at least 0.35 mm | Any positive active finger count | All fingers up | Relative pointer movement |
| Four-finger scroll | Exactly four active fingers and initial net movement of at least 0.2 mm | Any positive active finger count | All fingers up; eligible release can start momentum | Horizontal/vertical precise scrolling |
| Two-finger tap | A short stationary pair satisfying the tap limits | Only the original two IDs, with bounded landing/lift skew | Both fingers up within the limits | One primary click |
| Scroll momentum | Fresh, sufficiently fast release of an active scroll | Decelerates without fingers | Stop speed or duration reached | Momentum scroll events |

One finger cannot start mouse or scroll. Three fingers do not currently start
a gesture. Extra fingers do not switch an established gesture. Tap recognition
is discrete; it does not hold a mouse button or inherit continuous count latching.

**Acceptance:** the user confirmed mouse acceleration, count latching, scroll
and momentum feel on hardware. Tap was tested, improved after capture-backed
arbitration tuning, and the user reports it feels substantially better. Keep the
current tuning; do not claim all click delivery, lifecycle or application-specific
edge cases have passed. The acceptance/evidence table below records that boundary.

## 2. Input and output eligibility

Every output feature requires all of the following:

1. Trackpad Takeover is enabled.
2. The feature's checkbox is enabled.
3. The source pad is currently selected **and** actually owned through native FLTR.
4. A successful transition has armed output; failed transitions leave it paused.
5. Accessibility permission is granted.
6. Input is from the live ingestion path. Replay never posts output.

Mouse additionally requires its readable pointer profile; scroll requires its
readable scroll profile. Tap clicking is independent of acceleration profiles
and can work with mouse/scroll disabled. Missing profiles pause the affected
feature rather than silently using another response.

Identify pads by their physical native numeric ID, not the bridge's reusable
left/right `deviceIndex`. Match fingers by contact ID, not array order. Duplicate
left/right selections do not create duplicate ownership/output. Sessions and
momentum are independent per pad; a left-pad latch cannot enable the right pad.
The supported-device/preflight and rollback contract is in
[TRACKPAD_TAKEOVER.md](TRACKPAD_TAKEOVER.md).

An active contact means `making` or `touching`. Hover-only, starting, breaking,
lingering and leaving states are not active for recognition. Classified palm
telemetry (`fingerID == 6`), invalid coordinates/timestamps, duplicate active IDs
or more than 16 active contacts invalidate motion input. Sixteen is the current
fixed storage capacity, not a gesture chord requirement.

## 3. Shared arbitration and latching

### Recognition ownership

Activation and continuation are separate decisions. Do not classify a recognized
gesture again on every frame solely from its finger count.

Before recognition, accumulate the vector of common-contact motion. At 0.35 mm
of net displacement, exactly two fingers can claim mouse; at 0.2 mm, exactly
four can claim scroll, provided that feature is enabled. Changing the pending finger count
resets accumulated displacement while the chord finishes landing. This is a
movement threshold, not a fixed waiting period. Unsupported/disabled chords do
not gain ownership.

Once claimed, a continuous gesture owns that pad until all-up or explicit
cancellation. Counts of one, two, three, four or more continue the same mode.
Mouse plus a fourth finger stays mouse; scroll reduced to one stays scroll.
Lift all before deliberately choosing a different continuous gesture.

A recognized mouse/scroll gesture rejects tap-to-click for that entire touch
cycle. Stopping movement and lifting after mousing must never produce a click.
Before continuous recognition, a tap candidate may be tracked in parallel.

### Smooth membership changes

For each consecutive pair of valid frames:

1. Match active contact IDs present in both frames.
2. Compute each continuing finger's displacement.
3. Average those displacements to produce motion.
4. Establish baselines for new fingers; exclude departed fingers immediately.

With stable membership this equals centroid displacement. Adding a distant
finger must not turn its landing position into movement, and removing a finger
must not jump to a new centroid. Membership changes do not insert a motion pause.
No shared IDs ends the old session, covering a missed all-up frame; valid input
must establish a fresh baseline and chord before recognizing again.

### Completion versus cancellation

All-up is normal continuous-gesture completion. Scroll may then start a separate
momentum coast; momentum does **not** keep recognition ownership alive.

Release, feature/settings changes, device-selection transitions, capture teardown,
sleep, replay, refresh and invalid/stale input can cancel or reset recognition.
A future valid chord can begin again after cancellation. A rejected tap has a
stricter rule: it stays blocked until all-up.

## 4. Mouse rules

- Use matched-contact motion with the accepted Apple-source parametric pointer
  response. After the initial 0.35 mm recognition threshold, retain fine motion
  without requiring that threshold again each frame.
- One survivor moves from its own displacement. Added fingers participate after
  their baseline is established; count changes never become scroll or tap.
- Convert normalized contact motion using the current 160 × 114.9 mm surface
  assumption. X follows contact X; Y is inverted into Quartz coordinates.
- Sensitivity scales the provisional `resolution / 25.4` counts-per-mm conversion
  **before** acceleration; it is not just a final output multiplier.
- Post tagged relative mouse-moved events and clamp the destination to the nearest
  active display, including displays with negative coordinate origins.
- No synthesized held button, dragging or pinch output is part of mouse mode.
- Fixed 6 pt/mm remains an offline diagnostic comparison, not a production picker.

Equations and provenance: [POINTER_ACCELERATION.md](POINTER_ACCELERATION.md).
Implementation/acceptance detail: [TWO_FINGER_MOUSE.md](TWO_FINGER_MOUSE.md).

## 5. Scroll rules

- Start with the moving four-finger chord; continue with any positive count.
- Apply the pad's **scroll** curves and per-axis history. Do not substitute pointer
  acceleration or the pointer's fixed multiplier/magnitude flooring.
- Both horizontal and vertical deltas are supported, including diagonal movement.
  Axis locking and bounce are not implemented.
- Use the current surface-size and counts-per-mm assumptions, with separate
  scroll sensitivity applied before acceleration.
- Honor the global natural-scrolling preference when loading the profile. Reload
  settings through feature enable/selection updates; changing macOS settings is
  not a write performed by GesturePad.
- Send continuous pixel scroll events with physical began/changed/ended/cancelled
  phases. Retain fractional fixed-point deltas and carry fractional pixel remainder
  between frames; small movements must accumulate into single-pixel steps.
- On normal lift, finish the physical scroll and evaluate momentum. Interrupted
  scrolls cancel their phase and do not launch momentum.

Full scroll equations and source references:
[FOUR_FINGER_SCROLL.md](FOUR_FINGER_SCROLL.md).

## 6. Momentum rules

Momentum is part of the four-finger scroll feature by default, not a separate
recognition chord or checkbox.

Estimate release velocity from recent **accelerated pixel output**, independently
per pad. Zero-motion samples contribute elapsed time, so holding still before
lifting suppresses stale momentum. Direction reversal clears the older estimate.
Require an observed normal release; stale/missing release notifications cannot
launch a coast.

Integrate an exponential coast analytically:

```text
delta = releaseVelocity × tau × (exp(-t0/tau) - exp(-t1/tau))
```

Do not accelerate those already accelerated pixels a second time. Analytic
integration preserves travel across different timer rates. A stalled or invalid
timer ends the coast without a catch-up jump.

Send physical ended followed by momentum begin/continue/end, with ordinary
scroll phase none during momentum. Preserve the fractional remainder and original
scroll location. Momentum events do not move the cursor. Repeated all-up frames
must neither restart nor cancel an existing coast.

A new active touch on the **same pad** stops its momentum before recognition
continues. That braking touch cycle cannot also tap-click. Other pads retain
independent sessions/coasts. Left, right or center mouse-button activity cancels
coasts globally; release, disable, selection/lifecycle resets or loss of output
eligibility also cancel them and close their event phase. The contact watchdog
must not confuse a valid coast with stalled contact delivery.

The decay parameters below are current app tuning, not a recovered Apple momentum
algorithm. Hardware-accepted feel does not establish exact native equivalence.

## 7. Two-finger tap rules

- Track only the original pair. Allow either finger to land or lift first within
  the limits below; click once, only when the final active contact lifts.
- Reject a single-finger tap, extra fingers, replacement IDs, rejoining after lift
  begins, a long hold, excessive individual displacement, invalid/palm data or
  stale/nonmonotonic input.
- Check each finger's displacement even if opposing motion keeps the centroid
  stationary. The movement router takes priority: its 0.35 mm mouse recognition can
  reject a tap before the 1 mm individual outer limit is reached.
- Recognized mouse/scroll, physical button suppression, momentum braking or an
  explicit reset blocks the tap until all-up. Do not re-arm as fingers leave.
- Idle watchdog cleanup must not consume the next fresh tap. It invalidates an
  existing candidate rather than inventing a blocked session on an idle pad.
- Create primary down **and** up before posting either. Post both immediately
  at the current cursor under the output lock, with matching synthetic tag,
  modifier flags and click count. No delayed release or held-button state.
- Consecutive taps at nearly the same cursor position and with matching modifiers
  use macOS's double-click interval. Generated click counts progress 1, 2, then
  saturate at 3. Timeout, excess cursor travel, changed modifiers or an explicit
  click-history reset starts at 1. Mixing physical and synthetic click histories
  is not reconstructed.

Feature detail and acceptance steps: [TWO_FINGER_TAP.md](TWO_FINGER_TAP.md).

## 8. Current thresholds and units

These values describe current code, not promises about original FingerWorks or
all macOS devices. Change them here and in source/tests together.

### Shared motion and sensitivity

| Parameter | Current value/rule |
| --- | --- |
| Initial mouse recognition | Net displacement ≥ 0.35 mm |
| Initial scroll recognition | Net displacement ≥ 0.2 mm |
| Continuous contact timestamp interval | Strictly positive and < 150 ms |
| Active contact storage | Up to 16 unique IDs per pad/frame |
| Assumed surface | 160 mm wide × 114.9 mm high |
| Physical displacement guard | Reject a frame at ≥ 25 mm on either axis |
| Accelerated output guard | Reject at ≥ 150 points on either axis |
| Sensitivity, mouse and scroll independently | Default 1.00×; 0.25×–2.00×, UI step 0.01× |
| Input count conversion | Resolution / 25.4 × sensitivity per mm |
| Pointer nominal algorithm rate/cursor scale | 67; 96/67 |
| Scroll rate fallback | 67 Hz; scroll property is decoded as 16.16 |
| Scroll history | Nine-slot ring, eight retained samples per axis |
| Scroll direction/history reset | Direction change or > 500 ms axis interval |
| Scroll history interval clamp | 150 ms cap; 1–150 ms normalized mean |
| Scroll first-sample interval | Deterministic 150 ms |
| Pixel/wheel conversion | 10 pixel points per wheel unit |
| Contact-delivery watchdog | > 200 ms host receipt age, checked by 0.5-second status updates; skip valid coasts |

Rejected physical outliers establish the next baseline rather than accumulating
that displacement. Output guards clear affected acceleration history; scroll
recovery closes its active event sequence. Rejection is not permission to hand
the touch cycle to another gesture. Invalid/stale input cancels recognition;
subsequent valid input must establish a new baseline.

### Tap and click

| Parameter | Current value/rule |
| --- | --- |
| Total tap duration | ≤ 500 ms, first contact to all-up |
| Second finger joins | ≤ 80 ms after first contact |
| Simultaneous pair overlap | ≥ 20 ms |
| Final lift after first lift | ≤ 80 ms |
| Individual displacement from initial position | ≤ 1 mm |
| Tap timestamp interval | Strictly positive and ≤ 150 ms |
| Multi-click interval | `NSEvent.doubleClickInterval` |
| Multi-click cursor tolerance | ≤ 4 points, matching modifier flags |
| Generated click count | 1–3, saturating at 3 |

### Momentum

| Parameter | Current value/rule |
| --- | --- |
| Release-history window | Last 80 ms, up to eight samples |
| Eligible last-sample age at release | < 80 ms |
| First velocity-sample interval | 1/90 second |
| Minimum launch speed | 30 points/second |
| Maximum launch speed | 6000 points/second, vector magnitude |
| Decay time constant (`tau`) | 0.325 second |
| Stop speed | < 5 points/second |
| Maximum coast duration | 2.5 seconds |
| Timer frequency | 120 Hz; 1 ms scheduling leeway |
| Allowed timer interval | Strictly positive and ≤ 80 ms |

## 9. Defaults, release and lifecycle

| Setting/action | Rule |
| --- | --- |
| Trackpad Takeover | Persistent opt-in, default off for new users |
| Mouse, scroll and tap checkboxes | Default on with restored takeover and fresh explicit takeover enable |
| Manual feature-off overrides | Remain for the current process through ordinary selection/sleep/replay restoration |
| Sensitivity | Separate process-local values, default 1.00× each launch |
| Config close/reopen or in-process Restart during takeover | Preserve process/ownership and current settings; do not release solely for the window |
| Quit | Stop output/coasts, release ownership; preserve takeover preference |
| Sleep, replay, refresh | Cancel synthetic state and temporarily release; restore enabled takeover through existing reconciliation |
| Selection change | Pause output, validate/transition ownership, reconcile selected IDs, reset gesture state |
| Failed transition | No synthetic output until successful recovery or an explicit supported re-arm action |
| Uncheck takeover, Release Trackpads menu or Ctrl-Option-R | Stop output/coasts, release pads and persist takeover off |
| Left/right/center mouse button held | Suppress synthetic gestures and cancel pending taps/coasts |

Control changes can cancel all current gesture output state, even when changing
only one feature. Disabling mouse does not disable independently eligible scroll
or tap recognition. No output from unselected pads, stale bridge index slots or
extra ownership retained only for failed cleanup.

## 10. Source map and verification

| Responsibility | Current source/test |
| --- | --- |
| Live-only ingestion | `Runtime/InputRuntimeService.swift` |
| Eligibility, lifecycle, contact motion and serialized posting | `Runtime/HIDBlackholeExperiment.swift` |
| Initial chord arbitration, scroll curves/events, momentum | `Runtime/ScrollGesture.swift` |
| Pointer curve evaluation and motion engine | `Runtime/PointerAcceleration.swift` |
| Tap recognition and complete primary click pairs | `Runtime/TapClick.swift` |
| General recognition extension point | `Engine/TouchProcessorEngine.swift` |
| Mouse/latch/eligibility regression checks | `NativeTwoFingerMouseTests`, `HIDBlackholeIdentityTests`, `ApplePointerAccelerationTests` |
| Scroll/arbitration/fine events | `FourFingerScrollTests` |
| Momentum decay, phases, interruption and rate independence | `ScrollMomentumTests` |
| Tap rejection/completion and click events | `TwoFingerTapTests` |
| Capture-backed tap/mouse arbitration | `TapCaptureAnalysisTests` |
| Takeover preference and source identity | `NativeTakeoverPreferenceTests`, `SelectedDeviceSourceTests`, native lifecycle tests |

Paths above are relative to `GesturePad/GesturePad/` for production Swift and
`Tests/ProductionEngineTests/` for Swift tests. Recognition and numerical tests
can inspect generated events but must never post them. Optional registry checks
are read-only. Do not launch the app or activate hardware as an automated check.

The current output inventory is pointer movement, primary click pairs, precise
scroll and scroll momentum. Right-click, synthesized dragging/held buttons,
pinch/zoom, keyboard output and new gesture families are not implemented by
these rules. They need explicit behavior definitions and authorization.

## Capture-backed tap tuning (2026-10-20)

The move–tap capture exposed tap drift crossing the original 0.2 mm mouse
threshold. Production replay predicts 19 clicks at 0.2 mm and 25 at 0.35 mm,
with zero clicks during 29 clear movement cycles. All six recovered cycles pass
the independent tap rules; the 500 ms tap window was not the limiting rule.
The mouse-only threshold is now 0.35 mm. No fixed recognition delay or change to
latched acceleration is added. The user reported substantially improved feel on the follow-up. Its replay
predicts 22 taps and no clicks in 23 movement cycles; all independent tap
candidates survive arbitration. Retain 0.35 mm. Capture replay does not prove
actual click delivery or user intent. See
[the capture analysis](RewriteValidation/TWO_FINGER_TAP_CAPTURE_ANALYSIS.md).

## Acceptance and evidence checkpoint (2026-10-20)

| Behavior | Evidence retained | Remaining limit |
| --- | --- | --- |
| Pointer acceleration/fine movement | User reports accepted feel on hardware; independent equation vectors and pure motion replay pass. | Contact-to-count conversion is an explicit hypothesis, not recovered proprietary processing. |
| Continuous gesture latch | User tested original FingerWorks and GesturePad: 2→3→4→1 transitions feel smooth and match the intended interaction. | Other chord families need their own activation/handoff policy. |
| Four-finger scroll and momentum | User reports good feel; per-axis equations, fine pixel fields, phases, decay and cancellation have offline checks. | App-specific effects, OS/device differences and lifecycle edges need broader coverage; momentum is app tuning. |
| 500 ms tap window | User reports the longer maximum feels good; boundary tests accept 500 ms and reject longer cycles. | The maximum is not a fixed wait; timing alone did not fix movement arbitration. |
| 0.35 mm mouse/tap separation | First capture: 19→25 predicted clicks; follow-up: 17→22 versus old 0.20 mm. User reports substantially improved feel. | Contacts do not record actual click delivery, suppression state or explicit intent. |
| Tap false-positive control | Follow-up: no predicted clicks in 23 mouse cycles, including eleven final no-click strokes. Every independent tap candidate survives current arbitration. | This sample is not a universal false-click guarantee; retain no-click movement tests. |

Keep the **0.35 mm mouse / 0.20 mm scroll** initiation values. The first capture
had six valid tap candidates stolen by mouse mode; the second would lose five
under the old rule. Higher tested mouse thresholds (0.50, 0.75 and 1.00 mm) add
no accepted taps in either file. The change leaves latched acceleration intact;
in the first recording, median clear-stroke initiation moved from about 22.3 to
33.8 ms. Revisit that tradeoff only with evidence, rather than loosening more
limits on speculation.

Capture interpretation and repeatable tests:
[move–tap analysis](RewriteValidation/TWO_FINGER_TAP_CAPTURE_ANALYSIS.md),
`TapCaptureAnalysisTests` (local recordings optional). Current capture names are
`2finger_tap.atpcap` and `2finger_tap_test2.atpcap`.

The cross-project status, preserved firmware/SDK lessons and future typing work
live in [FINGERWORKS_IMPLEMENTATION_PLAN.md](../FINGERWORKS_IMPLEMENTATION_PLAN.md).
This engine is currently implemented in GesturePad only. Existing native takeover
in the keyboard apps does not imply these gesture rules have been ported there.

## 11. Template for the next gesture

Before implementation, add an entry here with:

| Field | Required definition |
| --- | --- |
| Name/status | Proposed, implemented/testable or hardware-accepted |
| Activation | Exact chord, motion/pressure/direction and timing requirements |
| Continuation | Permitted finger additions/removals, identity changes and latching |
| Arbitration | Priority against pending/owned gestures; any deliberate handoff |
| Completion | All-up, discrete trigger or another explicitly defined boundary |
| Cancellation | Invalid input, button activity, permissions, device/lifecycle changes |
| Output | Event type, timing, held state, repeat behavior and paired cleanup |
| Tuning/defaults | Values with units; checkbox defaults and persistence |
| Isolation | Pad identity, cross-pad interaction and live/replay boundaries |
| Verification | Positive cases, rejection cases, transition regressions and hardware test |

Never infer a new gesture from an extra finger in an already owned session
without an explicit handoff rule. Keep future plans visibly distinct from
implemented behavior. Preserve hardware-accepted feel unless a reviewed change
specifically modifies it.

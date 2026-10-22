# Gesture engine rules

**Central behavior specification for GesturePad. Updated 2026-10-21.**

The reverse-engineering source of truth for implementing FingerWorks gestures is
[mac/FINDINGS.md](../FINDINGS.md). It distinguishes original definitions, recovered
firmware flow, bounded validation and unresolved fidelity questions. This document
specifies current app behavior; a research difference must become an explicit
implementation decision rather than an automatic threshold or policy change.

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
| Three-finger drag/select | Exactly three close, aligned non-thumb contacts and ≥ 0.35 mm motion | Any positive count after activation | All fingers up | Primary down, accelerated primary drag, primary up |
| Four-finger scroll | Exactly four active fingers and initial net movement of at least 0.2 mm | Any positive active finger count | All fingers up; eligible release can start momentum | Horizontal/vertical precise scrolling |
| Two-finger tap | A short stationary pair satisfying the tap limits | Only the original two IDs, with bounded landing/lift skew | Both fingers up within the limits | One primary click |
| Three-finger tap | A short stationary three-contact chord without an identified thumb, satisfying the tap limits | Only the original three IDs, bounded landing/lift skew | All three up within the limits | One primary double-click (two balanced click pairs) |
| Thumb–middle–ring right-click | Short stationary tap with positively identified Thumb=1, Middle=3, Ring=4 | Original tracking IDs and bounded tap timing; no contradictory known identities | All fingers up within tap limits | One balanced secondary down/up pair |
| Scroll momentum | Fresh, sufficiently fast release of an active scroll | Decelerates without fingers | Stop speed or duration reached | Momentum scroll events |

One finger cannot start continuous motion. Three fingers can start a stationary double-click/right-click tap according to identity, or a moving drag chord. Extra fingers do not switch an established gesture. Tap recognition
is discrete; it does not hold a mouse button or inherit continuous count latching.

**Acceptance:** the user confirmed mouse acceleration, count latching, scroll
and momentum feel on hardware, and now confirms corrected three-finger drag/select
works great. Three-finger double-click still awaits explicit hardware acceptance. Two-finger tap was tested, improved after capture-backed
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

Mouse and drag additionally require their readable pointer profile; scroll requires its
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
four can claim scroll; three close, aligned non-thumb contacts can claim drag at
0.35 mm, provided that feature is enabled. Changing the pending finger count
resets accumulated displacement while the chord finishes landing. This is a
movement threshold, not a fixed waiting period. Unsupported/disabled chords do
not gain ownership.

Once claimed, a continuous gesture owns that pad until all-up or explicit
cancellation. Counts of one, two, three, four or more continue the same mode.
Mouse plus a fourth finger stays mouse; scroll reduced to one stays scroll.
Lift all before deliberately choosing a different continuous gesture.

A recognized mouse/scroll/drag gesture rejects tap-to-click for that entire touch
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

### Shared implementation boundary

Latching is an engine responsibility, not a mouse/scroll implementation detail.
`Engine/GestureSessionEngine.swift` now contains:

- `GestureContactMotionTracker`: shared contact-ID continuity, input validation,
  matched-contact motion, baseline/outlier handling and normal all-up detection.
- `GestureActivationRule<Gesture>`: gesture identity, initial chord count, movement
  threshold and a separate continuation policy (`untilAllUp` by default, or an
  explicitly bounded count range). Rule order defines priority when candidates tie.
- `GestureSessionEngine<Gesture>`: one owner per pad; pending displacement and
  begin/change/end/cancel lifecycle. Existing owners take priority over candidates.
- `GestureSessionUpdate`: recognized identity, lifecycle phase, optional movement
  and explicit cancellation reason. Completion is distinct from invalid/stale
  input, disable, continuation rejection and explicit reset.

A synchronous `activationFilter` receives gesture identity and a context with
time, count, current motion and accumulated pending motion. Future recognizers
can supply additional evidence here without adding branches to the ownership
engine. Once an owner commits, the activation filter is no longer consulted for
continuation. Dwell scheduling, angle/pressure extraction or a new output family
still requires its own reviewed recognizer implementation; the generic boundary
does not claim those gestures already exist.

`TrackpadGestureRouter` is now the registration/adapter for the current mouse,
scroll and drag rules. It delegates ownership to the shared engine and forwards motion
to the existing acceleration/output code. It no longer stores its own gesture
latch. `TwoFingerPointerTracker` remains a diagnostic/compatibility adapter over
shared contact motion; it does not own the live mouse/scroll decision.

Tap recognizers remain discrete candidates, cancelled when continuous ownership
commits, rather than pretending to hold a continuous latch. Momentum remains an
output coast after recognition completes. Output event posting, phase cleanup,
timers, eligibility and acceleration are outside the generic engine. Broad reset
callers must clean up owned outputs as well as clearing recognition state; the
existing live adapter already does so before reset.

All mutation stays under the current serial output lock. Rules/candidate storage
are configured outside raw callbacks; common contact matching uses fixed inline
storage. No event posting, I/O, registry reads or timers live in the shared engine.
The refactor preserves current initiation thresholds, latch behavior, tap limits,
acceleration, scroll phases and momentum. Both recorded tap regressions retain
the same predictions. `GestureSessionEngineTests` exercises arbitrary test-only
gesture identities, priority, activation filtering, continuation, independent
pads and explicit lifecycle/cancellation paths, without adding live gestures.

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
- Recognized mouse/scroll/drag, physical button suppression, momentum braking or an
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

### Three-finger tap to double-click

A stationary three-finger tap without a classified thumb completes on all-up and sends exactly two primary
click pairs, with counts 1 then 2. All four events are created before posting;
each is tagged, uses the same cursor/modifiers, and posts immediately under the
output lock. No delayed mouse-up or held-button/drag state is introduced. The
explicit sequence starts fresh, independent of previous single clicks, then
resets the normal tap multi-click history so the next two-finger tap starts at 1.

The three-finger recognizer uses the same timing/slop limits as two-finger tap:
500 ms total, all three joining within 80 ms of the first contact, at least 20 ms
full-chord overlap, and all-up within 80 ms of the first partial lift. Each finger
must stay within 1 mm of its landing position. Fourth fingers, ID replacement,
rejoining after partial lift, motion ownership, braking and explicit cancellation
reject the cycle until all-up.

Two-finger tap rejects the entire cycle as soon as a third active finger arrives;
it cannot fire when that three-finger chord reduces to two or one. Three-finger
tap cannot fire from a two-finger-only cycle. Moving two fingers before the third
arrives still claims mouse under the existing rule and cancels all tap candidates.
An established mouse/scroll latch never converts into a double-click by count.

The **3-finger tap to double-click** checkbox defaults on with takeover, including
startup restoration and fresh explicit enable. Its permission, selected-and-owned,
transition/lifecycle and manual-override behavior matches the existing tap control.
Tap-only double-click works independently of mouse/scroll profiles. It is a
GesturePad-only addition and awaits hardware acceptance.

### Thumb–middle–ring tap to right-click (historical; superseded below)

The user requested the FingerWorks TouchStream chord: **thumb + middle + ring**.
`ThreeFingerTapRecognizer` arbitrates three-contact taps before any click output.
Its timing/motion validation delegates to the same count-based recognizer as
other taps: 500 ms total, 80 ms landing and final-lift skew, 20 ms full-chord
overlap, 1 mm individual slop and ≤150 ms frame gaps. It completes immediately
on final lift, never waits a fixed half-second, and posts one secondary click.
There is no held right button, repeat or right-drag output.

At least one full three-contact frame must positively identify exactly one each
of native telemetry `fingerID` 1 (Thumb), 3 (Middle), and 4 (Ring). These values
come from the existing OMS anatomical labels, not contact tracking IDs, array
order, pad side or geometry. Conflicting nonzero `handID` values reject the cycle;
unknown hand does not invent a hand assignment. After matching, bind anatomical
slots to tracking IDs. Temporary Unknown labels are tolerated on those same
contacts, but contradictory known labels/hand assignments reject until all-up.
Classification can settle before matching; a positive match is always required.

Seeing a classified thumb reserves that tap cycle from generic primary
three-finger double-click, even if right-click is disabled or the chord fails.
This prevents an invalid right-click attempt falling through to primary output.
Other/unknown three-contact taps retain generic double-click compatibility when
that feature is enabled; wholly unknown identities cannot produce right-click.
Two-finger tap rejects upon the third contact. Continuous mouse/scroll/drag
ownership, physical-button suppression, momentum braking and lifecycle cleanup
cancel the entire tap cycle. Established latches never reclassify as right-click.
Drag activation already rejects classified thumbs; this chord adds no movement
threshold, geometry substitute or change to pointer/scroll acceleration.

The **Thumb + middle + ring: right-click** checkbox defaults on with restored or
freshly enabled takeover and follows the same per-process manual-off policy.
It is independent of pointer/scroll profiles and the double-click checkbox.
Only live, selected-and-owned, armed, Accessibility-approved input may post.
Prepare both tagged rightMouseDown/rightMouseUp events before posting either,
with the same cursor/modifiers, right button number 1, click count 1 and balanced
pressure. Reset primary multi-click history when dispatching either three-finger
action. Existing output lock/lifecycle resets cover the identity candidate too.
Native anatomical classification quality and context-menu behavior need hardware
acceptance; this implements the user's specified chord, not recovered proprietary
FingerWorks timing/classification logic.

### Three-finger drag/select

The **3-finger drag/select** checkbox defaults on alongside takeover. Starting
with three nearby fingers in a roughly straight row, move ≥ 0.35 mm to hold the
primary button and move using the accepted pointer acceleration and mouse
sensitivity. This supports dragging items and selecting text; all-up releases
immediately. There is no drag lock, all-up reposition grace or momentum for drag.
This is the requested Apple-style interaction, not a claim to reproduce Apple's
undocumented recognition thresholds.

Activation evidence is `ThreeFingerDragChord`, supplied through the shared
engine's activation filter. Coordinates use the common 160 × 114.9 mm scale:
all pair distances must be 2–60 mm; the middle point must be within 8 mm of the
line through the farthest pair and within 35 mm of each endpoint. The geometry
is rotation-independent, allowing natural hand angles. Classified thumb
(`fingerID == 1`) or palm rejects drag, even when the points happen to align.
Unknown/missing finger classification uses geometry only; it cannot prove which
anatomical fingers are down. The user reports the corrected drag/select works great with these ergonomic bounds.
Thumb–middle–ring right-click uses the separate anatomical tap rule and
arbitration described above. Contact tracking IDs and anatomical finger classifications are distinct.

Evidence is checked at activation only. Once latched, drag continues smoothly
through 3→2→1 or added fingers, using matched-ID motion. An established mouse or
scroll session cannot turn into dragging when a third finger arrives. Recognized
drag cancels pending tap candidates; a stationary three-finger tap still
double-clicks. Starting with two fingers and moving before the third lands can
still claim mouse first.

Only one pad can own the global primary button. While it is held, other pads'
synthetic gestures are suppressed and their pending taps cancelled. Starting a
drag closes scroll/coast output. `PrimaryDragOutput` creates both down and a
reserved up before posting down; drag events carry click count 1, modifiers,
pressure, delta and the interpreter tag. Its private Quartz event source owns the button pair. While drag owns the
primary button, **do not poll global/HID button tables to decide interference**:
that does not reliably distinguish the down we posted ourselves. A live,
listen-only button-down observer ignores interpreter-tagged edges and cancels
on outside left/right/other button presses, without filtering those events.
Failure to create the observer pauses drag only; observer disable cancels held
output and requires a takeover toggle to retry. Outside drag, the ordinary
combined-state physical-button suppression remains. The observer is installed
only by live enable and torn down with drag eligibility or output stop.

Drag movement uses the same pointer acceleration as two-finger mouse. Its next
destination accumulates from the last queued drag destination, avoiding an older
WindowServer cursor read while posted movement is still in flight. The first
down anchors at the current cursor. This does not warp/correct the cursor or
change the accepted curve, sensitivity, common-ID motion or latch.
Normal completion, stale/invalid input, permission/eligibility loss, disable,
selection changes, reset, sleep, replay, release and quit all return the reserved
up before clearing output state. A 120 Hz watchdog releases a drag after 200 ms
without a live frame. Release uses a fresh timestamp; normal completion preserves the last queued
drag destination, while lifecycle/interference cleanup reads the current cursor.
Output allocation failures also cancel; cleanup is idempotent. Tests inspect
unposted events. The user confirms corrected drag/select works great; broader
application and lifecycle coverage remains.

## 8. Current thresholds and units

These values describe current code, not promises about original FingerWorks or
all macOS devices. Change them here and in source/tests together.

### Shared motion and sensitivity

| Parameter | Current value/rule |
| --- | --- |
| Initial mouse recognition | Net displacement ≥ 0.35 mm |
| Initial drag recognition | Net displacement ≥ 0.35 mm plus close/aligned non-thumb chord |
| Drag watchdog | Release after > 200 ms without a live frame |
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
| Total tap duration, either chord | ≤ 500 ms, first contact to all-up |
| All required fingers join (two or three) | ≤ 80 ms after first contact |
| Simultaneous full-chord overlap | ≥ 20 ms |
| Final lift after first lift | ≤ 80 ms |
| Individual displacement from initial position | ≤ 1 mm |
| Tap timestamp interval | Strictly positive and ≤ 150 ms |
| Multi-click interval | `NSEvent.doubleClickInterval` |
| Multi-click cursor tolerance | ≤ 4 points, matching modifier flags |
| Repeated two-finger tap click count | 1–3, saturating at 3 |
| Identified right-click | Exact anatomical set {1,3,4}; shared tap limits; classified-thumb cycle reserved from primary double-click |
| Dedicated three-finger tap double-click | Two down/up pairs, counts 1 then 2; reset ordinary click history |

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
| Mouse, drag, scroll and all tap checkboxes | Default on with restored takeover and fresh explicit takeover enable |
| Manual feature-off overrides | Remain for the current process through ordinary selection/sleep/replay restoration |
| Sensitivity | Separate process-local values, default 1.00× each launch |
| Config close/reopen or in-process Restart during takeover | Preserve process/ownership and current settings; do not release solely for the window |
| Quit | Stop output/coasts/held drag, release ownership; preserve takeover preference |
| Sleep, replay, refresh | Cancel synthetic state and temporarily release; restore enabled takeover through existing reconciliation |
| Selection change | Pause output, validate/transition ownership, reconcile selected IDs, reset gesture state |
| Failed transition | No synthetic output until successful recovery or an explicit supported re-arm action |
| Uncheck takeover, Release Trackpads menu or Ctrl-Option-R | Stop output/coasts/held drag, release pads and persist takeover off |
| Physical left/right/center button held | Suppress synthetic gestures and cancel pending taps/coasts/drags; own private-source drag down is excluded |

Control changes can cancel all current gesture output state, even when changing
only one feature. Disabling mouse does not disable independently eligible scroll
or tap recognition. Each tap checkbox is independent; disabling two-finger click
does not disable three-finger double-click or identified right-click. No output from unselected pads, stale bridge index slots or
extra ownership retained only for failed cleanup.

## 10. Source map and verification

| Responsibility | Current source/test |
| --- | --- |
| Live-only ingestion | `Runtime/InputRuntimeService.swift` |
| Eligibility, output lifecycle and serialized posting | `Runtime/HIDBlackholeExperiment.swift` |
| Shared contact continuity, generic ownership/lifecycle and activation/continuation rules | `Engine/GestureSessionEngine.swift` |
| Mouse/scroll/drag rule registration adapter, scroll curves/events, momentum | `Runtime/ScrollGesture.swift` |
| Pointer curve evaluation and motion engine | `Runtime/PointerAcceleration.swift` |
| Two/three-finger tap and anatomical action arbitration, drag chord evidence, primary/secondary click pairs and held primary output | `Runtime/TapClick.swift` |
| Additional recognition extension point | `Engine/TouchProcessorEngine.swift` |
| Shared ownership, priority, lifecycle and recognizer activation-filter tests | `GestureSessionEngineTests` |
| Mouse/latch/eligibility regression checks | `NativeTwoFingerMouseTests`, `HIDBlackholeIdentityTests`, `ApplePointerAccelerationTests` |
| Scroll/arbitration/fine events | `FourFingerScrollTests` |
| Momentum decay, phases, interruption and rate independence | `ScrollMomentumTests` |
| Drag shape/identity, shared latch, tap arbitration, cancellation and reserved release | `ThreeFingerDragTests` |
| Anatomical right-click specificity, identity binding, lifecycle and balanced secondary events | `IdentifiedRightClickTests` |
| Tap rejection/completion and click events | `TwoFingerTapTests`, `ThreeFingerTapTests` |
| Capture-backed tap/mouse arbitration | `TapCaptureAnalysisTests` |
| Takeover preference and source identity | `NativeTakeoverPreferenceTests`, `SelectedDeviceSourceTests`, native lifecycle tests |

Paths above are relative to `GesturePad/GesturePad/` for production Swift and
`Tests/ProductionEngineTests/` for Swift tests. Recognition and numerical tests
can inspect generated events but must never post them. Optional registry checks
are read-only. Do not launch the app or activate hardware as an automated check.

The current output inventory is pointer movement, primary and secondary click pairs,
held primary dragging, precise scroll and scroll momentum.
Pinch/zoom, keyboard output and new gesture families are not implemented by
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
| Identified thumb–middle–ring right-click | Offline exact/incorrect/unknown/mixed-hand identities, specificity, shared tap timing/cancellation and balanced secondary events. | User tested it and reports missed triggers; suspects Thumb+Middle+Ring is often labelled Thumb+Ring+Pinky. Identity colors added for diagnosis; exact chord remains unchanged. |
| Three-finger drag/select | Offline aligned/rotated vs splayed/thumb chords, latching, stationary-tap separation, cancellation and balanced output tests. | User reported jitter/repeated selection in the first build. Own-button polling was removed in favor of tagged observation and queued destinations; User confirms the corrected drag/select works great on hardware; broader app/lifecycle coverage remains. |
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


## Drag hold correction (2026-10-21)

The first hardware run held the latch but repeatedly selected/jittered instead
of maintaining a smooth drag. Source review found a fragile self-cancellation
path: the live callback and watchdog polled HID button state after posting our
synthetic down, then reset/released output on a true result. It also anchored each
drag destination from an asynchronously updated system cursor. These are plausible
causes, not a captured trace proving which path fired on that run.

Both poll sites now bypass global button state during primary ownership. A
listen-only event tap handles outside button-down interruption by event tag;
our own down/drag/up cannot interrupt it. The reserved up and all lifecycle,
stale-frame, eligibility and allocation-failure safeguards remain. Destinations
accumulate from the last queued drag position. Regression tests cover one down,
continuous dragged events, one up through 60 frames/count changes while simulating
a globally held button; tagged/outside interference; and matching Apple-accelerated
deltas between two- and three-finger motion. Tests create events without posting
or installing an observer. The user subsequently confirmed corrected drag/select works great on hardware.

Apple documents global source-state tables as accumulated event state, not
individual physical input provenance:
[CGEventSourceStateID](https://developer.apple.com/documentation/coregraphics/cgeventsourcestateid).


## Anatomical color diagnostics (2026-10-21)

The user confirmed corrected three-finger drag/select works great. Right-click
misses are being investigated: their hypothesis is that intended Thumb+Middle+Ring
is sometimes classified Thumb+Ring+Pinky. Do not broaden the accepted chord yet.

Contact fills, telemetry direction arrows and contact trails use a fixed sRGB
palette keyed by anatomical `telemetry.fingerID`, not transient tracking ID:
Unknown/missing/unrecognized = black, Thumb = orange, Index = blue, Middle = green,
Ring = purple, Pinky = pink, Palm = gray. Both pads, new contact IDs and replay
share the mapping. Contact colors update immediately with classification (no
color latch); each trail uses its most recent classification. A labeled legend
is visible even with detailed telemetry off, and black contacts have a light
outline for dark backgrounds. Finger-name/F labels remain available through
Inspect touch data. Rendering changes do not affect recognition, tap limits,
right-click identity requirements, arbitration or output.

## FingerWorks right-click research checkpoint (2026-10-21)

**Documentation only; preserve the current exact chord and classifier.** The
quick guide page1 explicitly recommends thumb+middle+ring. However, research of
the shipped1.60 defaults shows that this is not sufficient evidence for an
exact-only anatomical recognition rule.

| Original evidence | Recovered meaning | Comparison with current implementation |
| --- | --- | --- |
| Right-hand `FW_stealth_chords.xml`: `finger_combo="T2F"`, `Search & Right Click/Drag`, `T2F Spread` | Thumb plus two fingertips, with arrangement selection | Current native-label set{1,3,4} is stricter than the recovered general selection path. |
| `FW_parameter_macros.xml`: T2F Spread has `best_fingers="STRP"` | Spread + thumb + ring + pinky is its preferred anatomical pattern; utility maps S/T/R/P explicitly | The user's suspected TRP classification is not inherently wrong for the original spread arrangement. Do not change accepted identities automatically. |
| Utility T2F parser retains any-permutation bit0x100000, even when preferred bits are added | Preferred fingers are not an exact-only acceptance requirement | Do not interpret `best_fingers` as either a hard whitelist or proof that every three-contact geometry qualifies. |
| Firmware8021AA exact lookup then thumb/nonthumb-count fallback;8021E1/C0395D arrangement scoring | Anatomical configuration, eligibility and geometry cooperate; competing compact/spread/TIP definitions can differ | Adding TRP to a whitelist alone would not reproduce the original selection/arbitration. |
| SyncTap→Secondary Click Event→Button2 click, configured duration30 | Quick tap is a discrete secondary-click action | Duration30 is action configuration, not a recovered contact timing threshold. Current app timing remains app policy. |
| Same template also has Timedown secondary press, XY secondary drag and LiftSlide release | Original right-click belongs to a larger tap/hold/motion family | Current implementation remains discrete tap only; no right-drag or held secondary output is added. |

The original compact T2F middle-click template is category-dependent
(`three_buttons emacs_op`); spread T2F right-click and TIP Spread/XWinder are
distinct candidates. The quick guide's later page also distinguishes spread
right-click/drag in three-button/Linux contexts. This evidence does not prove
the exact configuration on any particular physical TouchStream, nor execute the
full FP arrangement scorer. Apple's finger estimates are not interchangeable
with firmware anatomical slots.

The firmware also revises anatomical assignment contextually. Our stricter rule
that a known contradictory label rejects a matched tap is an explicit current
policy, not a recovered universal FingerWorks invariant. Retain it pending a
separately reviewed change.

For a useful capture, record intended TMR and TRP separately. Report whether a
full three-contact frame ever matched{1,3,4}, whether later known relabeling
invalidated it, and whether motion/timing/another owner cancelled it. Keep these
reasons distinct from actual event delivery. The current colors are appropriate
for diagnosing classification; they should continue updating with telemetry.

Detailed sources, original XML members, hashes, firmware addresses and limits:
[right-click reverse-engineering findings](/Users/nap/Documents/AppleMagicTouchstreamLP/FINDINGS.md).
No gesture code, anatomical assignment, thresholds, output or hardware state was
changed by this research checkpoint.

## Spread thumb+two-fingertip right-click implementation (2026-10-21)

This supersedes the exact{1,3,4} activation and known fingertip-label rejection
policy above. One full frame must contain a thumb(code1) and two known
fingertips(codes2..5), with compatible hand telemetry and spread geometry.
Fingertip separation must be2..40mm; the thumb's nearest fingertip must be at
least15mm away and at least1.5 times the fingertip separation. Coordinates use
the existing160×114.9 conversion. These are provisional app limits, not recovered
DSP coefficients or calibrated native dimensions. Contact order/hand orientation
do not determine the chord.

Bind the thumb and interchangeable fingertip roles to tracking IDs on matching.
Allow fingertip relabeling and temporary Unknown on those IDs; reject known
thumb/fingertip role changes and incompatible hand labels. Existing tap timing,
motion limits, all-up completion, per-pad cancellation and balanced secondary
output remain. Classified-thumb cycles remain reserved from primary double-click.
This does not implement competing compact/TIP arrangements or the complete
firmware FP scorer. The UI label is now Spread thumb + 2 fingertips. Hardware
acceptance remains pending. Canonical research: [FINDINGS.md](../../FINDINGS.md).

Verification for the spread fallback: ./test.sh passed138 tests (2 skipped,0 failures). New tests cover TMR/TRP and other fingertip pairs, relabeling and compact rejection; existing tap/lifecycle/output checks remain. Live hardware acceptance is pending.


## Diagnostic UI cleanup and 3spread replay (2026-10-21)

At user request remove the color legend and `(F: number)` from contact labels.
Retain live anatomical colors, contact tracking number, finger name, pressure,
colored arrows and paths. There is no recognition change.

`3spread.atpcap` offline replay predicts40 right-clicks under current T2F versus18
under the older exact-TMR implementation, over53 completed contact cycles. All494
anatomically eligible T2F frames pass the existing geometry. Five otherwise valid
taps are taken by mouse ownership; two exceed1 mm individual travel; six cycles
never reach three active contacts. See root [FINDINGS.md](../../FINDINGS.md) for
measurements, assumptions, binary mismatch and reproduction artifacts. The running
Applications app still held the older exact-TMR build; install the freshly built
current T2F version before evaluating new thresholds. Do not loosen geometry on
this capture's evidence alone. Actual delivery and intent remain hardware checks.

# Preserved macOS input research

Technical research recovered from the repository snapshot `60f4b9a`, before the
macOS prototype folders were removed. Each topic records the original Git blob
hash, so the exact source can be recovered with `git show <blob>` without keeping
the retired projects in the working tree. This archive preserves equations,
measurements, negative results and design proposals. It is not a set of active
build instructions or the current runtime specification.

For current behavior use [gesture rules](AppleMagicTouchstream/GESTURE_ENGINE.md),
[native takeover](AppleMagicTouchstream/TRACKPAD_TAKEOVER.md), and the
[implementation plan](FINGERWORKS_IMPLEMENTATION_PLAN.md). Original firmware
semantics are consolidated in [FINDINGS.md](FINDINGS.md). The full decoded Apple
report layout is preserved in [APPLE_CONTACT_HID_LAYOUT.md](AppleMagicTouchstream/APPLE_CONTACT_HID_LAYOUT.md).
Native FLTR is the production path; the archived custom-driver and notification
experiments are historical evidence, not dependencies or a proposed return to them.

The app's geometry scale is 160 × 114.9 app mm; the TouchStream comparison surface
is 165 × 121 mm per pad. Neither establishes the exact active sensing bounds.
Keep these physical comparisons separate from recovered report calibration.

## Pointer acceleration equations and measurements

Original source blob: `4d07b3a62c5d6850f705f8879a9129405cde76a2`.

#### 1. Sources and scope

Source revision examined: IOHIDFamily commit
`777ccd9698845aadf711e32d843c8c9b777431d9`.

| Source | Useful responsibility |
| --- | --- |
| [IOHIDPointerScrollFilter.cpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDEventSystemPlugIns/IOHIDPointerScrollFilter.cpp) | Select settings/algorithm, decide when to accelerate, handle pointer versus scroll events. |
| [IOHIDAcceleration.cpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDEventSystemPlugIns/IOHIDAcceleration.cpp) | Turn pointer deltas/timing into a gain; separate scroll history processing. |
| [IOHIDAccelerationAlgorithm.cpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDEventSystemPlugIns/IOHIDAccelerationAlgorithm.cpp) | Interpolate curves; evaluate parametric or piecewise table functions. |
| [IOHIDAccelerationAlgorithm.hpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDEventSystemPlugIns/IOHIDAccelerationAlgorithm.hpp) | Curve parameter types and the `96/67` cursor scale. |
| [IOHIDAcceleration.hpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDEventSystemPlugIns/IOHIDAcceleration.hpp) | Nominal rate and scroll-history constants. |

These files describe published HID filtering, not all proprietary Magic Trackpad
recognition. Their presence does not establish that this exact revision is the
installed binary. Our small independent model does not bundle Apple's files,
implement every fallback, or change installed settings. Detailed provenance and
related-project notes are in the source audit.


#### 2. Settings selection matters as much as the equation

`IOHIDPointerScrollFilter` can honor an explicit algorithm override. Its normal
selection tries parametric acceleration, then a table fallback. User-supplied
parametric curves take precedence over driver curves. Thus finding a driver's
curve is evidence of an available model, not proof it is the active one.

Pointer tracking acceleration is looked up through the service's acceleration-type
property, then mouse/general fallbacks. A trackpad can specify
`HIDTrackpadAcceleration`; reading only mouse tracking speed can select the wrong
index. Negative acceleration prevents creation of that pointer accelerator. A
separate linear-scaling mouse branch also exists; do not assume every service uses
the parametric path.

Useful property conventions:

| Property | Meaning for this investigation |
| --- | --- |
| `HIDAccelCurves` | Provider's available parametric curve dictionaries. |
| `HIDAccelIndex` | Curve selection/interpolation index, not a UI slider tick number. |
| `HIDPointerResolution` | Device count-resolution parameter; decode signed 16.16. |
| `HIDPointerAccelerationMultiplier` | Scales the magnitude used to evaluate the pointer curve. |
| `HIDPointerReportRate` | Pointer timing-normalization rate; zero skips that normalization. |
| `HIDTrackpadAcceleration` | Trackpad acceleration index, represented as 16.16 in our snapshot. |
| `HIDScrollReportRate` | Separate scroll rate; the scroll setup decodes it as fixed-point and supplies a nominal fallback. |

Do not apply the pointer property's integer-rate convention to the scroll property.
Fixed-point conversion is `signed_value / 65536`; the similarly named settings do
not all share one representation. Service overrides and third-party filters may
make provider/global snapshots differ from the effective runtime configuration.


#### 3. The pointer calculation

For input pointer-count deltas `(dx,dy)`, the published pointer accelerator first
computes:

```text
magnitude = floor(sqrt(dx² + dy²))
period    = 1 / pointer_report_rate
rate_gain = period / max(period, elapsed_time)  # when a nonzero rate is available

velocity = magnitude * (rate_gain if fixed_multiplier == 1
                        else fixed_multiplier)
velocity = max(velocity, 1/65536)

standardized = velocity / (resolution / 67)
gain         = curve(standardized) * (96/67) / velocity
output       = (dx * gain, dy * gain)
```

Important consequences:

- Magnitude is floored before curve evaluation; this is not simply speed in mm/s.
- X and Y share a radial gain, preserving input direction at this stage.
- A non-unit fixed multiplier **replaces** the timing factor. It is not an extra
  multiplier applied after acceleration. Its output effect depends on the curve.
- The nominal algorithm rate, report rate, contact sample rate and monitor refresh
  rate are different quantities. Do not replace 67 with 120 just because a display
  or device reports at 120 Hz.
- The `96/67` factor is part of this published model, not a measurement of the
  attached display's physical DPI. Retina pixel/point conversion is a separate
  question.

The executable code, rather than its introductory comments, determines these
operations. Our model defines first-sample timing explicitly; the published C++
constructor shown in this revision does not explicitly initialize its previous
pointer timestamp. Reproducing unspecified initial state is not a useful goal.


#### 4. Parametric curve equations

The low-speed function is:

```text
P(x) = linear*x + (parabolic*x)² + (cubic*x)³ + (quartic*x)⁴
```

The gain parameters are raised to powers along with `x`. For example, a parabolic
parameter of `0.5` contributes `0.25*x²`, not `0.5*x²`.

Between available curve indices, the implementation interpolates gains **and**
tangent-speed parameters before evaluating the resulting function. The parametric
path uses the highest available curve above its index range rather than inventing
further polynomial coefficients.

For the common case where both tangent speeds are nonzero, let `L` be the linear
tangent speed and `R` the root tangent speed:

```text
P'(x) = linear + 2*parabolic²*x + 3*cubic³*x² + 4*quartic⁴*x³
m0    = P'(L)
b0    = P(L) - m0*L
Y     = m0*R + b0
m1    = 2*Y*m0
b1    = Y² - m1*R

curve(x) = P(x)                 when x <= L
           m0*x + b0           when L < x <= R
           sqrt(m1*x + b1)     when x > R
```

The tangent construction joins these regions smoothly. Zero/omitted tangent
speeds select other branches. In particular, the published root-only branch has
specific coefficient calculations that should be checked directly rather than
reconstructed from its explanatory comment. Our model follows that source branch;
the inspected trackpad curve uses both tangents.


#### 5. Table fallback is a different model

The table implementation accepts recognized table signatures, selects neighboring
acceleration entries, interpolates their point sets and constructs piecewise
linear segments. It scales input breakpoints by `resolution/rate` and output
values by the cursor scale. Its boundary scaling includes an `(index+1)` ratio;
do not reuse the parametric index-clamping rule blindly.

The harness deliberately rejects absent parametric curves. It does not silently
substitute an arbitrary table or claim that table behavior has been implemented.
Our installed pads expose parametric dictionaries, making that the useful first
experiment. Table parsing, interpolation and original/legacy variants need their
own tests if a future device actually requires them.


#### 6. Pointer output must avoid accidental second acceleration

The filter checks acceleration-support and no-acceleration flags, and skips events
already marked accelerated. When it transforms an event, it can append an
accelerated child copy rather than replacing the original event in place.

This matters for future output design: deciding on a curve is only half the work.
We must establish where synthetic movement enters the system and which subsequent
stages process it. Manually accelerating deltas and then sending them through
another acceleration stage can produce the wrong feel. These HID event flags are
not proof that a superficially similar Quartz posting API exposes identical
behavior. Our recorder/model does not inject movement or implement that adapter.

Keep fractional movement until the eventual output boundary. Integer rounding,
residual accumulation, pointer-position clamping and display handling can change
small motions even when the curve itself is correct.


#### 7. Four-finger scrolling needs a separate transfer function

Apple's scroll accelerator has history and direction state rather than reusing
the pointer magnitude calculation. Published constants describe a nine-slot
history ring, a 500 ms history-reset horizon and a 150 ms event-time cap. It
averages recent magnitudes/timing, resets history on direction change or a long
pause, and applies additional rate-dependent processing.

Scroll table and parametric paths also differ, and the surrounding filter adjusts
momentum events using their dispatch-rate attachment. Per-axis scroll resolution
and acceleration settings are separate from pointer settings.

For our proposed four-finger scroll gesture, this suggests separate scroll state,
direction-change handling, units and momentum tests. A pleasant pointer curve does
not automatically supply native-feeling scrolling. The current harness implements
neither scroll acceleration nor momentum generation.


#### 8. What this Mac exposed in the test snapshot

The completed session's selected pad was Bluetooth `D0:C0:50:D5:69:55`, native
multitouch ID `288230377507875157`. IDs identify that connection/session; they are
not promised to remain the same after transport changes or reconnects.

All three captured services exposed ten parametric entries. The selected profile
contained:

| Setting | Raw observed value / decoded value |
| --- | --- |
| Pointer resolution | `26214400` / `400.0` |
| Pointer fixed multiplier | `48545` / `0.7407379150390625` |
| Pointer report rate | `0` |
| Trackpad acceleration index | `196608` / `3.0` |
| Selected curve linear gain | `1.0` |
| Selected curve parabolic gain | `1.8800048828125` |
| Selected curve cubic gain | `0.3600006103515625` |
| Selected curve quartic gain | `0.0` |
| Linear tangent speed | `7.0` |
| Root tangent speed | `12.0` |

For this published model/configuration, the non-unit fixed multiplier and zero
report rate mean the pointer timing-normalization branch does not determine gain.
That does **not** make all upstream trackpad processing independent of time.

Read current values for each trial. Do not hardcode this user's maximum tracking
index, coefficients or multiplier as defaults for every Mac.


#### 9. First native recording: useful, but not calibration yet

Session: native.7YcQ2s.

| Measurement | Result |
| --- | --- |
| Recording duration | 20.025 seconds |
| Contact callback records | 1,180 |
| Pointer event records | 659 |
| Dropped records | 0 contacts / 0 pointer events |
| Native start/stop | Both returned success |
| Tap disabled | No |
| Frames with one active contact | 1,104 |
| Usable paired displacement intervals | 887 across 23 segments |
| Pointer samples marked near a screen edge | 5; affected pairing intervals excluded |
| Median contact callback spacing | 11.248 ms |
| Median pointer callback spacing | 16.672 ms |
| Median pointer receipt minus event timestamp | 22.695 ms |

This is a successful capture. Different callback cadences, event coalescing and
receipt latency make individual contact intervals imperfect cursor intervals.
The contact-native timestamp also has a different epoch from host uptime; the
recorder preserves both clocks rather than assuming their raw values are equal.
The measured pointer receipt delay is not automatically the correct contact-to-
cursor alignment offset, and it is not a display-latency measurement.

The initial prediction used explicit, **unvalidated** assumptions:

- Normalized contact surface: 160 × 114.9 mm, matching the app's current dimensions.
- Contact displacement to counts: `400 / 25.4 = 15.7480314961` counts/mm.
- Additional pairing latency offset: 0 ms.
- Captured acceleration index/curves; no curve fitting or coefficient changes.

Results under those assumptions:

| Initial comparison | Result |
| --- | --- |
| Per-interval vector RMSE | 12.959 Quartz points |
| Median segment endpoint-vector error | 41.640 points |
| Sum of predicted segment endpoint-vector lengths | 14,301.093 points |
| Sum of observed segment endpoint-vector lengths | 13,229.759 points |
| Ratio of those two sums | 1.08098, about 8.1% higher predicted magnitude |

These are sums of **endpoint displacement lengths of usable segments**, not total
cursor path length. The ratio does not establish a uniform 8.1% gain error or
prove a particular correction. Per-interval RMSE includes pairing/timing error.
The comparison suggests the captured curves are worth pursuing; it does not
establish that the full native transfer function has been recovered.

Reproducible artifacts in that session folder:

- `settings.json`: captured provider curves and global tracking index.
- `native.jsonl`: original contacts, cursor-event positions, sampled cursor
  positions, source PID metadata and both receipt/native timestamps.
- `deltas.csv`: paired one-finger deltas in assumed millimetres.
- `predicted-initial.csv`, `comparison-initial.json`: initial model outputs.
- `analysis-initial.json`: capture statistics, parameters and aggregate results.

The cursor tap sees session mouse-move events, not proven per-physical-device
pointer events. The isolated-pad/no-other-mouse protocol matters. Other input
modifiers, synthetic movement and later WindowServer processing remain potential
confounders. This trial does not certify the absence of every confounder.


#### 10. Implications for TouchStream-style gestures

A clean implementation can separate three questions:

1. **Gesture recognition:** decide when coherent two-finger motion means pointing,
   when separation changes mean pinch, and when four fingers mean scrolling.
2. **Transfer function:** convert an explicit input unit into predicted output
   movement using a configurable, stateful model.
3. **Output adapter:** deliver that movement once, with verified scaling, rounding
   and subsequent OS processing.

For two contacts, centroid displacement and separation change are useful distinct
signals. They do not resolve intent by themselves. Fast typing can overlap two
contacts; gesture formation, adjacency, identity changes, latching and hand/finger
classification require separate capture/replay tests. A three-finger drag would
also need an explicit button lifecycle and reliable cancellation/release.

Apple's pointer accelerator accepts deltas; it does not implement our proposed
finger-count mapping, typing-versus-pointing classifier, pinch semantics or
historical FingerWorks gestures. The standalone harness does not add app output/recognition. A subsequent,
separately opt-in fixed-gain movement test is documented in
TWO_FINGER_MOUSE.md.

## Scroll history, precise output and momentum

Original source blob: `47f14b23945c783c2f86d42efa03c3c334430f06`.

#### Apple-source model

The scroll numerical model is independent code based on the published
[IOHIDScrollAccelerator equations](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDEventSystemPlugIns/IOHIDAcceleration.cpp)
and [scroll setup](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDEventSystemPlugIns/IOHIDPointerScrollFilter.cpp),
at the same pinned revision used in POINTER_ACCELERATION.md.

Read-only control-path registry inspection loads each selected pad's:

- `HIDUserScrollAccelCurves` or `HIDScrollAccelCurves`, independently of pointer curves.
- Acceleration-type property/index, then mouse/general scroll fallbacks.
- Per-axis/general scroll resolution and fixed-point scroll report rate (67 fallback).
- Global natural-scrolling preference, determining output direction.

The connected pads expose 400-resolution scroll profiles and 67 Hz report-rate
parameters. Current global fallback scroll index is 0.5. Service/OS overrides may
differ from these provider/global snapshots; unsupported table/third-party
behavior is not reproduced. No installed HID property is written.

For each axis, preserve the published nine-slot ring's eight retained samples,
absolute displacement and elapsed milliseconds, direction-change/500 ms reset,
150 ms interval cap and 1 ms minimum mean interval. With `r = reportRate / 67`:

```text
meanTime = clamp(mean(elapsedMS) * r, 1, 150)
velocity = max(1/65536,
  ((2/65536)*meanTime² - (955/65536)*meanTime + 98369/65536)
  * mean(abs(inputCounts)) * r)
gain = parametricCurve(velocity / (resolution/reportRate)) * (96/67) / velocity
wheelUnits = inputCounts * gain * (6554/65536)
pixelPoints = wheelUnits * 10
```

The independent existing parametric evaluator supplies polynomial, tangent line,
root and interpolated coefficients. Scroll does not reuse the pointer's floored
magnitude or non-unit fixed multiplier. Each axis has independent history.

Contact millimetres become input counts via **resolution / 25.4 × sensitivity**,
using the existing 160 × 114.9 mm surface assumption. This is an explicit
experimental conversion, not Apple's unpublished multitouch-to-scroll mapping.
First-sample timing is deterministic (150 ms) rather than inheriting an undefined
constructor timestamp. Cross-device calibration still needs native scroll captures.


#### Fine events and cleanup

Use [continuous pixel scroll CGEvents](https://developer.apple.com/documentation/coregraphics/cgevent/init(scrollwheelevent2source:units:wheelcount:wheel1:wheel2:wheel3:)),
with began/changed/ended/cancelled phases, both axes, and the existing synthetic
input tag. Keep fractional fixed-point wheel deltas. Pixel fields are integer;
carry their fractional remainder between frames so subpixel movement accumulates
into individual points instead of disappearing or becoming coarse wheel notches.
The local CGEvent constructor and AppKit tests confirm 10 pixel points per wheel
unit and `hasPreciseScrollingDeltas`, with eight 0.25-point samples delivering a
total of two pixel points to AppKit. No test posts events.

All-up emits physical ended and can start momentum from recent velocity.
Release, selection/feature changes, sleep/replay/refresh,
mouse-button suppression and failed transitions cancel active phases and clear
history/remainders. The existing status timer also cancels stale streams using
host receipt time, without cutting off an intentional coast. Contact timestamps
retain the 150 ms continuity guard. Only
current selected AND owned FLTR devices can generate events, with Accessibility
approval and a successful armed transition. Replay never posts output.


#### Momentum after lift

Momentum is included in the four-finger scroll feature by default, without a
separate checkbox. Estimate release velocity from the last 80 ms of accelerated
pixel deltas, using up to eight samples. Zero-motion samples count as elapsed
time: holding still before lifting suppresses stale momentum. Reversals reset
the release estimate so the coast follows the latest intended direction.

The initial coast tuning is explicit and provisional:

| Parameter | Initial value |
| --- | ---: |
| Minimum launch speed | 30 points/second |
| Maximum launch speed | 6000 points/second |
| Exponential time constant | 0.325 seconds |
| Stop speed | 5 points/second |
| Maximum duration | 2.5 seconds |
| Tick rate | 120 Hz |

For release velocity `v`, position over time is integrated analytically:
`delta = v * tau * (exp(-t0/tau) - exp(-t1/tau))`. This preserves total travel
across different tick rates. A delayed/nonmonotonic tick (over 80 ms) ends the
coast without a catch-up jump. Native contact timestamps determine release speed;
host monotonic time drives the coast, with no clock-domain subtraction.

The coast is independently generated after the published under-finger scroll
accelerator; these decay constants are **not** claimed to be Apple's unpublished
momentum algorithm. Native feel still needs hardware comparison and tuning.

Events use [Core Graphics momentum phases](https://developer.apple.com/documentation/coregraphics/cgmomentumscrollphase):
physical ended, then momentum begin/continue/end with ordinary scroll phase none.
Tests verify the corresponding AppKit `momentumPhase` and precise deltas, following
[Apple's event semantics](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html).
Fractional remainder and the original scroll location carry into momentum.
No pointer movement or cursor warp is generated by the coast.

A new active contact on the same pad, a mouse button, feature disable, release,
selection/lifecycle reset or loss of eligibility ends momentum immediately and
clears velocity. Repeated all-up frames do not restart or cancel a valid coast.
Each pad owns its own estimate and coast. The timer only posts for eligible
selected-and-owned devices; stopping capture also cancels the timer. No momentum
is launched by replay or by a stale/missing release notification. The existing
0.5-second status watchdog does not mistake a coast for stalled contact delivery.

## Original interpreter and adaptive keyboard design

Original source blob: `bfc2626f2017add8900e1f7ce72c77229166c2d7`.

#### 1. What was recovered and what to use

All firmware addresses here are DSP word addresses, four bytes per word. They identify evidence; they are not Swift structure layouts.

| Recovered behavior | Evidence | research prototype consequence |
| --- | --- | --- |
| Contact, typing candidate, sequence hypothesis and emitted action are separate objects. | Firmware `8013DF`, `803B48`, `803AD9`, `C0439F`. | A contact can survive cancellation of its typing interpretation. Never equate a raw down with key-down. |
| Initial spatial lookup is followed by alternative keys and a no-key interpretation. | `802E70`, `802ED9`, `803653`, `C04174`; ranked nodes at `803936`. | Keep ambiguity explicit. Allow “no output” to win; adding a language model is optional. |
| Candidate age is separate from finger identity. | Contact `[22]` increments; candidate `[19]` copies it. Startup `C02753` fills reciprocal weights. | Store sample count and anatomical identity in different fields. Sample count must not substitute for elapsed seconds. |
| A held stationary chord and a sliding chord share activation, followed by configured Lift. | `C03B53`, `C03BED`, `C03BC2`, `C01D1E`. | Model tap, dwell, motion and finish separately. Stationary activation must schedule and release correctly without a later motion frame. |
| Activation cancels recent typing through a hand/time-scoped cleanup path. | `C03BC2 → C04823 → C047F6`. | Claim a cohort and cancel its tentative typing atomically. Cleanup releases only owned outputs. |
| Exact finger patterns and geometric templates both contribute to chord selection. | `8021AA`, `8021E1`, `C0395D`; utility serializers. | Count alone is insufficient. Keep confidence and an explicit fallback when thumb identity is unknown. |
| Pointer motion uses configured gain and retained fractional state. | `802864`, `802881`, `C018A8`; host `h.java`. | Preserve small motion deltas and explicit units. Avoid accidental double acceleration with macOS. |
| Recognition feeds configured timed actions and stateful output. | `C036D4`, `C03596`, `80145C`, keyboard/mouse writers. | Reuse the action catalog, scheduler and dispatcher; recognizers do not post OS events. |

Selector `[9]` means **activated**, including stationary hold. The bounded
candidate `[38]` term participates in the **no-key alternative**.

The exact language model, all commit/replacement branches, adaptive TapArea transformations, anatomical classifier, partial-lift/rearm rules, physical units and complete pointer/scroll filtering remain incomplete. Firmware numbers such as 0.25 pressure-like threshold, 400 ms host timeout, 76 internal age units, or reciprocal sample weights are **research facts, not Apple defaults**. The sensor's 16×82 grid is below Apple's already tracked contact interface.

Read [current findings](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/FINDINGS.md), [reconstruction and address-level evidence](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/reconstruction-2026-10-17/PROGRESS.md), and [remaining uncertainty ledger](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/reconstruction-2026-10-17/coverage-ledger.json). Firmware SHA-256: `87262a818209a1e019990f1e40f1b55d9d2dd030644d0f5aa0ed7e8cf09476e1`.


#### 3. Define data contracts before moving the engine

The following are **proposed interfaces**, not existing type names or vendor definitions:

```swift
// Schematic contracts; use existing app types where they express these roles.
ContactKey(deviceID, rawID, generation, epoch)
ContactObservation(key, timestamp, positionMM, phase, optionalFeatures)
ContactState(key, acquiredAt, acquiredPosition, latestPosition,
             sampleCount, peakStrength, velocity, identityEvidence)
TypingCandidate(id, contactKey, state, geometryRevision,
                alternatives, bindingSnapshot, cancellationReason)
ChordCandidate(id, members, selection, confidence, activation, state)
DecisionProposal(owner, members, event, confidence, reason)
OwnedOutput(token, owner, action, epoch)
Engine.step(frame, dueDeadlines, configuration) -> bounded decisions
```

Each field has a contract:

- Use monotonic time and seconds internally; record source timestamps and frame sequence. Define how timestamp regressions and missing frames are handled.
- Convert positions into physical device-local millimetres once. Retain device dimensions, orientation and source coordinates in capture metadata. Mirror only under an explicit routing/orientation model.
- Track raw IDs by lifetime, not anatomical label. Reused IDs receive a new generation; reset, replay seek or reconnect starts a new epoch.
- Identity is evidence with validity/confidence, not a constant. The requested display convention is thumb=1, index=2, middle=3, ring=4, pinky=5, palm=6. It is distinct from FingerWorks internal bits and from stable contact IDs.
- **Apple capture evidence:** isolated intended index taps were mostly labeled4; adding contacts revised existing labels without lifting. A single-finger slide also changed5→4→3→2. Raw labels can be stable and wrong, so persistence alone is not confidence. No confidence value was supplied in these captured telemetry records. Use anatomical estimates as soft evidence; do not manufacture anatomical truth from stable codes. See the capture review.
- Optional pressure, area, orientation and finger labels require validity flags. Missing data is not zero pressure or “thumb absent.” Check what OMS actually supplies on the tested device before using it for classification.
- Derive peak, path length, maximum displacement and velocity from input frames, not rendered traces. Use elapsed time for temporal features rather than assuming a fixed frame rate.

Keep this state confined to the existing serial owner. Prefer bounded storage and reuse existing `TouchTable` until profiling supports replacement. No per-frame file I/O, verbose strings, configuration decoding or unbounded histories on the input queue. Record bounded numeric diagnostics and serialize off the hot path.


#### 4. Build typing in two stages

##### Stage A: interpretable deterministic candidates

Use `tentative → committed → finished`, plus terminal `cancelled`. Contact tracking continues after a typing candidate cancels.

At acquisition, snapshot the geometry revision, candidate bindings and relevant feature availability. Update motion/strength evidence while tentative. Plain keys commit under an explicit measured policy, initially the experiment's intended tap-release behavior; a configured hold/modifier/layer has its own activation deadline. Do not impose the firmware's global 1.5× timeout on every tap.

Movement beyond the chosen cancellation rule can cancel a **tentative** key. A candidate claimed by a pointer/gesture cannot type on later release. After commitment, movement cannot retract an emitted character. A held key keeps its original binding until cleanup; it does not silently morph into a gesture. Cross-pad modifiers must still apply to independently owned typing contacts.

Maintain reason codes such as `moved`, `claimedByChord`, `missingFeature`, `layoutReplaced`, `deviceLost`, and `ambiguous`. They make replay disagreements diagnosable. Preserve tuning behavior for peak-force bounds and per-key force holds unless evaluation justifies changing it; those are different conditions.

##### Stage B: bounded alternative interpretations

Once Stage A has a labeled baseline, consider a small configurable set of plausible keys plus `noKey`. Firmware supports that architecture but does not supply calibrated Apple scores or a recovered beam width.

For a proposed spatial model, normalize acquisition displacement against key geometry and measured per-user spread; score motion, duration and available strength evidence separately. Specify score direction and units. A research prototype log-score could be:

```text
sequenceScore = predecessorScore
              + spatialEvidence
              + temporalEvidence
              + optionalContextEvidence
```

This is a **proposal**, not the recovered complete firmware formula. Score `noKey` explicitly, use a rejection/ambiguity margin, bound alternatives and sequence depth, and record the components. Do not copy a skip-contact weight into a “keypress confidence” field. Include a tie-break based on stable candidate order so replay is deterministic.

Start with spatial evidence alone. Add optional language context only if held-out intended-text sessions show an improvement without unacceptable substitutions or delay. Emitted text cannot serve as its own ground truth. Modifier chords, shortcuts, password-like text and non-text actions need a context-free path. Do not automatically send Backspace to revise a prior application's text; any future correction feature needs its own explicit scope, focus guards and evaluation.

The latency tradeoff is unavoidable: early irreversible commitment reduces delay but closes the chance to recognize a later chord. Measure that tradeoff; no policy can promise both zero extra delay and perfect retrospective interpretation.


#### 5. Make every key movable without destabilizing typing

Separate stable identity, geometry and action binding:

```text
KeyDefinition: keyID, optional columnID, local shape/pose
ColumnDefinition: columnID, transform, stable ordered keyIDs
LayerBindings: (layerID, keyID) → actionID
LayoutSnapshot: revision, device transform, immutable resolved shapes/index
```

This is a proposed rewrite model. A key can belong to a column while retaining an independent offset. Moving a column composes its transform with each child's local transform; moving one key edits only that key's local pose. Never encode its identity solely as a row/column array index or displayed character. Keep visual labels separate from action semantics.

For click-and-drag editing, enter an explicit editing mode, suspend recognition output from affected surfaces, and release app-owned holds before an edit session. The UI works on a draft layout. Render a preview during dragging, validate on commit, then publish **one immutable new revision** and one undo operation. Coalesce pointer movement; do not rebuild the recognizer's index on every drag pixel.

Define overlap precedence, hit boundaries, out-of-pad geometry and transform order. Use one resolved geometry snapshot for both rendering and hit testing. Convert screen pixels through the device transform; retain millimetres as the recognition coordinate system. Layer changes usually replace bindings, not geometry. Layout generators produce editable definitions rather than regenerating away saved manual edits.

An active contact retains its target/binding snapshot. Publishing a structural layout edit cancels old tentative candidates and cleans up active outputs through their original bindings. New contacts use the new revision. Persist stable IDs, transforms and schema version; migrate current profiles with a preview and export/round-trip checks. A repeated load/save must not gradually move keys.

Do not introduce speculative spatial trees for a small keyboard. Cache resolved bounds at revision changes, benchmark linear scans versus the existing lookup, and optimize measured costs.


#### 6. Give chords distinct selection and activation

A **proposed** conservative lifecycle is:

```text
idle → assembling → selected
selected + valid quick release → tap action → finished
selected + dwell deadline     → activated(.hold)
selected + deliberate motion  → activated(.motion)
activated + updates           → motion/action updates
activated + finish/cancel     → release owned output → finished
```

Selection alone posts no output. Dwell uses the scheduler even when no new input frame arrives. If a chord activates, its later release must not also trigger the quick-tap action. A stationary drag-button hold still needs mouse-up on finish or cancellation.

Continuously revisable labels and a latched gesture are separate states. During acquisition, new context may change the preferred chord. At commitment, latch its semantic action and owning contact keys; a later label revision or partial lift must not silently create a different/smaller chord. For the initial conservative experiment, gate rearm on all-up of the owning hand/surface, including quarantined late arrivals, while permitting independent activity on the other pad. Action finish/release timing is a separate explicit rule. This is a proposed research prototype lifecycle; raw contact captures alone cannot prove the full TouchStream rule or any fixed one-second delay.

The [lifecycle follow-up](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/lifecycle-2026-10-17/PROGRESS.md) now directly verifies the ordinary activated-selection replacement guard. Firmware hand14 is raw contact count, hand17 ordinary assigned fingers, hand20 their peak, and hand19 an epoch-qualified subset. Its special grips and five-finger-peak path can finish/rearm without raw all-up. Therefore keep `rawContacts`, `estimatedFingerMembership`, `acquiringCandidate` and `activatedOwner` separate in the Swift design. Do not freeze the first uncertain anatomical label; freeze semantic ownership at activation. Log the explicit rearm reason and whether only an incidental palm remains. Test that distinction before weakening the conservative all-up policy. Never release another owner's outputs when changing epochs.

**Second Apple session:** the lifecycle capture review now supplies four repeated finger-pair cycles over a continuous14.6s palm-like contact, three3→2→3 replacements, two5→2→5 sequences and three independent pairs while the other pad stays held. The continuous palm-like contact revises6↔1 and includes raw code12, so current-code-only palm exclusion is insufficient. Preserve unknown codes and exclusion evidence over lifetimes; test both conservative raw-all-up and an explicitly justified cohort reset in shadow mode. Two one-sample pressure0/code0 lifetimes during landing also belong in tentative-acquisition and raw-ID generation tests. These observations do not establish gesture activation or its timing.

Assemble using a cohort of contact keys and arrival times, not just a count. Try reliable exact patterns before generic non-thumb-count/thumb-presence templates. Unknown identity gets its own fallback or rejection. Estimate geometric fit relative to centroid and hand size; document any normalization and missing-finger penalty as research prototype choices. Require a margin against the second candidate, not just the smallest residual.

Test staggered landings so an early two-finger subset does not fire while a three-finger chord is forming. For the first experiment, latch an activated cohort, quarantine extra arrivals, and disallow reinterpretation as a smaller chord on partial lift. Rebase centroid motion on any allowed membership change to prevent jumps. Requiring full cohort lift before rearming is a conservative **proposal**, not a recovered universal TouchStream law.

Keep gesture recognition in shadow mode in `research prototype`: output diagnostics and candidate states only. Add action dispatch later as a separately reviewed implementation stage.


#### 7. Resolve ownership in one place

Recognizers may observe the same tentative contacts; committed ownership is exclusive. One coordinator applies decisions in deterministic order before dispatch:

1. Expire/cancel stale epoch, disconnected device and invalid configuration work.
2. Deliver required releases and retire finished owners.
3. Evaluate tentative typing/chord/pointer proposals against remaining contacts.
4. Atomically claim the chosen cohort, cancel conflicting tentative interpretations, then emit semantic activation commands.
5. Schedule future work tagged with owner, epoch, sequence and configuration revision.

The priority and same-timestamp ordering above are proposed policy and must be fixture-tested. A pre-existing committed key/hold cannot be stolen by a newly arriving gesture. Several independent keys can commit with overlap; rollover is not automatically a chord. A held modifier can affect another contact without surrendering ownership.

Output ownership uses tokens/refcounts, not a single global “Shift is down” Boolean. Two owners sharing a modifier cannot release each other's hold. Reset releases **app-owned** state, not unrelated physical input. Haptics occur at the intended accepted transition and do not repeat merely because a replay frame is reevaluated.


#### 9. Use traces to explain decisions, not to make them

Keep the user's contact tracing option independent of policy. It displays observed paths even when recognition produces no key. Render snapshots may skip frames and cannot feed recognition history back into the engine.

A developer overlay should optionally show contact key/generation, raw identity versus interpretation, sample count, candidate target(s), ownership, phase, score components and cancellation reason. Keep displayed pressure peaks distinct from acquisition/activation thresholds. Publish bounded snapshots at UI cadence; no per-frame formatting or unlimited path arrays on the runtime queue.

Extend captures with recognizer/config version, dimensions/orientation, feature validity, geometry snapshot/revision, calibration and arbitration timings. Decision logs need owner/candidate IDs, input sequence, transitions, reasons and output tokens. Preserve older captures through an explicit reduced-feature policy. See production replay, telemetry contract tests, and capture format.


#### 12. What further firmware work would change this plan

**Connected-system checkpoint:** read the [contact → assignment → ownership → output → release map](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/system-2026-10-17/SYSTEM_MAP.md) before choosing new recognition policy. It joins contextual, revisable finger assignment to departure timing, scoped cancellation and explicit release ownership. The [remaining-work ledger](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/system-2026-10-17/coverage-ledger.json) keeps sensor/metric, FP, language and special-lifecycle gaps explicit. The candidate-refresh probe establishes that both identity and sample count keep
updating when position refresh is frozen.


**Follow-up, 2026-10-17:** the [rewrite-focused investigation](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/rewrite-followup-2026-10-17/PROGRESS.md) now reconstructs the positive-input log10 helper, alternative/head score ratio and increasing age threshold `t²/(300²+t²)`, plus the conditional 100/350-unit timing selection. The integer tail passed 960 synthetic branch cases. Sequence release/motion summary bits and a 24-candidate alignment/lookahead bound are also traced; that bound is not a recovered beam width.

This strengthens Stage B's case for confidence-dependent patience and retained motion evidence. It does not justify copying those numeric time units into Apple defaults, and return-zero from the gate does not guarantee emission. The full language/pruning model and adaptive geometry remain incomplete. The newer [lifecycle pass](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/lifecycle-2026-10-17/PROGRESS.md) adds verified register MPYI3 and one indirect TSTB3 form. Membership now completes174/174 integer-arm cases; its middle FP arm remains unexecuted. Another560 bounded cases verify ordinary replacement, termination and a five-finger rearm exception. These refine the policy choices but do not establish a universal firmware lifecycle.

**Apple-contact testing is prepared:** start with tomorrow's session walkthrough. The raw-contact playground has an offline `RewriteProbe` executable, declarative intended trials, readable contact tables, input hashes and focused tests. It checks contact assumptions and treats missing data/calibration as inconclusive. It changes no live recognizer or OS output; shadow recognizer/accuracy tests come after examining the recordings.

Exact confidence/time gates, adaptive geometry and language/pruning recovery could refine Stage B. Full lifecycle reconstruction could replace the conservative rearm proposal. Better axis/context reconstruction could supply additional motion experiments. None removes the need to calibrate Apple contacts or prove native-event suppression.

The latest processor suite has168 decoder/emulator assertions, 256 actual modifier-helper cases, 512 bounded candidate-gate cases, and 504 stationary-hold-gate cases, followed by the scoped probes above. These improve confidence in specific recovered paths; they are not tests of this proposed Swift recognizer. Both real Ghidra projects contain the follow-up annotations, and the [latest saved-project audit](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/lifecycle-2026-10-17/saved-project-verification.json) verifies that firmware memory remains unchanged.

The [next physical session](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/lifecycle-2026-10-17/RETURN_TESTS.md) targets a palm held across repeated finger cohorts, partial-lift replacement, five-to-two transitions and independent-pad rearm. Raw recordings can validate the available input evidence; a shadow decision stream is still required to test recognizer ownership and actual gesture selection.

## Capture-backed tap arbitration

Original source blob: `19c8881a6f92c1d2e4ec1da280b615a3fbfb8629`.

### Move–tap capture analysis

2026-10-20. User recording: `captures/2finger_tap.atpcap`.
SHA-256: `b2a420be66d2de32b022c8e53fa49053c116ee492c05e634bc2e5aac95351002`.

The reported task was rapid left-move/click/right-move/click, with missed taps
and a less immediate feel than FingerWorks. Replay confirms an arbitration
problem: small tap drift crosses the mouse-start threshold before release.


#### Evidence and limits

The capture contains 1559 frames over 25.672 seconds from right-pad native ID
`288230377507875157`, with 55 nonempty-to-all-up cycles. Production replay uses
`ReplayFixtureParser` and the actual `TrackpadGestureRouter` and
`TwoFingerTapRecognizer`, without posting events. Contact timing/state used by
the parser supplies the table below; raw container records can have different
release/hover timing than the parser's canonical frames.

This recording contains contacts, not actual posted click timestamps, application
responses, native mouse-button suppression state, or a per-tap intention label.
Consequently these are **predicted recognizer outcomes**, not proof of how many
clicks the application delivered. A small-motion cycle is not inherently a tap;
we compare the independent tap recognizer and retain conservative motion rejection.

| Mouse initiation threshold | Predicted clicks | Clear movement cycles (> 8 mm individual travel) | Clicks during those movement cycles |
| --- | ---: | ---: | ---: |
| 0.20 mm, old | 19 | 29 | 0 |
| 0.35 mm, new test | 25 | 29 | 0 |
| 0.50 mm | 25 | 29 | 0 |
| 0.75 mm | 25 | 29 | 0 |
| 1.00 mm | 25 | 29 | 0 |

The independent tap recognizer, without movement arbitration, accepts 25 cycles.
At 0.20 mm, six of these are instead claimed by mouse recognition:

| Cycle | Start relative to capture | Canonical duration | Largest individual displacement |
| --- | ---: | ---: | ---: |
| 12 | 4.520 s | 58 ms | 0.313 mm |
| 14 | 5.275 s | 100 ms | 0.264 mm |
| 16 | 6.062 s | 248 ms | 0.496 mm |
| 26 | 9.662 s | 44 ms | 0.294 mm |
| 40 | 14.847 s | 90 ms | 0.221 mm |
| 44 | 16.388 s | 67 ms | 0.463 mm |

The 500 ms tap maximum is not the main problem. These cycles satisfy all tap
limits and are rejected because the old 0.20 mm common-motion threshold claims
mouse first. Cycle 30 remains ambiguous and rejected: about 234 ms with 1.164 mm
individual motion, beyond the 1 mm tap limit. The change does not relabel it a tap.


#### Next test build

Set **only mouse initiation to 0.35 mm**, the smallest tested value that recovers
all six otherwise-valid tap cycles. Scroll stays at 0.20 mm. Keep the 500 ms
maximum, finger timing/slop rules, existing latches, accelerated response and
no-click-after-recognized-mouse rule. Do not retroactively click when a short
recognized mouse gesture ends.

This is an input-distance threshold, not a fixed wait. In the 29 clear movement
cycles here, median mouse initiation moves from about 22.3 to 33.8 ms after the
first active contact. Once latched, fine movement and acceleration are unchanged.
A click still fires at all-up, not after waiting for the 500 ms maximum. Earlier
click-on-contact would be a different gesture commitment/output design and has
not been implemented by this tuning.


#### Reproduction

Run from the repository root with the local recording available:

```sh
mkdir -p the archived prototype source
TAP_CAPTURE_REPORT="$PWD/the archived prototype source \
  ./the archived prototype source --filter TapCaptureAnalysisTests
```

`TapCaptureAnalysisTests.swift` checks the old/new click counts and that every
clear movement cycle still claims mouse with no tap clicks. It writes per-cycle
JSON when requested; it skips if the unbundled local recording is missing.
The local analysis also saved `build/TapCaptureAnalysis/cycles.csv` for inspection.
Synthetic unit tests separately verify that 0.24 mm landing drift can remain a
tap while 0.48 mm common motion claims mouse and prevents a click on release.
No tests open a FLTR session or post clicks.


#### Better hardware follow-up

The user's existing move–tap recording is already a useful test. On the updated
build, one capture with three separated blocks will make failures easier to label:

1. Ten stationary two-finger taps at a comfortable pace; leave a clear all-up gap.
2. Ten repetitions of move left, lift all, tap; move right, lift all, tap, at the
   same fast pace as this capture. Do not deliberately slow down to help it.
3. Ten short mouse strokes followed by lift, with **no intended tap**. These must
   not click.

Leave about two seconds untouched between blocks. Report intended tap counts,
observed clicks/misses in each block and whether mouse initiation feels worse.
Use a blank document area or an on-screen click counter to distinguish event
count from multi-click selection behavior. A small screen recording alongside
the contact capture would help locate any remaining individual misses, but it
is not required for the next test.

Do not use a new tap to stop momentum in this particular comparison: braking is
intentionally excluded from clicks. Hardware button presses or a pad that never
reaches all-up can also legitimately prevent a tap. Those conditions cannot all
be established from this file alone.



#### Follow-up: 2finger_tap_test2.atpcap

The user reported that the updated build feels substantially better. The follow-up
contains 1352 frames across 31.126 seconds from the same right pad, with 45
completed active-contact cycles. SHA-256:
`a33a652e5e61aa6944246f98c4eb3cb00ed8336f282cdffa88fe940f50dfc50f`.

| Mouse threshold | Predicted clicks | Cycles classified as movement |
| --- | ---: | ---: |
| Old 0.20 mm | 17 | 28 |
| Current 0.35 mm | 22 | 23 |
| 0.50, 0.75 or 1.00 mm | 22 | 23 |

The temporal pattern is consistent with the requested test blocks:

| Apparent block | Time relative to capture | Replay result at 0.35 mm |
| --- | --- | --- |
| Stationary taps | 0.009–5.724 s | 10 cycles, 10 predicted clicks |
| Alternating move/tap | 7.784–17.042 s | 12 move cycles and 12 predicted tap clicks |
| Mouse strokes without tapping | 18.706–30.947 s | 11 movement cycles, zero predicted clicks |

The block labels are inferred from the contact pattern, not an embedded intention
annotation. Every cycle accepted by the independent tap recognizer is also
accepted with current movement arbitration. None of the 23 cycles classified as
movement produces a click. The older threshold would lose five of the successful
tap cycles. Larger tested thresholds recover no additional taps, so **retain
0.35 mm**; no runtime behavior change is warranted by this capture.

These results predict recognition, not actual application click delivery. The
capture still does not record posted button events or physical suppression state.
The user's improved-feel observation supports this tuning; it does not prove
all application/lifecycle edge cases are resolved.

The follow-up is now covered by
`testFollowupCaptureAcrossMouseInitiationThresholdsWithoutPosting`: initial ten
taps, final eleven no-click strokes, 22 accepted clicks and no loss against the
isolated tap recognizer. To export the detailed local report:

```sh
TAP_CAPTURE_REPORT2="$PWD/the archived prototype source \
  ./the archived prototype source --filter TapCaptureAnalysisTests
```

No app rebuild or reinstall is needed for this analysis-only follow-up.

## Apple native field calibration experiments

Original source blob: `f6b00c5d4f28bb1dc7233d0325b2d80e5ef5c7f9`.

#### 1. Separate strength, force-like response and contact area

**Question:** which scalars respond to stronger contact versus a larger patch of skin? Can any form a useful, calibrated proxy for TouchStream strength?

| File | Recording steps |
| --- | --- |
| `amt-strength-ramp.atpcap` | Place the index pad near the centre. Hold lightly for 2 seconds, gradually press more firmly over about 2 seconds, relax over 2 seconds, then lift. Stay comfortable; a physical click is optional and should be noted. Repeat three times. |
| `amt-area-roll.atpcap` | Hold one index contact near the centre. Slowly roll from fingertip toward the flatter finger pad and back, aiming for a similar contact centre and comfortable light contact. Repeat three times, lifting fully between repetitions. |
| `amt-strength-hold.atpcap` | Hold the same finger as still as comfortable for 8 seconds, then lift. Repeat once with light and once with firmer contact. |

Analyze total, pressure, density, major/minor axes, ellipse-area proxy (`major × minor`, without asserting an area unit), position and state on the same timeline. Compare onset, saturation, hysteresis, drift and correlations within each lifetime. Keep raw zeros and transition samples; summarize them separately from steady contact. Check whether scalar changes coincide with label/state changes.

**Decision this informs:** which features to retain separately, whether a strength proxy needs geometry compensation, and whether a peak/envelope analogous to firmware t20 is useful. These hand-controlled trials do not measure force in newtons, prove channel independence, or recover a conversion to firmware t2.


#### 2. Calibrate coordinates and native velocity

**Question:** how do normalized position, absolute position and the two velocity vectors relate? What scale and axis conventions should an adapter use?

| File | Recording steps |
| --- | --- |
| `amt-axis-paths.atpcap` | With one index finger, make separate straight slides: left→right, right→left, near→far, far→near. Pause for a second before and after each slide while maintaining contact, then lift. Repeat at a slow and a comfortable faster speed. Note the pad's orientation. |
| `amt-distance.atpcap` | Use a ruler beside the pad to identify two points about 30 mm apart, comfortably inside the sensing area. Slide between them three times along each axis. Record the actual intended separation and endpoint uncertainty in notes. Do not infer the distance from the on-screen trace. |
| `amt-edge-path.atpcap` | Move slowly near each edge, then briefly beyond the sensing boundary and lift. Keep the finger otherwise comfortable and avoid accidental second contacts. Repeat once. |

Analyze normalized versus absolute coordinate pairs and fit their affine relationship per device/axis. Compare native velocity against timestamped finite differences in the same units; measure signs, scale, lag and behavior at stops. Check clipping, out-of-range coordinates and state changes near edges. Fit using source timestamps within one device; compare arrival timing separately.

**Decision this informs:** physical-distance mapping, axis inversion and orientation, usable speed estimates, and whether firmware speed/history gates can be meaningfully tested after recalibration. Outer case dimensions and the word “absolute” do not establish physical sensing dimensions. Ruler-guided travel has uncertainty; retain that uncertainty rather than declaring exact millimetres.


#### 3. Relate ellipse shape to orientation

**Question:** do the axes and angle behave like a consistent contact ellipse, suitable for comparison to TouchStream's aspect/orientation features?

File: `amt-orientation.atpcap`. Place an index finger with its long direction approximately along the pad's vertical axis, hold 2 seconds and lift. Repeat at approximately 45° and 90°. Then make one slow comfortable roll/rotation while down, keeping the centre approximately stationary. Repeat the sequence three times; note which orientation each segment represents.

Analyze axis ordering, minor/major ratio, angle range/wraps, and continuity near circular contacts. Determine whether an axis swap accompanies an angle jump. Compare total/density changes during the same motions.

**Decision this informs:** angle normalization, handling of ambiguous near-circular orientation, and whether the callback's aspect ratio is a useful proxy for firmware t4. Do not assume anatomical direction is uniquely recoverable from an ellipse; 180° symmetry may remain.


#### 4. Test identity revisions separately from contact continuity

**Question:** which changes follow hand context, which follow contact geometry, and do any force a new contact generation?

File: `amt-identity-context.atpcap`. Keep one known index finger planted. Hold alone 2 seconds; add middle, ring, pinky and thumb one at a time, about 1 second apart; hold all briefly; lift the added fingers one at a time while keeping the original index planted; finally lift index. Repeat three times. If comfortable, make a second file with the opposite hand in the same region of the pad.

Analyze the planted contact's ID, raw fingerID, handID, state, position, shape, total and pressure together. Count label revisions within its continuous lifetime; distinguish label revisions from explicit retirements, disappearances and ID reuse. Record delay after each contextual change, without interpreting that delay as gesture activation.

**Decision this informs:** how strongly to weight Apple's anatomical hints and how to keep those hints separate from recognizer membership. The existing all_fingers capture already demonstrates revisions; this more controlled timing sequence is for attribution and repeatability, not reconfirming that revisions exist.


#### 5. Resolve short lifts and replacement lifecycles

**Question:** what does the parsed contact stream actually report across short interruptions, and when is continuity uncertain?

Files: `amt-brief-lifts.atpcap` and, only if earlier captures leave a specific gap, `amt-replacement.atpcap`.

For brief lifts, make five ordinary taps, then five quick lift/recontacts in approximately the same spot, then five slower lift/recontacts. For replacement, hold index and middle, lift index while keeping middle down, place ring nearby, then lift everything. Repeat three times. Human timing is approximate; do not claim a millisecond debounce threshold from these instructions.

Analyze every state, not only active samples: last active record, explicit inactive records, disappearance, next appearance, ID reuse, timestamp gaps and acquisition scalars. Preserve `(device, ID, generation)` and mark ambiguous continuity. Compare native source time with callback/capture arrival time.

**Decision this informs:** tentative arrivals, retirement, partial-lift ownership and conservative rearm. A missing idle frame is not proof of continuous physical contact. Neither this test nor Apple's enum directly recovers TouchStream's missing-scan/departure rules.


#### 6. Check repeatability across devices or transport

**Question:** is a calibration reusable, or does it need a per-device/transport profile?

If available, repeat only the strength ramp and axis paths on the second pad. Optionally repeat them on the same pad over a different transport, after explicitly verifying the transport changed. Add `-pad2`, `-bluetooth` or `-usb` to filenames and record routing/identity each time.

Compare scalar ranges, coordinate transforms, callback cadence, ID/state behavior and label revisions. Do not infer anatomical hand from deviceIndex or subtract source timestamps across devices. The earlier opposite-pad capture already supplies overlap evidence; new recordings are needed only for these missing comparisons.

**Decision this informs:** per-device normalization and which assumptions can be shared. One recording per model is not a general hardware compatibility claim.


#### 7. Optional deeper report provenance experiment

**Question:** which transport/report parser is active for these recordings, and which hints are already in that report before contact forwarding?

This requires additional capture tooling; the current contact .atpcap files cannot answer it retrospectively. Before asking the user to record, implement and verify a separate read-only full-frame/report capture path with source identity, report bytes, lengths and timestamps. Establish which layer that callback represents; a “full frame” name alone does not establish on-wire provenance. Correlate it with the contact callback using a justified matching method.

First use a short one-finger hold/context-change trial. Decode only the identified report format and compare labels/state/geometry with the forwarded contacts. In the recovered Compact V7 parser, wire finger code 7 maps to callback code 12; 512 selected Ghidra cases validate that unpacker behavior. This is not yet proof that the earlier code-12 samples used that parser or proof of where anatomical classification occurred.

**Decision this informs:** provenance of fields and which transformations Apple adds. Driver replacement, exclusive access and OS-event suppression are outside this experiment.

## HID report truncation evidence

Original source blob: `e4233251f6a8c831949f209e72c451d17f148207`.

#### USB payload capture: relative mouse reports, not contact frames

Preserved `captures/usb_single_interface_payload.json`. The approximately 15.07-second exclusive single-interface recording contains 384 successful eight-byte reports, all report ID 2, zero dropped reports. Payloads arrived from roughly 0.14s through 6.33s; the remainder of the capture contains no reports.

The captured HID descriptor declares ID 2 as a relative mouse report: byte 0 report ID, byte 1 three button bits plus padding, bytes 2/3 signed eight-bit relative X/Y, bytes 4–7 declared constant padding. Captured byte 1 toggles between 0 and 1; relative X/Y change during movement. Bytes 4–6 are always zero; byte 7 varies between 2 and 3 despite its descriptor declaring constant padding, so its actual meaning remains unknown. It must not be labeled finger count/phase without evidence.

Descriptor additionally advertises vendor input IDs 0x3F (16 bytes payload) and 0x44 (1387 bytes payload), but neither was received. No ID 5 / 50-byte Windows-format reports or contact-coordinate records were captured. This establishes USB mouse-report delivery while seized, not raw multitouch delivery. A next investigation could determine the correct model/transport-specific multitouch-mode negotiation before sending any feature report; blind Linux feature-command transplantation is not justified by this payload alone. Current capture sends no mode-changing commands.


#### USB feature 02 01 request: no contact reports observed

Preserved `captures/usb_multitouch_mode_request.json`. Exclusive open succeeded; at +2.071s, after 53 baseline reports, the feature request ID02 bytes0201 returned success. The full ~15.07s recording contains 434 successful eight-byte ID2 reports /3472 bytes, zero drops, and no other report ID/length. Packets arrived ~1.47s to8.66s. Thus no12+9N touch packets, ID3F/44 reports or Windows-format contact packets were delivered after the request. Exclusive close succeeded. A successful feature call did not demonstrate a mode transition or raw contact delivery. This result cannot distinguish ignored command, alternate transport/interface routing, or macOS descriptor/report filtering; do not claim mode switched based on return code.


#### Original pre-copy report bytes recovered

Successful normal-ownership FBT capture1792304085:442 reports,188 length21 and254
length30. Every payload has ID02 and fits Linux USB Trackpad2 prefix12 +9N.
Decoded contacts using hid-magicmouse.c signed13-bit coordinate packing, tracking
IDs, pressure, dimensions, orientation and state. Pressure range0..32; X-1220..823,
Y-2019..1630;673 state80h down contacts,23 other lifecycle states. Tracking IDs are
identifiers, not anatomical finger labels. Contact payloads are present beyond
byte8 before descriptor-sized user queue processing. This validates the raw-data
lead under normal ownership; usable access with SIP enabled remains unresolved.

Preserved raw log and decoded/truncated actual-length packets as
captures/usb_original_unseized.log and usb_original_unseized.json. Added offline
decode-original-report.py (stdlib, works with systemPython3.9), validated against
all442 real report blocks/end-count. It excludes bytes beyond actual reportlength.
First DTrace timestamp label uptime_ns has not been aligned to system uptime;
new template calls it trace_timestamp_ns and includes walltimestamp unix_ns for
comparison against app capture start/end timestamps.

Prepared --seized variant:30s trace with same exact-device filtering, no firmware
commands, while user starts existing app15s single-interface seizure (mode checkbox
off) after READY. User moves one/two fingers during/after seizure. This is the next
live check of raw pre-copy contacts while OMS/native events are blocked. No new
seizure or trace activated during preparation; no app rebuild required.


#### Definitive paired capture: full contacts survive HID seizure

Original FBT trace1792304367 logged1146 valid ID02 packets. App seizure window
Unix1792304374.20816..1792304389.232792 contains668 original packets and exactly668
app callbacks (no app drops). All668 app payloads match the first8 bytes of their
corresponding original packet, in order. Original seized packets:265 length21
(one contact),341 length30 (two),2 length39 (three),60 length48 (four). Decoded
pressure range0..59.478 more original packets arrived after release.

This directly establishes complete packets reach IOHIDDevice during the exclusive
session and userspace receives a truncated8-byte prefix, consistent with the
64-bit report-handler element from the descriptor. Contact data itself is not lost
at the USB transport during seizure. Decoding is Linux Trackpad2 layout, not yet
validated anatomical classification. Capture is kernel tracing with SIP disabled;
this does NOT supply a production SIP-enabled acquisition method.

Preserved usb_original_seized.log, usb_original_seized_app.json,
usb_original_seized.json (actual-length payloads + decoded contacts and paired
summary). No additional touch test is needed to establish this mechanism. No
runtime interpreter or SIP-on driver has been installed by these experiments.

## Compact V7 native telemetry parity

Original source blob: `3ce47f175781ee9b6dba4edd9607bedfaa9f5e0b`.

#### Outcome

The DriverKit decoder now reconstructs **all telemetry fields exposed by research prototype's
OMS contact model**, using the installed Apple Compact V7 unpacker and contact filler
as an independent reference. Build and 68 tests pass. A fresh right USB takeover
recording passed all 1,686 contacts across 18 compared fields with zero mismatches.
See TELEMETRY_PARITY_LIVE_RESULT.json for capture hash, errors and scope.
A matching live Bluetooth recording remains to be checked.

The native scalar reconstruction includes total, density and the native hand-ID
default. Existing before/after recordings are retained unchanged.


#### Recovered contract

| Field | Reconstructed behavior |
| --- | --- |
| Tracking ID | Contact byte8 bits0–3, independent of finger classification |
| Finger type | Byte3 bits2–4; native maps7→12; other codes unchanged |
| Hand ID | Native Compact V7 path supplies1; not a recovered anatomical hand classifier |
| State | Byte3 bits5–7, all eight OMS states; native immediate0-after-active transition handled |
| X/Y | Signed13-bit values, native2× conversion and Y+5000; native clipping and normalization using device bounds |
| Absolute position | Native signed position /100, with native clipping |
| Major/minor | Native piecewise integer quadratic/linear unpacking, followed by /100 |
| Angle | Native angle code ×4096, then ×pi/32768 (equivalent code×pi/8) |
| Total | Native nonlinear size-byte conversion, then /256 |
| Pressure | Native nonlinear pressure-byte conversion; not simply the raw byte |
| Density | Native integer formula with family0x81 parameters600/430, then /256 |
| Absolute velocity | Sensor-timestamp delta, native float subtraction,1/8 quantization, signed16 saturation and native zero-vector sentinel handling |
| Normalized velocity | Native operation order and surface bounds, reconstructed from quantized velocity |
| Source time | Unwrapped21-bit millisecond compact-header clock; rollover handling |
| Source frame | Receiver-session sequence, retained separately from app capture sequence; origin can differ from old OMS listener |

Density formula in native integer units:
`400*total / (max(600, floor(sqrt(max(600,major)*max(600,minor)))) - 430)`.

As an independent check against the existing real BEFORE recording, all623
contacts fit these normalized/absolute coordinate bounds to float precision,
and all reported Hand ID1. This corroborates calibration; it is not a same-packet
comparison with the older AFTER recording.

Measured Sensor Surface Descriptor on both known pads:
`f03c0000202b000044e352ffbd1ee426`.
Native bounds: Xmax7869/Xmin−7356, Ymax9956/Ymin−174; surface15600×11040.
research prototype checks the selected service descriptor **before** takeover and refuses
an unknown calibration instead of silently applying these values to another pad.


#### Independent verification

Apple framework8440.5, UUIDB172DB85-9E88-3A4E-AB6E-B458FD373A58, macOS15.7.4/24G517:

- All256 possible values for **each** major/minor/size/pressure byte match the native
  unpacker (1,024 scalar comparisons).
-576 independent density input cases match the native integer density routine.
-256 full native-filled contacts match the Swift adapter on **both** USB and Bluetooth
  wrappers, including clipping, code7→12, states, position, hand, axes, total,
  pressure, density and angle.
-96 two-frame native-reference cases match reconstructed velocity and state,
  including all states, the extra/sentinel bit, zero motion, negative motion and
  sensor-edge clipping. Native current-position velocity uses **unclipped** input
  against the prior clipped output; this distinction is preserved.
- Tests cover source-clock wrap, per-pad isolation, raw byte preservation, optional
  metadata compatibility, and legacy captures without DriverKit provenance.

The oracle uses only the current process's mapped framework, synthetic structs and
local calibration state. No kernel tracing or SIP changes. research prototype itself uses
portable Swift conversions, not private offsets or copied Apple machine code.
See tools and reproducible commands.


#### Capture fidelity

New contacts retain optional `telemetry.driverKit`:
- `conversionVersion:2`
- Original nine contact bytes and full enclosing report bytes
- Compact sensor tick value
- Velocity availability/reset status

Converted fields are recorded alongside the bytes. Earlier raw9-byte captures can
be reinterpreted for scalar recovery; captures made before bytes were retained
cannot recover discarded bits. The old AFTER_takeover capture lacks them.
The normal app capture/replay model remains unchanged except optional metadata.


#### Limits kept explicit

- This is parity with the **contact callback contract**, not raw electrode images
  or the whole Apple gesture/classification pipeline.
- The native parser's hand1 constant and finger12 category retain their native
  values without asserting anatomical meaning.
- Session counter origins differ. Absolute original native callback timestamps from
  before takeover cannot be reconstructed merely by matching counter numbers.
- First-frame/gap/stale-frame velocity resets are intentional safety boundaries;
  reference checks identify those cases rather than fabricating continuity.
- Missing-contact cleanup and any upstream Apple binary filters need live recording
  evidence. Synthetic decoder parity does not prove those delivery behaviors.
- Continuous DriverKit ownership is unchanged; explicit release and lifecycle
  safeguards remain. No automatic hardware activation occurred during this work.

##### Follow-up installation check

The reported persistent notTouching display was observed while the installed app
was still the 08:01 build, preceding the 09:07 render fix. On the next follow-up,
69 tests passed including single-pad selection guards; the installer was rerun to
update `/Applications/research prototype.app`. New both-pad recording not yet located:
the capture folder still contains the earlier 08:56 right-only recording.

## Contact lifecycle capture findings

Original source blob: `80bff2bfccde2e30425599cfc165e6cf3239d415`.

#### What we learned

Your distinction between revisable finger estimates and a stable gesture owner remains a useful design. These recordings provide concrete lifecycle fixtures for a future shadow recognizer. They do not themselves demonstrate whether any gesture activated or stayed selected.

| Capture | Observed contact structure | Rewrite implication |
| --- | --- | --- |
| palm-held-cohorts | One continuous contact8 for14.619s; four finger-pair cycles while it stays down; peak3 | Raw all-up blocks independent finger-cohort rearm while an incidental palm remains |
| partial-lift-replacement | Three episodes each containing3→2→3; two tracked IDs survive each replacement | A later third contact must not silently retarget an activated owner; acquisition and late-arrival policy need separate tests |
| five-to-two-rearm | Two5→2→5 sequences; IDs8/9 survive each two-contact interval | Retain member lifetimes and distinguish peak size, current membership and possible rearm |
| opposite-pad-held | Route1 contact held0–6.457s; route0 completes three pairs during it | Owner/reset scope must be per pad unless a specific bimanual gesture owns both |

Route indices identify capture routing, not anatomical left/right.


#### Palm-held: raw label filtering alone is insufficient

Contact8 stays active from the first recorded frame until explicit release at14.619s. Its label histogram is:

| Raw code | Active samples on contact8 |
| --- | ---: |
| 6 | 1,198 |
| 1 | 54 |
| 12 | 48 |
| 0 | 1 |

There are19 label revisions on this same lifetime, including repeated6↔1 changes while it is the **only** active contact. For example, code6 becomes1 at3.617s and returns to6 at3.875s; a second such interval runs4.608–4.832s. Code12 is retained as an uninterpreted raw value; this investigation has not established its anatomical meaning. It must not be forced into the1–6 UI convention.

The four finger-pair intervals are approximately1.277–3.584s,5.012–6.959s,8.274–10.097s and11.548–13.550s, measured from the first captured arrival. Their individual landings/releases are slightly staggered. The palm-like contact remains through every gap between them; the only raw-empty transition is its final release.

Therefore an implementation that ignores **only the current code6** will intermittently treat this continuous contact as a thumb or unknown. A future exclusion decision needs retained lifetime/geometry evidence and an explicit uncertainty policy. Do not globally blacklist code1 or12, and do not silently change an active owner's membership when the label changes. Whether this recorded contact is truly a palm comes from the intended trial, not from firmware-equivalent classification.


#### Partial lift and replacement: three repeated examples

All times below use the capture arrival clock. The surviving IDs stay active while one contact lifts and a new contact joins.

| Episode | Original IDs | Partial lift | New third contact | Final raw-empty |
| --- | --- | --- | --- | --- |
| 1 | 1,9,11 | 11 leaves1.429s;1/9 survive | 6 joins2.396s | 5.321s |
| 2 | 5,8,10 | 8 leaves7.303s;5/10 survive | 6 generation2 joins8.314s | 9.416s |
| 3 | 2,3,7 | 2 leaves12.532s;3/7 survive | 6 generation3 joins13.961s | 15.232s |

There are21 raw label revisions overall. A peak count or instantaneous count alone cannot tell an original member from a new arrival. Preserve `(device, contactID, generation)` plus the activated owner's explicit membership. The same raw ID6 is reused across separate episodes and must not inherit old ownership.

These repetitions include partial holds of approximately0.87–1.42s before the first lift. Capture start and sparse idle delivery prevent precise claims about every physical first-down time; they are not a measured acquisition or activation delay.


#### Five to two: useful steady survivors and tentative contacts

First sequence: IDs8/9 survive while the other three leave by1.271s. Three new contacts join3.262–3.274s; all lift by5.580s. Second sequence: the ordinary five-contact set is established by7.717s, falls to IDs8/9 by9.483s, then returns to five by11.452s before final release13.590s.

There are two additional one-sample lifetimes during the second landing: ID9 generation2 and ID8 generation2, each lasting about11ms, with pressure0 and raw label0. Both have explicit inactive records before their later generations start. The analyzer correctly retains them as separate observed lifetimes. These are evidence for tentative input handling and ID-generation tests, not proof that two real fingers physically tapped or that the tracker lost established contacts. Do not invent a merge rule from this one capture.

The stable two-contact intervals are about1.99s and1.95s. Raw captures cannot establish whether the TouchStream five-finger exception, or any proposed Apple equivalent, would activate in those intervals. Its epoch count and action/option/timing gates are not present in this telemetry.


#### Opposite pad: reset independence is directly testable

Route1 has one continuous contact until6.457s. Route0 completes pairs at1.491–2.548s,3.100–4.394s and4.967–6.015s. Each route0 pair ends with explicit release while route1 is still held. A hypothetical global all-up reset could not rearm between those pairs. A per-pad reset could.

Use arrival times for this cross-device comparison. Native source timestamps remain per-device evidence and are not subtracted across devices.


#### Data quality and limits

All observed routes have zero active-frame gaps over the declared100ms budget, timestamp regressions, duplicate IDs, invalid samples or device-identity changes. All observed lifetimes end explicitly. Telemetry is present for every active sample.

The existing analyzer still conservatively marks several lifetimes start-censored:1 palm-held,7 replacement,8 five-to-two, and6+1 across the two routes of opposite-pad. That includes contacts present in the first frame and first observations after sparse idle frame delivery. These flags were retained; no thresholds or earlier test expectations were changed to make a report pass. Release/member overlap evidence is stronger here than a claim about exact physical landing time.

Physical sensing dimensions remain uncalibrated, so this pass makes no millimetre drift or distance assertions. Pressure0 at acquisition is a recorded device value, not a force threshold recommendation.

## Native identity and device ownership requirements

Original source blob: `bb4ed69a3c60cc0c803681177e822d0751853b54`.

#### Required behavior

- Zero selected devices is valid: native input, no takeover request.
- One or two selected devices is valid even with other pads connected.
- Selection changes apply to individual devices, without routine extension
  installation/removal or repeated approval dialogs.
- Identify supported model/report formats and transports, not personal serials.
  Runtime registry identity distinguishes individual connected instances.
- Unsupported models remain native until their protocol/calibration is validated.
- Preserve normal native gestures on unselected pads. Reimplementing a pointer
  does not count as restoring Apple's native touch/gesture path.
- Release, process loss, sleep and disconnect retain explicit recovery semantics.

## Driver transport and native telemetry comparison

Original source blob: `6b967b327cdf2faa7004657348d2f3e8ea4f961c`.

#### Primary protocol references

- [Linux hid-magicmouse decoder](https://github.com/torvalds/linux/blob/master/drivers/hid/hid-magicmouse.c): positions, pressure, extent bytes/scaling and transport headers.
- [VoodooInput packed report layout](https://github.com/acidanthera/VoodooInput/blob/master/VoodooInput/VoodooInputSimulator/VoodooInputSimulatorDevice.hpp): nine-byte bitfield, finger and full state bits.
- [VoodooInput finger enum](https://github.com/acidanthera/VoodooInput/blob/master/VoodooInput/VoodooInputMultitouch/VoodooInputTransducer.h): finger-type mapping.
- [VoodooInput report construction](https://github.com/acidanthera/VoodooInput/blob/master/VoodooInput/VoodooInputSimulator/VoodooInputSimulatorDevice.cpp): orientation4 corresponds to pi/2.

These are reverse-engineered implementations, not a published Apple guarantee.
Earlier original full USB capture has finger codes0,2,3,4 and state codes0–7;
this corroborates field layout, but does not replace a per-finger labeled trial.


#### Verification

research prototype build and61 automated tests passed, including signed coordinates,
independent finger/tracking IDs, all state codes, geometry/orientation conversion,
velocity reset behavior, raw-byte JSON round-trip and legacy telemetry decoding.
The visual result, reported labels and derived velocity still need a live check.
Driver and ownership machinery are unchanged; no activation performed during this fix.

## Driver notification transport investigation

Original source blob: `92fff4e5848ea2b110f400f5405afe694ec191c7`.

#### Verified current-public-API result

Tools/TransportNotifications is a standalone read-only public general-interest
observer. During45s, the existing two receivers advanced3,690 and3,646 reports,
with zero general-interest or property-change messages. Both pads were Bluetooth
in this run. This disproves relying on current SetProperties publication alone to
wake the app. It does not measure CPU use or report-to-app latency, and does not
prove every possible IOKit notification mechanism impossible. Saved JSON is
NOTIFICATION_TRANSPORT_RESULT.json. The initial idle run had no advancing reports
and is not used as active-frame evidence.

The installed public DriverKit SDK gates SendIOMessageServicePropertyChange behind
PRIVATE_WIFI_ONLY. Apple's kernel implementation has the same restriction. Do not
expose private declarations or call private RPC IDs as a shipping transport.
IOServiceAddInterestNotification is public on the app side, but observing messages
does not cause SetProperties to emit them.

Sources:
- https://developer.apple.com/documentation/iokit/1514866-ioserviceaddinterestnotification
- https://github.com/apple-oss-distributions/xnu/blob/main/iokit/DriverKit/IOService.iig
- https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/IOUserServer.cpp


#### Routes

###1. Improve the existing transport without new permissions

Use IOServiceAddMatchingNotification for receiver appearance/removal and cache
service handles, avoiding full IORegistry discovery every16ms. Arrival of a new
source must not implicitly accept replacement frames: existing explicit Sync
semantics remain unchanged.

Publish changing data only when reports/state change, keep static metadata out of
repeated payloads, and check sequence before reading unchanged rings. Keep the
bounded ring, generation/sequence validation and explicit gap handling. A suitably
measured active/idle polling strategy can then reduce redundant work. These changes
still poll for contact data; they are not an OMS-like callback transport. Shorter
poll intervals alone reduce delay at the cost of more work.

This is the strongest immediate route using exactly the current permissions.
Before implementation, record receive-to-consumer latency percentiles, batches,
idle/active wakeups, CPU and gaps for both transports. Capture timestamps currently
preserve report timing; they do not directly measure processing latency.

###2. Public vendor-defined HID report relay — promising, not yet validated

A driver-side IOUserHIDDevice provider could publish a data-only, vendor-defined
HID collection. Send one compact contact record per report using handleReport;
consume via IOHIDDeviceRegisterInputReportCallback in the app. This uses the system
HID client path, not a custom DriverKit UserClient. Use no keyboard, pointer or
consumer-control usages; the relay must produce no native UI actions.

Potential advantages: callback-driven delivery, no idle contact polling and no
full64-record registry copy on each poll. This still crosses OS/HID queues and
copies data; efficiency/latency must be measured, not assumed equal to OMS.

It requires additional HID device-family authorization/provisioning. The existing
Apple-issued driver profile has no com.apple.developer.driverkit.family.hid.device.
Apple also documents com.apple.developer.driverkit.family.hid.virtual.device as a
requested entitlement; applicability to this topology/OS must be checked rather
than assuming the device-family checkbox alone grants permission. No capability
was enabled, request submitted, profile regenerated or relay installed here.
This avoids the pending UserClient entitlement but may introduce another approval
requirement. App Input Monitoring requirements also need live validation.

Sources:
- https://developer.apple.com/documentation/hiddriverkit/iohiddevice
- https://developer.apple.com/documentation/hiddriverkit/iouserhiddevice
- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.driverkit.family.hid.device
- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.driverkit.family.hid.virtual.device
- https://developer.apple.com/documentation/iokit/1588666-iohiddeviceregisterinputreportca

###3. Other notification/shared-memory approaches

IODataQueueDispatchSource has producer/consumer notification support, but no public
app bootstrap for mapping this driver's memory and registering its callback was
established without a custom client. DriverKit's service/system-state notification
sources are not a general app message bus. App-style Foundation notifications/XPC
must not be presumed available from the restricted DriverKit runtime. These are
not established alternatives for the current permissions.

Do not repeatedly call RegisterService/rematch hardware per packet merely to force
matching notifications: that invokes driver matching machinery, not lightweight
report delivery, and works against the efficiency/ownership goals.

## Process exit and native input restoration

Original source blob: `7721427e48aa4bdf5e100350fce538335a22ec81`.

#### Established evidence

- v22 Release/Exit submits a system-extension deactivation request. The user reports
  an administrator password is required. That is extension removal authorization,
  not a touch-parser or ordinary HID Close permission.
- DEVICE_HANDOFF_V12_RESULT.json physically established Bluetooth native movement
  returning while USB remained controlled. That experiment used an authorized
  UserClient to close/terminate the receiver and request provider matching. It is
  not evidence of seamless handback without a UserClient or successful USB handback.
- v22 intentionally compiles no UserClient. Registry telemetry is readable, but this
  does not provide an app-to-driver release command channel.


#### Public API findings

Apple documents RemovableSystemExtensions as allowing application deactivation
without administrator authorization. Its System Extensions policy payload requires
user-approved MDM. This is useful for managed fleets, not a general consumer fix.
https://developer.apple.com/documentation/devicemanagement/systemextensions
https://support.apple.com/guide/deployment/depa5fb8376f/web

The SDK's IOService::SetProperties is a driver-to-service RPC and must not be
mistaken for an app-to-driver command endpoint. The SDK places UserSetProperties
behind PRIVATE_WIFI_ONLY. Apple's public IOUserServer implementation supplies no
public forwarding endpoint for an arbitrary app property command. Do not invent
an unsupported public override or claim reading IORegistry implies write/control.
https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/IOUserServer.cpp

A standalone, inert property probe was prepared in /tmp/amt-property-probe.swift.
It found no active v22 coordinator and sent no property write. Therefore no live
write-path result exists; do not describe it as a tested permission denial.

## Capture interpretation and anatomy

Original source blob: `25d25ebf175c243ac8c18188762c0960551aa1cc`.

#### Results from the six planned trials

| Recording | Observed result | Interpretation |
| --- | --- | --- |
| Index taps | 10 lifetimes; 226 active samples, 224 labeled 4 and 2 labeled 0; two 0→4 revisions. | The user declares these index taps, but code 4 means ring under the UI convention. Repeatable classification is not anatomical accuracy. |
| Thumb taps | 10 lifetimes; 219 active samples, 215 labeled 1 and 4 labeled 0; four 0→1 revisions. | Consistent with the user's thumb trial and UI convention, but not proof the convention/estimate always holds. |
| Stationary hold | One continuous lifetime, about 1,766 ms; one 0→4 revision. | Only the `maximumIdentityChanges=0` assertion fails. Duration, lifetime count and contact count pass. This invalidates the zero-revision expectation; it is not evidence that the physical contact broke. |
| One-finger motion | One lifetime, about 821 ms; labels 5→4→3→2 while only one contact is active. | Revisions also occur without another contact landing. More-finger context is not the only situation in which labels change. |
| Staggered/partial lift | Two lifetimes, peak 2; one partial-lift frame; landing spread about 856 ms. | The input contains the requested membership transition. The spread is longer than the suggested 200 ms stimulus; this does not validate any chosen acquisition window. |
| Palm observation | One lifetime; 123 active samples, first 4 labeled 1 then 119 labeled 6. | Acting on the earliest apparent thumb label could misinterpret a declared palm contact. |

All selected-device active samples have identity telemetry. The analyzer found no active-frame gaps over the declared 100 ms budget, regressing timestamps, duplicate IDs or invalid samples in these recordings. Original recordings and the original trial plan were not changed to make assertions pass.

Five planned trials pass their observation checks. The hold trial fails the strict label-stability check only. That failure is useful data about the hypothesis, not a reason to throw away the capture.

Physical dimensions are still uncalibrated in the supplied plans. No conclusion about drift in millimetres or the suitability of the keyboard experiment's 3 mm boundary is made here.


#### `all_fingers.atpcap` directly demonstrates context revisions

This recording contains both capture routes. Treat them independently: raw device IDs and touch IDs are device-scoped.

| Capture route | Frames | Active contact samples | Peak contacts | Lifetimes across the recording | Label revisions |
| --- | --- | --- | --- | --- | --- |
| 0 | 599 | 2374 | 5 | 6 | 7 |
| 1 | 653 | 2358 | 5 | 9 | 13 |

The total 20 revisions include 13 transitions from raw0 to a nonzero code and 7 nonzero-to-nonzero changes. This is a numeric distinction; it does not infer the driver's undocumented meaning for0. All active samples have telemetry, and neither route has the analyzer's continuity/quality errors.

Examples of **existing contacts changing label without lifting**:

| Route | Stable contact:generation | Label change | Simultaneous contacts | Time after latest context landing, same device source clock |
| --- | --- | --- | --- | --- |
| 0 | 1:1 | 4→2 | 2 | about 11 ms |
| 0 | 9:1 | 4→3 | 4 | about 11 ms |
| 0 | 11:1 | 5→4 | 4 | about 11 ms |
| 1 | 9:1 | 5→4 | 4 | about 11 ms |
| 1 | 5:1 | 5→4 | 5 | about 12 ms |
| 1 | 6:2 | 3→2 | 5 | about 12 ms |
| 1 | 9:1 | 4→3 | 5 | about 12 ms |

These events have matching active-contact continuity and generation. There is no synthetic finger-up/down caused by relabeling. The same changes occur about 11.1–12.9 ms after the latest landing on the capture-arrival clock. Source clocks are compared only within a device; their absolute values differ across devices and must not be mixed.

This supports context-sensitive revisions, but does not establish the internal inference algorithm or whether it recomputes on every frame. The capture supplies a raw estimate each sample; an unchanged output cannot reveal whether the internal estimate was recomputed.

It also does not prove that all final labels are anatomically correct. The index trial's stable but wrong label is a direct counterexample to using persistence alone as confidence.


#### The gesture model the user described

Keep these separate:

1. **Observation:** position, stable contact key and latest anatomical guess continue to update.
2. **Acquisition:** while uncommitted, consider arrivals, geometry and current label evidence. A first arriving finger is not necessarily the whole intended chord.
3. **Commitment:** freeze the selected semantic gesture and its owning contact keys. Later label changes do not replace the gesture or transfer output ownership.
4. **Partial lift:** remaining members do not become a newly recognized smaller chord. The cohort remains committed or draining under the action's defined finish policy.
5. **Rearm:** require all-up on the owning hand/surface before a new cohort. Until reliable hand segmentation exists, a conservative implementation can use all-up on that routed pad, including quarantined late arrivals. Do not require the opposite pad to lift its independent modifier.

This describes **gesture latching**, not label freezing. The exact action finish rule—such as when a held mouse button releases—must be specified separately from when another chord can start.

These raw-playground captures contain no gesture-recognition/commit decisions. They therefore cannot prove the full TouchStream latch/rearm law, a one-second gesture delay, or a particular existing recognizer's release semantics. No fixed wait is inferred from the 11–12 ms label revisions. Testing those laws needs a shadow recognizer decision trace or actual gesture/output events alongside the contacts.

## Accessibility and signing identity

Original source blob: `76706c44f6d78ecbece17a4b8a98bd563b3952c1`.

#### Accessibility appears enabled but the checkbox refuses

A verified local failure was a stale TCC code requirement: the approved identity
was `Apple Development`, while `/Applications/research prototype.app` was now signed with
Developer ID Application by the same developer. The TCC log explicitly reported
`Failed to match existing code requirement` for `ink.ranna.research prototype` and
`kTCCServiceAccessibility`. Enabled-looking duplicate rows did not grant the new
signing identity access. This is distinct from a missing DriverKit entitlement.

The targeted repair is to quit research prototype, reset only its Accessibility approval
with `tccutil reset Accessibility ink.ranna.research prototype`, then add/enable the current
`/Applications/research prototype.app` in System Settings > Privacy & Security >
Accessibility and relaunch. The reset does not grant permission; the user approves
the current app in System Settings. Do not reset all apps, edit the TCC database,
or add private TCC entitlements. Keep installed builds signed consistently with
the existing Developer ID identity to avoid repeating the development/release
identity mismatch. Other historical bundle identifiers may have separate rows.

## Acceleration source provenance

Original source blob: `ae3a6cc97dfed323ad0a840c031e4c8674d52ba9`.

### Acceleration source audit

The numerical experiment is informed by Apple's published IOHIDFamily source at
commit `777ccd9698845aadf711e32d843c8c9b777431d9`, retrieved 2026-10-20. Upstream
source files are not bundled or linked into the app. This is an independent,
small mathematical model plus a diagnostic recorder, not a claim that this source
revision is the exact implementation running on the installed OS.

Primary sources:

- [IOHIDAcceleration.cpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDEventSystemPlugIns/IOHIDAcceleration.cpp): `IOHIDPointerAccelerator::accelerate` floors the Euclidean delta magnitude, applies a timing factor **only when fixedMultiplier equals 1**, clamps velocity to at least 1/65536, then scales X/Y by accelerated velocity / input velocity.
- [IOHIDAccelerationAlgorithm.cpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDEventSystemPlugIns/IOHIDAccelerationAlgorithm.cpp): parametric coefficient interpolation, polynomial, tangent line and square-root continuation. The actual polynomial uses `(parabolicGain*x)^2`, `(cubicGain*x)^3`, `(quarticGain*x)^4`; treating these gains as ordinary polynomial coefficients changes the result. Follow the executable source, including its root-only case, rather than assuming its introductory comments are exact.
- [IOHIDAccelerationAlgorithm.hpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDEventSystemPlugIns/IOHIDAccelerationAlgorithm.hpp): cursor scale 96/67.
- [IOHIDAcceleration.hpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDEventSystemPlugIns/IOHIDAcceleration.hpp): nominal algorithm frame rate 67. This differs from a device's report-rate property; zero report rate disables timestamp normalization in the pointer accelerator.
- [IOHIDPointerScrollFilter.cpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDEventSystemPlugIns/IOHIDPointerScrollFilter.cpp): uses user curves before driver curves; normally tries parametric acceleration before table fallback, subject to explicit algorithm overrides. Pointer resolution and multiplier are service properties; tracking acceleration is selected through the device's acceleration type and fallbacks.


#### What was actually inspected locally

Read-only IORegistry snapshots found three AppleMultitouchDevice services, each
with ten HIDAccelCurves entries, HIDPointerResolution=26214400 (400 in 16.16),
HIDPointerAccelerationMultiplier=48545 (about 0.7407379), and
HIDPointerReportRate=0. IOHIDSystem's HIDTrackpadAcceleration was 196608 (3.0).
These are a point-in-time observation, not constants to hardcode into an app.
The generated snapshot is under build/PointerAccelerationProbe/installed-settings.json;
run `snapshot` or `record-baseline.sh` to get current settings.

Provider/global properties do not prove the effective user/service overrides,
filter algorithm, additional third-party changes, proprietary multitouch motion
conditioning, display scaling or WindowServer processing. The probe currently
implements the parametric branch exposed by these pads, not Apple's table
fallback, scroll acceleration, subpixel accumulation/rounding or a native output
injection path. It rejects missing parametric curves rather than substituting a
made-up curve. The model initializes first-sample timing deterministically instead
of reproducing unspecified/uninitialized state in the published C++ constructor.

OMS coordinates are normalized contact positions, not unaccelerated HID pointer
counts. Resolution alone does not establish their conversion. Millimetre inputs
therefore require an explicit counts-per-mm assumption. `resolution / 25.4` is a
useful initial hypothesis, not a measured fact. Do not label a fitted model
"Apple Default" until held-out native recordings at several speeds/settings
support that claim. Do not fit and validate solely on the same strokes.


#### Other projects

- [INRIA libpointing](https://github.com/INRIA/libpointing): relevant comparison framework; its README describes OS transfer-function replication and references the UIST 2011 characterization work. Its stated license is GPLv2-or-later, with alternative licenses available by request. No dependency or source from it was added.
- [Mac Mouse Fix PointerSpeed.m](https://github.com/noah-nuebling/mac-mouse-fix/blob/master/Helper/Core/PointerSpeed/PointerSpeed.m): useful evidence that acceleration parameters can be selected through HID service properties. The file is under the project's MMF License and contains unfinished paths; it is not a drop-in ready trackpad engine. No code from it was imported and none of its setting-changing operations is performed.

The two-finger pointing / three-finger dragging / four-finger scrolling proposal
is a separate recognition/output task. Pinch can coexist with centroid translation,
but gesture formation, typing/chord overlap and latching need separate tests.
This harness neither implements those gestures nor verifies the pasted chat's
claims about exact historical FingerWorks semantics.


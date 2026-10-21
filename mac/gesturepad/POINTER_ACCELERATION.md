# Apple pointer acceleration: code findings and first native recording

Documented 2026-10-20 for GesturePad / future TouchStream-style input work.

Apple publishes a useful downstream pointer accelerator. We can model its
parametric branch using coefficients exposed by this Mac's trackpad services.
The remaining question is how native multitouch processing turns contact motion
into that accelerator's input counts—and how later event/display processing
changes the result. We have a working measurement harness and one usable native
recording, not a proven reproduction of Apple's complete trackpad behavior.

## 1. Sources and scope

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
related-project notes are in [the source audit](Tools/PointerAccelerationProbe/SOURCES.md).

## 2. Settings selection matters as much as the equation

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

## 3. The pointer calculation

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

## 4. Parametric curves: the details easy to get wrong

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

## 5. Table fallback is a different model

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

## 6. Pointer output must avoid accidental second acceleration

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

## 7. Four-finger scrolling needs a separate transfer function

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

## 8. What this Mac exposed in the test snapshot

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

## 9. First native recording: useful, but not calibration yet

Session: [native.7YcQ2s](build/PointerAccelerationProbe/native.7YcQ2s).

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

## 10. Implications for TouchStream-style gestures

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
[TWO_FINGER_MOUSE.md](TWO_FINGER_MOUSE.md).

## 11. Recommended next work

First analyze alignment and contact-to-count scaling while holding the captured
Apple coefficients fixed. Distinguish a scalar sensitivity mismatch from
speed-dependent curve error and anisotropic X/Y conversion. Inspect raw event
positions versus sampled cursor positions and compare stroke totals alongside
per-interval errors.

Then repeat native trials at several tracking settings and speeds, including
held-out strokes or a separate recording. Fit on one subset and report validation
on another; fitting scale, latency and curve coefficients on the same data can
hide an incorrect model. Include both Bluetooth and USB before making transport-
independent claims.

Only after that evidence supports it, build a small opt-in two-finger pointer
experiment using the measured transfer function. Evaluate small targets, long
travel, slow precision, fast reversals and finger-count changes. Keep four-finger
scroll and pinch as separately testable work. Until then, describe this model as
Apple-source-based experimental acceleration rather than a verified Apple Default.

## 12. Tools and verification

[Probe README](Tools/PointerAccelerationProbe/README.md) contains capture/conversion
commands. The standalone model has 14 numerical/data-handling tests; the recorder
builds without warnings. Tests cover analytic polynomial/tangent/root vectors,
coefficient interpolation, timing/fixed-multiplier behavior, units, subpixel/zero
motion and bad/incomplete recordings. They establish internal model behavior, not
native equivalence. No new app build or live input activation is needed to read
or reproduce the offline analysis.

[libpointing](https://github.com/INRIA/libpointing) is a relevant comparison
framework; its README states GPLv2-or-later and describes alternative licensing by
request. [Mac Mouse Fix's pointer code](https://github.com/noah-nuebling/mac-mouse-fix/blob/master/Helper/Core/PointerSpeed/PointerSpeed.m)
is useful background on HID service settings, but has its own license and some
unfinished paths. Neither project's code was imported or added as a dependency.

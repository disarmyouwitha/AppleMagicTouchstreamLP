# Four-finger scroll

Added to GesturePad on 2026-10-20 at the user's request, after hardware acceptance
of accelerated, latched two-finger mouse movement. This is the first scroll
hardware test, aimed at native Magic Trackpad acceleration and fine control.

## Use

Enable **Trackpad Takeover**. **4-finger scroll** defaults on with it, alongside
**2-finger mouse**. Start at **1.00×** scroll sensitivity. Land four fingers,
then move vertically or horizontally. Flick and lift to coast; touch the same
pad again to brake. Lift all before starting a different
kind of gesture. Uncheck the scroll checkbox to disable only scroll recognition;
Ctrl-Option-R still releases takeover.

Both feature checkboxes default on for restored takeover at process launch and
for a fresh explicit takeover enable. Manual checkbox overrides survive ordinary
selection/sleep/replay restoration in the same process. Sensitivities are
process-local. Missing Accessibility or a selected pad's scroll profile pauses
scrolling and shows a message; it does not silently substitute pointer curves.
Toggle a feature off/on to reload changed macOS settings.

## Gesture arbitration and latching

A shared per-pad router waits for 0.2 mm of initial coherent contact displacement
before committing the current two-finger or four-finger chord. Membership changes
reset that pending displacement. This small initiation threshold lets four
fingers finish landing rather than the first two immediately taking mouse mode.
It applies only before recognition; tiny movements after activation are retained.

Once recognized, the mode stays latched through any positive finger count:

- Mouse started with two stays mouse if a third/fourth joins.
- Scroll started with four stays scroll as fingers leave or join.
- All-up ends the mode. No shared contact IDs, invalid/palm input, stale chronology
  or explicit lifecycle cancellation ends it safely too.
- Average only contact IDs shared between frames. New fingers establish their
  own baseline, so landing locations never become synthetic movement.

No mode switch is inferred merely from changing counts mid-gesture. The mouse
acceleration formula and sensitivity remain the hardware-accepted ones; the new
initial 0.2 mm arbitration is a change to initiation timing that needs acceptance.
See [GESTURE_ENGINE.md](GESTURE_ENGINE.md).

## Apple-source model

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

## Fine events and cleanup

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

## Momentum after lift

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

## Verification and hardware acceptance

Offline checks cover independent Python numerical history vectors, direction
reversal, timing gaps, fractional movement, natural/traditional direction,
continuous/phase encoding, pixel remainder preservation through AppKit, momentum
decay and termination, tick-rate independence, reversal, idle lift, interruption,
per-pad coast isolation, event phase sequences, and gesture
arbitration/latching, per-pad isolation and routing of the existing user capture.
`SCROLL_PROFILE_REGISTRY_ID=<id> ./test.sh --filter FourFingerScrollTests` adds a
read-only installed-profile check without opening a device or starting takeover.

For hardware acceptance:

1. Land four and move slowly: scroll should advance in fine individual points.
2. Compare short, medium and fast strokes with native two-finger scrolling while
   takeover is off; report direction, sensitivity and travel differences.
3. Check horizontal and diagonal scrolling in a document/browser.
4. Continue scrolling while lifting down to one or adding fingers back. Flick
   and lift all: coast should taper smoothly. Touch the same pad to stop it.
   Compare slow-release/no-coast and native fast-flick travel.
5. Lift all, start mouse with two, then add fingers: it must stay mouse.
6. Check per-pad independence and that unchecking scroll leaves mouse available.
7. Confirm all-up/release/shortcut, selection changes, sleep and replay end cleanly.

No exact native-feel claim follows from the numerical tests. Hardware acceptance
is required before calling this behavior locked in.

# Gesture engine

Current behavior for AppleMagicTouchstream. The implementation separates input
recognition, session ownership, configurable actions and output lifetimes.
[Firmware findings](../FINDINGS.md) describe the original device; the thresholds
below are the app's tested policy. [Engine audit](GESTURE_ENGINE_AUDIT.md) records
the architecture review and remaining work.

## Session contract

1. Route by native numeric device ID. Each pad has independent contact, candidate,
   movement, acceleration and ownership state.
2. Pending candidates collect evidence. Finger count selects an activation family;
   it does not reclassify an already active gesture.
3. An activated continuous gesture owns its pad through all-up. Added/lifted fingers
   and anatomical relabeling do not change its action. New membership is rebased
   without injecting motion from contact landing positions.
4. Invalid input, lost identity continuity, stale delivery and lifecycle reset
   cancel output. A cancelled candidate cannot emit a delayed tap. Keyboard
   reservation includes the terminating frame and does not fall back to typing.
5. Normal completion and cancellation are distinct. Scroll may coast only after
   normal lift; cancellation balances output and stops momentum.
6. Every acquired output has an explicit release obligation. Shared cursor/button
   state is separate from per-pad recognition state.

## Inputs and factory actions

| Input | Default action | Activation / completion |
| --- | --- | --- |
| 2-finger movement | Move Pointer | 0.35 mm coherent travel; all-up completion |
| 3-finger movement | Drag / Select | 0.35 mm and fingertip-row geometry; all-up completion |
| 4-finger movement | Scroll / Pan | 0.20 mm; all-up completion with momentum |
| 2-finger tap | Primary Click | Valid tap completes on all-up |
| 3-finger tap | Double-Click | Valid non-thumb tap completes on all-up |
| 4-finger tap | None | Valid tap completes on all-up |
| Thumb + 2 fingertips tap | Secondary Click | Spread-thumb geometry; valid tap completes on all-up |
| 2–5-finger Pinch and Spread | Zoom | Recognized thumb plus shape change; all-up completion |
| 1-finger force click | Primary Click | Any active contact reaches P ≥ 130 |
| 2–5-finger force click | None | Same pressure crossing, independently configured per count |
| 2–5-finger stationary Hold | None | 0.5 s, fires once while down |
| Thumb + 2 fingertips Hold | None | Own binding and shared spread-thumb geometry; 0.5 s |
| Single-pad 4 Corners Hold | Open Config | Four outer corners; 1 s |
| Both-pad 4 Corners Hold | Open Config | Outer two corners on each pad; 1 s |
| Both-pad 3 or 4 fingers per hand, Tap / Hold | None | Tap at all-up; Hold after 0.5 s |

One-finger gesture Hold is unavailable. Its gray lifecycle card reads “No
separate gesture is available for this.” Keyboard key holds remain supported.
Both corner families are Hold-only. Legacy one-finger Hold and corner Tap fields
remain decodable but inactive.

## Arbitration and independent hands

The serialized live frame path evaluates established keyboard chords, coordinated
Both ownership, single-pad corners, keyboard reservation and local recognition.
An established same-pad MO(n) layer or modifier chord retains keyboard priority
through its final release. Its original contact is identified before gesture
suppression; the other pad remains independent.

Configured multi-finger candidates, pressure crossings and configured Hold
candidates reserve keyboard input before a pending key can be emitted. Reservation
is independent of permission/profile availability, so a paused gesture cannot type
keys accidentally. Rejected candidates remain reserved until all-up.

Local output processing gives an already fired Hold its cycle, then evaluates
Force, continuous/pinch recognition and pending Hold. A real movement activation
wins over pending Hold; a fired Hold blocks subsequent movement and tap. Directional
Hold is cancelled only when a direction actually commits, not by the lower-level
continuous threshold. Pinch/Spread assignments may coexist with Hold, but their
pages expose only automatic gray Hold/Lift lifecycle cards.

Pressure is an explicit override of same-pad movement: a configured Force crossing
ends that pad's drag, scroll or zoom, fires once, and owns the rest of the cycle.
Primary clicks/double-clicks are suppressed while another pad owns a drag; unrelated
secondary/system actions remain independent.

A valid second hand may acquire a coordinated Both chord immediately, releasing
independent outputs and rebasing both hands at acquisition. Single-hand gestures
start without a join delay. Both owns both pads until both lift; pending keyboard
layer/modifier ownership blocks acquisition.

## Motion, geometry and timing

Only `.making` and `.touching` records count as active gesture contacts. Terminal
records are still retained for capture/release processing. Tracking IDs and native
finger labels have separate roles.

| Policy | Current value |
| --- | --- |
| Normalized motion scale | 160 × 114.9 app mm; provisional physical conversion |
| Continuous identity/timestamp gap | Strictly less than 150 ms |
| Per-axis frame-motion guard | Strictly less than 25 app mm |
| Discrete Tap maximum | 500 ms from first landing |
| Tap landing / lift skew | 80 ms each |
| Tap minimum complete overlap | 20 ms |
| Tap per-contact travel | ≤ 1 app mm |
| Generic Hold landing window / settling | 80 ms / 2 app mm |
| Generic Hold duration | 500 ms after complete chord landing |
| Timer-driven freshness | 200 ms, using host receipt time |
| Force freshness | Up to 200 ms between native samples |
| Both Tap maximum / overlap / lift skew | 500 ms / 20 ms / 150 ms |
| Both and corner settling | 2 app mm |
| Corner regions | Outer 20% of each axis |
| Direction commit / turn threshold | 0.75 app mm |
| Direction axis dominance | 1.25× competing axis |
| Minimum committed-turn interval | 80 ms |
| Positive repeat interval | 20–5000 ms; 80 ms default for volume/brightness |

Motion uses only IDs shared across adjacent frames, not the centroid of whichever
contacts happen to be present. Pending count changes reset accumulated travel.
No shared IDs, malformed coordinates, palms or invalid chronology terminate
continuous ownership safely.

Three-finger row activation rejects a recognized thumb/palm, requires pair distances
2–60 app mm, a middle contact within 35 mm of each endpoint, and arch depth no greater
than `min(14 mm, longest span × 0.35)`. This geometry is an activation gate only.

Thumb+2 recognition requires a positively recognized thumb and two known fingertips
(codes 2–5). Fingertip spacing is 2–40 app mm; nearest-thumb distance is at least
15 mm and 1.5× fingertip spacing. Known hand labels must agree. A matched Tap binds
tracked thumb/fingertip roles and tolerates fingertip relabeling; known contradictory
role/hand labels reject. The dedicated Hold shares its initial geometry and keeps
a positive chord match through subsequent label ambiguity. It never falls back
to ordinary three-finger Hold when its own action is None.

## Pinch / Spread

All counts 2–5 require a recognized thumb to activate either direction. Measure
RMS pairwise spacing of the whole shape, independently of translation. Activate
at ≥ 0.6 app mm shape change with shape dominance over translation scaled by
`3 / max(2, active count)`.

The original input/action remains latched through reversals, partial lifts and
added fingers. Rebase changed membership without jumps. A lone survivor uses the
previous partner centroid as a virtual anchor. Shape span must stay within the
supported 5–200 mm range; single-frame span jumps of 15 mm or more reject the sample.

Pinch and Spread have independent actions for each count and hand. Zoom sensitivity
is one shared per-hand gain (0.25–2×), regardless of which count/direction starts it.
Magnification posts balanced began/changed/ended or cancelled phases, uses a fixed
activation location, and clamps each output delta to ±0.25.

## Movement and directional actions

The 2/3/4-finger movement inputs all use the same router, directional stepper,
repeater, output dispatcher and lifecycle gates. Continuous and directional modes
are mutually exclusive while retaining both sets of saved assignments.

Continuous actions: None, Move Pointer, Drag / Select, Scroll / Pan. Directional
cards can independently assign clicks, system shortcuts, small-step volume or
brightness, Scroll Up/Down and Pan Left/Right. Empty directional configurations do
not acquire movement.

Discrete directions fire on commit and, when enabled, repeat on the shared host
clock timer while held. Stationary contact frames keep the direction alive. There
is at most one repeat per tick, no catch-up burst, and stale delivery stops repeats.
A changed direction requires its own travel/dominance evidence. The loop toggle
stores enabled state separately from the remembered interval. Text editing permits
an empty draft; Return/focus loss validates/clamps the value.

Scroll Up/Down and Pan Left/Right follow projected motion rather than timed repeat.
The assigned gesture direction chooses the input axis/sense, while the action
chooses the output axis/sign. For example, Left can produce Scroll Down and Up can
produce Pan Right. Zero, perpendicular and opposite travel produce no output until
a new direction commits. These explicit signs ignore Natural scrolling.

Normal Scroll / Pan uses a per-hand optional Natural scrolling override, inheriting
the system preference when absent. The app never changes system preferences.

## Output and acceleration

Pointer and scroll use independent numerical models of published Apple parametric
acceleration, loading profiles for the selected pad. Contact-to-count conversion is
`app mm × resolution / 25.4 × sensitivity`. This conversion and momentum tuning are
app policy; they do not establish Apple's complete private multitouch algorithm.
See [preserved acceleration research](../RESEARCH_ARCHIVE.md).

Pointer retains fractional motion. Scroll retains independent per-axis history,
fractional precise events and phase sequences. Momentum uses recent release velocity
and analytic exponential decay; a same-pad touch brakes it without also clicking.

The primary button is globally shared, with explicit per-pad drag owners. One down
is posted for the first owner and one up after the last owner ends. Either pad can
move the held cursor, using the latest queued destination. A reserved up event is
created before posting down. Physical-button interference, observer failure,
staleness and lifecycle reset release owned output.

Tap, Hold, directions and Both discrete actions use the shared dispatcher.
Mission Control and App Exposé use resolved CoreDock requests; Notification Center,
Launch Pad and Show Desktop use validated shortcut plans. Small-step volume and
brightness use balanced media events with Option–Shift. The action menu exposes
only supported choices for its input; four-finger Tap includes the Force Click
System choices. No action modifies system shortcut preferences.

## Ownership, permissions and lifecycle

Synthetic output requires live input, selected native identity, owned FLTR clients,
a successful armed transition and Accessibility permission. Pointer/drag additionally
require a pointer profile; scrolling requires its scroll profile. Missing profiles
pause that output. Open Config is app-local and does not require Accessibility.

Selection/settings changes and lifecycle transitions balance output before resetting
state. Release, sleep, replay and quit stop synthetic output before native clients
are closed. Replay records keyboard commands and never posts gesture events or
haptics. [Takeover](TRACKPAD_TAKEOVER.md) specifies native ownership/recovery.

The shared exclusive-owner all-up path consumes Hold, Force and every Tap candidate
together. No candidate may emit a second action when another owner's cycle lifts.

## Haptics

Force feedback is fixed waveform 6 / level 0.25, once per pressure-owned cycle,
with at least 50 ms between same-pad pulses. Typing uses waveform 6 and its separate
0–2 Haptic Strength slider, step 0.01. Saved strength uses level ×100 encoding.
Feedback targets the originating pad; replay is recording-only.
[Native haptic evidence](FORCE_CLICK_HAPTICS.md) describes the parameter bounds.

## Settings and interface

Left/Right edit independent settings. Mirror Edit applies subsequent edits to both
pads without overwriting differences when enabled. Both edits coordinated bindings.
Duplicate physical selection resolves Left's non-None binding, then Right fallback,
and uses Left sensitivity. Device routing never uses reusable bridge slots.

Import Settings / Export Settings below Mode Toggles include gesture actions, Hold,
Both, directional modes/actions/repeats and per-hand gains/Natural preference under
`HostExtensions.mac.GestureBindings`. Missing gesture settings preserve local values.
Takeover opt-in and device selection remain app-local. Unsupported legacy fields
stay inert and unknown action labels fail rather than silently losing mappings.

The 2–5-contact shape pages are named **Pinch, Spread, and Rotate**. Rotate Left
and Rotate Right cards sit beneath Pinch and Spread, with independent per-count,
per-hand saved actions, Mirror Edit and settings import/export. Both rotation slots
default to None. Rotation recognition/output is not active in this GUI preparation
step; saved rotation slots do not reserve keyboard input or alter working gestures.
The examples illustrate the selected turn direction and fade before restarting.

The Gestures workspace has resizable navigation/inspector columns, searchable Action
sheets, movement cross cards and a shared right-hand inspector. Hold uses the same
white unselected card background as Tap/Force; unavailable lifecycle cards are gray.
Badges and descriptions sit beside the animation; assignment guidance shares its
heading row with a narrow-width fallback.

Examples are display-only, pause when hidden, restart when selected, and respect
Reduce Motion. They use the anatomical palette: unknown black, thumb orange,
index blue, middle green, ring purple, pinky pink, palm gray. Movement cycles
vertical out/back/fade then horizontal out/back/fade. Other examples also fade to an
empty pad; Hold begins filled and remains filled throughout its hold and fade.

## Verification

`./test.sh` runs offline native ownership tests and Swift production-engine tests.
Tests cover per-pad latching, membership/ID changes, competing tap/motion/force/Hold,
Both acquisition and release, stale/reset paths, shared button ownership, scrolling,
settings round-trips and offscreen interface rendering. Optional external captures
and registry checks skip when their prerequisites are absent. Offline event
construction/recognition establishes intended output, while actual application
receipt and physical feel require hardware testing.

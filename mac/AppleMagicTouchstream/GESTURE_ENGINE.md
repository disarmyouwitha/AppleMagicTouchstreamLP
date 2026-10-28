# Gesture engine

Current behavior for AppleMagicTouchstream. The implementation separates input
recognition, session ownership, configurable actions and output lifetimes.
[Firmware findings](../FINDINGS.md) describe the original device; the thresholds
below are the app's tested policy. [Engine audit](../../../new_code/touchstream-archive/AppleMagicTouchstream-research-2026-10-26/notes/GESTURE_ENGINE_AUDIT.md) records
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
   cancel output. An activated/cancelled gesture owner cannot emit delayed typing.
   Unresolved count-only candidates retain keyboard proposals; only never-activated
   rollover may resolve to typing. Cleanup includes the terminating frame.
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
| 5-finger movement | None | 0.20 mm; same continuous/directional engine |
| 2-finger tap | Primary Click | Valid tap completes on all-up |
| 3-finger tap | Double-Click | Valid non-thumb tap completes on all-up |
| 4-finger tap | None | Valid tap completes on all-up |
| 5-finger tap | None | Valid tap completes on all-up |
| Thumb + 2 fingertips tap | Secondary Click | Spread-thumb geometry; valid tap completes on all-up |
| Thumb + 2 fingertips diagonal swipes | None | Shared spread-thumb geometry; coherent corner-directed travel of at least 0.75 mm |
| 2–5-finger Pinch and Spread | Zoom | Recognized thumb plus shape change; all-up completion |
| 1-finger force click | Primary Click | Any active contact reaches P ≥ 130 |
| 2–5-finger force click | None | Same pressure crossing, independently configured per count |
| 2–5-finger stationary Hold | None | 500 ms; one-shot or held shortcut output |
| Thumb + 2 fingertips Hold | None | Own binding and shared spread-thumb geometry; 500 ms |
| Single-pad Outer Corners Hold | Open Config | Four corners of one pad; 500 ms default |
| Both Outer Corners Hold | Open Config | Outer two corners on each pad; 500 ms default |
| Both Inner Corners Hold | None | Inner two corners on each pad; 500 ms default |
| Both Top/Bottom Outer/Inner Corners Hold | None | One finger per pad in the mirrored corner pair; 500 ms default |
| Both-pad 3 or 4 fingers per hand, Tap / Hold | None | Tap at all-up; Hold after 500 ms |

One-finger gesture Hold is unavailable. Its gray lifecycle card reads “No
separate gesture is available for this.” Keyboard key holds remain supported.
All corner families are Hold-only. Legacy one-finger Hold and corner Tap fields
remain decodable but inactive.

## Arbitration and independent hands

The serialized live frame path evaluates established keyboard chords, coordinated
Both ownership, single-pad corners, local candidate evidence and keyboard output.
An established same-pad MO(n), modifier or committed key hold retains keyboard
priority through final release; the opposite pad remains independent.

Count alone starts a provisional local candidate. Keyboard input is retained in
two preallocated proposal banks (1,024 frames × 16 contacts per bank), with owned
copies rather than retained native pooled buffers. Pointer/gesture processing
continues immediately on original frames. A recognized movement, force, Hold or
Tap wins the cycle and discards proposals. Corners/Both remain exclusive through
their existing acquisition path. Permission/profile-paused gestures stay reserved.

Without activation, rollover resolves to typing when fewer than two contacts
remain and no fully formed tap can still complete, or at all-up. Retained keyboard
input then uses the shared keyboard processor in original per-pad order, with
original timestamps, sequences and captured modifier context. The typing cycle
cannot be stolen again until all-up. Isolated one-finger taps use the direct path.
Invalid/stale input, overflow, configuration/layer/lifecycle invalidation cancel
proposals instead of flushing stale keys. The retired Typing Grace field is
ignored in old imports and absent from active settings and new exports.

For pending two-finger movement, the interval straddling arrival/removal of a chord
member establishes its baseline; a surviving finger's earlier solo displacement
cannot activate the new chord. Stable-pair activation remains 0.35 mm. Existing
three-finger staggered drag keeps its activation policy; already activated latches
keep their matched-contact deltas and count transitions unchanged. This uses an
activation-rule policy in the shared session engine, not a second mouse recognizer.
See [typing arbitration audit](../../../new_code/touchstream-archive/AppleMagicTouchstream-research-2026-10-26/notes/TYPING_GESTURE_ARBITRATION.md) for the captured
regression and differences from the recovered TouchStream firmware.

Local output processing gives an already fired Hold its cycle, then evaluates
Force, continuous/pinch recognition and pending Hold. A real movement activation
wins over pending Hold; a fired Hold blocks subsequent movement and tap. Directional
Hold is cancelled only when a direction actually commits, not by the lower-level
continuous threshold. Pinch/Spread assignments may coexist with Hold, but their
pages expose only automatic gray Hold/Lift lifecycle cards.

When an eligible four-finger Hold competes with continuous four-finger movement,
translation activation needs at least three of the four tracked contacts to have
travelled 0.2 app mm along the candidate direction since the full chord formed.
The shared contact-motion/session engine computes this projected agreement from
fixed-size contact baselines. A single settling fingertip cannot claim scroll by
moving the average. Membership/ID changes rebase this pending evidence. This adds
no fixed delay and does not raise the post-activation scroll threshold or alter
acceleration, momentum, partial-lift latching, Force/shape competition, directional
assignments, or two-/three-finger movement. It applies only while a configured
four-finger Hold remains eligible; without that competing Hold, the accepted
ordinary four-finger motion policy remains. The agreement threshold is app tuning,
not a recovered firmware constant.

`shift_hold_accidental_scroll.atpcap` (SHA-256
`f0865a1a2a2555f4aec9de20d74af99525f9188bcd219e5091dafee52c42b6c2`)
contains fourteen four-contact episodes and seven balanced recorded Shift lifetimes.
Offline arbitration with four-finger held Shift at 100 ms reproduced seven Holds
and seven premature scroll starts. Agreement gating produces fourteen Holds,
zero scroll starts, and preserves the original seven successful firing frames.
Complete four-contact episodes, raw phases/positions/telemetry and both clocks
are preserved in `Tests/ProductionEngineTests/Fixtures/shift-hold-settling.json`.
The capture omits current per-hand settings; the 100 ms Shift/scroll assignments
are explicit regression configuration corroborated by current saved preferences,
not a claim of complete captured live-state or application event receipt.

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
| Five-finger Hold acquisition | Up to 200 ms to assemble when its Hold action is enabled; late partial chords cannot fire smaller Holds |
| Pending three-finger movement with fourth pre-contact | Defer activation during the first 80 ms only while a fourth starting/hovering contact is visible and four-finger movement is assigned |
| Generic Hold duration | 500 ms after complete chord landing |
| Timer-driven freshness | 200 ms, using host receipt time |
| Force freshness | Up to 200 ms between native samples |
| Both Tap maximum / overlap / lift skew | 500 ms / 20 ms / 150 ms |
| Both and corner settling | 2 app mm |
| Corner regions | Outer 25% of each axis, shared by single-pad and Both corners |
| Direction commit / turn threshold | 0.75 app mm |
| Direction axis dominance | 1.25× competing axis |
| Minimum committed-turn interval | 80 ms |
| Positive repeat interval | 20–5000 ms; 80 ms default for volume/brightness |

Corner targets use one shared geometry policy for both variants: the outer quarter
of each axis, with the middle half excluded. Single-pad input requires four distinct
corners. Both targets are relative to the two selected pads, not anatomical labels:

| Both gesture | Left pad | Right pad | Contacts total |
| --- | --- | --- | --- |
| Outer Corners | Top-left + bottom-left | Top-right + bottom-right | 4 |
| Inner Corners | Top-right + bottom-right | Top-left + bottom-left | 4 |
| Top Outer Corners | Top-left | Top-right | 2 |
| Top Inner Corners | Top-right | Top-left | 2 |
| Bottom Outer Corners | Bottom-left | Bottom-right | 2 |
| Bottom Inner Corners | Bottom-right | Bottom-left | 2 |

All use the shared coordinated recognizer, exact per-pad counts, independent saved
Hold thresholds (500 ms default), existing action/held-shortcut output, freshness
and cleanup. Inner Corners and the four pairs are Both-only; the per-pad four-corner
gesture is renamed Outer Corners without changing its geometry or saved identity.
The new coordinated bindings default to None and reserve nothing until assigned.
The original `fourCorners.hold` and `fourCorners` threshold keys remain unchanged.

An unactivated top/bottom pair may acquire its enabled complete Outer/Inner chord
when complementary corners join. Original contacts must remain within 2 app mm;
new contacts must occupy distinct complementary corners on the same edges. An
incomplete expansion cannot fire the smaller Hold from a timer. Full acquisition
rebases the chord and starts its own Hold threshold. A lift during expansion,
replacement, stale input or invalid geometry cancels rather than reviving the pair.
Fired Holds never promote; ordinary Both continuation/cancellation still applies,
and the cycle stays reserved until both pads are all-up. The same mechanism serves
all four pairs, rather than separate recognizers or output handlers.

The widened corner targets are provisional usability tuning,
not capture-derived or recovered firmware dimensions. Hold thresholds, 2 app-mm
settling allowance, contact validation, freshness and balanced release stay unchanged.

In Mirror Edit, unequal repeat intervals display an empty field with a Mixed
placeholder. Return explicitly applies the entered interval to both pads, including
20 ms and an unchanged numeric value with mixed On/Off states. A valid interval
also enables repeat on both pads. Empty or invalid drafts do not replace settings.

Five-finger Hold uses the shared recognizer with a bounded acquisition extension,
not a new latch. A stationary sequence of contact additions may assemble within
200 ms of first landing if five-finger Hold is assigned. After the ordinary 80 ms
window, a partial chord is eligible only to become five fingers; it cannot fire a
smaller Hold from either frames or the timer. The configured Hold threshold starts
at complete landing. Real lifts, ID replacements, excessive motion, invalid/stale
input and competing activation still cancel acquisition. A previously fired Hold
keeps ownership. Four-finger and other gesture acquisition windows stay unchanged.
The 200 ms window is provisional app tuning, not a recovered firmware constant.

Motion uses only IDs shared across adjacent frames, not the centroid of whichever
contacts happen to be present. Pending count changes reset accumulated travel.
No shared IDs, malformed coordinates, palms or invalid chronology terminate
continuous ownership safely.

Three-finger row activation rejects a recognized thumb/palm, requires pair distances
2–60 app mm, a middle contact within 35 mm of each endpoint, and arch depth no greater
than `min(14 mm, longest span × 0.35)`. This geometry is an activation gate only.

Four-finger movement acquisition also uses native pre-contact evidence: three
touching fingers plus a finite, non-palm starting/hovering fourth contact defer
three-finger movement activation during the first 80 ms of the continuous input
episode, if four-finger movement is enabled. Pre-contact does not count as touch
or emit scrolling. Full four-finger contact qualifies through the usual 0.2 app-mm
motion threshold. A vanished pre-contact, expired landing interval or disabled
four-finger movement permits ordinary drag activation immediately if it otherwise
qualifies. Existing owners keep their all-up latch. This does not change Hold or
Tap windows, acceleration, or two-finger activation.

Capture regression: `4_finger_scroll.atpcap` (SHA-256
`8fb793f98ec8a0e9f6f3df9c1ebf7da559b40cfbfaf3d957e4a4ffa2c3e6b40a`).
With mouse/drag/scroll enabled, offline routing reproduced accidental drag starts
at sequences 10200 and 10838, each with a visible fourth pre-contact that became
touching about 12 ms later. The guard yields scroll starts at 10201 and 10840;
the other 26 movement starts retain their gesture and activation frame. The
capture omits current per-hand settings, so this is an explicit router regression,
not a complete replay of captured live configuration or downstream event receipt.
The two failing episodes and one normal scroll episode are retained in
`Tests/ProductionEngineTests/Fixtures/four-finger-scroll-landing.json`.

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

Thumb+2 additionally exposes diagonal-only movement under `thumbTwoMove`.
Its assignment grid is `[↖, Tap, ↗] / [Rotate Left, empty, Rotate Right] /
[↙, Hold, ↘]`. The empty center has no continuous Movement assignment. Tap,
Hold and existing rotation bindings retain their identities/defaults. Each arrow
has the same action picker, shortcut builder, Behavior menu, loop control and repeat interval as
ordinary directions, independently per hand with Mirror Edit and Import/Export.
All four diagonal actions default to None, with no live candidate/timer enabled
when none is assigned. Existing two-/three-/four-/five-finger cardinals are unchanged.

Activation requires three contacts satisfying the same `ThumbTwoChord` spread
geometry as Thumb+2 Hold/Tap: one recognized thumb, two recognized fingertips and
consistent nonzero hand identities. The whole chord must translate: the shared
coherent-motion tracker requires all three contacts to contribute at least
0.75 mm along the pending translation. The movement also projects at least
0.75 mm along one diagonal unit vector, within ±22.5° of that diagonal. Pure
horizontal/vertical travel and one-finger adjustments do not activate a swipe.
The full-cohort baseline excludes motion before all three contacts have landed.
Pinch/Spread and rotation retain their existing shape/angular priority; ordinary
three-finger row movement rejects a positively recognized thumb.

Once activated, `GestureSessionEngine` supplies the existing until-all-up latch,
matched-ID delta rebasing, count-change continuation and cancellation. Anatomy is
not re-required after activation. The shared `GestureDirectionalStepper` projects
onto diagonal vectors for this trigger, retaining 0.75 mm turn evidence and the
80 ms turn interval. Other triggers still classify only cardinal directions.
The host-clock repeater, stale-input handling, per-pad independence, held-output
cleanup and Both handoff are shared. Directional scroll/pan projects fine travel
along the selected diagonal before mapping it to the assigned output axis/sign.
No absolute corner landing region is required: these gestures drag *toward* a
corner from the chord's starting position.

The diagonal rules are app policy pending hardware validation. Offline tests cover
both hand orientations, all directions, positive anatomy/spread/hand validation,
coherent motion, thresholds, shape competition, latch/release, turns/repeat/stale
input, disabled acquisition, fine scroll projection, settings round-trips and UI
rendering/animation. No hardware input is opened by those tests.

The 2/3/4/5-finger movement inputs all use the same router, directional stepper,
repeater, output dispatcher and lifecycle gates. Continuous and directional modes
are mutually exclusive while retaining both sets of saved assignments.

Continuous actions: None, Move Pointer, Drag / Select, Scroll / Pan. Directional
cards can independently assign clicks, system shortcuts, small-step volume or
brightness, Scroll Up/Down and Pan Left/Right. Empty directional configurations do
not acquire movement.

Each direction has a Behavior menu: **Repeat every ms** or **Repeat with motion**.
The choice is saved independently per hand/direction and included in Import/Export;
Mirror Edit shows Mixed when the hands differ. Existing discrete assignments retain
timed behavior and existing Scroll/Pan assignments retain motion behavior when the
new optional field is absent. Choosing a behavior enables repeat and preserves the
remembered timer interval. The loop control can still disable repeat (one output
on direction commit).

All directions use the same activation, turn/reversal arbitration, session latch
and output cleanup. In timed mode, discrete actions and Scroll/Pan fire on commit
and repeat on the shared host clock while held, including stationary contact frames.
There is at most one repeat per tick, no catch-up burst, and stale delivery stops
repeats. A Scroll/Pan timer step uses the existing profile/acceleration/output path
with 0.75 mm of projected travel, retaining per-hand scroll sensitivity and explicit
action direction; it does not create momentum on release.

In motion mode, discrete actions fire on commit, then require another 0.75 mm of
coherent travel in the committed direction per repeat, bounded to one output per
80 ms and one output per frame. Turns discard old repeat travel and require their
own direction evidence; excess travel never queues a burst. Pausing produces no
output. Scroll/Pan retains smooth projected travel/speed output and release momentum.
The host timer is disabled for every motion assignment. All-up, invalid/stale input,
ownership loss, replay, reconfiguration and lifecycle changes use shared cleanup.
The loop toggle stores enabled state separately from the remembered interval.
Text editing permits an empty draft; Return/focus loss validates/clamps the value.

For motion scrolling, the assigned gesture direction chooses the input axis/sense,
while the action chooses the output axis/sign. For example, Left can produce Scroll Down and Up can
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
and analytic exponential decay. An active contact on either selected/owned pad
brakes released momentum on both pads, before keyboard/gesture arbitration. Each
started momentum output receives one ended phase and its velocity is cleared;
terminal, hover and unselected-pad frames do not brake. Active scrolling under
fingers is independent and is not cancelled by this coast-only operation.
A same-pad brake remains consumed without also clicking/typing; an opposite-pad
touch keeps its normal tap, pointer, typing, Hold and coordinated-chord eligibility.
The frame and momentum timer share the output lock, so no subsequent coast tick
can race past the interruption. This does not reset the other pad's motion tracker,
gesture owner or held output. `cross-pad-momentum.json` preserves the right-flick /
left-pointer handoff from `momentum.atpcap` for offline regression.

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

## Custom shortcuts and held keys

Keyboard and Gesture inspectors share one Shortcut Builder: generic/left/right
Ctrl, Shift, Option and Cmd, optional key (None means modifiers only), and App/file/
folder/URL target with Browse, plus an optional Name. Keyboard Primary/Hold Apply
assigns to the selected key; Keyboard Shortcuts Apply adds to the library. Gesture
Apply assigns the input and adds to the shared library. The gesture
Action sheet retains its built-in groups and includes a Shortcuts group. Rendering
or editing a draft never posts input.

Emoji's Globe shortcut translates to Control–Command–Space through the same
balanced keystroke factory as other shortcuts. Its key-up restores pre-shortcut
flags, including independently held modifiers, so later taps do not inherit the
borrowed Control/Command state.

Manage Shortcuts opens the same searchable library editor from the Gesture Action
picker and the Keyboard builder beside Primary/Hold/Shortcuts. Edit prefills the
shared builder; Apply replaces that library entry and merges duplicates. Delete
removes only the saved entry. Existing key and gesture assignments retain their
own action snapshots, including after settings export/import; an assigned shortcut
absent from the library appears under Current Assignment in the gesture picker.

Named shortcuts display their name on keys, Hold labels, action cards and pickers.
Manage Shortcuts shows the command beneath the name and can edit or clear the name.
An empty/whitespace-only name falls back to the command's existing display label.
Names are optional KeyAction metadata; canonical command label, code, flags and
app target remain unchanged. String-only shortcut lists, portable key assignments
and gesture identities preserve the metadata in a `NAMED_SHORTCUT:` JSON envelope.
The catalog resolves it once into the ordinary action before dispatch. Existing
unnamed labels/files remain valid; older app versions do not understand newly
named envelopes. Named variants can coexist in the library, including with their
unnamed command. Renaming a library entry keeps the existing snapshot semantics.

Tap, Force, directions, movement activation, Pinch/Spread and rotation can dispatch
custom shortcuts once. Directional repeat uses the same interval controls. Hold
assignments (including Both and corners) additionally offer Once after threshold
or Hold until release for keyboard shortcuts. App targets always open once. Hold
recognition geometry remains unchanged. Each Hold assignment has a saved threshold
(default 500 ms), editable in its Action inspector from 100–5000 ms in
10 ms steps. Ordinary counts, Thumb+2 and per-pad corners are independent
per hand; Mirror Edit writes both hands. Both-hand chords have separate thresholds.
Thresholds round-trip with settings; older files missing them use 500 ms.
Timing controls and recognition labels use milliseconds; the existing serialized
threshold fields and monotonic runtime clocks retain seconds for compatibility.
Timing edits cancel current output through the existing settings-change cleanup.
Normal movement/shape assignments cannot acquire a held-key lifetime through imported settings.

The dispatch queue shares synthetic key ownership across gesture pads, corners,
Both and existing keyboard mappings. A held shortcut presses modifiers and the
optional key; releasing an owner releases only keys with no remaining owner.
Typing strokes inherit held gesture flags, and their up edges preserve those
flags. Sided modifier choices use the corresponding physical virtual-key code.
All-up, invalid/stale input, settings/selection changes, lifecycle resets and Both
handoff balance owned output. Ordinary per-pad held output keeps the existing
count/label continuation latch; corner/Both continuation follows its own geometry.
Queue clears preserve accepted key-up cleanup edges. Recording dispatch exercises
the same logical ownership transitions without posting events or opening apps.

Built-in actions retain their original string encoding. Custom assignments encode
a validated catalog label plus the hold lifetime in a prefixed gesture-action
string, preserving the existing settings envelope and portable host extension.
Catalog actions resolve once when assigned/decoded; frame processing uses the cached
value rather than reparsing labels.

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
[Native haptic evidence](../../../new_code/touchstream-archive/AppleMagicTouchstream-research-2026-10-26/notes/FORCE_CLICK_HAPTICS.md) describes the parameter bounds.

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

The 2–4-contact shape pages are **Pinch and Spread**. Five contacts use **Pinch,
Spread, and Rotate**, with Rotate Left/Right below Pinch/Spread. **Thumb+2fingers**
uses the diagonal grid described above, with Tap top-center, Hold bottom-center,
and Rotate Left/Right on either side of the empty center. The existing
three-contact rotation binding IDs serve this thumb-plus-two input; unused two-
and four-contact fields remain readable for compatibility without visible cards.
Rotation assignments are independent per hand/direction, default None, and support
Mirror Edit and settings import/export. Assigned Thumb+2 and five-contact rotations
reserve their corresponding input family and dispatch once on activation. Two/four-
contact rotation fields remain inactive.

Five Fingers has the same Tap and Move cross as the other movement pages: Tap, Up
and Force Click across the top; Left / Movement / Right in the middle; Hold beside
Down at the bottom. Tap and Movement default to None to preserve existing settings.
Its independent Hold defaults to 500 ms, and only Lift stays under Session
Lifetime. Direction/repeat, scrolling/panning, gains, Mirror Edit and portable
settings use the same engine as the other counts.

The Gestures workspace has resizable navigation/inspector columns, searchable Action
sheets, movement cross cards and a shared right-hand inspector. Its default width
is 381 px, matching Keyboard's settings column; navigation remains 286 px. The old
untouched 286 px inspector default migrates, while deliberate resize values persist.
Pointer/drag sensitivity and Scroll sensitivity/Natural scrolling appear above
Behavior in the movement inspector. Zoom retains its separate placement.
The Shortcut Builder appears above Recognition on discrete, directional and shape
assignment inspectors; center continuous Movement omits it. Hold's Behavior picker
sits immediately below Action, saves lifetime changes directly, and is enabled for
assigned keyboard shortcuts. App targets and built-in one-shot actions cannot be
held through that picker. Hold uses the same
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

## Rotation recognition

Thumb+2 and five-contact rotation use a tracked recognized thumb as the pivot and
measure the angle of the fingertip group's centroid relative to it. Three- and five-contact activation require a recognized thumb and reject
palm/invalid/duplicate contacts. Rotation uses angular evidence rather than the
spread-Tap arrangement bounds; Tap/Hold keep their own geometry. Radius must be at least 15 app mm.
Membership/identity or native chronology changes rebase pending evidence. Pending
positions are retained by tracking ID before labels settle; a positive thumb label
is still required to activate. Initial Unknown labels therefore cannot give scale
recognition an older geometric baseline than rotation.

The provisional commit threshold is 3°, at least 0.75 app-mm arc travel, with arc
travel exceeding radial travel by 1.1×. A pending turn above 0.2°, at least 0.5 app-mm arc travel and arc/radial
ratio above 0.65 defers competing scale activation until the turn commits or
radial change overtakes it. The final 3° / 0.75 mm / 1.1× commit gate remains
stricter than this early competition gate. With rotation unassigned, Pinch/Spread behavior is unchanged.
Clockwise in screen coordinates selects Rotate Right; counterclockwise selects Left.

Rotation is registered in the shared continuous session engine. After activation,
the original input/action stays owned through reversal, anatomical relabeling and
partial lifts until all-up; it fires once rather than on every frame or direction
change. Force and Both handoff keep their existing explicit precedence. Hold/tap
candidates are cancelled through the common ownership paths. Actions use the shared
discrete dispatcher (including Dock system actions), permissions and replay gates.
There is no continuous native rotation-output action in this pass.

Offline replay of `rotate_no_work.atpcap` contains 718 frames and eight completed
rotation cycles, with roughly 25–51° counterclockwise travel. All eight activate
Thumb+2 Rotate Left with Pinch/Spread and three-finger movement competing. This
predicts recognition, not actual target-application receipt. Synthetic regressions
cover both directions/counts, reversal, partial lift, missing thumb and pure scaling.

### Right-turn capture regression

`rotate_right.atpcap` contains 723 frames: two initial left turns, eight right-turn
cycles and four final two-contact cycles. Early radial contraction in clockwise
turns can reach the scale gate before 3° of angular travel. Several cycles begin
with the thumb labeled Unknown for ~100 ms. One fingertip pair spans 40.6 mm, which
is valid angular evidence but outside the spread-Tap pair bound. Rotation now
retains its initial tracked geometry across label settling and uses its own angular
contract rather than the Tap spacing predicate. The pending rotation
evidence gate prevents that early shape claim while leaving the final rotation
commit unchanged. Regression replay runs with Pinch/Spread and three-finger motion
competing; recognition results do not themselves establish OS action delivery.

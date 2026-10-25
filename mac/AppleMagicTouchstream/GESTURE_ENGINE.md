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
| Two-, three-, four- or five-finger pinch / spread | Zoom |
| Close, aligned three-finger movement | Drag / Select |
| Non-thumb three-finger tap | Double-Click |
| Four-finger movement | Scroll / Pan, precise scroll and momentum |
| Spread thumb + two known fingertips tap | Secondary Click |

### Configurable one- through five-finger force clicks (2026-10-22)

Each count has an independent Action menu with the same choices as Tap: None,
Primary Click, Double-Click, Secondary Click. Settings persist per hand. Existing
saved settings migrate without losing bindings or gains. One finger defaults to
Primary Click (preserving the tested feature); counts 2–5 default to None.

During selected/owned/armed takeover, a contact reaching P ≥ 130 immediately
selects the force action for the current active count. The maximum per-contact
pressure is used, never the sum. Fingers may be added before pressing; after
fingers lift or IDs are replaced, the remaining chord cannot become another
force click until all-up. Invalid/duplicate/palm/over-five-finger contacts or
nonmonotonic/stale (>200 ms) samples block recognition until all-up. After a force
fires, added/lifted fingers and pressure jitter cannot produce another output.

An enabled pressure chord reserves the keyboard before posting, cancels taps and
movement for the remaining cycle, stops scroll/momentum, and balances any
same-pad drag before dispatching the chosen click events. Other-pad drag ownership
blocks output. No pointer/scroll profile is required for a force click; AX and
live-only gates still apply. An already-sent key cannot be undone retroactively.
Disabling a force action removes that input's reservation and feedback.

Force-click feedback is fixed at **waveform 6, level 0.25** for every count and
mouse action. The experimental per-hand haptic controls and Test button were
removed after the user's hardware test. Previously saved experimental values are
decode-only and cannot override live force feedback. Live pulses remain once per
cycle and throttled per pad to a minimum 50 ms interval.

Typing uses fixed **waveform 6**, independently of force feedback. Keyboard →
Typing Tuning → Haptic Strength is a fine 0–2 slider with 0.01 steps; zero disables
feedback. Profiles/UserDefaults retain the existing `hapticStrength` value ×100
encoding (60 becomes level 0.60, 150 becomes level 1.50). The engine, live dispatcher
and replay conversion preserve levels above 1 through 2; invalid values disable
feedback and higher values clamp at 2. Device targeting and throttling remain.
See [FORCE_CLICK_HAPTICS.md](FORCE_CLICK_HAPTICS.md) for the clamp investigation.

Movement inputs offer None, Move Pointer, Drag / Select and Scroll / Pan.
Each finger-count Pinch and Spread input has its own None or Zoom menu, with an independent
per-hand Zoom sensitivity (0.25–2×). All eight directional inputs default to Zoom when takeover
is opted in; old bindings migrate without changing existing actions. These
bindings and gains are included in keymap export.
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
Keymap appears directly under Mode Toggles in the scrolling Keyboard column. Gestures contains the colored
chord examples and Left/Right/Both Action menus. Keyboard retains the existing
layout, column, keymap, haptics and tuning controls. Both shows Mixed assignments;
choosing an action applies to both. Factory settings start mirrored.
In Both scope, each gesture subsection places the left-hand diagram before its
label and the right-hand diagram after it; finger-count headings are text-only. Clicking a subsection label or its disclosure arrow toggles expansion.
Gesture subsections start collapsed
except two-finger Tap and Move. Each 2–5-finger group has a separate Pinch and Spread subsection; two-finger Tap and
Move contains tap, force click and movement in that order. Force click appears
directly below tap in sections containing both. Sensitivity controls
appear directly below the action they tune, including pointer and zoom gains.

Bindings and gains persist in app-local UserDefaults under
`AppleMagicTouchstream.handGestureBindings.v1`. Keymap Export now also writes the
complete Left/Right bindings (including all force inputs) and pointer/scroll gains
to `HostExtensions.mac.GestureBindings`. Import normalizes and persists included
gesture settings, resets current recognition, and reconfigures live eligibility.
Old bundles or bare keymaps without GestureBindings preserve current gestures.
Known retired brightness/voice and related GTK labels are accepted as inert
legacy actions on import, retaining their labels and primary/hold positions for
round-tripping. They remain outside the live action catalog. Unknown labels
still fail import rather than silently losing mappings.
Takeover remains a separate,
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

## Default keyboard input (2026-10-22)

Every unreserved contact cycle defaults to keyboard interpretation. Moving more
than 3 mm, landing outside a key, or legacy drag/intent settings cannot select a
mouse mode or disqualify a typing contact. Key hit regions, explicit keyboard
mode/output state, release timing, per-key actions and lifecycle cleanup remain.
Configured gestures still reserve the originating pad's cycle before keyboard
output and latch through all-up; the other pad remains usable for typing.

Typing Tuning no longer has Force Min or Force Max. Legacy profile fields/setters
remain compatible but never gate ordinary taps, snapped taps or hold-repeat output.
Per-key **Force instead of hold** remains: an assigned positive hold-force threshold
uses pressure instead of elapsed dwell, including when reported pressure is zero.
There is no fallback to timed hold for a pressure-controlled binding.

## General pinch / spread and Zoom (2026-10-22)

Two-, three-, four- and five-contact pinch / spread inputs compete with movement
in the shared gesture ownership engine. Thumb plus one through four fingertips
is supported. Inward Pinch activation requires a recognized thumb; outward
Spread remains independent of anatomical labels. Every contact
contributes: shape scale is the RMS of all pairwise distances, independent of
rigid translation and rotation. Recognition produces a scale delta; the assigned
Zoom action converts that delta into magnification output.

Pending geometry requires valid, distinct contact IDs, RMS spacing at least 5 mm,
and monotonic sample gaps below 150 ms. Activation requires at least 0.6 mm
spacing change and spacing change greater than (3 / active count) × centroid
travel. This accounts for a stationary thumb with multiple moving fingertips.
Spacing-dominant pending motion defers competing movement activation. Existing
movement thresholds remain unchanged. These are provisional hardware-test values.
Once either wins it cannot turn into the other during that cycle.

**Pinch latches until all-up**, just like other continuous gestures. Added fingers
join the shape measurement. Membership changes establish a fresh constellation
with zero delta on that frame; subsequent motion continues using all contacts.
If only one survivor remains, it continues against the prior non-survivor
centroid as a virtual anchor. Its movement can still zoom. The original trigger
and action own the entire cycle, including 2→5→1 transitions. Invalid samples,
stale input, disabling or lifecycle reset may cancel for the same integrity/output
safeguards as other gestures. Tiny/degenerate geometry and implausible jumps
cannot generate magnification spikes.

Zoom uses incremental shape-spacing ratios, including pre-activation travel at
begin, multiplied by the hand's gain and bounded to ±0.25 per packet. Recognized
pinches cancel taps, scroll/momentum and pointer translation; keyboard reservation
includes the release frame. A force-click action can explicitly interrupt zoom.
Zoom has no momentum or click haptic. No pointer/scroll profile is required.

The app emits native-style CGEvent magnification packets (undocumented event type
29, HID type field 110 = 8, magnification field 113, phase field 132 = 1/2/4/8 for
begin/change/end/cancel). These constants were cross-checked with the independent
[Mac Mouse Fix event adapter](https://github.com/noah-nuebling/mac-mouse-fix/blob/master/Helper/Core/Touch/TouchSimulator.m)
and the local Calf Trail Touch archive. The implementation is independent Swift;
no external driver or library is bundled. Offline tests validate conversion via
NSEvent to `.magnify`, magnification amount, phase, flags, fixed cursor anchor and
interpreter tag. AppKit's receive-side semantics are documented by
[Apple](https://developer.apple.com/documentation/appkit/nsevent/magnification).
Actual target-app delivery and feel still require hardware testing.

Output is limited to selected/owned/armed/AX-trusted live pads. A watchdog cancels
an open magnification sequence after 200 ms without input. Reset/selection edits,
sleep/replay/quit, mouse-button interference and force-click interruption balance
open zoom phases; replay posts nothing. The cursor stays where pinch began.

### Separate Pinch and Spread bindings (2026-10-23)

Every 2–5-finger Pinch and Spread subsection now has two independent Action
menus: inward Pinch and outward Spread. Both default to Zoom. The signed initial
shape-spacing change selects the input when activation passes the existing
thresholds. That original input/action remains latched until all-up, including
reversal and finger-count changes; Zoom continues using signed deltas in both
directions without ending or restarting its native magnification phase.
Disabling one direction prevents it from initiating a gesture but does not cancel
an already-latched opposite direction merely because motion reverses.

Existing combined assignments migrate to both directions. Optional spreadActions
preserves old saved/keymap decoding; the first directional edit freezes the
migrated assignments so subsequent edits are independent. Both bindings persist
per hand and round-trip with keymaps. Zoom sensitivity is shared per hand and
appears once beneath the two menus. No new output action types were introduced.

## Apple shortcut actions (2026-10-23)

Notification Center, Mission Control, App Exposé, Launch Pad and Show Desktop are
available in all 2–5-finger Pinch/Spread and 1–5-finger Force Click Action menus.
Defaults stay unchanged; settings persist per hand and round-trip with keymaps.
Movement and ordinary Tap menus retain their existing choices.

Pinch/spread emits a shortcut once on activation, then reserves the cycle until
all-up, including reversal and count changes. It never produces zoom, mouse or
tap output for that cycle. Force actions emit once at the existing P>=130 crossing,
with the fixed waveform-6/0.25 force feedback and normal force arbitration.
Selected/owned/armed/Accessibility/live gates remain; replay does not post.

Mission Control and App Exposé use native Dock requests, independent of keyboard
shortcut configuration. AppleShortcutPlan resolves CoreDockSendNotification from
HIServices at configuration time and keeps the library resident. Messages are
com.apple.expose.awake and com.apple.expose.front.awake respectively. This is an
undocumented API: absent symbols disable the plan with an unavailable status,
not a crash or shortcut-preference mutation. The symbol was confirmed available
on the test Mac without invoking it. Real invocation still needs hardware testing.

Notification Center, Launch Pad and Show Desktop retain their hardware-tested
keyboard dispatch. AppleShortcutPlan reads com.apple.symbolichotkeys /
AppleSymbolicHotKeys only at configuration (not inside input callbacks). Valid
enabled custom shortcuts take precedence; key codes, modifiers and standard type
are validated. Their symbolic IDs are 163, 160 and 36; documented fallbacks are
Fn-N, Fn-Shift-A and Fn-H. No preferences are changed and no Apple Events
automation, extra entitlement or external driver is introduced.

Keyboard invocations build both edges before posting, use exactly the shortcut
modifiers (not accidental held modifiers), and tag events as this interpreter.
Native Dock invocations send one message and no keyboard or mouse events. There is no autorepeat or delayed key-up. The selected shortcut plan
is cached until the next configure/permission refresh/selection change.

On Tahoe 26+, Apple's Launchpad shortcut opens its replacement Apps view. The UI
keeps the requested Launch Pad action label. Native delivery still needs hardware
acceptance; offline tests inspect complete events without posting them.

References: [Apple keyboard shortcuts](https://support.apple.com/en-us/102650)
and [symbolic identifier research](https://github.com/noah-nuebling/mac-mouse-fix/blob/master/Various%20Notes/SymbolicHotKeys%20Reference.txt).
Implementation is independent Swift; no third-party source or library is bundled.

Mission Control/App Exposé dispatch correction: the original Control-arrow
fallbacks did not work in the user's hardware test. The other three actions did.
Native Dock messages replace only those two paths, for both Force Click and
Pinch/Spread. One-shot activation, force haptics and all-up latching remain.
Protocol reference: [Dock action messages](https://gist.github.com/unixzii/7091dda6aea958c6da669e436365df65).

## Momentary layer release across pads (2026-10-23)

Primary MO contacts live in a separate momentary-layer table, not ordinary pending
or active key state. Missing-contact cleanup now reconciles that table against
each frame from its originating pad, including empty native frames with no
terminal touch record. Frames from the opposite pad never imply release.
A released layer-only contact cannot fall through to release-tap hit testing,
which would re-engage the layer at its former position. Explicit terminal release,
gesture reservation and normal momentary-layer held-key cancellation are retained.
Production replay covers both left/right layer sources, cross-pad number typing,
missing and explicit terminal release, and returning immediately to base typing.

### Thumb-required inward Pinch (2026-10-23)

All 2–5-finger inward Pinch inputs require at least one active making/touching
contact classified as Thumb (telemetry fingerID 1) on the activation frame.
Unknown/nil labels and non-thumb fingertips do not qualify; geometry alone is
not a thumb substitute. The requirement applies to every assigned action,
including Zoom and the Apple shortcuts. Ineligible inward pinching does not defer
ordinary movement activation. Spread activation is unchanged and does not require
a thumb. Keyboard candidate reservation remains conservative until all-up.

The thumb is an activation requirement, not a continuation condition. Once a
Pinch owns the cycle, label fluctuations, lifting the thumb, count changes and
motion reversal retain the original action/latch until all-up under the existing
integrity/lifecycle safeguards. Tests cover every count, unknown/non-thumb labels,
thumb lift/relabel, spread without a thumb, and pointer fallback.

Hand indicators are attached to each clickable subsection (Tap and Move, Pinch
and Spread, and the other action groups), not the finger-count headings. Pinch /
Spread examples show thumb plus 1–4 fingertips for counts 2–5. Tap/move examples
retain their existing fingertip diagrams and the fixed anatomical palette.

### Thumb rule applies to both directions (2026-10-23 correction)

The first implementation guarded inward Pinch only. That allowed a non-thumb
Spread to activate and remain latched through reversal into inward motion. Both
Pinch and Spread now require an active recognized Thumb (fingerID 1) to activate,
for all counts/actions. This supersedes the earlier Spread exception. Continued
latched motion still tolerates thumb lift/relabel; direction reversal cannot create
a new unqualified owner. UI labels identify the requirement for both directions.
Regression tests cover non-thumb opening followed by closing without all-up.

### Quick Reference-style sidebar indicators (2026-10-23)

Subheader labels now lead the row; their hand indicators are grouped at the right
edge (Left/Right/Both still selects which examples are shown). Finger-count
headings remain text-only; the full subheader stays clickable. Original vector
hand silhouettes use red contact markers and blue tap rings, inspired by page 1
of FingerWorks' [Quick Reference Guide](https://images-na.ssl-images-amazon.com/images/I/91xS3iP3tHL.pdf).
Combined Tap and Move examples show red dots with blue rings. The live contact
visualizer keeps its anatomical palette; only sidebar diagrams change.

The two-finger Pinch/Spread example shows thumb+middle; the three-finger example
shows thumb+middle+ring. These are preferred examples, not extra matching rules.
Recognition still accepts thumb plus any appropriate number of fingertips and
requires a recognized thumb only at activation. The guide's two-contact editing
examples use thumb+middle; this app's action assignments remain configurable.
The icon drawing was rendered and inspected offline at sidebar size.

### Paired right-hand action examples (2026-10-23)

Sidebar illustrations now represent actions, not left/right settings scope.
Pinch and Spread shows two right hands labeled Pinch and Expand, with converging
and diverging animated arrows. Tap and Move shows a right-hand tap with pulsing
blue rings beside a right-hand move with motion arrows. Four-finger movement /
force shows Move and Force examples; single-action sections show one right hand.
Left/Right/Both continues selecting settings only. Recognition/output is unchanged.

Animation is isolated to the icon TimelineViews at 12 fps, paused in background
and with Accessibility Reduce Motion enabled; arrows remain legible when static.
Original hand silhouettes remain vector artwork. Offline rendering was inspected
at sidebar size for direction, label legibility, alignment and clipping.

Pinch/Expand motion arrows now follow a diagonal through the thumb–index gap:
two inward arrows for Pinch and outward arrows for Expand. Move shows a four-way
arrow cross in the thumb–index gap. Indicators remain at 75% of their original hand size;
captions, tap pulses, Reduce Motion handling and recognition are unchanged.

## Three-finger drag natural-arch correction (2026-10-23)

The user's 3drag.atpcap contains 21 three-contact cycles. Most staggered landings
reach three contacts within 11–23 ms; the dominant failure was the old 8 mm
middle-finger distance-to-endpoint-line limit. Natural rows in the capture often
measured 9–13 mm. Offline replay of the production router/geometry produced six
drag activations before the change, twenty afterward. One brief three-contact
cycle loses its third finger before reaching the existing movement threshold.
This analysis does not exercise live event output.

Row activation now permits an arch depth up to min(14 mm, 35% of endpoint span).
It retains 2–60 mm pair distances, 35 mm middle-to-endpoint limits, finite/valid
contacts, and explicit thumb/palm rejection. This app-local tuning supersedes the
ported 8 mm value; no sibling projects changed. The 0.35 mm movement threshold,
shared latch, acceleration and held-button output are unchanged. No landing timer
or ownership switch was added. Regression tests cover 9/11/13 mm arches,
excessive curvature, staggered 1→2→3 landing, then 3→2→1→0 continuation.

The Move illustration's cross is shifted five display points left. Its Canvas
has extra transparent margin so the arrows remain visible without moving or
resizing the hand or captions. Offline rendering was checked for clipping.

## Same-pad momentary-layer keyboard chords (2026-10-24)

Once MO(n) is held, its originating pad has keyboard priority through that pad's
all-up frame. Adding another finger for a key on the same pad no longer reserves
a two-finger gesture or removes the layer hold. This is an explicit exception to
gesture-first keyboard arbitration for an already-established keyboard chord.
The opposite pad continues ordinary gesture/typing arbitration independently.

The serial engine marks the originating device when a primary or hold MO action
activates. Both raw-frame paths honor that ownership before gesture reservation.
Live ingestion skips native gesture output for that pad, cancels its prior
recognizer state once on entry, and consumes the final all-up frame to clear tap /
force cancellation flags. The cycle remains keyboard-owned if the MO finger lifts
before the other key finger; layer release still returns immediately to base.
Normal gesture eligibility resumes with a fresh all-up cycle, or after reset.
No global cross-pad gesture reset is used. Replay produces no gesture output.

Regression coverage: same-pad MO + Left Arrow on either pad, independent opposite-
pad gesture reservation, thumb-first lift, empty-frame layer release, reset, and
restoring gesture reservation on the next cycle. No recording was needed to
reproduce the previous unconditional layer cancellation.

### Contact-only example diagrams (2026-10-24)

Removed the example hand silhouettes. Red/blue contact markers, tap pulses,
directional arrows/crosses, captions and spacing remain in their existing positions.
Animation, Reduce Motion behavior and recognition are unchanged.

Contact-only example dots and tap rings now use the same AnatomicalFingerPalette
as live contacts: thumb orange, index blue, middle green, ring purple, pinky pink.
Motion arrows remain neutral; captions, geometry and animation are unchanged.

The pinch/spread examples are labeled Pinch and Spread beneath their diagrams.
Tap/Move/Force captions remain. Anatomical colors apply to both the contact dots
and pulsing rings, using the live palette directly.


### Small-step volume and display brightness actions

Tap, force-click, and Pinch/Spread action menus offer Volume Up/Down (Small Step)
and Brightness Up/Down (Small Step). Each recognition sends one balanced media-key
pair with Option–Shift, using GlassToKey's media codes 0/1/2/3, subtype 8 and
0xA/0xB states at the session event tap. No modifier keys are held or system
preferences changed. Pinch/Spread emits once on activation, preserving its all-up
latch; continuing movement does not repeat adjustments. These actions persist
per hand and travel with keymap gesture settings. Existing output eligibility and
replay suppression still apply. Brightness/volume support depends on the current
display/audio device, as with the keyboard controls.

Apple documents Option–Shift fine adjustments in
[Mac keyboard shortcuts](https://support.apple.com/en-us/102650).

### MO starting-frame ownership fix (2026-10-24)

The same_hand_layer_bug capture shows successful cycles beginning with `making`
and failed cycles beginning with `starting` (first failure at sequence 1150).
MO activates in either state. Cycle cleanup must also count `starting` as contact,
or it drops keyboard ownership on the activation frame and the next same-pad
finger reserves a gesture, cancelling the held layer. Both production frame paths
and native layer suspension now use matching contact phases. Offline regression
covers starting → making → repeated same-pad arrow taps on either pad, followed
by all-up cleanup; the test fails before this correction.

### Established modifier keyboard priority (2026-10-24)

User-authorized extension of MO priority: a modifier owns its originating pad's
keyboard chord after its key-down has been dispatched. This includes Shift, Ctrl,
Option/AltGr, Cmd, Hyper and modifier-only combinations, as primary or explicit
hold actions. Pending ordinary keys do not claim ownership. Same-pad gesture
reservation and native output stay suspended through all-up; the opposite pad
remains independent. Lifting the modifier releases its flags immediately, while
remaining contacts retain keyboard priority until all-up. Reset clears ownership
and balances held modifiers. Internal layer-only ownership names are generalized
to keyboard-chord ownership; no profile or capture schema changes.

Offline regression covers repeated same-pad modified taps on either pad, combined
modifiers, hold-assigned Shift, opposite-pad reservation, both release orders,
reset and restoring gesture eligibility after all-up.

## Expanded assignment workspace (2026-10-24)

The Gestures tab now replaces the trackpad/visualizer area with a chord browser,
assignment canvas and selected-action inspector. Keyboard returns to the original
keymap/trackpad editor. Device selectors and the takeover checkbox remain available
above the gesture workspace, so emergency/ownership controls are not hidden.

Only current GesturePane/GestureTrigger inputs appear: taps, existing XY movement,
1–5 contact force clicks, thumb-required pinch/spread and thumb+two-fingertip tap.
Every existing input appears once. Chord illustration anatomy is illustrative;
no new compact/spread classifier or directional/rotation input is introduced.
The workspace retains the anatomical colors and contact-only examples.

The user requested Left/Right only. They edit independent per-pad settings, using
the existing controller and persistence path. No Both selector and no coordinated
two-hand inputs are offered. The underlying saved both-hand editing API remains
compatible, but is not a coordinated gesture recognizer.

Select an assignment card to change its existing Action menu. Behavior is a
read-only description of that action's implemented output. Pointer, scroll and
zoom sliders retain their existing per-hand shared scope. Hold/Lift cards explain
existing lifetime and mandatory release behavior; they are not new assignable
recognizers. Action changes, reset behavior and keymap gesture import/export are
unchanged. Runtime status/permission failures remain visible in the inspector.

Offline tests verify full one-to-one trigger coverage, behavior descriptions and
native SwiftUI rendering without input clients. Optional AMT_WORKSPACE_PREVIEW_DIR
writes the value-only rendered layouts for visual inspection. No live input or
new settings are enabled by rendering.

### Shared header and resizable columns (2026-10-24)

Device selectors, refresh and takeover controls now occupy the shared header in
Keyboard and Gestures. The lower Keyboard content holds the visualizer on the
left and settings menu on the right. Gestures retains navigation on the left,
assignments in the middle and an inspector on the right. Left/Right has no visible
label and fills the gesture navigation column; its accessibility label remains.

Keyboard's settings menu has its own saved width (381 points by default, one
point above the stacking threshold; bounded 220–620). Gesture navigation and
inspector have independent saved widths, both defaulting to 286 points. Navigation
is bounded 220–620 and the inspector 200–480, reserving room for center content.
Eight-point drag targets have
resize cursors, visible grips and accessibility increment/decrement actions.
Window shrinkage clamps displayed widths without overwriting the saved choice.
Widths are app-local UI preferences, not keymap gesture/recognition settings.

Narrow Keyboard menus stack labels and controls below 380 points. The old inner
420-point sidebar frame is removed; typing sliders and mode toggles fit the
available width and the menu scrolls vertically. Each column width remains persistent. Import/Export stack vertically below the
same 380-point breakpoint and remain equal-width side-by-side above it. Mode
Toggles uses one vertical column at every width.

### Mirrored editing (2026-10-24)

Mirror Edit is a persistent, default-off editor preference beside the Gestures
heading, above the hand selector. It disables the single-hand selector and routes action and sensitivity
edits through the existing both-pad settings scope. It does not copy settings on
enable: differing assignments/gains show Mixed until edited. Turning it off
restores the selected single-hand editor. Recognition remains independent per pad;
this is not coordinated two-hand recognition. The preference is app-local; the
resulting per-hand bindings/gains still round-trip with keymaps.

### Animated trackpad examples (2026-10-24)

Gesture demonstrations now use a trackpad outline and blue contacts inspired by
mac/frame1.jpg–frame3.jpg: a continuous 30 fps eased motion between rest, active
contact and release, with fading motion trails. The selected assignment determines
the demonstration (tap/force/move/pinch/spread), including the starting count and
thumb geometry. Reduced Motion and actual window visibility pause animation. These
are illustrative drawings only and never access devices or dispatch input.

Tap examples follow mac/tap_frame1.jpg–tap_frame4.jpg with continuously expanding
halos, hollow lift contacts and an empty-pad rest. Force examples emphasize the
pressure halo. None of these timings or graphics change recognition thresholds.

Movement demonstrations follow the eight drag_frame references and
mac/drag_recording.mov. Hollow contacts fill on touch, move with blurred fading
trails, pause and return, then lift and fade. These illustrations belong to their
input triggers independently of their assigned outputs. Recognition is unchanged.

Config uses an AppKit NSWindow/NSHostingView rather than a SwiftUI Window scene.
Do not gate demonstration playback on scenePhase (it can remain background while
Config is visible). A local AppKit visibility observer now resumes on window
visibility/occlusion changes and pauses on cover/minimize/close. Reduced Motion
and deterministic preview phases still pause playback. No live input is accessed.

Force-click demonstration pressure halos are red; contact markers and ordinary tap
halos remain blue. Pinch/spread illustrations scale around the contact centroid,
recentered in the trackpad, so two contacts move equal distances at equal speeds
in opposite directions. This corrects the earlier pad-centered unequal travel;
recognition, force thresholds and haptic feedback are unchanged.

Three/four/five-contact illustrations now use a natural fingertip arch (middle
highest, pinky lower, thumb offset for five), shared by taps, force clicks, movement
and scale examples. This is illustration geometry, not a recognition constraint.

Demonstrations use elapsed time from their own playback start, rather than a shared
wall-clock phase. Restart at the beginning when the view appears, the selected
input/family changes, the window becomes visible again, or Reduce Motion is turned
off. Hidden-window playback stays paused; deterministic previews retain their
explicit phase and Reduce Motion retains its static representative pose.

All current Move in any direction inputs use the same four-stroke animation as
the approved four-finger scroll example: top/down/up/fade, left/right/left/fade,
repeat over approximately 9.3 seconds. Two-, three- and four-finger examples keep their own
natural contact arrangements and stay in contact through each return stroke.
All restart when selected or shown; these changes affect demonstration only.

Movement-example stationary holds are now half their original length: the combined
turnaround hold is 0.784 s (previously 1.568 s), and the pause before lift is 0.168 s
(previously 0.336 s). Touch, movement and lift/fade retain their original speed;
the complete two-axis cycle is 9.296 s. Tap, force and pinch examples are unchanged.

All animated contacts now use the live hardcoded anatomical palette for fills,
outlines, ordinary tap halos and trails, across every contact count. Thumb orange,
Index blue, Middle green, Ring purple and Pinky pink. Force pressure halos remain
red. This replaces the temporary two-contact outline/four-contact fill comparison.
Pinch/spread and movement share the same blurred fading trail renderer; scale
examples sample their actual previous positions so each trail follows its dot's
direction and finger color. Motion geometry, timing and recognition are unchanged.

Pinch/spread demonstration travel is wider (scale 0.65 to at most 1.65, bounded
by pad edges for larger chords) and completes in 1.176 s instead of 1.624 s.
The larger, faster motion makes the shared colored trails easier to see. Pinch
and spread use the same endpoints in reverse, keeping two-contact travel equal.
This is illustration tuning only; zoom sensitivity and recognition are unchanged.

Keyboard/Gestures tab switching destroys and recreates the visualizer's native
view. Render revision updates now create a fresh bounded subscription per attach;
canceling a detached visualizer removes only that subscriber. The snapshot service
broadcasts coalesced revisions on its delivery queue, outside the input path and
outside its subscriber lock. Input, recognition, takeover and snapshots continue
through tab switches. Offline tests reproduce cancellation/re-attach and overlapping
old/new subscribers; both failed against the previous single reusable AsyncStream.

### Movement cross editor: GUI stage

Two-, three- and four-finger movement use Up/Down/Left/Right cards around a center
Movement card. Continuous and Directional are mutually exclusive modes per input
and per hand. Active mode uses an accent tint; inactive cards are muted but remain
clickable to switch. Tap and Force Click occupy the top-left and top-right cells beside Up, with
equal column widths. They remain independent of the movement mode. Missing
tap inputs (such as four-finger tap) leave that cell empty.

Selecting an outer card selects directional mode; selecting the center restores
continuous mode. Choosing a direction's Action also selects directional mode.
Bindings in both modes are preserved. Directional actions allow None, mouse clicks,
Apple shortcut actions and small-step volume/brightness controls. Mirror Edit
updates both hands and displays Mixed for different modes or assignments.

Three-finger directional recognition is now live; two- and four-finger directional
assignments remain saved-only. Directional mode suppresses that input's continuous
output in the routed configuration, while retaining its original saved binding.
The editor identifies which inputs are available. No new GestureTrigger values
are required; the shared session still owns the existing movement input.

Optional per-hand directionalMovement fields round-trip in existing gesture/keymap
settings. Old profiles default to Continuous. Tests cover persistence, mirrored
editing, mode switching without data loss, allowed actions and inactive-output gates.

Selecting an Up/Down/Left/Right card now shows a matching single-direction swipe
illustration: hollow contacts at the opposite edge, touch/fill, slide in the chosen
direction with colored trails, brief pause, release to hollow, fade, empty-pad
rest. The 2.8 s loop restarts on direction changes. The center Movement card keeps
its complete two-axis return cycle. This preview does not enable directional
recognition or dispatch; direction assignments remain saved-only in this stage.

The Thumb+2fingers page is grouped under 3 fingers in the navigation, alongside
Tap and Move and Pinch and Spread. Its existing thumb-plus-two tap trigger,
anatomical illustration, assignments and saved identifiers are unchanged.

### Three-finger directional test and repeat control

Only three-finger movement has live directional output in this stage; two-finger
mousing and four-finger continuous scrolling are unchanged. Select a three-finger
outer card to use directional mode, or the center to restore Drag / Select.
Defaults do not change any assignments or activate directional mode automatically.

The existing row/arched-three-fingertip router owns the gesture and latches through
added/lifted contacts until all-up. Pinch/spread and force-click arbitration remain
in place. After ownership, a pure per-device stepper needs 0.75 mm on a dominant
axis (1.25 ratio) to emit a direction. Deliberate turns/reversals need 0.75 mm in
the new direction; small jitter does not switch it. Screen-space up is negative Y.
These thresholds are provisional for hardware testing.

Each direction has a compact saved millisecond interval field (repeat icon), including
Mirror Edit and Mixed states. The clickable loop enables/disables repeat: off
is crossed out and mutes/disables the interval field while retaining its value.
Enabled values are bounded
to 20–5000 ms. Missing settings default to 80 ms for small-step volume/brightness,
zero for other actions. Old checkbox true/false decodes as 80/0 ms. A newly enabled
unset interval starts at 20 ms; volume/brightness retain their 80 ms default. Explicit
intervals survive action changes and keymap export/import. Two/four-finger
intervals remain saved-only, matching their directional assignments.

The first action fires when the direction activates. A host-clock scheduler then
repeats at the selected interval while the same latched chord remains held, even
when stationary. A deliberate direction change emits immediately (subject to the
existing 80 ms direction-change guard) and starts the new direction's interval.
At most one event is emitted per timer tick; missed ticks never cause catch-up
bursts. The existing 120 Hz timer services repeats alongside momentum/watchdogs,
so intervals are approximate. Native frame timestamps never enter repeat timing.
0.75 mm is a provisional responsiveness threshold, not a tap minimum: the shared
router already arbitrates movement ownership at 0.35 mm. Preserve that arbitration.
Each click/shortcut dispatch uses balanced one-shot output; no directional mouse
button or key is held. Dock actions use the existing cached native dispatch plan.

Selected/owned/armed/Accessibility/live-only gates still apply. Three-finger
candidates reserve typing even when output permission is missing; an active owner
cancels taps and other continuous outputs. Same-pad established layer/modifier
holds keep their existing keyboard priority. Reset/reconfigure, force takeover,
disconnect, all-up, stale/nonfinite input and contact discontinuity discard the
stepper and repeater. The timer stops held output after 200 ms without contact
delivery; no indefinitely repeating stale chord. Replay never posts directional
output. No new hot-path I/O is added.

Offline tests cover all axes, thresholds/diagonal ambiguity, stationary timed repeats/no catch-up bursts, repeat off, direction changes, reset/stale input, independent pads, the
shared all-up latch through membership changes, unchanged two-finger routing and
repeat defaults/legacy migration/interval bounds/persistence. Hardware acceptance remains the next step.


## Cmd+S followed by failed two-finger clicks: capture investigation

Capture: `tap_normal_drag_normal_HOLD_S_buggy_click.atpcap` (831 processed frames,
about 16.3 seconds). Times below use arrival ticks relative to the first record;
native timestamps have different offsets on the two pads.

- A normal tap is accepted offline at 2.992 s.
- The recognized three-finger drag begins at 6.446 s and ends at 7.694 s.
- The left pad emits one Cmd+S `keyStroke` at 10.322 s, not a stream of repeats.
- Offline replay through the production contact router and tap recognizer accepts
  taps at 12.667, 13.555, 14.446 and 16.087 s after that shortcut. The tap near
  15.322 s instead crosses the existing movement activation threshold.
- All contact cycles have all-up releases. The keyboard dispatch queue depth and
  drop count remain zero in this recording. This does not prove no raw/native
  frames were lost: the bridge's raw-delivery overflow is not currently counted
  by the capture's live-drop metric.

The capture records keyboard dispatch but not native gesture mouse output or
WindowServer modifier state. It establishes valid tap input after Cmd+S, not
that each click reached the target application or that Command was stuck there.

The previous one-shot keyboard dispatcher put the shortcut flags on both S-down
and S-up. Gesture clicks inherit combined-session flags, so retained Command is
an output-state explanation consistent with the report. The focused fix now
captures flags before posting a one-shot keystroke and restores them on its up
edge, rather than leaving that shortcut's added modifiers on the final event.
Pre-existing held modifier flags are preserved. The explicit held-key/modifier
path and drag timing are unchanged. Offline tests construct actual production
key/click events without posting input; hardware acceptance must repeat the
hold-S then tap sequence in the affected app.


## Coordinated Both-hand gestures

The Gestures hand selector now offers Left / Right / Both. Both selects a separate
coordinated assignment collection: one input involves both selected pads. Mirror
Edit is disabled in that view and retains its independent per-pad meaning.
Existing Left/Right assignments are neither copied nor replaced.

| Coordinated chord | Contacts | Tap | Hold |
|---|---|---|---|
| 4 corners | Left: top-left + bottom-left; right: top-right + bottom-right | Default None | Default Open Config; 1 s |
| 3 fingers per hand | Three contacts on each pad; six total | Default None | Default None; 0.5 s |
| 4 fingers per hand | Four contacts on each pad; eight total | Default None | Default None; 0.5 s |

Every slot can choose None, Open Config, a balanced mouse click/double-click/
secondary click, the supported Apple actions, or small-step volume/brightness.
Hold fires the assigned discrete action once, consumes Tap, and never repeats or
keeps a mouse button/key down. Continuous drag/scroll/zoom output is not offered
for these discrete slots. Assignments persist in `HandGestureSettings.coordinated`
and travel with existing gesture/keymap export/import. Missing coordinated data
preserves old profiles and supplies the defaults above.

Provisional recognition rules for hardware testing:

- Two distinct selected pads, both owned by native takeover and output-armed.
  Open Config does not require AX; synthetic mouse/system output does.
- Common host time across pads; their native timestamp offsets can differ.
- Single-hand taps and continuous gestures run immediately; there is no join
  grace period or delayed local output. A second hand may join later, as long as
  both contact sets are current and match an enabled coordinated chord. The
  complete chord rebases contact positions and starts its tap/hold clock then.
- Corners use the outer 20% of X and top/bottom 20% of Y on each pad. Corner hands
  may land separately before the complete chord starts its one-second hold.
- On acquisition, the coordinated chord replaces existing single-hand gesture
  ownership, releasing drag buttons and ending scroll/zoom/directional output
  before its own output. Already completed clicks/actions cannot be undone.
  Established keyboard layer/modifier holds still take priority.
- A Tap ends on both-hand all-up within 0.5 s of the complete chord, with at least
  20 ms contact and at most 150 ms lift skew. Hold begins only while both original
  contact sets remain down. Each tracked contact has 2 mm motion slop.
- Shared ownership persists through partial lifts, added/replaced fingers or
  invalid/moving contact data until both hands are up. Such disqualifications
  suppress further output, rather than handing the cycle to local typing/mousing.
  Hold excludes Tap. Both independent outputs are canceled only at acquisition;
  subsequent frames must not re-block the already released other hand.
- The existing shared timer checks holds and freshness. More than 200 ms without
  updates from either hand invalidates the cycle. No held output can escape cleanup.
- Sleep/replay/quit, release, lost ownership, selection/settings changes and stop
  reset the coordinator. Replay never invokes the live coordinated entry point.

The reference map's G041 describes the four-corner one-second configuration hold;
see `Design/GestureAssignments/GESTURE_MAP.md`. The 20% zones, 150 ms lift
window and 2 mm slop here are implementation choices, not firmware claims.
Offline tests cover taps/holds/default corners, timing, all-up, stale input,
identity/movement/count rejection, immediate single-hand output, late joining and balanced handoff,
selection eligibility, Mirror isolation, old profiles and keymap round-trips.
Offscreen previews cover all six Both assignment pages without opening devices.
Hardware acceptance remains necessary for the new gestures.


### Immediate single-hand → Both transition

User requested removing the candidate join delay. The coordinator now observes
single-hand input without reserving it. When the second hand forms an enabled
chord, its acquisition decision cancels both local gesture states exactly once;
`PrimaryDragOutput.end` supplies the reserved up edge before any coordinated
Tap/Hold action can dispatch. Samples anchor at acquisition so preceding single-
hand travel does not disqualify the new shared cycle. Both must lift to rearm.
The tap duration is measured from the completed two-hand chord, not the first
hand's earlier landing. Hold and tap recognition thresholds otherwise remain.


## Independent simultaneous hands and editable repeat intervals

The prior runtime globally rejected other-pad frames while a primary drag was
owned. That restriction is removed. Per-device recognition, tap latches, scrolling,
zooming, directional repeats and acceleration can now run concurrently. Starting
a drag cancels only that device's scroll, preserving the other pad's scroll state.

The system still has one cursor and one primary button. While any drag owner is
active, two-finger pointer motion from either pad uses the last queued drag
position and emits `leftMouseDragged` through the existing private drag source.
It does not acquire button ownership. Releasing that pointer's pad therefore
cannot end the drag. Two independently recognized drags may share one button down;
ending/staling/resetting one owner retains the other, and the last owner posts
the reserved up at the latest shared location. Emergency/global release emits one
up and clears all owners. Coordinated Both acquisition still cancels both pads'
independent outputs before taking ownership.

Discrete primary click/double-click output is suppressed while a drag holds that
same primary button, so its up edge cannot prematurely end another pad's drag.
Other discrete output remains available; real external mouse presses retain the
existing interruption policy. New regression tests exercise both hand orders,
shared motion, dual owners, per-owner versus global release, and concurrent
scroll/directional recognition without posting live input.

The compact repeat interval now edits a local string draft. Backspace may leave
it completely empty while entering a replacement such as 80. Return or focus loss
commits a valid finite number bounded to 20–5000 ms. Blank/invalid commit restores
the previous value. Typing an intermediate digit never saves settings, clamps the
visible draft or resets an active gesture. Disabling repeat discards an unfinished
edit and retains the saved interval. The loop remains the enable/disable control.


## Two-finger directional output

Two-finger directions are now live, using the same discrete action dispatcher and
held-repeat policy as three fingers. The earlier two-finger editor saved actions
but never dispatched them; the controller, keyboard reservation and runtime now
route both supported inputs. Four-finger directions remain saved-only.

Runtime configuration is keyed by selected device and movement trigger. Two- and
three-finger assignments coexist independently. The latched directional stepper
remembers its owning trigger; the shared repeat timer looks up that trigger's
assignments, not the current finger count. A two-finger chord can continue through
added/lifted fingers until all-up under the existing shared session rules.

The 0.75 mm dominant-axis activation/turn threshold, timed repeats, tap exclusion,
force/pinch arbitration, selected/owned/armed/AX/live gates and stale cancellation
are shared with three fingers. Switching center Movement back to continuous
restores normal pointer output without deleting directional assignments. Existing
settings and import/export formats already contain both inputs; no migration or
factory mode changes are required. Tests cover independent configurations,
activation/turn/repeat, surviving one finger, release and continuous-mode fallback.


## Four-finger directional output

Four-finger Up/Down/Left/Right assignments now dispatch live through the same
shared engine used by two and three fingers. This supersedes all earlier
saved-only four-finger restrictions in this document. All movement inputs use
one supported-trigger list; the controller/status, keyboard reservation, contact
router, discrete dispatcher and held-repeat timer route the latched trigger.

Each direction supports the same mouse/Apple/small-step volume/brightness actions
and loop enable/disable with remembered 20–5000 ms intervals. Recognition uses
the same 0.75 mm direction/turn threshold and dominant-axis rules, per-device
contact ownership, force/pinch arbitration, stale-input cancellation, selected/
owned/armed/AX/live gates, independent-hand output and Both-hand handoff.

Four-finger continuous Scroll / Pan remains the factory assignment. Selecting a
direction switches to directional mode and disables continuous scroll for that
input; directional output must not feed scroll momentum. Selecting center
Movement restores continuous scrolling/momentum while keeping all directional
actions and repeat settings. No profile/default migration is needed; exported
settings already include the four-finger configuration.

Offline coverage includes four-finger activation, turns/timed repeats via the
shared policy tests, partial-finger continuation, all-up, independent assignments,
no continuous scroll routing in directional mode, scroll restoration and keymap
round-trip. Offscreen previews include the four-finger directional editor.

## Single-hand stationary Hold

Session Lifetime now contains a Hold Action menu for each contact count (1–5),
per hand and with Mirror Edit. It remains visible while a direction is selected.
Defaults are None; existing profiles keep their actions and gain no new output.
Optional `holdActions` fields in each hand's settings round-trip through Import
Settings / Export Settings with the existing gesture extension.

On Tap/Move assignment pages, Hold is available alongside BOTH continuous
Movement and directional assignments. Bindings alone no longer lock Hold.
Actual movement or shape motion competes with stationary Hold before activation.
On the Pinch and Spread pages themselves, Hold remains an automatic, gray,
nonassignable lifecycle card. These pages cannot edit the count's Hold binding.

Hold is a selectable assignment card; its Action menu is in the right inspector,
matching other configurable cards. Mirror Edit supports both continuous and
mixed movement modes. Hold uses the contact count, not the thumb/fingertip
identity for ordinary count-based inputs. Thumb+2 now has its own anatomical
Hold binding, independent of ordinary three-finger Hold (see below).

A stationary chord fires its discrete action once after 0.5 seconds. Fingers can
join within 80 ms; the timer starts when the complete count lands. Substitutions,
early lifts, palms, invalid coordinates, non-increasing native timestamps, a
native frame gap over 150 ms, or per-contact displacement over 2 mm cancel the
candidate until all-up. Continuous movement and pinch/spread ownership cancel a
pending Hold immediately. Directional recognition cancels it when the shared
stepper actually chooses a direction (0.75 mm), rather than at the earlier
continuous-motion candidate threshold. An empty directional assignment does not
claim motion. A directional swipe or its stationary repeat cannot also become a Hold. Once
Hold fires, it owns the cycle through added/lifted fingers until all-up, preventing
a subsequent Tap, Force Click or movement action from the same cycle.

The existing shared timer can finish a Hold only with input fresh within 200 ms;
there is no timer per chord and no repeat output. Native frame time validates
ordering; host monotonic time measures the deadline. Per-device state keeps hands
independent. Force Click, Both-hand acquisition, established keyboard modifier/
layer priority, settings/device changes and lifecycle cleanup cancel pending
Holds. Both/keyboard release frames clear the Hold latch as well. Selected/owned/
armed/AX/live gates still apply; no acceleration profile is required for these
discrete actions. A configured eligible Hold reserves its candidate before the
keyboard engine, including without output permission. An explicitly assigned
one-finger Hold therefore takes that touch cycle away from ordinary typing.

Offline tests cover count eligibility and saved-action preservation, old profiles,
Mirror Edit, portable round-trips, timer/freshness rules, motion arbitration,
all-up latching, independent hands, invalid/replaced contacts and keyboard
reservation. Hardware acceptance remains the user's test.

### Four-finger Hold capture regression

`LHS_4FHold_bad.atpcap` contains nine four-contact attempts lasting roughly
1.1–2.0 s each, with the final contact landing within 0–33 ms. Eight crossed the
initial 0.75 mm per-contact Hold limit before the 0.5 s deadline. Measured drift
at the deadline was about 0.65–1.95 mm. The former limit was rejecting ordinary
landing/settling; Hold now uses the same 2 mm stationary allowance as Both.

The current saved left-hand settings had four-finger directional mode with every
direction set to None. It still claimed raw movement at the earlier 0.2 mm
continuous threshold and canceled Hold. Inputs with no directional assignments
now stay out of movement recognition. For real directional assignments, early
movement candidacy alone no longer cancels Hold: the direction must commit.

An offline regression feeds the capture through the shared router, force,
directional and Hold recognizers using that left-hand configuration, checks one
four-finger Hold per attempt, and checks firing 0.50–0.55 s after the full chord
lands, while contacts remain down. It posts no events. The local capture is
optional when absent on another checkout. Capture profiles do not currently
include these app-local gesture preferences; the regression specifies them
explicitly rather than inferring them from the keyboard profile.

## Directional Scroll Up / Scroll Down

Two-, three- and four-finger directional Action menus include Scroll Up and
Scroll Down, independently assignable per direction/hand and through Mirror Edit.
These are motion-following actions, superseding the initial repeated wheel-step
experiment. The source direction selects the travel axis and positive sense;
the assigned action selects the output sign. Examples:

| Input | Action | Result |
| --- | --- | --- |
| Up / Down | Scroll Up / Scroll Down | Vertical travel scrolls in the same named direction |
| Up / Down | Scroll Down / Scroll Up | Vertical travel reverses the named scroll direction |
| Left / Right | Scroll Down / Scroll Up | Horizontal travel scrolls vertically |

Project each frame's contact displacement onto the committed input direction.
Ignore perpendicular or opposite travel while waiting for a deliberate turn;
never take the absolute value of the source displacement. Feed positive projected
millimetres through the selected pad's existing vertical Apple scroll profile
and per-hand scroll sensitivity, then apply the explicit Up (positive) or Down
(negative) output sign independently of natural-scroll preferences. Fine travel
preserves fractional pixels. Direction/action changes reset the acceleration
history and end the old scroll phase before beginning the next.

Reuse precise scroll begin/change/end/cancel events and the shared momentum
engine/timer. Movement controls output rate and distance; stationary contacts
produce no timed scroll. Observe stationary samples to prevent an old velocity
from flinging on a delayed lift. A normal all-up may coast; a turn to another
action, malformed/stale input, force/Both/keyboard takeover, settings/device changes
or lifecycle reset ends/cancels scroll and momentum. The existing directional
0.75 mm commitment, all-up ownership, per-device independence and selected/owned/
armed/AX/live gates apply. A readable scroll profile is required and status reports
when unavailable. No pointer movement is emitted by these actions.

Scroll selections show Scroll sensitivity and motion behavior instead of Repeat
controls. They ignore legacy repeat intervals/enabled fields while preserving
those fields for round-trip and reuse if the slot is changed back to a discrete
action. Volume/brightness and other discrete directions retain their repeat
behavior; they can coexist with scrolling on other directions. Continuous
Scroll / Pan retains its acceleration and momentum. Keep action IDs `scrollUp`
/ `scrollDown` and the existing settings schema; Import/Export retains assignments,
per-hand sensitivity and dormant repeat fields. These actions remain confined
to directional menus.

Offline tests cover all source axes/output signs with both natural-scroll
preferences, subpixel travel, stationary/perpendicular/opposite suppression,
turn/action rebasing, invalid input, profile processing, precise event phases,
legacy-repeat suppression, mixed actions and portable settings. Existing tests
cover momentum and reset/cleanup behavior. Offscreen previews include scroll
inspectors and both narrow/wide Pinch/Spread pages.

Pinch/Spread's nonassignable Hold and Lift lifecycle cards use identical gray
styling and stretch to the same row height while preserving wrapped text.

### Natural scrolling for normal Movement

Normal Movement → Scroll / Pan shows a Natural scrolling toggle directly below
Scroll sensitivity. Optional per-hand `naturalScrolling` settings preserve the
system preference when absent (old profiles); an explicit choice overrides the
selected pad's configured scroll profile without changing system preferences.
Mirror Edit changes both values, mixed values are visible, and Import/Export
retains the choice. It applies to normal Scroll / Pan across contact counts;
explicit directional Scroll Up/Down retains its named sign. Configuration resets
active output/momentum before changing direction, as for sensitivity changes.


### Directional Pan Left / Pan Right

Pan Left and Pan Right are motion-following directional actions in the same
family as Scroll Up/Down. Every input direction can map to either output axis:
Up → Pan Right translates upward finger travel to horizontal rightward panning;
Left → Pan Right reverses horizontal direction; Left → Scroll Down translates
horizontal travel to vertical scrolling. The assigned gesture always determines
which source component/sense to measure. The action independently determines
output axis and sign. Perpendicular/opposite travel remains suppressed until a
new direction commits, and a stationary finger produces no output.

Use the selected pad's horizontal Apple scroll profile for Pan, vertical profile
for Scroll, and the shared scroll sensitivity. Positive wheel axes mean Up/Left,
negative mean Down/Right. Explicit actions retain their named direction regardless
of Natural scrolling. Fine movement, precise event phases, momentum, reset on
turn/action changes, all-up/stale/lifecycle/AX gates and per-device independence
are shared. Pan actions have no timed repeats; dormant repeat fields remain saved.
The existing directional menus, Mirror Edit and Import/Export carry `panLeft` and
`panRight` without a new schema. They are not offered as Tap/Force/Hold actions.

Normal Movement → Scroll / Pan already handles both axes using the same
sensitivity, acceleration, momentum and Natural scrolling override. No changes
to those normal movement thresholds or timing are needed to unlock Hold: movement
that activates first cancels pending Hold immediately; a stationary Hold firing
at 0.5 seconds owns the rest of the cycle. There is no added delay to mousing,
dragging or scrolling. Hardware testing should assess how easily Hold can win
against the existing continuous-motion thresholds.


## Additional per-pad chords and searchable assignments

- Four-finger Tap is an independent trigger on the four-finger **Tap and Move**
  page, default None. It shares the count-based 2/3-finger tap recognizer: 0.5 s
  window, 80 ms landing/lift skew, 20 ms minimum full chord and 1 mm motion slop.
  Extra/replaced contacts, stale/invalid input and another gesture owning the cycle
  cancel it. Use the same discrete outputs, eligibility, keyboard reservation and
  all-up/reset/force/drag arbitration as the other taps.
- Thumb+2 Hold has a separate saved binding (default None), using the same spread
  geometry as Thumb+2 Tap: recognized thumb plus two interchangeable fingertips,
  closer pair 2–40 mm, nearest thumb distance at least 15 mm and 1.5× pair spacing.
  Tap and Hold share the geometry helper. Once positively matched, Hold tolerates
  fingertip relabeling/temporary Unknown with unchanged tracking IDs. A thumb
  chord cannot fall back to ordinary three-finger Hold when its own action is
  None. Hold fires at 0.5 s while down, once per all-up, with the existing 2 mm
  tolerance, movement-first arbitration and input freshness. Ordinary 3F Hold
  keeps its existing action and never inherits the Thumb+2 action.
- **4 Corners**, under each hand's 4 Fingers group, has independent Tap and Hold
  slots for four contacts on one pad, one in each outer 20% corner. Match the
  coordinated Both corner thresholds: Tap within 0.5 s, at least 20 ms down,
  150 ms lift skew, 2 mm movement tolerance; Hold once at 1 s, consuming Tap.
  Default Tap None / Hold Open Config. Unlike Both, a single native frame supplies
  all four anchors atomically. No half-frame samples from a previous report may
  complete the chord. Added/replaced contacts, movement, late re-addition, invalid
  input or >200 ms missing delivery cancel output but retain ownership until
  all-up. Settings/device/lifecycle changes reset the session.

Single-pad corners acquire before ordinary gestures/typing on that pad, after
coordinated Both acquisition. Existing established keyboard modifier/layer chords
retain priority; Both cancels the independent corner session on acquisition.
Other pads stay independent. Open Config is app-local and works without AX;
synthetic actions retain AX/selected/owned/armed/live gates. Corner recognition
and its shared-timer Hold do not run during replay. All-up, Both, keyboard and
force cancellation paths also clear the newly added four-finger tap state.

Persistence uses optional `fourFingerTap` / `fourCornersTap` binding fields and
reserved Hold binding keys: `6` = Thumb+2, `7` = single-pad 4 Corners (these are
binding IDs, not contact counts). Existing keys 1–5 keep their meanings. Old
profiles retain all existing assignments; new four-finger Tap / Thumb+2 Hold
slots default None, single-pad corner Hold defaults Open Config. Per-hand and
Mirror Edit changes, Import Settings / Export Settings and coordinated Both
settings remain independent and round-trip without a schema change.

The movement cross now places Hold immediately left of Down. Thumb+2 and single-
pad corners show Tap and Hold as peer cards. Pinch/Spread retains nonassignable
Hold/Lift lifecycle cards. Every gesture Action editor—Tap, Move, direction,
Force, Pinch/Spread, Hold and coordinated Both—uses a grouped, searchable sheet
shared with Keymap Tuning Primary/Hold. It lists only actions supported by that
input, shows the current choice, supports Mixed hand settings and empty search
results, and never changes settings merely by opening/closing or searching.
Keymap search still matches both labels and picker text; its action catalog and
semantics are unchanged.

Offline coverage: old-profile defaults, separate hand/chord actions and portable
round-trips; Thumb+2 matching/relabeling/no-fallback; four-finger tap completion,
skew and rejection; corner geometry, tap/hold separation, deadline lifts,
replaced/extra/moving/stale contacts and per-pad isolation; keyboard reservation;
search filtering, action-catalog coverage and offscreen keyboard/gesture sheets
and workspace pages. Hardware acceptance remains the user's test.

### Four-finger Tap System actions

Four-finger Tap now offers the same discrete action list as Force Click, including
Notification Center, Mission Control, App Exposé, Launch Pad and Show Desktop.
The old narrower Mouse Buttons / Sound & Display list was an oversight for this
new input. Existing 2/3-finger tap choices and all defaults remain unchanged.
Tap dispatch delegates to the same one-shot dispatcher as Hold/directions,
including native Dock requests for Mission Control/App Exposé and balanced
keyboard/media events for the other system actions. Do not route Dock actions
through a CGEvent-only tap path. Existing tap timing, per-pad/all-up ownership,
output permissions, drag-button protections and settings export stay unchanged.

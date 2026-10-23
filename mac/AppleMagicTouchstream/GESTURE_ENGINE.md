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
In Both scope, each finger-count heading places the left-hand diagram before the
label and the right-hand diagram after it. Clicking a subsection label or its disclosure arrow toggles expansion.
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
is supported without requiring accurate anatomical labels. Every contact
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

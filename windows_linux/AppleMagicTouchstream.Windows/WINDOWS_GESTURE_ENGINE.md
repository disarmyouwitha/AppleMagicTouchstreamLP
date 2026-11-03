# Windows gesture engine

Current recognition lives in Core HandGestureEngine/CoordinatedHandGestureEngine;
WindowsHandGestures adapts PTP contacts and gates native output. Mac is the reference,
with Windows anatomy/output limitations below. Shared legacy Linux recognizers are
retained; Windows explicitly selects the hand-gesture runtime.

## Recognition, ownership and configuration

Left and Right have independent assignments/gains. Mirror Edit changes both saved
hands; the Both page configures coordinated chords rather than merging per-pad
assignments. Tap, movement, directions, force, hold and supported shape inputs retain
stable settings identities. None is explicit. Custom shortcuts/Text use the shared
keyboard dispatch pump; only Hold accepts held shortcut output.

Ordinary count recognition keeps the existing row/geometry rules and coherent
identity-based motion. Landing/lifting contacts cannot jump a centroid. Assigned
2F taps retain the 1 mm/500 ms eligibility window before movement can acquire.
Three-finger drag/four-finger scroll competition uses bounded 80 ms fourth-contact
landing evidence, not the retired blanket 120 ms drag delay. Windows can supply
confident in-range non-tip PTP slots as pre-contact evidence. Activated ownership
stays latched through count changes until all-up.

Recognition, reservation, keyboard proposals and activated ownership are distinct.
Established keyboard modifier/MO/hold ownership retains same-pad priority.
Unresolved gestures retain bounded typing proposals; winners discard them.
Never-activated rollover may resolve at partial/all lift. Invalid, stale, overflowed
or reconfigured proposals cancel without typing. The terminating frame reaches
cleanup. Two-finger motion excludes pre-membership-change displacement.

Both 3+3 and 4+4 force require reported pressure on each pad, <=150 ms force crossing
skew and <=1 second cohort landing stagger. Existing activated single-pad owners
block late coordinated takeover. Force fires once and stays latched through both
all-up. Corner pairs may grow into full enabled chords before firing, with original
identity/slop limits; a fired owner cannot be replaced. Hold thresholds remain
independent, 100–5000 ms, default500. One-finger gesture Hold is unavailable.

Pads share primary drag ownership and the cursor. Other-pad mouse movement and
secondary clicks remain usable; the last drag owner sends button-up. Primary/
double clicks cannot interrupt a held primary button. Other-pad keyboard holds
and modifiers retain their own cleanup lifetimes.

## Output and motion

Output requires selected live ingress and Mouse Takeover; recognition/arbitration
outside STENO still protects native gesture cycles from accidental typing when
Takeover is off. Replay has no native output. Takeover transitions cancel output,
retain all-up barriers and use the existing emergency/sleep/disconnect lifecycle.
Button-up cleanup remains available after eligibility loss. External injected
button-down interference cancels our owner; output failure/overflow releases
Takeover. Windows shell gestures may still conflict and need OS settings changes.

**Motion (updated after hardware feedback):** movement and drag now default to the same parametric Apple acceleration equations as Mac, with the recorded reference coefficients from Mac `ApplePointerAccelerationTests.installedExample()`: resolution 400, acceleration index 3, multiplier 48545/65536, linear 1, parabolic 123208/65536, cubic 23593/65536, linear tangent 7 and root tangent 12. These are a reference preset, not a query of this user's active Mac/Windows tracking setting. The Mac cross-language golden vectors pass against the C# model to 1e-9 tolerance. It retains the Mac contact-mm-to-count hypothesis (resolution/25.4, with sensitivity before acceleration), rate/multiplier behavior, 96/67 output scale, and finite-value safeguards. The Windows screen-space limit differs as described in the fast-motion fix below.

The Action inspector offers **Use captured Mac pointer and scroll** for Pointer/Drag and Scroll assignments. It is opt-in, independent per hand, and follows Mirror Edit. Enabling restores the source Mac's sensitivity/direction; those controls remain adjustable. The selected response also serves STENO pointer movement. Disabling restores the accepted reference pointer/fixed-scroll response. Profiles are bundled and validated once on the configuration path. See [MotionProfiles/README.md](MotionProfiles/README.md) for capture provenance and testing. No proprietary upstream processing or identical visual travel across display scales is claimed.

Pointer injection uses absolute virtual-desktop coordinates to avoid adding Windows relative-mouse acceleration. Subpixel remainders are retained; drag positions accumulate from the last queued destination and clamp to the nearest display.

**Scrolling:** the captured-Mac option uses the Mac per-axis parametric history/acceleration model and contact-mm-to-count conversion. The legacy option uses fixed 6 scroll points/mm. Both feed the same momentum model. Touching either pad brakes a released coast without clicking. The per-hand **Natural scrolling** checkbox reverses both axes and momentum; Both displays an indeterminate state when hands differ. Existing direction is preserved by default (checked); uncheck to use the opposite direction. Ten points map to one Windows wheel detent (120 units); fractional units are retained. Vertical sign follows natural scrolling; horizontal sign is reversed for Windows' wheel convention. The current SendInput wheel adapter does not expose macOS pixel-scroll phase/momentum fields, and application handling of small wheel deltas varies. Test direction, pan, speed, and momentum in actual Windows applications.

**Shape gestures:** each 2–5-finger page contains independent Pinch, Spread, Rotate Left and Rotate Right assignments. Pinch/Spread retain the accepted RMS pair-distance model and 0.6 mm shape threshold. Rotation uses stable contact IDs, at least 3 degrees of turn, 0.75 mm angular travel and angular-over-radial dominance. Geometry rebases on membership changes; the chosen action/direction remains latched through count changes and reversals until all-up. Translation competes coherently across the whole group when rotation is enabled. An activated shape wins over a pending Hold; configured reported-pressure Force can end it and claim the cycle.

Discrete shape actions offer Once, timed repeat (20–5000 ms, default 80), and motion repeat (each 5 degrees or logarithmic 6 percent scale in the activated direction). Motion reversal subtracts progress; stillness emits nothing in motion mode. Timed repeats require fresh contact frames and never catch up in bursts. Cleanup clears per-pad repeat state on lift, invalid/stale input, output ineligibility, settings changes and cancellation. Zoom remains continuous. Settings, full exports, Left/Right, Mirror Edit and same-device fallback preserve the repeat behavior.

**Anatomy:** PTP tracking IDs identify contacts, not fingers. The current decoders provide no positive thumb/fingertip/hand classification. The spread-thumb recognizer therefore cannot safely choose Secondary Click. Its assignment menu remains editable (None and all mouse click actions), with a visible unavailability note; its inactive effective binding does not reserve three-finger input by itself. Unknown three-contact taps use the ordinary three-finger tap action, matching Mac's unknown-identity fallback. Pinch/Spread use geometric recognition without a thumb prerequisite. Rotation uses an all-contact centroid fit; actual positive anatomy, if available offline, selects Mac's thumb-to-fingertip-centroid model. No thumb classification is inferred. Windows rotation triggers run assigned actions/shortcuts; there is no fabricated native Rotate Content event.

**Reset:** changes to settings/routes stop output and require a clean all-up boundary before recognition resumes. Lift all fingers once after enabling or changing settings. This also prevents a contact already down during a change from becoming an accidental click or drag. Cancelled/discontinuous cycles remain blocked until all-up rather than attempting an in-cycle recovery.

**Recognition feedback:** the live pad headers show the latest recognized gesture beside Peak, matching Mac's two-second lifetime. Gestures also displays recent Left/Right recognition in its footer. The recognizer records only gesture identity/direction/count and host time; it never derives feedback from a dispatched shortcut. Continuous owners refresh their original gesture label through count changes; discrete taps/Force/Hold remain visible briefly after completion. Both feedback appears on both pads. STENO retains its separate 2F mouse, 1F drag, 2F/3F click and 4F force-scroll names. Invalid/stale input, cancellation and configuration resets clear the applicable feedback. Reading UI snapshots starts no input/output and stores no capture/settings/custom-action payload. Replay does not display live recognition. Long labels truncate within their own pad header.

**Routing:** with the same physical path selected in both slots, only one frame reaches the gesture/keyboard actor. An active Left binding wins, with Right used when Left is None; Left gains win. Both visualizers may observe the frame. Selecting separate paths gives independent per-hand sessions.

**Output and cleanup:** the existing actor serializes recognition and keyboard arbitration. A bounded, separate output worker performs SendInput without holding the actor/configuration locks: SendInput can call the UI thread's low-level hook. Queue generations discard cancelled work; stale queued commands are not injected. Takeover is rechecked before posting. Button-up cleanup passes even when takeover is off. The worker also releases a held drag on takeover loss or an input stall. Output failure/overflow requests fail-open takeover release. External injected button-down events, distinguished from our own tagged output, cancel gesture ownership; no marker is treated as a hardware device identity.

Sleep/session changes, emergency release, timeout, decoder faults, disconnect handling, and shutdown continue to use the existing Mouse Takeover lifecycle. Native hook removal/timeouts and SendInput restrictions against higher-integrity applications remain platform limitations. An active status is not proof of device-exclusive ownership.


## STENO and Layout Editor

[WINDOWS_REWRITE.md](WINDOWS_REWRITE.md) defines current STENO layouts, fixed mouse/
force actions, haptics, built-in translation, dictionary manager and secure Text.
STENO uses its own pointer policy plus Outer Corners; ordinary configured gestures
remain inactive. Entering Layout Editor temporarily restores normal gestures and
suppresses keyboard/STENO dispatch. Show Contacts excludes 4F/5F candidates and
uses an isolated overlay rather than per-contact document rebuilds.

## Verification

Portable hand-gesture regressions, STENO core/actor tests, coordinated force and
layout/settings tests run without input/haptics. Captured-Mac numerical vectors,
scroll history/momentum and cross-pad braking are offline-tested. Built-in Javelin
has host native formatting/undo/dictionary tests; plugin tests use a private
ephemeral socket. Windows Release cross-build passes; actual WPF/DPAPI/SendInput,
Windows DLL loading and hardware feel still need the Windows acceptance checklist
in WINDOWS_REWRITE.md. Do not interpret the cross-build as Windows hardware testing.

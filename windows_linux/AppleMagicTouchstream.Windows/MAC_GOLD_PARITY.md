# Mac gold standard → Windows

The reference is `mac/AppleMagicTouchstream`, especially ContentView.swift,
GestureInspector.swift, HandGestureSettings.swift and GestureSessionEngine.swift.
This is a substantial functional port; the remaining differences below are real.

## Implemented

- Top-level **Gestures / Keyboard** workspace selector, in Mac order. Keyboard
  remains the default. Device/takeover controls span both workspaces. Gestures hides
  the visualizer and keyboard inspector and presents navigation, assignment cards
  and a separate Action column, with two resizable dividers and independent scroll
  areas with hidden scrollbar tracks; wheel and keyboard scrolling remain available.
  Cards select the Action inspector, including the movement cross, Hold,
  directional actions and coordinated Both assignments. The Shortcut Builder is
  inline in the Action column. Selecting a keyboard key returns to Keyboard.
  The settings inspector stays visible, with no Hide Controls toggle. Keyboard's
  inspector and the Gesture Action column share a width: dragging either divider
  updates both. Decoder Profiles and the header contact-count pills are hidden.
- Gesture Left and Right select independent settings. Mirror Edit writes the same
  edit to both independent settings. Both edits a separate coordinated namespace.
  Mirror Edit never changes coordinated assignments.
- Searchable gesture actions and a shared-identity Action Builder: modifier/key
  shortcuts, Hyper, modifier-only shortcuts, apps, files, folders and URLs.
  Hold shortcuts can fire once or keep their keys down until release. Other actions
  fire once. Windows Voice uses the
  explicit Win+H invocation. Nothing starts recording during build/replay/tests.
- Four/five-finger taps, five-finger movement and per-count 2–5-finger Hold.
  New taps/movement/ordinary holds default to None. Hold thresholds are independent,
  default 500 ms, editable from 100–5000 ms.
- Cardinal directional movement for 2–5 fingers. Activation requires 3 mm of
  translation. The winning direction latches through count changes until all-up.
  Optional repeat intervals are bounded to 20–5000 ms (0 disables repeat), and
  each repeat also requires 1 mm of further forward travel. Stationary/reverse
  movement cannot generate repeated shortcuts. Continuous movement remains the
  default and retains the accepted pointer/drag/scroll profile.
- Single-pad four-corner Hold; coordinated 3/4 fingers per hand Tap/Hold; and
  coordinated outer/inner/top/bottom corner Holds. Outer Corners defaults to Open
  Config, independently for each pad and for Both. Other corner bindings default
  None. Corner targets use the outer quarter of each axis.
- TouchStream: all 43 left and 45 right traced rotated hit regions, independent
  side labels, stable row/column identities, per-key geometry overrides and the
  separate Mac LHS/RHS PNG references at 42% opacity. The revised positions,
  sizes and rotations are regenerated from the current Mac image traces, keeping
  all 88 key identities and per-key overrides. Column tuning is disabled. The geometry sync
  script reads the Mac source and regenerates the checked-in C# definition.
- Contact pressure labels, bounded contact trails and unknown-anatomy black
  contacts. Windows never assigns a thumb/finger color from contact order.
- Global typing Force Min/Max gates are neutralized for Windows. Per-key Force
  Instead of Hold remains available. Linux's legacy settings remain intact.
- Typing Tuning contains Hold Duration, Haptic Strength and Restore Defaults.
  Typing Grace, Drag Cancel and intent movement/velocity controls are removed.
  Their legacy saved fields cannot select a mouse mode or cancel Windows typing.
  Unreserved contacts default to keyboard input, including off-key snap candidates.
  Movement within a key no longer cancels typing. A release still must match its
  key/snap eligibility and finish within max(200 ms, Hold Duration). Holds retain
  ownership through movement. Snap is bounded to 0–100%; toggling on selects 100%.

## Recognition, ownership and cleanup

All new recognition lives in Core and can be exercised without OS input. Tap
recognizers retain the existing 20 ms overlap, 80 ms landing/lift skew, 500 ms
duration, 1 mm movement limit and identity checks. Holds require a stationary
cohort within 2 mm; motion can acquire an ordinary gesture before a Hold fires.
An assigned two-finger tap retains priority over movement while it remains valid
within that 1 mm/500 ms budget. With Tap=None, movement keeps its 0.35 mm
activation. This Windows usability policy intentionally delays small initial
pointer movement with Tap assigned; it adds no fixed timer and does not change
an activated owner's acceleration, movement or cleanup.
Pending four-corner holds reserve their cycle instead of becoming tiny scrolls.
The completed corner chord gets a fresh anchor and Hold deadline even if movement
of its earlier partial cohort invalidated a generic Hold. Corner regions select
the initial chord only; subsequent jitter is measured against its original IDs
with the shared 2 mm allowance. Partial lift before firing cancels acquisition.
An activated held shortcut survives partial lift until all-up; replacement,
rejoining or excessive motion releases invalid corner output.
An activated motion/force/hold owner persists through membership changes until
all-up; a pressure crossing cannot replace an activated drag.

Three-finger movement follows Mac's evidenced acquisition policy: a visible fourth
pre-contact defers activation only during the first 80 ms of the contact episode
when four-finger movement is enabled. A real drag without that evidence starts
normally; a hovering fourth slot cannot delay it indefinitely. Windows PTP lacks
Mac's native starting/hovering phases, so confident in-range non-tip slots supply
the available evidence. They never count as touching or emit scroll. An unowned
four-finger cohort cannot become a three-finger drag during lift. Activated owners
retain precedence through added/lifted fingers. When an eligible four-finger Hold
competes with ordinary movement, three of the four IDs must project at least
0.2 mm along the candidate translation, as on Mac; directional assignments and
ordinary scrolling without a competing Hold retain their existing thresholds.

Coordinated chords require two different selected devices, landing within 80 ms,
fresh samples within 150 ms and stationary original identities within 2 mm.
Coordinated taps finish within 500 ms and 150 ms of the first partial lift.
Rejoining, replacement, invalid data, stale input and loss of eligibility cancel
the session without fallback output. Holds activate once per cycle; a held shortcut
retains its keys until both pads lift. An already active independent gesture takes precedence.

Keyboard arbitration follows the Mac actor boundary. Established MO/modifier
chords and committed key holds own their pad through all-up. Unresolved candidates
retain up to 1,024 owned frames per pad with original timestamps and modifier
snapshots. Gestures see original input once. Activated/cancelled owners discard
proposals. A never-activated rollover resolves to typing at all-up or partial lift
once no tap remains viable. Configuration/layer/epoch changes, invalid IDs,
staleness and overflow cancel rather than resurrect typing. The other pad remains
independent. Replay never posts live gesture output.

Gesture keyboard output shares the existing keyboard pump and reference counts;
the pointer worker no longer owns gesture shortcut keys. Left, Right and Both have
separate leases. Modifier-only/Hyper groups have no dummy character or repeat.
Keyboard and gesture owners may overlap the same modifiers or ordinary held key;
only the final owner releases it. A physical-key observer distinguishes physical
owners from injected input without recording text. Cleanup runs on all-up,
staleness, eligibility loss, reconfiguration, fault and teardown. Failed gesture
releases are retried on the output pump and faults reach takeover's release path.

Live keyboard events publish directly into the bounded dispatch queue, bypassing
the 512-event ring retained for offline replay/diagnostics. Deferred batches cannot
overflow that intermediate ring. If output publication overflows, the actor stops
the batch, invalidates proposals, resets recognition and inserts a keyboard release
barrier. Deferred holds cannot replay historical typematic repeats in a burst.
Settings/export round-trip held modes and all dictionaries with deep clones.
Existing serialized identities and capture formats remain unchanged.

## Remaining differences

- Windows PTP reports do not provide trustworthy thumb/hand identity. Thumb+2,
  its diagonal swipes/holds, and thumb-dependent rotation are unavailable. Existing
  Thumb+2 tap assignments remain saved but inert on Windows. Pinch/spread retains
  the previously accepted geometric Windows recognizer; it cannot enforce the
  Mac's positive-thumb prerequisite.
- Coordinated movement/directional gestures, growth of pending corner pairs
  into larger chords, and thumb/rotation recognition remain outside this pass.
- Mouse Takeover retains Windows' all-mouse hook and emergency
  Ctrl+Alt+R. It cannot reproduce Mac selected-device FLTR ownership. Windows shell
  3/4-finger actions may still conflict. No driver/settings changes are made.
- Windows Zoom remains Ctrl+wheel; Voice uses Windows voice typing. Haptic
  transport and strength retain their existing Windows implementation. Force
  pressure feel, speech behavior, reconnect behavior and movement feel require
  hardware acceptance. The Mac's AX autocorrection and native speech pipeline
  are platform-specific and are not claimed to be reproduced.
- Windows import/export preserves Windows settings. Automatic translation of
  the Mac host extension's gesture schema is not implemented.

## Verification and hardware handoff

Build and full `--selftest` run against the Windows project. The suite includes
the existing recorded tap/long-motion regressions and new hold/direction/chord,
custom shortcut-plan, settings export/clone and TouchStream geometry checks.
`WindowsDiagnostics/Fixtures/TwoFingerTapMovingMouse.json` preserves all 1,189
production-decoded frames of `2F_taps_moving_mouse.atpcap`, its SHA-256 and
normalization. Both sides and Pointer/Drag assignments recover the two valid
short taps at frames 255–259 and 489–494: default replay changes from 13 to 15
tap actions and 895 to 860 pointer calls, with balanced drag cleanup. A separate
short cycle at 301–307 exceeds the 1 mm tap allowance and still emits four Zoom
packets when geometric pinch is enabled; it is not counted as a repaired tap.
The older captured regression retains 11 clicks and all 14 movement cycles;
their small initial motion now waits for tap invalidation (546 pointer calls).
Synthetic cases cover corner acquisition after partial-cohort motion, region-edge
jitter, cancelled reassembly, held-key cleanup, four-finger Hold/scroll agreement,
actual Windows contact extraction and bounded fourth-contact acquisition.
`WindowsDiagnostics/Fixtures/FourCorners.atpcap` preserves the 484-record raw
`4-corners.atpcap` found in the app's local data folder. Its maximum raw X is
15,224, beyond the provisional normalization extent of 14,720. Auto previously
misclassified 211 packets as Legacy, corrupting contact identities/coordinates
and breaking corner acquisition. Auto now permits bounded 10% edge overshoot,
checks the official reserved byte and retains the official decoder's existing
coordinate clamp. Native PTP and explicit legacy selections retain their paths.
Live Auto now learns a profile, report size and payload layout from the first
successfully decoded touching report per device connection. Empty/hover-only
startup packets do not establish a lock. Movement, all-up and malformed packets
do not trigger reclassification; locked decoding has no alternate-profile/offset
fallback. Failed packets are dropped with the existing stale-input cleanup.
Device arrival/removal invalidates that handle and its cached metadata; Refresh,
device reselection, metadata/identity changes and explicit profile changes permit
reacquisition. Opening Config or unrelated settings edits do not reset the live
runtime's lock. The learned choice remains in memory, outside saved preferences.
Both tray and standalone Config/capture input use this same session decoder.
Re-running live Auto selection on the raw capture (rather than honoring its
historical per-record profile) produces three Open Config actions on either hand
with the standard 500 ms threshold, and no drag edges. Current offline tests pass;
tap/pointer feel and live corner/scroll acquisition still require hardware acceptance.
Optional off-screen rendering parses a plain XAML Window, never MainWindow's
live constructor, and opens no devices or input hooks.

The normal Release folder can be locked by a running app. The
updated build is `bin/Release/net10.0-windows/AppleMagicTouchstream.exe`. Exit the old tray instance
before starting it. No live takeover or hardware input tests were run by the agent.

Hardware sequence:

1. With takeover off, switch Gestures / Keyboard. Confirm Gestures replaces the
   visualizer with three columns and cards edit the separate Action column. Resize
   both dividers. Inspect TouchStream and the reduced Typing Tuning controls.
2. Check Left/Right and Mirror Edit separately; export/import settings and verify
   the new Hold, directional and Both assignments survive.
3. Use the existing **30sec test** on a blank document. Check ordinary typing,
   two-finger tap/pointer, three-finger drag and four-finger scroll first.
4. Assign a harmless action to a 4/5-finger tap and each desired Hold. Check early
   lift, movement before the deadline, added/lifted fingers and one action per cycle.
5. Assign Hyper or a shortcut to Hold and enable **Hold keys until release**.
   Test it while the other pad holds the same modifier/key. Lift each owner in
   either order; release must happen only after the final owner. Repeat with a
   physical modifier, emergency release and a disconnect. Check ordinary typing
   rollover, MO chords and key holds while another contact lands on that pad.
6. With two different pads selected, test Both taps/holds, the corner chords and
   the per-pad four-corner Open Config gesture. Try staggered lift and reconnect.
7. Confirm Ctrl+Alt+R and timed expiry release takeover. Capture any unexpected
   typing, delayed clicks, missed corner chords or changes in drag/scroll feel.

For optional visual QA, set `APPLEMAGICTOUCHSTREAM_PREVIEW_XAML` to MainWindow.xaml and
`APPLEMAGICTOUCHSTREAM_PREVIEW_DIR` to an output directory before running `--selftest`.

## STENO / Plover (Windows)

STENO and STENO Voyager now share Mac's geometry, 1.5 mm expanded hit regions,
rolling two-hand chord accumulation and both-pads-up emission. Layout mappings save
independently and export/import with settings. Ordinary keyboard/gesture recognition
pauses in STENO; only STN_* primary assignments contribute to chords.

Windows uses the bundled PloverPlugin machine over local TCP, with no COM driver.
Mac remains unchanged. See [plugin setup](PloverPlugin/README.md). Mouse Takeover
must be enabled for live Windows strokes. Invalid/stale input, overflow, device loss,
Refresh and reconfiguration cancel the cycle; lift both hands before the next stroke.
Disconnected output is dropped, never queued for reconnect.

Automated checks cover wire vectors, layouts/mappings, two-hand all-up, seams,
cancellation, mode transitions, transport framing, disconnect/reconnect and plugin
packaging. Manual checklist: install/restart Plover, choose AppleMagicTouchstream,
select each STENO layout, confirm connection and stroke monitor output; test upper/
lower seams, rolling chords across both pads, rapid repeated chords, disconnect
while held, Refresh/reselection, Ctrl+Alt+R, leaving STENO, saved mappings and export/
import. Windows currently accepts five contacts per pad. Real trackpad/Plover typing
feel has not yet been verified by these automated tests.

# Mac gold standard → Windows

The reference is `mac/AppleMagicTouchstream`, especially ContentView.swift,
GestureInspector.swift, HandGestureSettings.swift and GestureSessionEngine.swift.
This is a substantial functional port; the remaining differences below are real.

## Implemented

- Extended-driver pressure is used directly (0–255, no synthetic phase) for
  per-key/custom-button Force Instead of Hold, 1–5-finger Force, coordinated
  3+3/4+4 Force and STENO. A reported zero still requires the configured force;
  only unavailable pressure retains timed-Hold fallback. Custom-button binding
  compilation preserves its saved force threshold. Windows STENO thresholds are
  bounded to 1–255, including older unreachable settings. The per-key inspector
  reports the selected decoder's pressure range and warns about saved thresholds
  above 255; these are preserved for Apple pressure/phase compatibility. Global
  Force Min/Max remain retired. `ExtendedPressureForceTests` runs actual 112-byte
  reports through decoding and production recognizers on both sides, including
  threshold crossings, zero/missing pressure, custom buttons and balanced output.
- Gesture availability follows the selected pad's actual decoded report format,
  independently for Left/Right. Apple and older PTP formats dim Thumb+2 and all
  Pinch/Spread/Rotate pages/cards, explain the missing finger classification, and
  prevent editing those assignments without deleting them. Extended reports
  re-enable the controls. Detection is connection-local and resets on refresh,
  device selection and reconnect; an unknown/disconnected device keeps offline
  editing available and prompts for a touch to check support. Ordinary/count-based
  and coordinated inputs remain available. `DecoderGestureCapabilityTests`
  verifies the WPF controls and saved settings; optional themed renders use
  `APPLEMAGICTOUCHSTREAM_CAPABILITY_PREVIEW_DIR` and
  `APPLEMAGICTOUCHSTREAM_PREVIEW_XAML` during `--selftest`.
- Thumb + 2 diagonal movement (↖/↗/↙/↘) and its independent Hold are available
  beside Thumb + 2 Tap. New assignments default to None. Activation requires one
  positively reported thumb and two distinct reported fingertips, consistent
  reported hand identity when present, and Mac's spread-thumb geometry. Every
  contact must contribute at least 0.75 mm of coherent diagonal travel; joining
  contacts establish a fresh baseline. Shape/rotation arbitration remains first.
  The existing owner survives relabeling/partial lifts until all-up. Deliberate
  direction changes require another 0.75 mm and an 80 ms output interval. Each
  diagonal supports Once, timed (80–5000 ms), or motion repeats; stale delivery,
  invalid input, cancellation and reconfiguration stop output without catch-up.
  Thumb Hold has its own saved 100–5000 ms threshold (default 500), shortcut-key
  ownership and balanced release. Known thumb chords cannot fall through to
  ordinary three-finger Hold. Settings, Mirror Edit, single-pad fallback, action
  search, feedback and demonstrations cover these inputs. Offline verification:
  `ThumbGestureParityTests`; optional WPF renders use
  `APPLEMAGICTOUCHSTREAM_THUMB_PREVIEW_DIR` during `--selftest`.
- Every 2–5-finger shape page matches the current Mac catalog: **Pinch, Spread,
  Rotate Left, Rotate Right**, plus automatic gray Hold/Lift lifecycle cards.
  Shape demonstrations follow the selected direction. Left/Right, Mirror Edit,
  searching, Shortcut Builder, recognition notes and persisted/exported settings
  cover all eight rotation bindings. Rotation defaults to None; existing numeric
  trigger identities and Pinch/Spread defaults remain unchanged.
- Discrete shape actions support **Once**, **Repeat every ms** (20–5000 ms,
  default 80), and **Repeat with motion**, matching Mac's 5-degree rotation and
  logarithmic 6-percent scale steps. Reversal removes forward progress; pausing
  stops motion repeats. Timed repeats require fresh frames. Late ticks emit at
  most one action; lift, invalid/stale input, eligibility loss, reconfiguration
  and teardown cancel the originating pad's repeat without affecting the other.
  Continuous Zoom keeps following motion and does not use shortcut repeats.
- Rotation competes with Pinch/Spread and translation at Mac's 3-degree,
  0.75-mm arc threshold and angular/radial dominance ratios. Pending rotation
  suppresses premature shape activation; competing translation requires agreement
  from every tracked contact. The winning direction latches through reversal,
  relabeling and count changes until all-up. Membership changes rebase geometry.
  Real shape/movement activation beats a pending Hold on the same frame;
  a configured Force crossing can override a shape and balance its output.
- Optional captured-Mac motion response bundles both selected Mac trackpads' pointer
  and scroll curves, source sensitivity/direction, per-axis scroll history and the
  existing release momentum. It applies per hand, follows Mirror Edit, and also
  serves STENO pointer movement. Either pad can brake a released scroll. The legacy
  reference pointer/fixed-scroll response remains available. See
  [MotionProfiles/README.md](MotionProfiles/README.md). Mac production parity vectors
  and the portable offline runner verify the numerical model; Windows hardware/UI
  acceptance and application wheel behavior remain manual checks.
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
- Gesture actions, keyboard Primary/Hold actions and shortcut-key selectors use
  the same Mac-style action panel: dedicated search, categorized sections, current
  selection checkmarks, result counts and an empty-results message. Search matches
  titles, categories and semantic shortcut/key labels without changing the saved
  assignment. Arrows/Page keys browse; Enter or a result click chooses; Escape,
  Done or outside dismissal cancels. Closed selectors ignore incidental text,
  navigation and wheel input. Keyboard catalog and STENO restrictions remain intact.
  `ActionPickerTests` verifies the actual WPF templates, both catalogs, explicit
  commits, handed settings, shortcut keys, source filters and selection isolation.
  Set `APPLEMAGICTOUCHSTREAM_MENU_PREVIEW_DIR` during `--selftest` to render the
  popup contents offline without creating a runtime or posting input.
- Closed action selectors display the selected human-readable Title/Display,
  including None and Mixed, instead of an option object's diagnostic string.
  Regression tests inspect the actual closed-control template and selection updates.
- Like Mac's pressure header, each visualizer displays the latest recognized
  gesture beside Peak for two seconds. Continuous owners refresh their label;
  taps remain visible briefly after lift. The Gestures workspace also shows
  independent Left/Right feedback. Pure engine snapshots cover taps, movement,
  latched directional arrows, Pinch/Spread/Rotate, Hold, Force, corner/Both and
  STENO mouse actions. Labels identify input gestures, not assigned shortcuts.
  Normal lift retains recent feedback; invalid/stale input, cancellation and
  reconfiguration clear it. Polling never starts input, hooks, haptics or output;
  no feedback or custom-action payload is persisted. Replay excludes live feedback.
  Recognition and WPF template tests run under `--selftest`; optional offline
  visual previews use `APPLEMAGICTOUCHSTREAM_FEEDBACK_PREVIEW_DIR`.
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
- Contact pressure labels, bounded contact trails and reported anatomical colors,
  with unknown contacts black. Extended packets supply shape, orientation and
  finger type; IDs/contact order never determine anatomy. Gesture projection
  preserves native finger labels. Windows Pinch/Spread/Rotate require a positive
  thumb, and Thumb+2 tap uses the same spread-chord geometry as Mac. A valid shape
  activation wins over a pending tap; thumb-bearing shape competition requires
  full-chord translation. Existing owners retain their all-up latch through label
  loss and partial lift. Linux's legacy geometric policy remains separate.
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
all-up. An explicitly configured reported-pressure Force can override a shape
and own the remainder of that cycle. Established pointer/drag/scroll ownership
retains Windows' accepted all-up priority.

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

Natural three-fingertip arches use Mac's `min(14 mm, longest span × 0.35)`
depth bound, replacing the obsolete 8 mm straight-row limit. A native confident
non-tip third contact can defer pending two-finger pointer acquisition for at
most 80 ms. A hovering palm is excluded, and no such delay is added without
native landing evidence. The adapter and Windows recognizer are covered together
by `NativeGestureParityTests`, including staggered land/lift, hover expiry,
thumb-only activation, late labels, shape competition and balanced drag release.

Coordinated chords require two different selected devices, landing within one second,
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

- Legacy PTP packets do not supply anatomy; thumb-only gestures require the
  extended driver's reported labels. The driver does not supply hand identity,
  and Windows never invents it from the selected pad. Thumb+2 Tap, Hold and
  diagonal movement use positive native finger labels.
- Rotation runs assigned discrete actions/shortcuts. Windows has no equivalent
  to Mac's native Rotate Content event; per user direction, no substitute native
  action is offered. Applications can use their own rotation shortcuts.
- Windows retains established pointer/drag/scroll ownership
  when Force crosses, unlike Mac's broader Force override.
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

`2F_skips.atpcap` contains 302 successfully decoded reports across eight Right-pad
movement episodes (SHA-256
`d137cd7e8787932456644701d4095320e1ea74a9056e7a6647ca749f13bbaf9f`).
Its companion selects captured Mac motion on Right, no 2F shape bindings, and
2F Primary Click. Replaying the original settings and an explicit tap=None
variant identified nonlinear amplification when accumulated startup travel was
sent to the pointer curve as one sample. Pending Pointer/Drag now accelerates
each source delta before retaining its output, publishing only on acquisition.
With tap=None, median first-step output across the eight episodes changes from
5.39 to 2.15 pixels; the original profile's median changes from 33.29 to 8.40.
All acquisition frames and pointer-call counts remain unchanged. The imported
curve and post-acquisition response are unchanged. Existing checks verify the
same acceleration vectors, gesture arbitration, drag cleanup and capture paths;
live precision acceptance remains a hardware check.

`ShapeGestureParityTests` verifies every 2–5-finger direction on both pads,
signed repeat behavior, all-up/cancellation, shape/Force/Hold arbitration and
settings cloning. `RotationCountsMac.json` projects all 1,875 frames from Mac's
`rotation-counts.json` (SHA-256
`2c6cdd8e7854bc2bd49330fb84e3f21086c41566ecc432fb54909f68474f6453`)
into screen millimetres, preserving sequence numbers, anatomy and landing evidence.
All 16 recorded shape trials select the same rotation family/direction as Mac
with Pinch/Spread and movement competing, both with native labels and with labels
removed to exercise Windows' actual input capability. WPF tests exercise all shape
cards, Left/Right/Mirror repeat edits, settings save/load/export/import, mixed values
and continuous-Zoom controls. Offline rendering can be enabled with
`APPLEMAGICTOUCHSTREAM_SHAPE_PREVIEW_DIR`; it creates no live runtime or hooks.
Live feel, timing and target-application shortcut behavior still need hardware testing.

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

## Current layout / STENO rewrite

See [Windows rewrite contracts, implementation and acceptance](WINDOWS_REWRITE.md)
for the current three layouts, inline editor, built-in translators, dictionary
manager, fixed force mouse policy, Both force and encrypted Shortcut Text.
This replaces the former optional 1F pointer and single-choice haptic prototype.
Windows native/UI/hardware acceptance remains required after the Mac-host offline
suite and cross-build. Mac source and live behavior are unchanged.

# AppleMagicTouchstream

Scope: this directory only. Build/test with `./build.sh` and `./test.sh`; Xcode project `AppleMagicTouchstream/AppleMagicTouchstream.xcodeproj`, scheme `AppleMagicTouchstream`. Identity is in `project.env`.

This project targets faithful FingerWorks TouchStream emulation. GTK gesture recognizers and product-specific features were deliberately removed. Haptics are the user-authorized exception: keep optional accepted-key feedback and its strength control. Do not restore other removed features or treat the temporary key-landing/3 mm movement classifier as original TouchStream behavior. Original chords, English spelling correction/BackSpace Auto-Correct and variable-speed typematic are future fidelity goals; the removed GTK implementations were not faithful substitutes.

Keep the multitouch bridge, raw telemetry, device selection, capture/replay tools and useful keyboard bootstrap (normal key/modifier/shortcut output, tap/hold, layers, repeat) working while implementing the original interpreter. Menu-bar config, capture/replay, restart and quit are development utilities. Do not launch the app or exercise live HID/input without an explicit test request.

`AppleMagicTouchstream/AppleMagicTouchstream/ContentView.swift` preserves the original GUI. Keep its layout, trackpad IDs, visualizers, test area, keymap/column inspectors and useful tuning. Remove unwanted feature controls in place; do not replace or simplify the interface without explicit user direction. `Engine/TouchProcessorEngine.swift` is the temporary keyboard engine; `Engine/EngineActorBoundary.swift` owns serial execution and production replay. `Runtime/` owns ingestion, telemetry and capture/replay. `Compatibility/LegacyGTKProfile.swift` is decode/serialization compatibility for old captures and saved layouts, not a live gesture implementation. Unsupported GTK action kinds must remain inert through primary, hold and custom-button paths. Preserve existing settings keys/capture formats; changing serialized enums needlessly breaks fixtures.

Keep Swift bridge work in `Sources/OpenMultitouchSupport`, Objective-C work in `Framework/OpenMultitouchSupportXCF`. XCFramework output is generated: rebuild with `./build_framework.sh` after bridge changes, never hand-edit it. Do not add allocation, logging or I/O to hot input paths. Preserve deterministic replay and update baselines only for intentional behavior changes. Register added app files in the Xcode project as well as SwiftPM. Never change sibling projects incidentally.

Haptic settings retain level ×100 encoding in saved profiles and use a bounded 0...2 scale in the engine (user-authorized fine control, waveform 6). Route feedback to the selected originating pad, rate-limit per pad, and keep replay recording-only.

Feature audit: keep Auto-resync as device recovery and Hold Repeat as output scaffolding. Keyboard/Mouse and its native mouse-event blocker are removed; do not restore them from legacy profiles. Run at Startup and GTK Typing Grace are removed. Preserve profile decoding without reactivating them; preserve GUI layout when removing controls.


As of 2026-10-19, the user removed the entire custom DriverKit takeover implementation,
helper embedding, decoder, restart transfer, UI, menu and release shortcut from this
project. Native contact capture is the input path. Do not restore DriverKit. The user explicitly authorized the native FLTR feature
port on 2026-10-20; see the current policy below. Preserve
optional legacy telemetry.driverKit serialization for existing captures.


## Native Trackpad Takeover (user-authorized 2026-10-20)

The app now has GesturePad's continuous selected-device FLTR takeover, independent
of custom DriverKit. See TRACKPAD_TAKEOVER.md. Keep exact USB VID05ac/BT VID004c,
PID0324/type4 validation, all-selection preflight, deduplication, own-client checks,
partial-start rollback and release retry. No helper, restricted driver entitlement,
startup/reconnect auto-takeover or separate synthetic pointer output is added.
Preserve native keyboard ingestion and capture/replay, selection/refresh locks,
paused auto-resync, and awaited keyboard reset before filter release. Explicit
Release/menu/Ctrl-Option-R, sleep, replay and Quit release. Config close/reopen and
active Restart retain the same owner process/controller/native clients; inactive
Restart still relaunches. Test with ./test.sh (includes offline native lifecycle
and coordinator tests), rebuild the XCFramework after native edits, and do not
activate live takeover without the user's hardware test request.


## TouchStream layout (2026-10-20)

The user authorized the GlassToKey TouchStream preset/reference port. Preserve
independent traced left/right regions, editable per-key geometry and inert
placeholders for unsupported legends. Editor, startup and replay use
ContentView.makeTouchStreamKeyLayout. Bundle Resources/TouchStreamReference.gif
in Xcode and SwiftPM; the visual-only background follows the selected TouchStream
layout with no separate checkbox. See
TOUCHSTREAM_LAYOUT.md and the offline TouchStreamLayoutTests. Existing hidden
Mobile/Planck presets remain hidden. Do not restore removed gesture features.


## GesturePad takeover and contact display port (2026-10-21)

User explicitly requests GesturePad's takeover behavior and placement, left pane,
always-on contact paths/telemetry, centered pressure without P/F numbers and the
fixed anatomical palette. This supersedes earlier button/locked-selection/no-
startup policies and authorizes the local V2 bridge differential transition port.
Persistent checkbox defaults off; startup/wake/replay exit reconcile selected native
IDs after opt-in. Emergency release disables persistently; sleep/replay/quit preserve
preference. All transitions await keyboard reset, serialize, and commit changed
logical selection only on successful native preparation. Refresh temporarily
suspends/reconciles; auto-resync remains paused during ownership/transition.
Preserve retained filters, rollback/retry and exact ownership validation.
Keep keyboard engine, keymap/reference, haptics and inspectors. No GesturePad
mouse/scroll/action engine is ported. Colors: Unknown black, Thumb orange, Index
blue, Middle green, Ring purple, Pinky pink, Palm gray. Keep #ID/name adjacent,
plain centered pressure, arrows and paths. No legend/display toggles.
Build native framework from source, test offline, build/install and leave closed.


## Configurable GesturePad gestures (2026-10-22; supersedes no-gesture-port policy)

User explicitly requests all currently implemented GesturePad gestures and approves
gestures taking priority over the keymap for the whole touch cycle. Local copies
of session recognition, acceleration, tap/drag, precise scrolling/momentum and
per-hand bindings are authorized. Keep legacy GTK action kinds inert.
GESTURE_ENGINE.md is this app's integration spec; GesturePad spec governs ported
thresholds. Right inspector has Gestures/Keyboard tabs. Persist app-local actions
and gains; takeover opt-in and selected/owned/armed/AX/profile/live-only gates
remain mandatory. Reserve enabled multi-finger candidates before keyboard output,
cancel same-pad pending/held actions, latch until all-up including empty release
frames, and preserve the other pad's typing. Replay never posts gesture output.
Preserve keymap, haptics, capture schema and native ownership lifecycle.
Do not modify siblings or concurrent mac/REWRITE.md/Hand.jpg work. Build/test,
install with stable Developer ID, leave closed for explicit hardware testing.


## Import/Export placement; trace tuning reverted (2026-10-22)

Keep equal-width Import/Export directly under Mode Toggles in the scrolling
Keyboard settings. User reverted the temporary TouchStream column experiment:
keep fixed traced positions, column tuning disabled, and original per-key
geometry behavior. No column offsets/scales/rotations apply to TouchStream.

## Reference alignment and menu icon (2026-10-22)

User authorized realigning all TouchStream key rectangles against the reference
and replacing the menu-bar status circles with a monochrome hand inspired by
mac/Hand.jpg. StatusHand is a vector template asset; let macOS choose its tint.
Do not restore colored mode/layer/disconnect badges or their subscriptions.
Preserve the underlying keyboard/layer state and device recovery behavior.
The key trace changes base position, size and angle only; preserve mapping
identities, saved per-key overrides and disabled column tuning.

Unassigned key holds must stay inert and match the inspector's None value.
The engine must never fall back to KeyActionCatalog's legacy hold table.
Explicit saved/imported holds still work and appear in the inspector/grid.

User authorized one-finger P>=130 primary click during native takeover, with a
gentle targeted haptic. Keep once-per-all-up behavior, multi-finger/stale/invalid
cycle rejection, keyboard reservation, selected/owned/armed/AX/live-only gates,
and per-pad haptic rate limiting. See GESTURE_ENGINE.md. No sibling port yet.

User authorized configurable 1–5 finger force-click Action menus (Tap mouse actions),
per-hand persistence and bounded experimental force-haptic waveform/level controls.
Preserve old bindings on decoding; only 1-finger force defaults to Primary Click,
2–5 default None. Use max contact P>=130, not summed pressure. Keep all-up latch,
keyboard/drag/tap arbitration and live eligibility. Test feedback only on explicit
button press; never on slider changes or replay. See FORCE_CLICK_HAPTICS.md for
verified framework clamp evidence. Build/install app only for this pass; no DMG.

After hardware testing, user fixed force-click feedback at waveform 6 / level
0.25; remove its experimental controls/test button and ignore legacy saved force
feedback values for live output. Typing uses fixed waveform 6 with Haptic Strength
0–2 / 0.01 steps. Preserve profile level ×100 encoding, device targeting, throttling
and recording-only replay. This supersedes earlier variable force-feedback policy.

User removed the temporary 3 mm/off-key mouse-intent classifier, movement-based
keyboard cancellation and global Force Min/Max typing gates. Do not restore them
from saved profiles. Unreserved contacts default to typing; preserve hit regions,
per-key Force instead of hold, hold/repeat semantics, gesture reservation and
lifecycle cleanup. Keep legacy force/drag fields decodable with inert setters.
Keymap bundles include HandGestureSettings under HostExtensions.mac.GestureBindings;
import normalizes, persists and reconfigures included bindings/gains. Missing gesture
settings preserve current preferences. Takeover opt-in remains app-local.

Portable import must accept known retired brightness/Voice and related GTK labels
as decode-only actions so existing exports round-trip. Preserve labels and mapping
positions without re-enabling their live output; unknown labels must still fail.

User authorized two-finger pinch/zoom in this app only. Use shared gesture ownership
and latch through added/lifted fingers until all-up (including survivor motion
against a cached partner/virtual anchor); rebase identity/membership changes without
zoom jumps. Pinch and mouse translation compete before activation, never switch
owners mid-cycle. Preserve per-hand Action/gain persistence and keymap round-trips,
AX/owned/armed/live gates, tap/keyboard arbitration, balanced native magnification
phases and stale-input/lifecycle cancellation. See GESTURE_ENGINE.md. Hardware
acceptance is still needed. Do not port to sibling apps or auto-exercise input.

User generalized pinch/spread to independent 2–5-contact inputs, each defaulting
and assignable to Zoom (or None). Measure whole-shape scale using all contacts;
accept thumb-plus-fingertip chords without mandatory anatomical labels. Rebase
membership changes without jumps, retain original ownership/action until all-up,
and continue a lone survivor against a virtual anchor. Keep recognition scale
deltas independent of Zoom output. Preserve existing two-finger saved bindings,
per-hand defaults, gains and keymap round-trips. This supersedes pair-only pinch.

User authorized Apple shortcut actions (Notification Center, Mission Control,
App Exposé, Launch Pad, Show Desktop) for Pinch/Spread and Force Click menus.
Use cached, validated keyboard-shortcut plans; emit once per latched cycle with
balanced key edges. Preserve all eligibility, replay and haptic safeguards. Do
not mutate system shortcut preferences; report disabled/unusable shortcuts. See
GESTURE_ENGINE.md for defaults, symbolic IDs and Tahoe Apps behavior.

Mission Control/App Exposé keyboard dispatch failed hardware testing. These two
now use dynamically resolved CoreDockSendNotification requests, one per gesture
activation/force crossing, with no synthetic keyboard edges. Resolve/check symbols
at configuration; report unavailable if absent. Keep Notification Center,
Launch Pad and Show Desktop on their tested keyboard dispatch paths. Preserve
all-up latching, haptics, no replay output and no preference mutations.

User now requires a recognized active Thumb (fingerID 1) to activate every inward
Pinch input, counts 2–5. Unknown/missing labels do not qualify. Spread remains
unchanged. This supersedes anatomy-independent inward-pinch activation; preserve
the all-up latch after activation, including thumb lift and relabeling.

Correction: require a recognized active Thumb to activate BOTH Pinch and Spread.
A thumb-free Spread otherwise bypassed the inward rule through latched reversal.
This supersedes the prior Spread exception. Preserve the continuation latch after
valid activation, including thumb lift/relabel. No sibling changes.

Established MO(n) holds now give their originating pad keyboard priority through
all-up, so same-pad layer+arrow/key chords work. This is a user-authorized
exception to gesture-first arbitration; opposite-pad gestures remain independent.
Suppress native output as well as keyboard reservation on that pad, consume the
all-up frame, and clear ownership on reset. See GESTURE_ENGINE.md/tests.


User authorized restoring GlassToKey's Run at Startup toggle and launch-at-login
behavior on 2026-10-24. Use the app-local LaunchAtLoginManager with
SMAppService.mainApp, default off, reconcile saved preferences at app launch,
and reflect actual registration state in the toggle. Match GlassToKey's keymap
import/export behavior. This supersedes the earlier removed-control policy;
never register login items as part of a build or an offline test.

User authorized an expanded GUI for the existing gestures on 2026-10-24, using
the Design/GestureAssignments mockup structure. Gestures replaces the visualizer
area with navigation, assignment cards and a shared inspector. Keep Keyboard's
existing editor, visible device/takeover controls, and only working triggers.
User explicitly chose Left/Right only; do not offer Both or coordinated two-hand
gestures in this UI. Hold/Lift describe lifecycle, not new assignable gestures.
No recognition/default changes. Build/sign/install Release in Applications;
DMGs only on explicit request. Keep app closed for user hardware testing.

User authorized a Mirror Edit checkbox for Gesture editing. It uses the
existing both-pad settings scope for subsequent edits, preserves differences on
enable, and does not add coordinated two-pad recognition. This supersedes the
Left/Right-only editing UI restriction; see GESTURE_ENGINE.md.

User authorized a Movement cross editor GUI stage: center continuous action and
four direction cards with mutually exclusive saved modes. Put independent Tap
and Force Click cards beside Up in the equal-width top row when those inputs exist. Directions can save
mouse/Apple shortcut/small-step volume/brightness actions, but direction recognition,
dispatch and motion-based repeat remain unimplemented for a later pass. Mark that
clearly. Directional mode suppresses that input's continuous output without erasing
either mode's assignments. Preserve per-hand/Mirror Edit and keymap round-trips.

User authorized live THREE-finger directional movement and a per-direction Repeat
with movement checkbox, default on for volume/brightness and off for other actions.
This supersedes the GUI-only policy for three fingers only; two/four directions
remain saved-only. Reuse shared gesture ownership and all-up latching, preserve
pinch/force/tap arbitration and keyboard reservation/established-MO priority, and
keep all selected/owned/armed/AX/live-only gates. User now authorizes a per-direction
millisecond repeat field (0 off, 20–5000 ms positive), including stationary held
repeats through the existing shared timer, with 200 ms stale-input cancellation,
no catch-up bursts and balanced key/button output. Activation/turn threshold is
now provisionally 0.75 mm; preserve shared tap/movement arbitration. See GESTURE_ENGINE.md for provisional
thresholds and testing. Build/install signed Release, leave closed for hardware tests.

Repeat UI now uses a clickable loop/slashed-loop toggle, separately persisting
enabled state and the remembered interval. Disable the field while off; enabling
an unset interval starts at 20 ms, preserving 80 ms volume/brightness defaults.
Keep old zero/checkbox profiles compatible and retain Mirror Edit/keymap behavior.
Config window default height is now 800 px (user requested +200).


## Coordinated Both-hand gestures (user-authorized 2026-10-24)

The Both selector now edits independent coordinated bindings, not Mirror Edit.
Implement only four outer corners (two contacts per pad), three fingers per hand,
and four fingers per hand, with separate Tap/Hold actions. Four-corner Hold defaults
to Open Config after 1 s, following the guide; other slots default None. Three/four
Hold fires once after 0.5 s. Use two distinct selected, owned, armed pads, common
host time and per-hand freshness. No new DriverKit or sibling changes.

Single-hand gestures now run immediately with no join-window delay. A second
hand forming a valid coordinated chord may take over an active single-hand
gesture/force cycle, releasing its output and rebasing both hands at acquisition.
Established keyboard layer/modifier chords retain priority. On acquisition
cancel both independent outputs once. Reserve until both pads are all-up, consume
release frames, and prevent Hold+Tap duplication or mid-cycle handoff. Stale input,
invalid/moving/replaced contacts cancel output; stop/replay/emergency release and
selection/settings changes reset coordination. Open Config is an app-local action;
other actions retain AX/live-only gating and balanced one-shot output. Keymaps must
round-trip coordinated settings; old profiles keep all existing per-hand settings.


## Independent hands and repeat editing

User authorizes simultaneous independent gestures across selected pads, including
one pad dragging while the other moves the pointer. Do not restore the old
other-pad-drag suppression. Gesture/contact/acceleration state stays per device;
the global cursor and primary button are shared. Either pad's movement uses the
latest queued drag position and posts dragged events while that button is held.
Multiple drag owners share one down and release only after the last owner ends;
stale/reset/disconnect cleanup must remove only that owner. Both acquisition and
global stop still release every owner. Preserve physical-button interference
handling and prevent discrete primary-click up edges from breaking another drag.

The repeat interval editor must keep incomplete text local, permitting deletion
of the entire old value. Validate/clamp 20–5000 ms only on Return/focus loss;
blank/invalid commit restores the previous interval. The loop controls enablement.


User authorizes live two-finger directional actions using the same engine, actions,
thresholds, held repeats and safety gates as three fingers. This supersedes the
three-only restriction for two fingers; four-finger directions remain saved-only.
Keep directional configuration indexed by device AND input trigger, so two/three
assignments coexist without overwriting. Shared ownership determines the active
trigger for timer output; never infer it from the current finger count after
latching. Continuous two-finger mouse mode remains unchanged when selected.


User now authorizes live FOUR-finger directions as well. All movement triggers
(two/three/four fingers) share the existing directional engine, action dispatcher,
repeat scheduling and lifecycle gates. This supersedes saved-only restrictions.
Preserve per-pad/per-trigger settings, independent hands and Both handoff. In
continuous mode, four fingers still scroll/pan with momentum; directional mode
must not simultaneously scroll. Switching modes retains assignments and gains.

User authorizes assignable single-hand Session Lifetime Hold for counts 1–5,
default None. This supersedes the old nonassignable Hold UI policy. Directional
and continuous movement assignments both coexist with count-based Hold. Binding
configuration no longer locks Hold; actual activated movement cancels a pending Hold. Pinch/Spread bindings may coexist, but the
Pinch and Spread pages keep the old gray, nonassignable Hold lifecycle card.
Editable Hold is a selectable card with its Action menu in the right inspector.
Use one shared count-based stationary recognizer,
0.5 s one-shot with all-up ownership, 2 mm settling tolerance, existing per-hand/Mirror Edit/settings
exports and selected/owned/armed/AX/live gates. Preserve movement-first, force,
Both and established-keyboard-chord arbitration, stale cancellation and release
cleanup. See GESTURE_ENGINE.md. Build/install signed Release and leave closed.

Four-finger Hold capture showed empty directional slots were claiming movement
and the old 0.75 mm Hold slop rejected natural settling. Ignore all-None
configurations in movement recognition, and cancel pending Hold only once a
real direction commits, not at the router's lower continuous-motion threshold.
Keep the existing 0.75 mm directional activation and repeat behavior unchanged.

User authorizes independent directional Scroll Up / Scroll Down actions for
2/3/4 fingers. They now follow motion, superseding the initial timed wheel-step
implementation: project travel onto the assigned input axis/sense, then choose
vertical output sign from the action. Support swapped Up/Down and horizontal
Left/Right mappings. Reuse Apple scrolling profiles, sensitivity, precise phases
and momentum; ignore legacy repeat settings for these actions while preserving
fields. Discrete directions keep repeats. Keep these actions confined to
directional menus, preserve per-hand/Mirror Edit, import/export, all-up/stale/
lifecycle gates and live-only output. Pinch/Spread Hold and Lift lifecycle cards
must have matching gray styling AND equal row heights. Build/install signed
Release and leave closed for hardware testing. See GESTURE_ENGINE.md.

User also authorizes a Natural scrolling toggle under Scroll sensitivity for
normal Movement → Scroll / Pan. Persist an optional per-hand override, defaulting
to the existing system preference when absent; support Mirror Edit, mixed state
and portable settings. Never change system preferences. Explicit directional
Scroll Up/Down semantics remain independent of this toggle.

User authorizes Pan Left / Pan Right as directional, motion-following actions.
The input direction selects source travel axis/sense; the action independently
selects horizontal output axis/sign, allowing swapped horizontal and vertical-to-
horizontal mappings. Reuse horizontal scroll acceleration, sensitivity, precise
phases and momentum; preserve explicit output semantics independent of Natural
scrolling, ignore timed repeats and preserve portable/Mirror Edit settings.
Hold is also unlocked alongside continuous Movement without delaying movement
activation. Preserve first-activated ownership until all-up and keep Pinch/Spread
pages' Hold card nonassignable. See GESTURE_ENGINE.md.


User authorizes independent Thumb+2 Hold, four-finger Tap on renamed Tap and Move,
Hold left of Down in movement crosses, and single-pad 4 Corners Tap/Hold under
4 Fingers. Keep Thumb+2 Hold separate from ordinary 3F, sharing spread-thumb Tap
geometry and tolerating matched fingertip relabeling. Single-pad corners use
Both's thresholds, default Hold Open Config at 1 s / Tap None, atomic native-frame
anchors, per-pad ownership through all-up, app-local Open Config without AX and
normal AX gates for synthetic actions. Preserve established keyboard/Both
priority, stale/reset/replay safety, optional old-profile fields and independent
per-hand/Mirror Edit/portable settings. Use the shared searchable Keymap Tuning
chooser for all gesture Action editors, with each input's supported actions only.
Do not change keymap action semantics. See GESTURE_ENGINE.md; build/sign/install
Release and leave closed for hardware tests.

User authorizes four-finger Tap's System actions to match Force Click. Reuse the
shared discrete dispatcher, including Dock requests for Mission Control/App
Exposé; preserve tap recognition, defaults, gates and portable assignments.

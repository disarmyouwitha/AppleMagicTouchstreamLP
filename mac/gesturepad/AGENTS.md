# GesturePad

## Central gesture specification

[GESTURE_ENGINE.md](GESTURE_ENGINE.md) is the current consolidated gesture behavior
contract. Start there; historical experiment policies below must be read in that
context. Update its inventory, thresholds, arbitration, lifecycle and acceptance
status alongside any behavior change. Feature notes retain implementation and
research detail. Documentation consolidation alone does not authorize a code change.

## Scope and purpose
This folder is the independent FingerWorks/TouchStream gesture/chord playground. Keep raw-touch inspection, finger/pressure telemetry, traces, device selection and capture/replay. The opt-in control checkbox now filters selected-pad native movement and scrolling through event identity, without HID seizure, and enables experimental two-finger pointer output. Preserve clicks, drag events, unknown sources and other mice. No keyboard, click, scroll, voice, app-launch or haptic output is synthesized. Keep release safeguards and the temporary Test Pointer Sources observer. Historical raw-HID backend/capture schemas remain for diagnostics but have no UI buttons.

## Build and test
- `./build.sh`: app `GesturePad/GesturePad.xcodeproj`, target/scheme `GesturePad`.
- `./test.sh`: Swift package, runtime module `GesturePadRuntime`, replay and HID identity tests.
- `./release.sh --check`: validate app/release metadata without signing/notarization.
- App product: `build/DerivedData/Build/Products/Debug/GesturePad.app`.
- `./build_framework.sh`: bridge/XCFramework rebuild using project-local caches.
Scripts resolve their own directory. Identity is defined in `project.env`.

## Source organization
- `GesturePad/GesturePad/GesturePadApp.swift`: menu bar, config, capture/replay UI.
- `GesturePad/GesturePad/GesturePadController.swift`: device/raw-surface startup and capture/replay forwarding.
- `GesturePad/GesturePad/ContentViewModel.swift`: raw-contact monitoring model.
- `GesturePad/GesturePad/Engine/TouchProcessorEngine.swift`: live/replay contact processing boundary for future FingerWorks recognition.
- `GesturePad/GesturePad/Runtime/HIDBlackholeExperiment.swift`: exclusive HID ownership experiment; preserve release safeguards.
- `GesturePad/GesturePad/Compatibility`: historical capture/profile schemas and decoding, including legacy keyboard-shaped fields. Preserve their serialization and no-op behavior; do not restore keyboard features as incidental fixes.
- `LegacyReference`: saved original settings/screenshots, not app resources.
- `Sources/RewriteProbeKit` and `Sources/RewriteProbe`: offline contact analysis; see RewriteValidation/START_HERE.md.

## Rules
Preserve the menu-bar shape, existing defaults keys/bundle ID, capture formats, and deterministic replay. Keep sources independent of sibling projects. Do not add avoidable allocations, logging, or I/O on touch hot paths. Update the Xcode project when adding sources. Keep Swift bridge APIs in Sources/OpenMultitouchSupport and Objective-C bridge sources in Framework/OpenMultitouchSupportXCF; rebuild XCFramework after bridge changes and never hand-edit generated bundles. Report build/test limitations.

The checkbox enables continuous selected-pad event filtering (no timeout); the separate 30sec test button enables a timed session. Preserve explicit release/global shortcut plus selection-change, config-close, sleep, replay and termination cleanup for both modes.

TwoFingerPointerTracker uses per-device two-contact midpoint deltas; count/identity changes and stale frames reset the baseline. InterpretedTrackpadPointer posts tagged movement only on the live ingestion path while selected-pad control is active and Accessibility is granted. It pauses when mouse buttons are held. Keep replay output-free. Constant gain and recognition are provisional, not recovered TouchStream calibration.

SelectedTrackpadEventPolicy must only suppress positively identified selected-device mouseMoved/scrollWheel events. No last-active-device or click/drag timing guesses. Resolve sender services through current selected interface ancestry, including AppleMultitouchDevice children; never hardcode sender IDs or do registry I/O inside the event tap. Generated pointer events bypass the filter by tag. Stop control if selected services change or the tap disables. Test source observation and control are mutually exclusive.

Cursor correction/warping was rejected by the user and removed. Do not reintroduce it or global mouse/cursor dissociation. Dropping matched movement CGEvents alone was observed to leave the visible cursor moving; preserve that limitation in UI/docs until an upstream solution is validated. Keep working scroll filtering, synthesis toggle/counter, native button/drag passthrough and OS three-finger-drag status.

The user has authorized a separate single-interface exclusive-open experiment: choose exactly one non-keyboard interface belonging to the selected pads, seize for 15 seconds, with synthesis/filtering stopped and independent live-contact frame evidence. Preserve timed/manual/lifecycle release and per-interface result files. Do not combine interfaces automatically. This exception does not change the normal control checkbox's nonseizing event-filter behavior. The unsuccessful minimum-gain controls have been replaced; retain Test Pointer Sources while verifying.

User authorized one exact Linux-documented USB multitouch mode command as an optional single-interface capture variant. Restrict to transport USB, vendor 05AC, product 0324, usage 0001:0002. Default off; capture baseline for 2s, then send feature report ID02 bytes0201 once. Preserve exact bytes/result/timing and full 15s capture even on command error. Do not invent reverse commands or firmware writes. Release restores ownership, not a proven device mode; reconnect may be necessary. No automated hardware activation without the user's live test.

The same exact USB 0201 request also has a standalone direct-parent-USB transport
probe in Tools/USBTransportProbe. Ordinary parent USBDeviceOpen and report-descriptor
read were validated without displacing Apple's interface driver. The synchronized
script waits for a new selected eligible single-interface capture start marker;
helper checks it again before sending the one command. Preserve marker cleanup
on release, exact known right USB pad serial guard, two-second baseline, and both
wall-clock/uptime command logs. Do not automatically activate this hardware test.

A standalone lower-layer single-interface variant now exists as
Tools/USBTransportProbe/run-interface-capture.sh: explicit15s USBInterfaceOpenSeize
for only the known right05AC:0324 serial/interface1, async endpoint83 capture.
Keep app control released, refuse other identities, stop on denied open, and retain
15s/interrupt cleanup. No driver detach/terminate/reset/configuration changes or
mode writes are part of this variant. Do not activate it without the user's live test.


## Current takeover policy (2026-10-19; supersedes historical experiments above)

The user removed the entire custom DriverKit implementation from GesturePad and
AppleMagicTouchstream. Do not restore its driver/helper, raw decoder, synthetic
button output, signing/provisioning integration, inventory or restart transfer.
GesturePad now has continuous native Trackpad Takeover/Release Trackpads controls
for the current nonempty Left/Right selection, following user confirmation of both
Bluetooth and USB FLTR tests. Deduplicate identical selections, validate all before
starting, roll back partial starts, attempt release for all owned pads and retain
failed-stop ownership for retry. Keep model0324/type4, USB VID05ac / Bluetooth
VID004c validation, own-client verification, Ctrl-Option-R, lifecycle release,
refresh/selection locks and paused auto-resync while owning pads. No timeout,
automatic reconnect takeover, startup activation or synthetic output. See
TRACKPAD_TAKEOVER.md and NATIVE_FILTER_TEST.md.

APPLE_CONTACT_HID_LAYOUT.md preserves the removed raw decoder's bit layout and
native Compact V7 conversions. Retain optional telemetry.driverKit serialization,
reference vectors and historical research/capture files for compatibility; these
are not executable DriverKit integration. Use ./test.sh and ./release.sh --check;
the removed DriverKitProbe Python test suite no longer applies.

While native takeover is active, Config close hides/destroys only the window and
keeps the owning process/capture running. Restart rebuilds Config in the same
process, preserving native clients/controller; it is not a process relaunch in
this state. Reopening Config must not synchronize/release ownership. Inactive
Restart/Config-close retain ordinary process relaunch. Keep process-level sleep
release even when no Config view exists, plus replay/Exit/explicit release.
No interprocess ownership transfer lease is used.

The USB test was confirmed by the user. The requested continuous selected-pad
feature is now implemented; simultaneous multi-pad/lifecycle hardware acceptance
is still pending. ./test.sh also runs offline native lifecycle checks.


## Persistent automatic takeover (2026-10-20; supersedes prior button/lock policy)

The user explicitly authorized a persistent Trackpad Takeover checkbox, default
false, restored at startup without Config. Only GesturePad has this behavior so
far. Keep selectors/Refresh unlocked. Native differential transitions validate
additions first, preserve retained FLTR clients, acquire additions before releasing
removed pads and roll back failures without committing the new picker/settings.
Preserve preflight/own-client checks, explicit recovery diagnostics and retryable
failed ownership. NativeTakeoverPreference owns enabled state, selection and
sleep/replay/refresh suspensions; the AppDelegate owns lifecycle callbacks even
with Config closed. Explicit release/menu/Ctrl-Option-R persist off. Quit releases
without erasing preference. Wake and replay end can restore enabled takeover;
ordinary auto-resync remains paused during ownership. Refresh releases before
rebuilding refs and reapplies preference; selection changes use the serial native
transition without cycling retained refs. See TRACKPAD_TAKEOVER.md. Rebuild the
XCFramework for native edits, and do not activate hardware during automated tests.

Config has only the takeover checkbox; keep Release Trackpads in the menu and
Ctrl-Option-R as emergency controls. After stopping a removed FLTR client, restart
ordinary mode before counting remaining filters, allowing bounded registry
teardown (up to 100 ms). IOServiceClose can return while its registry entry is
still published; do not fail transitions on that immediate stale count. Preserve
retained sessions and the deferred-registry regression tests.

Route live contacts/counts/rendering by selected native numeric device ID, not
OMS deviceIndex: its two slots can be reused by a third/deselected pad. Parse IDs
once on selection updates and compare integers in the callback/engine path. Clear
cached render contacts when selection changes. Preserve index fallback for legacy
recordings without numeric identity; see SelectedDeviceSourceTests.


## Standalone pointer acceleration research (2026-10-20)

The user requested the standalone experiment in Tools/PointerAccelerationProbe,
not app pointer/gesture output. Keep its parametric model and ordinary/listen-only
recorder isolated from app build/settings. Do not activate recording in automated
checks. Numeric tests and recorder --help are offline; snapshot is read-only
registry inspection. OMS contact-to-pointer-count scaling remains unvalidated and
must be explicit, not marketed as native-equivalent. See the tool README/SOURCES.


## Live 2-finger mouse checkbox (2026-10-20; user-authorized output exception)

The user explicitly requested an opt-in 2-finger mouse test in GesturePad. It is
off each process launch and can post movement only for current selected AND owned
native FLTR IDs while takeover is enabled and Accessibility is granted. Preserve
live-only delivery, release/transition/failed-transition pausing and per-pad
baseline resets; replay never posts. Existing fixed 6 pt/mm centroid sensitivity
is provisional, separate from Apple-source acceleration research. Do not add
click/drag/scroll/pinch/keyboard output incidentally. See TWO_FINGER_MOUSE.md.
Do not activate the test during automated verification or launch the live app.


## Live acceleration comparison (2026-10-20; user-authorized continuation)

The user approved moving on from the working fixed two-finger mouse to a live
acceleration test. Keep Apple acceleration (test) and Fixed comparison modes,
process-local sensitivity, and mouse default-off on launch. PointerAcceleration
is a pure independent parametric model shared by live movement and offline
capture tests. The resolution/25.4 counts-per-mm conversion is provisional.
Registry settings are read on the control path only, never inside raw callbacks;
missing/unsupported profiles pause Apple output rather than silently switching.
Mode/sensitivity changes reset baselines. Preserve selected-and-owned/live-only
movement gating and all existing release safeguards. No incidental button,
scroll or keyboard synthesis. Do not launch the app or activate hardware tests
automatically. See TWO_FINGER_MOUSE.md for replay evidence and limitations.


## Accepted acceleration defaults (2026-10-20; supersedes test opt-in/UI above)

The user hardware-tested and accepted acceleration, requesting default activation
with Trackpad Takeover. Two-finger mouse now defaults true on process launch;
it remains gated by takeover enabled, selected-and-owned IDs, transition arming
and Accessibility. A fresh explicit takeover enable rechecks the mouse control;
manual mouse-off survives selection/sleep/replay transitions until the next
explicit takeover enable or process launch. Startup does not prompt for permission.
Takeover retains its persistent default-off-until-opt-in preference. The response
picker and ordinary status counters are removed; acceleration is the app response,
sensitivity sits next to the mouse checkbox, and actionable failure/waiting
messages remain. Preserve the numerical model and offline Fixed comparison.
Do not automatically launch or activate hardware during verification.


## Gesture latching (2026-10-20; supersedes exact-count continuation)

The user requested FingerWorks-style latching as a rule for future gesture work.
Activation and continuation are separate: two active fingers initiate mouse mode;
one remaining finger continues it until all contacts lift or explicit safety
cancellation. Count/ID changes re-anchor motion, rather than producing centroid
jumps or requiring the starting chord again. Three-plus contacts pause mouse
motion but retain an existing latch; they do not initiate one. Sessions are
per physical native device ID. Preserve stale/invalid/palm cancellation and all
selection/release/lifecycle reset paths. Future recognizers must define activation,
continuation, completion and cancellation explicitly and arbitrate an existing
session before recognizing a new gesture. See GESTURE_ENGINE.md. This rule does
not authorize new output types or a broad engine rewrite.


## Any-count mouse continuation (2026-10-20; supersedes extra-finger pause)

The user tested original FingerWorks hardware: the mouse latch also continues
through added fingers (2→3→4). After exactly two activate, any positive active
count continues. Do not pause/reclassify on count changes. Average displacement
of contact IDs common to consecutive frames; newly added fingers establish their
baseline, lifted fingers contribute nothing. This avoids both centroid jumps
and a transition-frame motion pause. All-up, no shared IDs or existing explicit
safety/lifecycle cancellation ends the old session. Fixed inline contact storage
avoids hot-path arrays/sets; duplicate IDs/capacity overflow cancel safely. Keep
future gesture activation separate from continuation. See GESTURE_ENGINE.md.


## Four-finger scroll (2026-10-20; explicit user-authorized output extension)

The user requested four-finger scrolling with native-like acceleration and fine
control, checkbox default on alongside takeover. ScrollGesture.swift provides
independent scroll curves/history per pad and axis, continuous pixel CGEvents,
fractional fixed-point deltas plus carried pixel remainder, natural direction,
and began/changed/ended/cancelled phases. Do not silently use pointer curves.
The input mm-to-count scale is provisional. Momentum is not implemented yet;
do not claim exact native equivalence before hardware acceptance.

Live arbitration now waits for 0.2 mm initial coherent motion to choose enabled
2-finger mouse vs 4-finger scroll, allowing fingers to finish landing. Once
latched, counts do not switch modes: both continue through any positive count
until all-up or explicit cancellation. Preserve matched-ID motion and accepted
mouse acceleration. Both feature checkboxes default on for restored takeover
and explicit enable; independent manual off overrides survive ordinary lifecycle
restoration. Missing profile/permission, failed transition, stale input, selection,
release and replay guards remain; scroll cancellation closes active event phases.
Only the live selected-and-owned path posts. Never launch/activate automated
hardware tests. No new keyboard, button, drag or pinch synthesis. See
FOUR_FINGER_SCROLL.md and GESTURE_ENGINE.md.


## Scroll momentum (2026-10-20; supersedes deferred momentum above)

The user explicitly requires momentum after lift as part of four-finger scroll.
ScrollMomentum estimates recent accelerated pixel velocity and integrates a
provisional exponential coast, independently per pad. Preserve quiet-release
suppression, reversal reset, bounded velocity/duration, analytic tick-rate
independence and no catch-up jump after stalled ticks. Contact and host clocks
stay separate. Physical ended is followed by momentum begin/continue/end, with
ordinary phase none and preserved precise remainder/scroll location. A new active
touch on that pad, mouse buttons, disable/release/selection/lifecycle cleanup or
loss of eligibility cancels the coast and closes its event phase. Repeated
all-up frames must not restart/cancel a valid coast, and the contact watchdog must
not cut one off. The timer is gated by live selected-and-owned eligibility and
cancelled with capture; tests/replay never post events. Momentum does not extend
gesture recognition ownership. Decay tuning is not Apple's recovered algorithm;
keep hardware acceptance explicit. See FOUR_FINGER_SCROLL.md.


## Two-finger tap click (2026-10-20; explicit button-output authorization)

The user requested two-finger tap for click. A separate checkbox defaults on with
takeover, following the existing feature lifecycle/default policy. TapClick.swift
recognizes short stationary two-contact taps, tolerates bounded landing/lift skew,
and completes once at all-up. Extra/replaced contacts, holds, individual motion,
invalid/stale input and recognized mouse/scroll movement reject until all-up.
Braking momentum or physical mouse-button activity blocks that cycle too.
Preserve per-pad isolation and idle-watchdog invalidation without eating fresh taps.

Only live selected-and-owned, armed, Accessibility-approved devices can click.
Tap eligibility is independent of acceleration profiles and other feature toggles.
Build both tagged primary down/up events before posting either, immediately under
the output lock, with matching cursor/modifiers/click counts. No held-button or
scheduled-up state, dragging, secondary click, keyboard or pinch output. Reset
pending taps on disable/release/selection/lifecycle interruption; replay/tests
never post. Keep accepted pointer/scroll/momentum behavior intact. See
TWO_FINGER_TAP.md for thresholds and hardware acceptance. Do not automatically
launch or hardware-activate verification.


## Capture-backed mouse/tap arbitration (2026-10-20)

The user reported missed clicks in rapid move–tap sequences. Production replay
of 2finger_tap.atpcap reproduced six valid taps losing to the 0.2 mm mouse
initiation threshold. Mouse initiation is now 0.35 mm; scroll stays 0.2 mm.
Preserve no-click-after-recognized-movement, 500 ms tap maximum, latch and
acceleration behavior. No fixed delay or release-time click for a recognized
mouse stroke is introduced. The local optional capture regression compares
thresholds without posting output. See GESTURE_ENGINE.md and
RewriteValidation/TWO_FINGER_TAP_CAPTURE_ANALYSIS.md; hardware acceptance pending.


## Three-finger tap double-click (2026-10-20; explicit user request)

Three stationary contacts completing the bounded tap produce a dedicated primary
double-click on all-up: counts 1 then 2, four balanced events created before any
post, same cursor/modifiers/tag, immediate under the output lock. Reset ordinary
single-tap click history; no delayed mouse-up or held/drag state. A separate
checkbox defaults on with takeover, with the same per-process override/lifecycle
gates as existing features. It is independent of acceleration profiles.
TwoFingerTapRecognizer is parameterized for two/three-contact chords with shared
500 ms/80 ms/20 ms/1 mm limits. Seeing a third contact blocks the two-finger tap
until all-up, not a single click on partial lift. Fourth contacts, replacements,
rejoining, active mouse/scroll, braking and physical buttons reject candidates.
Preserve accepted mouse/scroll/momentum behavior and both capture regressions.
No right-click/drag/keyboard/pinch output. See GESTURE_ENGINE.md; hardware acceptance
pending. Tests never post events or activate live input.


## Shared gesture-session engine (user-authorized latching refactor)

The user requested latching as a general gesture-engine concept. Live mouse/scroll
ownership now delegates to Engine/GestureSessionEngine.swift, with generic gesture
identities, activation rules and optional synchronous activation evidence filter,
separate continuation policy, priority and begin/change/end/cancel results.
Common fixed-storage contact motion/validation is GestureContactMotionTracker.
TrackpadGestureRouter only registers current rules/adapts outputs; do not grow
per-gesture latches there. TwoFingerPointerTracker is a legacy diagnostic adapter.
Discrete taps observe pending candidates and cancel on continuous ownership;
momentum remains output state after gesture completion. Posting, timers and
eligibility stay outside the generic recognition engine; reset callers must clean
up owned outputs before clearing recognition. Preserve current thresholds, accepted
feel and both capture regressions. New gesture rules do not authorize new output
families. See GESTURE_ENGINE.md and GestureSessionEngineTests. No automated live
activation/launch or bridge changes are needed by this refactor.


## Three-finger drag/select (2026-10-21; explicit held-output authorization)

The user requested Apple-style three-finger drag/select and specified close,
aligned fingers, reserving thumb–middle–ring for a future identified right-click.
ThreeFingerDragChord supplies activation evidence through the shared engine:
0.35 mm motion, bounded row geometry, reject classified thumb/palm. Unknown finger
classification falls back to geometry; do not claim anatomical certainty.
Keep this filter activation-only and shared any-positive-count continuation.
Stationary three-finger taps remain double-click; prior continuous owners cannot
switch by count. New drag checkbox defaults on with takeover, follows existing
manual-override/eligibility policy and uses the accepted pointer profile/sensitivity.

PrimaryDragOutput is explicitly allowed to hold the primary button. Reserve up
before returning down, use tagged private-source drag events and release at all-up,
reset, allocation failure, >200 ms missing input, physical-button interference,
permission/eligibility loss and every existing lifecycle output cleanup. Clean up
held output before resetting recognition. Only one pad can own the global button;
suppress competing pad output while held. Private-source synthetic down must not
cancel itself via the physical HID-state check. Preserve live-only posting and
emergency release. No drag lock/reposition delay or right-click is implemented.
Update GESTURE_ENGINE.md thresholds/acceptance with tuning; hardware acceptance is
pending. No automatic app launch/hardware activation during verification.


## Drag hold correction (2026-10-21; supersedes HID-state check above)

The user reported that the first drag build repeatedly selected/jittered rather
than holding, despite good latching. Do not use global/HID left-button polling
while owning a synthetic drag: it can classify our own down as interference.
Both callback and watchdog skip polling during ownership; a live-only listen-only
button-down observer ignores interpreter tags and cancels on outside edges.
Observer creation failure pauses drag and observer disable cancels held state;
stop tears it down. Keep reserved-up, stale/eligibility/lifecycle cleanup.
Accumulate drag destinations from the last queued drag point so an asynchronous
system-cursor read cannot rewind it. Mouse acceleration/sensitivity remains shared
and unchanged; keep equivalent-movement regression and single-down/up sequence
coverage. Corrected hardware feel awaits retest; do not auto-launch or activate.


## Identified thumb–middle–ring right-click (2026-10-21; explicit user request)

The user requested the FingerWorks TouchStream right-click chord using anatomical
finger identification. ThreeFingerTapRecognizer arbitrates the shared three-contact
tap timing into double-click or right-click. Require a full positive native set
{Thumb=1, Middle=3, Ring=4}; never infer anatomy from tracking IDs, order or shape.
Bind tracking IDs after matching, tolerate temporary Unknown but reject known
contradictions/mixed known hands. Seeing a classified thumb reserves primary
triple-tap fallback for that cycle, including right-click disabled/failure. Unknown
non-thumb generic triples retain existing double-click compatibility, not right-click.

Reuse accepted 500 ms/80 ms/20 ms/1 mm tap limits and continuous-owner/braking/
physical-button/lifecycle cancellation. New independent checkbox defaults on with
takeover, same manual-off policy, selected-and-owned/armed/AX/live-only gates;
no acceleration profile dependency. Prepare both tagged secondary edges before
posting, same cursor/modifiers, click count 1, button number 1, balanced pressure;
no held right button or right-drag. Reset ordinary primary click history. Preserve
accepted mouse/scroll/drag behavior and no replay/test posting. Central spec is
GESTURE_ENGINE.md; hardware classification/context-menu acceptance is pending.
Build/install without automatically launching or activating hardware.


## Anatomical diagnostic colors (2026-10-21)

User confirms corrected drag/select works great. Right-click misses may be native
Thumb+Ring+Pinky classification instead of intended Thumb+Middle+Ring. User explicitly
does not want gesture acceptance changed yet. Keep exact {1,3,4} and all thresholds.
Use the shared UI anatomical palette for contact fills/arrows/trails, same on both
pads and replay: Unknown black, Thumb orange, Index blue, Middle green, Ring purple,
Pinky pink, Palm gray. Update from live classification without latching colors;
tracking IDs still own path continuity. Preserve name labels and visible legend.
No recognition or native bridge changes. Build/install without automatically launching.


## UI cleanup and installed T2F verification (2026-10-21)

User removes the color legend and F-number annotation; retain anatomical colors,
names, tracking IDs and pressure. Current T2F source was not in the running
Applications build. 3spread capture replay finds40 current T2F vs18 old exact-TMR
predicted right-clicks, and all494 eligible frames pass geometry. No recognition
changes authorized/performed in this cleanup. Rebuild/install current source and
leave closed for hardware retest. Preserve concurrent changes and root FINDINGS.md;
measurements and caveats are recorded there and in GESTURE_ENGINE.md.


## Accepted T2F / centered pressure (2026-10-21)

User confirms the fresh T2F build is excellent. Preserve recognition/thresholds.
Inspect touch data shows #trackingID and finger name beside the contact; show
pressure separately as a plain number at its center with contrasting outlined
text, no P prefix. Keep anatomical colors, no legend/F-number. Rendering only;
no schema/native/gesture changes. Build/install and leave closed as before.


## Always-on touch inspection and paths (2026-10-21)

User removes both diagnostic display checkboxes; main surface telemetry and contact
paths are always enabled, including replay. Keep colors, ID/name labels and centered
pressure; no empty controls panel, feature setting or recognition changes.


## Gesture sidebar (2026-10-21; user-requested UI replacement)

User removes both per-pad raw-measurement lists and requests a menu like sidebar.jpg.
ContentView now has a grouped gesture sidebar and selected settings panel for the
implemented point/click, drag/double-click, scroll/pan and spread T2F right-click.
Preserve all existing feature setters, status failures, sensitivities, device/replay/
takeover controls and live/replay contact rendering. No recognizer/native/schema
changes. Sidebar Left/Right/Both is an explicitly labeled diagram preview only,
not independent hand settings; shared settings remain for both selected pads.
No placeholder gestures/actions. Selecting/collapsing/previewing does not activate
input or alter capture/ownership. Keep no automatic live launch/hardware testing;
offscreen sidebar rendering may be used without creating native controllers.


## Independent hand configuration (2026-10-21; supersedes preview-only policy)

User explicitly requests actual Left/Right/Both gesture editing. Seed mirrored
current settings on both pads, not TouchStream's asymmetric defaults. Scope edits
feature enables and pointer/scroll sensitivity; Both applies to both and shows
mixed state without silently copying on selection. Native mixed checkbox click
sets both on. Preserve existing process-local feature defaults/lifecycle policy.

HandGestureSettings binds logical picker slots to explicit native IDs; None and
swaps cannot route by compacted index. Apply selected/owned/armed/AX/profile guards
per device and independent gains to existing models. One bad profile must not block
the other read. Same physical pad on both sides deduplicates, ORs feature enables,
uses Left gain and explains this in UI. Keep global held-button ownership and all
output reset/release safeguards. No recognizer/threshold/momentum/native/schema
change. Update central spec and meaningful routing/mixed/gain tests. Build/install
without automatically launching or activating live input.

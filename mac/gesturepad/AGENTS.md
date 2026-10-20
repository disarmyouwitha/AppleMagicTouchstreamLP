# GesturePad

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

Preserve ordinary Config-close background restart and explicit Restart. Both
release the native test before relaunch; no ownership transfer lease remains.

The USB test was confirmed by the user. The requested continuous selected-pad
feature is now implemented; simultaneous multi-pad/lifecycle hardware acceptance
is still pending. ./test.sh also runs offline native lifecycle checks.

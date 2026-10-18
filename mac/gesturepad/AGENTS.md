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


## DriverKit integration (user-authorized 2026-10-18)

The separate DriverKit 30sec takeover button now uses v0.5 of DriverKitProbe with
both exact tested pad serials (rightUSB/leftBluetooth) and requires both selected.
This is an exception to the normal checkbox's nonseizing CGEvent filtering path.
See DriverKitProbe/INTEGRATION_TEST.md. Preserve hard30s driver close, independent
signed helper owner-process watchdog/removal, global release shortcut, lifecycle
release, and honest restoration-pending state. No tool should automatically
activate the hardware test without the user ready to touch it. Build/install
alone does not activate. Do not lift the cap before integrated restoration is
verified. Continuous/general-device control is follow-up work, not yet validated.
Keep registry stream publication on the timer, bounded ring/mapping in callbacks,
per-session deduplication, stale/gap resets, duplicate OMS source gate and replay
output suppression. Tracking IDs must never become anatomical finger labels.


User explicitly requested continuous DriverKit takeover and removal of obsolete
filter/test GUI controls after the v0.5 integration build. Current v0.6 therefore
has no30s session deadline. Preserve explicit Release Trackpads/global shortcut,
owner-process watchdog and lifecycle release; do not restore a timed cap based on
older instructions above. UI contains only DriverKit Takeover, Release Trackpads,
one synthetic two-finger checkbox and status. Diagnostic backend schemas remain.


As of v0.7, the user explicitly rejected a separate probe application. Package the
windowless driver service inside GesturePad.app/Contents/Helpers, with no Dock
item or independent controls. Preserve existing signing/profile identifiers and
watchdog. The installer installs only /Applications/GesturePad.app; do not restore
the separate /Applications/GesturePadRawHIDProbe.app. Activation/removal state is
shown by GesturePad; native macOS authorization prompts are still expected.


DriverKit telemetry conversionVersion2 is a native Compact V7 reconstruction.
Read RewriteValidation/COMPACT_V7_TELEMETRY_PARITY.md before altering conversions.
Do not replace native nonlinear scalar conversions with Linux raw byte scaling.
Hand1 is a native parser flag, code7→12 preserved; tracking ID is not anatomy.
Preserve original report/contact bytes, sensor-clock timestamps, native clipping
and quantized velocity, per-device resets and descriptor calibration check.
Tools/TelemetryParity uses pinned private addresses for offline research only;
never add those offsets or native binary fragments to the production app.
Synthetic parity and right USB live parity (1,686 samples, zero mismatches) are
established; matching Bluetooth live validation remains. Preserve terminal
notTouching records in capture but exclude them from the visible render snapshot.

v8 adds an explicit per-device handoff experiment through AMTHandoffClient and the
embedded service's --handoff command. Keep exact caller identity and argument
validation, same receiver dispatch queue, per-pad deliberate-handoff tracking,
owner watchdog and full Release fallback. Do not interpret Close/Terminate success
as native restoration: this remains a physical test pending validation. Do not
broaden static matching before native handoff is demonstrated. Both-pad live
telemetry parity passed 2,815 samples with zero mismatches (see saved JSON result).

v15 adds the exact Linux Magic Trackpad2 Bluetooth multitouch-enable featureF1 02 01,
once after2s only when no full contact packet arrived. User authorized driver
completion/reconnect testing; preserve tested model/serial/transport checks and
report exact mode result/first packet bytes. Earlier "no Bluetooth mode write"
notes describe pre-reconnect experiments, superseded for this initialization test.

User explicitly stopped automatic reconnect work. v17 requires manual selector
verification + another DriverKit Takeover click after stream loss/replacement.
Never remove the whole extension solely because a receiver/pad disconnects. The
Takeover button remains enabled while active and resyncs stream routing; no
inventory polling or automatic reconnect retry. Preserve explicit/lifecycle
release and owner-process cleanup. Older reconnect-watchdog instructions above
are superseded by this user-requested workflow simplification.

v19: DriverKit Stop must wait for timer/action cancellation completions before
calling super Stop. v18 still crashed at timer Cancel completion because the timer
was freed first; duplicate-Cancel guards alone were insufficient. Keep receiver
and provider retained across drain, including failed Start. Run driver tests with
`python3 -m unittest discover -s DriverKitProbe/Tests -p 'test_*.py'` as well as
app tests. App Restart must await confirmed driver removal before relaunching;
never start its replacement while the previous helper still owns the devices.

v20 user spec supersedes v19's restart-removal rule: keep the live extension across
an explicit app Restart, using the signed helper's bounded owner-transfer lease.
Actual Exit still removes/releases. Sync applies selectors without driver cycling;
zero/one/two selections are valid. Model0324 USB/Bluetooth matching uses arbitrary
serials; do not claim all AMT generations. A control-only IOUserResources service
keeps per-device handoff available with zero receivers. Preserve exact helper
user-client identity validation. Native-to-driver reverse reclaim is unproven;
never silently deactivate the extension to implement Sync. See
DriverKitProbe/TAKEOVER_SPEC.md for the acceptance checks and bootstrap limitation.

v21 Bluetooth framing: macOS IOHIDUserDevice's KeyholeReportIDF1 transport prepends
F1. Pass reportIDF1 with payload02 01, not F1 02 01; v20 logs proved the latter sent
F1 F1 02 01 and was rejected. Keep USB payload02 01 unchanged. Use/test the shared
Driver/MultitouchMode.h command. Explicit helper --initialize-bluetooth diagnostic
is guarded to supported, already-controlled, zero-contact Bluetooth sources; its
user-space Open was denied in the live test, so do not assert it repaired hardware.

# Native Trackpad Takeover in AppleMagicTouchstream

This uses Apple's existing native FLTR
user client; it does not restore the removed custom DriverKit implementation.

## Controls and behavior

The **Trackpad Takeover** checkbox lives inside the Left/Right device-selector
panel in the top-aligned left workspace. It defaults off.
Its value persists under `AppleMagicTouchstream.nativeTrackpadTakeoverEnabled`.
After opt-in, startup restores takeover on the restored selection. An explicitly
saved None remains None; a missing saved native ID is not replaced with a default
pad during startup restoration.

Both selectors remain editable while owned. Native transitions deduplicate numeric
IDs, validate additions, retain unchanged filter sessions, acquire additions before
releasing removals and roll back failed changes. The UI/keyboard selection commits
only after success. Selecting None releases that side; selecting None on both
releases all filters without clearing the saved opt-in. Failed transitions keep
the old selection and report recovery failures. There is no retry timer loop.

Unchecking the checkbox, **Release Trackpads** in the menu, or **Ctrl–Option–R**
releases and persistently disables takeover. Another app may occupy the global
shortcut; its hint appears only after successful registration. Release failure
retains tracked ownership for retry through the menu/shortcut.

Refresh temporarily suspends ownership, refreshes ordinary device sessions and
reconciles the current selection. Auto-resync pauses while filters are owned or a
transition is running. Controls pause during the transition and during replay.
Closing/reopening Config and active Restart retain the same owner process and
native clients. Sleep, replay and Quit release without clearing the saved opt-in;
wake and leaving replay reconcile the current selection. Lifecycle suspension
reasons compose, so leaving replay during sleep cannot reacquire filters. Emergency
release during suspension prevents later automatic reacquisition.

Contacts flow through the existing native OMS ingestion and existing keyboard
engine. Native pointer behavior is suppressed by the filter routing. Configurable gestures provide synthetic pointer/click/drag/scroll
output on eligible live input; see [GESTURE_ENGINE.md](GESTURE_ENGINE.md). Release awaits keyboard listening suspension
and a reset (clearing held keys/repeat state), closes the filter clients, restores
ordinary native callbacks and resumes listening only when live input is appropriate.
All ownership transitions serialize across awaited keyboard cleanup. Concurrent release callers await the same cleanup task. Quit waits for cleanup.

## Mechanism and restrictions

`MTDeviceStart(device, 0x40000000)` uses IOServiceOpen type `0x464c5452` (FLTR)
on the inspected native driver type4 implementation. Incoming touch frames route
to filter clients rather than ordinary consumers. Apple parses the contacts;
we consume callbacks without reinjecting frames. Closing the clients restores
ordinary routing. No raw HID decoder is used here.

Model gates: external USB VID05ac/PID0324 or Bluetooth VID004c/PID0324, native
driver type4. The bridge verifies FilterEnabled and own-PID client ownership.
Partial starts attempt rollback; release attempts every owned pad even if another
fails, retains failed-stop ownership for retry, and reports native recovery codes.

USB and Bluetooth takeover have been hardware-tested on the supported external
model. Private API compatibility still depends on macOS/native driver behavior.
The discovery evidence is preserved in [native filter research](Tools/HIDSeizureProbe/NATIVE_FILTER_TEST.md)
and [the research archive](../RESEARCH_ARCHIVE.md). Test keyboard/gesture output,
two pads, release/restoration, Config/Restart, sleep and replay on each supported
release target.

## Implementation and checks

- `Framework/OpenMultitouchSupportXCF/OpenMTManagerV2.{h,m}`: independent local
  copy of the guarded native ownership implementation, contact counts and cleanup.
- `Sources/OpenMultitouchSupport/OMSManager.swift`: Swift native takeover wrappers.
- `AppleMagicTouchstream/AppleMagicTouchstream/Runtime/NativeTrackpadTakeover.swift`: observed coordinator,
  asynchronous output-reset/release sequence and controls. Native backend is
  injectable for offline lifecycle tests.
- `AppleMagicTouchstream/AppleMagicTouchstream/ContentView.swift`: inline checkbox, live selectors and independently scrolling left workspace.
- `AppleMagicTouchstream/AppleMagicTouchstream/ContentViewModel.swift`: device recovery gate and keyboard
  lifecycle handoff through the existing runtime lifecycle coordinator.
- `AppleMagicTouchstream/AppleMagicTouchstream/AppleMagicTouchstreamApp.swift`: shortcut/menu, sleep/replay/quit cleanup,
  and ownership-preserving Config close/Restart.

`./build_framework.sh` rebuilds the generated XCFramework from local source.
`./test.sh` includes fake-device Objective-C start/rollback/release tests and Swift
coordinator tests for selections, output-reset ordering, concurrent release,
release retry, saved opt-in and nested lifecycle suspension. Native tests also cover retained sessions, delayed registry teardown and selection rollback. Tests do not activate hardware. `./release.sh --check` verifies app identity. App signing/entitlements require no new driver grant.

To hardware-test: release/quit other trackpad apps, open this app,
select one pad first, take over and verify contacts plus intended keyboard output.
Release and verify native input returns without held/repeating keys. Repeat with
both pads, one unselected pad, Config close/reopen, active Restart, sleep and replay.
No hardware takeover is activated by building/installing this port.

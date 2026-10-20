# Native Trackpad Takeover in AppleMagicTouchstream

Ported from GesturePad on 2026-10-20. This uses Apple's existing native FLTR
user client; it does not restore the removed custom DriverKit implementation.

## Controls and behavior

Select the intended USB/Bluetooth pads, then press **Trackpad Takeover** under
Left Trackpad. The current nonempty selection is deduplicated and validated in
full before any ownership changes. Only those selected native services are
opened as filter clients. Unsupported selections or existing owners cause refusal.

**Release Trackpads**, the menu action, and **Ctrl–Option–R** release. As with any
global hotkey, another running app can occupy this shortcut. Its hint is shown only after
successful registration; use the button/menu
and quit other trackpad apps when testing. There is no timeout or startup takeover.
Refresh, selection and auto-resync are locked/paused through ownership and release.

Closing/reopening Config preserves the same native clients and keyboard engine.
Restart while owned rebuilds Config in the same process; a real process relaunch
would close its clients. Sleep, replay and Quit release. There is no automatic
reconnect takeover or interprocess handoff. Reconnect/reselect and start explicitly.

Contacts flow through the existing native OMS ingestion and existing keyboard
engine. Native pointer behavior is suppressed by the filter routing. Takeover adds
no synthetic mouse/click consumer. Release awaits keyboard listening suspension
and a reset (clearing held keys/repeat state), closes the filter clients, restores
ordinary native callbacks and resumes listening only when live input is appropriate.
Concurrent release callers await the same cleanup task. Quit waits for cleanup.

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

The private API was hardware-confirmed through USB and Bluetooth in GesturePad on
macOS15.7.4/24G517 Intel. This port needs its own hardware acceptance, including
keyboard output, two pads together, release, Config close/reopen, Restart, sleep
and replay. It does not establish compatibility with every OS/CPU or trackpad.
See [the discovery and evidence](../gesturepad/TRACKPAD_TAKEOVER.md).

## Implementation and checks

- `Framework/OpenMultitouchSupportXCF/OpenMTManagerV2.{h,m}`: independent local
  copy of the guarded native ownership implementation, contact counts and cleanup.
- `Sources/OpenMultitouchSupport/OMSManager.swift`: Swift native takeover wrappers.
- `AppleMagicTouchstream/AppleMagicTouchstream/Runtime/NativeTrackpadTakeover.swift`: observed coordinator,
  asynchronous output-reset/release sequence and controls. Native backend is
  injectable for offline lifecycle tests.
- `AppleMagicTouchstream/AppleMagicTouchstream/ContentView.swift`: buttons and selector/Refresh locks.
- `AppleMagicTouchstream/AppleMagicTouchstream/ContentViewModel.swift`: device recovery gate and keyboard
  lifecycle handoff through the existing runtime lifecycle coordinator.
- `AppleMagicTouchstream/AppleMagicTouchstream/AppleMagicTouchstreamApp.swift`: shortcut/menu, sleep/replay/quit cleanup,
  and ownership-preserving Config close/Restart.

`./build_framework.sh` rebuilds the generated XCFramework from local source.
`./test.sh` includes fake-device Objective-C start/rollback/release tests and Swift
coordinator tests for selections, output-reset ordering, concurrent release,
release retry and rejected starts. Tests do not activate hardware. `./release.sh --check` verifies app identity. App signing/entitlements require no new driver grant.

To hardware-test: release/quit GesturePad and other trackpad apps, open this app,
select one pad first, take over and verify contacts plus intended keyboard output.
Release and verify native input returns without held/repeating keys. Repeat with
both pads, one unselected pad, Config close/reopen, active Restart, sleep and replay.
No hardware takeover is activated by building/installing this port.

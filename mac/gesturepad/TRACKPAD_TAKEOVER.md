# Trackpad Takeover through the native FLTR client

**Current gesture rules:** [GESTURE_ENGINE.md](GESTURE_ENGINE.md) is the central
behavior specification. This file supplies feature-specific detail and history.

Updated 2026-10-20. GesturePad offers a persistent, opt-in **Trackpad Takeover**
checkbox for the selected trackpads. The custom DriverKit implementation remains
removed. This preference/selection behavior is currently GesturePad-only.

## User behavior

- The checkbox defaults off. Enabling it captures the selected supported pads and
  saves `GesturePad.nativeTrackpadTakeoverEnabled` in the app's existing defaults
  domain. Startup restores that preference after restoring device selection and
  starting ordinary contact capture; Config need not be open.
- Left/Right selectors and Refresh remain enabled. Duplicate selections produce
  one native filter. Selecting None on both sides releases all pads while leaving
  the preference checked, ready for the next selection.
- A selection transition computes retained, added and removed IDs. Retained FLTR
  clients are verified but not stopped. New additions get ordinary callback
  sessions and full preflight before any existing filter changes. Additions are
  acquired first; removed pads are released only after additions succeed.
- If acquisition/removal fails, only additions are undone and removed previous
  pads are reacquired where possible. The picker and saved selection stay at their
  previous values. Recovery failures remain in status and ownership for retry;
  this is a serial best-effort transition, not an atomic hardware transaction.
  Preparing a failed addition may leave its ordinary monitoring session cached
  until the next refresh/teardown; it is not a filter client.
- Every selection must be external USB/Bluetooth model0324/type4 with the existing
  vendor and own-client checks. Unsupported selections do not displace working
  filters. Failure does not cause a timed automatic retry loop.
- Unchecking **Trackpad Takeover**, the **Release Trackpads** menu action and
  **Ctrl–Option–R** save the preference as off and release ownership. There is no
  separate release button in Config. These actions do not immediately recapture
  the pads.
- Refresh temporarily releases all filters before rebuilding native references,
  then reapplies the current selected set if enabled. A failed stop aborts refresh.
  Auto-resync remains paused while filters are owned; this is not a new background
  reconnect scanner. Refresh or selection changes explicitly reconcile devices.
- Config close/reopen and Restart retain the owner process while takeover is
  active or the preference is enabled. Quit releases ownership without clearing
  the preference, allowing the next launch to restore it.
- Sleep and replay release filters while preserving the preference. Wake refreshes
  devices after a one-second settling delay, then restores enabled takeover.
  Replay and sleep suspension overlap safely: both must end before restoration.
- Contact callbacks still feed the ordinary display/capture pipeline. Takeover
  itself supplies ownership; enabled gesture controls provide mouse movement,
  two-finger tap clicks and four-finger scrolling with momentum. These feature
  checkboxes default on with takeover; their rules are centralized in
  [GESTURE_ENGINE.md](GESTURE_ENGINE.md). No keyboard output, DriverKit helper or
  restricted entitlement is added.

USB and Bluetooth native FLTR were individually hardware-confirmed. Automatic
startup, selection transitions/rollback, Refresh and sleep/replay restoration
require hardware acceptance with this version. No live input is activated by
building or running the offline tests.

## Contact source identity

Live contact counts and rendered touches match the selected **native multitouch
numeric device ID** carried by each frame. The bridge's two reusable device-index
slots are telemetry hints, not physical identities: a third pad or a deselected
pad's ordinary monitoring frames can reuse them. Routing by those slots alone
could show the old Bluetooth pad after switching to USB even when FLTR ownership
had switched correctly. Selection changes clear cached rendered contacts.

The selected numeric IDs are parsed once during configuration, with integer
comparisons in frame processing. No registry lookup, string conversion or new
allocation is added per frame. Old recordings without numeric frame identities
retain index routing for compatibility. MAC/USB serial identify inventory entries;
they are transport-specific and are not substitutes for the ID carried by live
contact callbacks. This change does not claim one persistent ID across transports
or reconnects. Regression tests cover a BT-to-USB replacement, index collisions,
old-pad rejection, stale-render clearing and legacy capture routing.

## What made it work

The key call is Apple's private MultitouchSupport API:

```objc
MTDeviceStart(device, (MTRunMode)0x40000000u);
```

Read-only inspection of the installed macOS 15.7.4 (24G517), Intel binaries found:

1. `MTDeviceStart` tests bit 30 for native driver type **4**. It opens a user client
   with `IOServiceOpen` type **`0x464c5452`** (ASCII **FLTR**) instead of type zero.
   The run-mode bit and user-client type are different values.
2. `AppleMultitouchDeviceUserClient::initWithTask` recognizes this type and
   publishes **FilterEnabled=true** in the IORegistry.
3. The native driver registers these clients in a separate filter-client array.
   `_handleTouchFrame` chooses that array for incoming hardware frames when it is
   nonempty, instead of the ordinary-client array.
4. Injected frames can be routed to ordinary consumers. GesturePad does not
   reinject or forward frames, so native input is suppressed in the tested path.
5. Removing the last filter client restores ordinary routing.

```text
Normal:   trackpad → Apple multitouch driver → ordinary native consumers + OMS
Takeover: trackpad → Apple multitouch driver → GesturePad FLTR contact callbacks
Release:  trackpad → Apple multitouch driver → ordinary native consumers + OMS
```

Apple's framework still parses contacts into `MTTouch` callbacks. The change is
which client receives them; we did not recover contacts from the eight-bit mouse
interface or gain raw Bluetooth channel ownership. This describes the inspected
private implementation, not an Apple public API contract. No binary offsets or
Apple machine code are embedded in the app.

Ordinary user-space IOHID seizure had stopped both native movement and OMS
contacts, but returned zero raw reports. Feature initialization did not fix that.
New Bluetooth interrupt-channel access failed, reconnect observation did not
obtain the HID channels, and baseline input GET_REPORT failed. Earlier Quartz
event filtering dropped matched events while the cursor still moved. The FLTR
receive mode supplied the missing combination: contact access plus native-input
suppression and restoration.

See [the original investigation](../AppleMagicTouchstream/Tools/HIDSeizureProbe/NATIVE_FILTER_TEST.md)
for binary-inspection details and preserved standalone logs.

## Start, validation and rollback

`OpenMTManagerV2.beginNativeTakeoverForDeviceIDs:` runs synchronously on its native
serial state queue. It deduplicates the supplied IDs and validates **all** before
stopping any ordinary session. Each must have a retained native device reference,
a registered contact callback, and belong to the active native selection.

The checks require external USB or Bluetooth, PID **0324**, native driver type
**4**, and Apple VID **05ac for USB / 004c for Bluetooth** from the native service
ancestry. Existing or unreadable filter ownership causes refusal.

For each validated pad, the bridge stops ordinary monitoring, resets its atomic
frame counters, records the pad in its ownership set, and starts mode `0x40000000`.
It verifies exactly one filter client exists and that exactly one belongs to this
process using `FilterEnabled` and the `IOUserClientCreator` PID prefix.

If a stop/start/verification fails during a multi-pad start, release is attempted
for all pads already touched, including a failed-start pad. Failures remain visible
in the status. Other processes' native clients are never closed by GesturePad.

## Release, callback delivery and diagnostics

Release iterates a snapshot of every owned pad and attempts each even if another
fails. It stops our FLTR session, accumulates final counters, clears successfully
stopped ownership, inspects remaining own filters, and starts ordinary mode zero.
IORegistry may briefly retain a closing FLTR client after a successful stop.
The bridge restarts ordinary mode before inspecting remaining own filters, then
allows up to 100 ms for registry teardown. This avoids mistaking the closing
client for failed release during selection changes; retained pads are untouched.
Stop failures retain ownership for an explicit retry. Status reports native stop,
recovery and own-filter results rather than equating a return code with observed
hardware restoration. Releasing an already released session does nothing.

The same native callback/listener/OMS pipeline drives visualization and capture.
Only atomic frame/nonempty-frame counters are added to the callback. Status text
and registry work stay outside the hot callback. The app samples status on a common
main-run-loop timer. This timer updates diagnostics; it is not an ownership deadline.
There is no constant cursor correction, global cursor dissociation or event tap
in the takeover path.

The capture manager is **OpenMTManagerV2**. The older `OpenMTManager` serves haptics;
changing that alone would not change the raw-contact ingestion path. Rebuild the
XCFramework from source after Objective-C bridge changes.

| Source | Responsibility |
| --- | --- |
| [OpenMTManagerV2.h](Framework/OpenMultitouchSupportXCF/OpenMTManagerV2.h) | Begin selected IDs, end takeover, snapshot status. |
| [OpenMTManagerV2.m](Framework/OpenMultitouchSupportXCF/OpenMTManagerV2.m) | Native preflight, ownership set, starts, rollback, release, callback counts. |
| [OMSManager.swift](Sources/OpenMultitouchSupport/OMSManager.swift) | Swift API wrappers. |
| [HIDBlackholeExperiment.swift](GesturePad/GesturePad/Runtime/HIDBlackholeExperiment.swift) | Persistent preference, differential transitions, suspension, polling and release. |
| [ContentView.swift](GesturePad/GesturePad/ContentView.swift) | Persistent checkbox, unlocked selectors and Refresh. |
| [GesturePadApp.swift](GesturePad/GesturePad/GesturePadApp.swift) | Menu/shortcut, lifecycle release, auto-resync ownership hook. |

## Evidence, signing and remaining acceptance

Successful standalone trials included 609 filter frames / 601 nonempty with zero
sampled cursor span, followed by a one-finger run with 712 / 712 filter frames and
447 / 447 recovery frames. The latter measured a small nonzero cursor span
(4.11 / 3.43), despite no visible movement; its cause remains unestablished. An
earlier trial stalled, and another recovery monitor received no frames despite
native movement returning. Preserve these limitations alongside later success.

The user confirmed the integrated Bluetooth test worked “phenomenally well,” then
confirmed the integrated USB test works. This does not establish long-session,
simultaneous-pad, crash/sleep/reconnect, complete click/drag/gesture, or other
macOS/CPU compatibility. Verify these on the continuous feature separately.

The app adds no DriverKit extension, restricted entitlement, provisioning profile,
privileged helper, sudo step, SIP/security change, or kernel patch. This private
input mechanism does not itself supply a virtual HID output device or establish
App Store/notarization eligibility. The raw-report decoder was removed; its
findings remain in [APPLE_CONTACT_HID_LAYOUT.md](APPLE_CONTACT_HID_LAYOUT.md), and
optional old capture provenance remains readable.

## Build and regression checks

```sh
./build_framework.sh
./build.sh
./test.sh
./release.sh --check
```

`test.sh` includes [offline native lifecycle checks](Tests/NativeTakeover/main.m)
with fake native devices/operations: complete preflight, selection deduplication,
release/reuse, failed second-pad start rollback, owner-verification rollback, and
partial-release retry. They never open hardware. The Swift suite includes NativeTakeoverPreferenceTests for default-off/persistence,
startup ordering, deduplication, selection changes, refresh ordering, overlapping
suspensions, emergency release and failed transitions. Native fake-device tests
cover retained clients, rejected additions, acquisition/removal rollback and
incomplete recovery as well as the original lifecycle checks. The suite checks the
remaining app/runtime behavior. Hardware acceptance is in
[NATIVE_FILTER_TEST.md](NATIVE_FILTER_TEST.md).

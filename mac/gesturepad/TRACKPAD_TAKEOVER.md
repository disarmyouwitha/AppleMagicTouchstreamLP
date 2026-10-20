# Trackpad Takeover through the native FLTR client

Updated 2026-10-19 after the user confirmed both Bluetooth and USB native-filter
trials work. GesturePad now offers continuous **Trackpad Takeover** and
**Release Trackpads** for the currently selected trackpads. The custom DriverKit
implementation remains removed from both GesturePad and AppleMagicTouchstream.

## User behavior

- Select zero, one or two pads with the existing Left/Right selectors.
- **Trackpad Takeover** captures the nonempty current selection, deduplicating a
  pad selected on both sides. Unselected pads are not opened as filter clients.
- Every selection must be an active, external, supported USB/Bluetooth pad. An
  unsupported selection fails the whole preflight rather than being skipped.
- Native contact callbacks continue through the ordinary GesturePad display and
  capture pipeline. No synthetic pointer, click or keyboard output is added.
- Takeover continues until explicit/lifecycle release; the former 15-second cap
  has been removed following USB confirmation. Nothing activates on app launch.
- **Release Trackpads**, the menu action, and **Ctrl–Option–R** release ownership.
- Release before changing the selectors or using Refresh; both are disabled while
  ownership remains. Auto-resync is paused during ownership and restored afterward.
- Config close preserves takeover and leaves the process/native capture running.
  Restart rebuilds Config in the same process while takeover is active, retaining
  the controller and native clients. A real process relaunch would close FLTR
  ownership; no interprocess transfer is attempted. Inactive Restart still relaunches.
- Sleep, replay and Exit release the native clients. A process-level sleep observer
  works even with Config closed. There is no automatic takeover on reconnect or
  driver helper.

USB and Bluetooth were individually hardware-confirmed by the user. Continuous
simultaneous two-pad operation is the next integrated hardware acceptance check.

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
| [HIDBlackholeExperiment.swift](GesturePad/GesturePad/Runtime/HIDBlackholeExperiment.swift) | Explicit start, status polling, legacy-experiment exclusion, central release. |
| [ContentView.swift](GesturePad/GesturePad/ContentView.swift) | Selected-pad buttons and selection/refresh locks. |
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
partial-release retry. They never open hardware. The Swift suite checks the
remaining app/runtime behavior. Hardware acceptance is in
[NATIVE_FILTER_TEST.md](NATIVE_FILTER_TEST.md).

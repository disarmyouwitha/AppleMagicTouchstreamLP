# Trackpad takeover through the native FLTR client

Documented 2026-10-19. Implementation: GesturePad's **Native filter experiment**.

GesturePad can receive Bluetooth Magic Trackpad contact frames while suppressing
its normal native pointer behavior by opening Apple's existing multitouch
**filter user client**. The key call is:

```objc
MTDeviceStart(device, (MTRunMode)0x40000000u);
```

The user tested the integrated GesturePad experiment and reported that it works
“phenomenally well.” This follows the successful standalone Bluetooth trials
with contact delivery during suppression and native movement restored on release.
The integrated test is still explicitly bounded to 15 seconds and one selected
pad at a time. The user subsequently requested removal of the entire custom DriverKit implementation
from both apps; only this native test remains in GesturePad. Raw contact decoding
knowledge is preserved in [APPLE_CONTACT_HID_LAYOUT.md](APPLE_CONTACT_HID_LAYOUT.md).

## What made it work

The breakthrough was finding a different receive mode inside Apple's private
MultitouchSupport framework, then following that mode into the installed
AppleMultitouchDriver implementation through read-only binary inspection.

On the inspected macOS 15.7.4 (24G517), Intel host:

1. `MTDeviceStart` checks bit 30 (`0x40000000`) for native driver type **4**.
2. With that bit set, the framework opens a user client with `IOServiceOpen`
   type **`0x464c5452`**, the four-character code **`FLTR`**, instead of ordinary
   client type zero. The run-mode flag and user-client type are different values.
3. `AppleMultitouchDeviceUserClient::initWithTask` recognizes this type and
   publishes **`FilterEnabled = true`** on the client in the IORegistry.
4. The native driver registers filter clients in a separate client array.
   Its incoming-touch-frame handler chooses that array when it is nonempty,
   redirecting frames away from ordinary consumers.
5. Removing the last filter client restores routing to ordinary consumers.

Apple's own MultitouchSupport code still parses the contact frames. GesturePad
receives the familiar `MTTouch` callbacks through the filter connection and feeds
its existing contact display. We do not forward or inject those frames into the
ordinary-client path during this test. That combination preserves contact access
while suppressing the native behavior observed in the hardware tests.

Conceptually, the routing found in the inspected binaries is:

```text
Normal:
Bluetooth trackpad → Apple multitouch driver → ordinary clients
                                              ├─ native input consumers
                                              └─ GesturePad contact callbacks

During our FLTR session:
Bluetooth trackpad → Apple multitouch driver → filter client
                                              └─ GesturePad contact callbacks
                                                 (no frame reinjection)

After our filter client closes:
Bluetooth trackpad → Apple multitouch driver → ordinary clients again
```

This is a description of the observed private implementation, not an Apple
public API contract. Symbol locations and the original investigation are in
[the standalone research notes](../AppleMagicTouchstream/Tools/HIDSeizureProbe/NATIVE_FILTER_TEST.md).
No binary offsets are used by the application.

## Why the earlier approaches did not get us here

| Approach | Actual result from our experiments |
| --- | --- |
| Ordinary user-space `IOHIDDeviceOpen` seizure | Native movement and ordinary multitouch delivery stopped, but our report callback received zero raw/contact reports. |
| Feature-report initialization after seizure | The write succeeded, but contact reports still did not arrive. |
| New Bluetooth interrupt channel | The requested channel open failed; no listener was attached. |
| Bluetooth reconnect notifications | Device connection was visible, but the experiment did not obtain the native HID channels. |
| Input `GET_REPORT` polling | Baseline report request failed, so the guarded test did not proceed to seizure. |
| Quartz movement-event filtering | Earlier experiments dropped matched events while visible cursor motion remained. |
| Native FLTR receive mode | Contact callbacks continued while native movement was visibly suppressed, and native input returned after release in successful trials. |

The correct device had already been identified: ordinary seizure stopping its
native contact delivery was evidence of that. The missing piece was a receive
path that preserved rich contacts while changing their destination. We did not
solve this by decoding an exposed eight-bit mouse report or by taking ownership
of Bluetooth's raw channels.

## How GesturePad implements it

### Start and validation

`OpenMTManagerV2` owns the experiment on its existing serial native state queue.
`beginNativeFilterTestForDeviceID:` looks up the **exact active native device ID**
from GesturePad's selection and the manager's retained native device references.
It does not hardcode the research pad's Bluetooth address or seize every pad.

Before starting, it requires:

- An active selected device, with an existing registered contact callback.
- An external Bluetooth device, not a built-in trackpad or USB device.
- Apple vendor `0x004c` and product `0x0324` from the service ancestry.
- Native driver type `4`.
- No existing `FilterEnabled` client on that native service.
- No concurrent legacy takeover experiment, enforced by the app controller.
  The previous DriverKit ownership path has been removed.

The bridge then:

1. Stops the selected device's ordinary native monitoring session with
   `MTDeviceStop(device)`, retaining its device reference and callback context.
2. Resets its atomic frame and contact-frame counters.
3. Records the active filter device and schedules the 15-second release deadline.
4. Calls `MTDeviceStart(device, (MTRunMode)0x40000000u)`.
5. Verifies exactly one filter client exists and exactly one belongs to this
   process, using `FilterEnabled` and the `IOUserClientCreator` PID prefix.
6. Rolls back through the release path if start or ownership verification fails.

We inspect registry state to verify ownership; we do not mutate registry
properties or close another application's clients.

### Contact delivery and diagnostics

The existing `openMTManagerV2ContactFrameCallback` continues forwarding native
contacts through the same raw listener and `OMSManager` pipeline used by the
visualizer. There is no second decoder, external probe process, or DriverKit
packet conversion in this path.

The callback adds atomic total-frame and nonempty-frame counters. Registry work,
status strings and cursor sampling happen outside the touch callback. The app
samples status every 0.25 seconds and reads cursor position with
`CGEvent(source: nil)?.location`; it never changes that position. The display
shows counts, sampled cursor span, remaining time and release/recovery status.

Cursor span measures the global cursor, so moving another mouse contaminates
that measurement. Periodic samples can also miss brief intermediate movement;
visual observation is part of the test.

### Release and lifecycle

`endNativeFilterTest` runs on the native state queue and:

1. Calls `MTDeviceStop` on our selected native filter session.
2. Saves the final filter-frame counters.
3. Keeps ownership marked active if stop fails, so Release can be retried.
4. On successful stop, clears the active filter device and invalidates the
   session generation used by the deadline.
5. Reads the remaining filter clients belonging to this process.
6. Calls `MTDeviceStart(device, 0)` to resume ordinary contact monitoring and
   reports the recovery return code.

The timed release is a `dispatch_after` on the native state queue, independent
of the SwiftUI/main-run-loop timer. A stalled UI alone does not extend the test;
a blocked native API or state queue is not covered by a separate process watchdog.
Generation checking prevents an old deadline from releasing a newer session.

The app's existing central release now also calls `OMSManager.endNativeFilterTest`.
That connects the experiment to **Release test**, menu **Release Trackpads**,
**Ctrl–Option–R**, and existing sleep/replay/config-close/restart/exit cleanup.
The native manager also ends the experiment before stopping all callbacks.
Refresh and device selectors are disabled while the test owns a filter session;
the bridge also refuses refresh/reselection while active.

### Source map

| File | Responsibility |
| --- | --- |
| [OpenMTManagerV2.h](Framework/OpenMultitouchSupportXCF/OpenMTManagerV2.h) | Native begin/end/status API. |
| [OpenMTManagerV2.m](Framework/OpenMultitouchSupportXCF/OpenMTManagerV2.m) | Validation, FLTR start, registry verification, contact counters, deadline, release and ordinary-mode recovery. |
| [OMSManager.swift](Sources/OpenMultitouchSupport/OMSManager.swift) | Swift wrappers around the native experiment API. |
| [HIDBlackholeExperiment.swift](GesturePad/GesturePad/Runtime/HIDBlackholeExperiment.swift) | App ownership exclusion, UI status polling, cursor sampling and central release integration. |
| [ContentView.swift](GesturePad/GesturePad/ContentView.swift) | Per-selected-pad test buttons, live status, release button and refresh/selection locks. |

The capture path is **OpenMTManagerV2**, not the older `OpenMTManager` used for
haptic support. A future port must modify the actual contact-capture manager.
After changing the Objective-C bridge, rebuild the XCFramework from its source;
do not patch generated framework binaries.

## What this means for entitlements and output

This experiment uses the native user client already provided by Apple's driver.
It adds no custom DriverKit extension, restricted entitlement, provisioning
profile, privileged helper, or `sudo` invocation to the GesturePad test path.
No SIP/security change, system-binary modification, kernel patch, event tap,
cursor warp, or global mouse/cursor dissociation was introduced.

The user reported success after testing the integrated GUI build. We have not
collected a new terminal log or a formal permissions matrix from that run. The
standalone trials used `sudo`; the GUI implementation itself contains no elevation
step. Existing app permissions and the host's configuration should not be inferred
to apply identically to every other Mac.

This is an **input takeover** mechanism. It does not itself provide a virtual
keyboard/mouse output driver, inject replacement events, or integrate Karabiner.
The initial integration preserved DriverKit; the user subsequently requested
removing its implementation, helper, decoder and output integration from both apps.
Existing serialized capture metadata remains readable. Success of this private receive path does not establish App Store
eligibility, notarized public distribution, or support on other macOS versions.

## Evidence and current limits

The standalone second trial recorded **609 frames / 601 nonempty** during the
filter phase and exactly zero sampled cursor span. Its recovery monitor received
no callbacks even though the user confirmed native cursor recovery.

The third trial, with one finger moving continuously, recorded:

| Phase | Total frames | Frames with contacts | Sampled cursor span X / Y |
| --- | --- | --- | --- |
| Baseline | 383 | 382 | 802.47 / 167.50 |
| Filter | 712 | 712 | 4.11 / 3.43 |
| Recovery | 447 | 447 | 822.44 / 675.42 |

The user observed cursor before, no visible cursor movement during filtering,
and cursor after. The filter client's presence and removal were verified. The
small nonzero span in this trial remains recorded; its cause was not established.
See the [saved third-run log](../AppleMagicTouchstream/Tools/HIDSeizureProbe/captures/native-filter/third-run-one-finger.log).

After integration, GesturePad built successfully, signature verification passed,
and **81 Swift tests plus 11 DriverKit regression checks** passed. These checks
do not emulate the hardware FLTR path. The user then confirmed that the integrated
experiment works very well. That is the current hardware acceptance evidence;
no precise integrated-run frame counts were supplied.

Still to establish before promoting FLTR to continuous production control: long sessions,
repeated cycles, sleep/crash/reconnect recovery, complete click/drag/scroll/gesture
behavior, independent simultaneous pads and other mice, and other OS/CPU versions.
The initial stalled trial and the second trial's missing recovery callbacks remain
part of the evidence, even though later runs succeeded. The working implementation
remains an explicit 15-second experiment until further changes are authorized.

## Rebuild and reproduce

From this directory:

```sh
./build_framework.sh
./build.sh
./test.sh
```

Quit other trackpad apps and the old GesturePad before opening
`build/DerivedData/Build/Products/Debug/GesturePad.app`. Select a Bluetooth pad,
then use **Left Trackpad → Native filter experiment → Test [serial] · 15s**.
Move one finger continuously, watch the contacts and native pointer, and confirm
normal input returns after release. Keep another mouse available.

See [NATIVE_FILTER_TEST.md](NATIVE_FILTER_TEST.md) for the shorter hardware checklist.

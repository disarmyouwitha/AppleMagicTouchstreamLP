# Native multitouch FLTR receive experiment

Prepared 2026-10-19 for this iMac: macOS 15.7.4 (24G517), x86_64. This is a new
receive/routing experiment, not a claim that takeover now works. The production
app, custom DriverKit implementation and release scripts are unchanged.

## Concrete evidence behind this test

Read-only inspection of the installed MultitouchSupport and AppleMultitouchDriver
kernel collection found the following chain:

1. `MTDeviceStart` tests mode bit 30 for native driver type 4. It passes
   IOServiceOpen type `0x464c5452` (ASCII FLTR) rather than ordinary type 0.
2. `AppleMultitouchDeviceUserClient::initWithTask` recognizes that type, marks the
   client internally, and publishes `FilterEnabled=true` on that client.
3. `_registerUserClient` stores these clients in a separate filter-client array.
4. `_handleTouchFrame` chooses that array for incoming hardware frames when it is
   nonempty. A frame injected by a filter client selects the ordinary-client array
   instead. The filter-receive and ordinary-receive paths are distinct.
5. `_unregisterUserClient` removes a filter client from that array; the routing
   branch returns to ordinary clients when no filter client remains.

This is a static interpretation of the installed binaries, not Apple API support
or a hardware result. Our hypothesis is that one FLTR client can receive/parse
contacts without forwarding them to native ordinary consumers. We do not call
frame injection, nor enable the framework's binary-filter plug-ins.

Read-only metadata confirmed the right Bluetooth pad has driverType=4. Its current
WindowServer and BetterTouchTool native user clients did not have FilterEnabled
set. A normal shared baseline is essential: with no existing filter, the ordinary
baseline and the new filter path should receive the same native frame format,
with the kernel choosing a different destination array. The parser remains Apple's
private MultitouchSupport implementation. This is not an independent sensor decoder.

Relevant local symbol locations in the inspected binaries:

| Symbol | Address/offset |
| --- | --- |
|MultitouchSupport MTDeviceStart|text address 0x7ff81277522c|
|Mode-to-FLTR selection|0x7ff81277533a through 0x7ff812775366|
|AppleMultitouchDeviceUserClient::initWithTask|0xffffff8001b2e2c0; FLTR comparison at 0xffffff8001b2e349|
|AppleMultitouchDevice::_registerUserClient|0xffffff8001b29204|
|AppleMultitouchDevice::_handleTouchFrame|0xffffff8001b28ab4; array selection at 0xffffff8001b28c01 through 0xffffff8001b28c41|
|AppleMultitouchDevice::_unregisterUserClient|0xffffff8001b29510|

Disassembly and a temporary read-only view of the kernel-collection kext header
were created under /tmp for analysis only. No system binary was modified or
loaded, no SIP/security setting was changed, and no kernel/Apple code is bundled
into this experiment. The probe calls the existing native user-client path.

## Hardware command

1. Release DriverKit takeover; quit AppleMagicTouchstream, GesturePad and BTT.
   Keep another mouse/keyboard available. Keep the **right pad ON and connected**.
2. From repo root run:

```sh
sudo ./mac/AppleMagicTouchstream/Tools/HIDSeizureProbe/run-native-filter-test.sh D0:C0:50:D5:69:55
```

3. Move several fingers on the right pad continuously through these stages:

| Stage | Duration | Observe |
| --- | --- | --- |
|BASELINE|5 seconds|Contacts and normal native cursor movement|
|FILTER|8 seconds|Do contact counts/coordinates keep changing while native movement stops?|
|RECOVERY|5 seconds|Do normal native movement and contacts return?|

Do not move another mouse during measurement; global cursor-span measurements
cannot attribute motion to a device. Do not press down to click during this first
test, particularly across phase boundaries. Two-finger scroll can be observed.
The other mouse is available for recovery, not part of the measurement.

4. Send the full output plus what native cursor/scroll did during FILTER and
   whether it recovered. Logs are saved to a private /tmp/amt-native-filter.XXXXXX
   folder and returned to the invoking user when run through sudo.

## Gates and cleanup

- Exact explicit Bluetooth address, not built-in, exactly one native MT device;
  filter additionally requires VID 0x4c, PID 0x324 and native driverType 4.
- Refuses active AMTRawHIDReceiver DriverKit takeover. Requires nonempty ordinary
  baseline contact frames. Refuses an existing FilterEnabled client.
- Verifies exactly one FilterEnabled client belonging to this PID after opening.
  Verification failure closes our client. We never close another process's client.
- Baseline is stopped before filter activation. MTDeviceStop closes our FLTR
  client before recovery; a new ordinary monitor verifies no filter remains.
- Eight-second filter window, with a twelve-second process alarm covering filter
  start, verification and close. A stalled API therefore ends the process and its
  connections. Whole baseline phase also has a 35-second alarm; recovery has ten.
  Signals request normal cleanup; suspension is ignored. A stop return code and
  removal of our client are not proof of native restoration; user observation is
  required. If the selected pad does not recover, stop the probe and power-cycle it.
- No IOHIDDevice exclusive open, Bluetooth channel open/delegate replacement,
  GET_REPORT, SET_REPORT, global property writes, native callback replacement,
  event taps, cursor dissociation/warping or synthesized output.
- Contact callbacks update static atomics only. Counts and first-contact normalized
  coordinates are sampled once a second. They are diagnostic snapshots, not a
  coherent full-frame capture. Cursor position is read at about 20 Hz without
  changing it; reported span supplements human observation and may miss brief
  motion. The raw sensor capture/production integration is future work.

A successful experiment requires **all three**: changing contact data during
FILTER, native movement/scroll suppression, and native recovery after release.
A successful FLTR open or property verification alone does not establish that.
No live activation of this experiment has been performed by the agent.

## Other avenues checked in this research pass

- The pasted ChatGPT table conflicts with the real results: ordinary Bluetooth
  IOHID seizure did stop native movement and native contacts. Its failed point was
  receiving contact bytes during that seizure. Existing Quartz filtering had
  already discarded matched events while cursor coordinates still moved.
- Apple's HIDEventSystemClient headers require private admin/event-monitor grants
  for upstream event monitoring/filtering; successful object allocation does not
  establish access. That is not a verified entitlement-free substitute.
- Updating a ReportDescriptor IORegistry value after the native IOHIDDevice has
  parsed it would not by itself rebuild its existing kernel report elements.
  No descriptor/property mutation was tried.
- Third-party HCI logging examples used global diagnostic flags including an
  authorization-skipping setting. That recipe was not adopted or executed under
  the user's no-security-weakening constraint. Logging is also not demonstrated
  as a suitable production input path.
- Unrelated MT touch/power/UI-lock modes were inspected, not invoked. Their
  presence is not evidence that arbitrary values safely preserve contacts.

## Verification

The standalone NativeFilterProbe is universal arm64+x86_64 and Developer ID signed,
hardened runtime, no restricted entitlements/provisioning profile; not notarized.
Only this Intel host's installed native routing was disassembled. Other macOS/
architecture behavior remains unverified. No release integration was made.

The test suite compiles NativeContacts with fake MT and registry functions and
**without linking IOKit/MultitouchSupport**. It checks ordinary versus FLTR mode,
exact selection/model/type gates, pre-existing-filter refusal, own-client
verification, callback counters/coordinates, late-callback rejection and failed
start cleanup. This validates our bridge logic, not native hardware routing.

Reference source reviewed (alongside the local binaries):

- [Apple HIDEventSystemClient type/access documentation](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/HID/Headers/HIDEventSystemClient.h)
- [Apple IOHIDDevice descriptor construction](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDDevice.cpp)
- [Independent multitouch framework declarations](https://github.com/asmagill/hs._asm.undocumented.touchdevice/blob/master/MultitouchSupport.h)

## First hardware results

Preserved logs: [first run](captures/native-filter/first-run.log),
[second run](captures/native-filter/second-run.log).

The first run verified one own FilterEnabled client and received 204 filter frames
(201 nonempty), but counts paused for several seconds and measured cursor span
was nonzero. The user reports continuous finger movement and a temporary cursor
stop. The cause/timing of the stall is not established; the available unified
log did not identify a filter timeout or reset. Do not infer a watchdog cause
from the duration alone.

The second run is positive evidence for the core receive/suppression combination:
609 frames, 601 nonempty, changing contact coordinates, and cursor spans X=0/Y=0
throughout the eight-second filter phase. Counts increased on every printed
filter interval. Baseline had 375 frames/373 nonempty and normal cursor motion.
The filter was removed after close (no FilterEnabled clients remained).

The second recovery monitor received zero contact frames, while the cursor span
became nonzero again. Which input produced that movement and whether the user
continued touching the selected pad during recovery require user observation.
This establishes the core eight-second result on this machine, not a reliable
release/reacquisition lifecycle or production readiness. Keep this evidence;
do not replace it with an unverified alternative transport experiment.

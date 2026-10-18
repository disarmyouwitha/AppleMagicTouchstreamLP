# First raw HID capture findings

**Current conclusion:** see the [2026-10-18 DriverKit takeover checkpoint](DRIVERKIT_TAKEOVER_CHECKPOINT.md) for successful SIP-enabled USB and Bluetooth results. The sections below are chronological research history, including superseded hypotheses.

Inputs: `captures/left_hid_capture.json`, `captures/right_hid_capture.json`.

Both recordings ran approximately 15 seconds and ended through the automatic capture deadline. Both selected physical trackpads were connected via Bluetooth (product ID 804 / 0x0324). Each session successfully seized and closed all ten eligible interfaces, five per trackpad. Both files contain descriptors and identities, but **zero input reports**, zero bytes received, and zero dropped reports across every interface. No USB recording is present in these two files.

Consequently, these recordings cannot establish contact packet format, finger counts, coordinate packing, or pressure fields. They demonstrate successful ownership calls and absent input callback delivery. They do not establish why callbacks were absent. In particular, the initial capture format did not record Input Monitoring authorization.

The next build checks/requests Input Monitoring before capture, records its state at start/end, and explicitly reports zero-report sessions. Repeat one Bluetooth capture after permission is granted and GesturePad is relaunched. If callbacks remain absent with confirmed access, investigate receive scheduling and device multitouch mode; obtain a USB comparison before selecting a decoder. The Windows official PTP spec is a candidate format reference, not evidence of the Mac payload format.

## Permission-confirmed retry

`captures/hid_retry.json` again contains zero reports on all ten Bluetooth interfaces, with `inputMonitoringAtStart` and `inputMonitoringAtEnd` both `granted`. The initial permission hypothesis is not supported as the explanation for this retry. No decoding conclusion is possible.

Receive-lifecycle audit found that callback removal passed a null context rather than the registered owner context. Apple's public IOHIDDevice implementation matches callback registrations by context. Cleanup now uses the original context. Every new open also creates a fresh IOHIDDevice connection rather than reusing a callback-bearing object; report callback registration precedes the open. These changes address lifecycle correctness, but are not established explanations for zero reports.

A new **Capture baseline (15s)** control opens only selected trackpad interfaces nonexclusively and leaves native input enabled. Captures record `captureMode` (`shared-baseline` or `exclusive`) and `callbackSetup`. Baseline capture releases any prior exclusive session first; its checkbox remains off. Explicit release, selection/refresh, sleep, replay, config close and quit close baseline handles as well. Compare baseline callback delivery with exclusive capture before trying device-mode commands or a different receive backend. No multitouch mode commands have been sent.

## Nonexclusive Bluetooth baseline

`captures/hid_baseline.json` records `captureMode: shared-baseline`, granted Input Monitoring at start/end, and approximately 15 seconds of recording. All ten shared opens and closes succeeded, but all ten interfaces again contain zero reports and zero dropped reports. This rules out exclusive ownership as a necessary condition for the observed missing delivery. It does not establish that decoding or multitouch mode negotiation would fix delivery.

The next receive implementation uses IOHIDDeviceSetDispatchQueue targeting the main queue, explicitly activates each fresh connection, and cancels it after closing. The cancellation handler keeps the callback context/buffer alive until internal queues finish cancelling. It also registers input-value callbacks as an independent delivery counter. New per-interface fields are `reportCallbackCount`, `inputValueCallbackCount`, `lastInputValueReportID`, `lastInputValueResult`, `matchingInputElementCount`, and `declaredInputReportIDs`. Counters cover the lifetime of each open; payload recording covers the capture interval. The UI shows report/value counts separately. No feature reports, device-mode commands, transport changes, or global event filters are introduced.

Next hardware check: one nonexclusive baseline with the updated dispatch receiver. If it still contains zero report callbacks and zero input-value callbacks despite declared input elements, inspect the Bluetooth service/transport path and compare USB before asking for gesture-specific captures. Build/test success cannot validate physical callback delivery.

## Dispatch baseline and change of experiment

`captures/hid_dispatch_baseline.json` again contains zero raw report callbacks and zero input-value callbacks for both Bluetooth pads. The mouse/digitizer collection on each pad enumerates 1395 matching input elements with declared report IDs 2, 63 and 68. Thus element discovery succeeded, but no callback payload was observed. This still does not identify the underlying cause. Further raw-HID recordings with unchanged behavior are paused.

A separate pointer-identity observer now compares generated CGEvents while retaining Apple's normal contact stream. It dynamically checks for an attached IOHIDEvent and its sender ID; labels and timestamps alone are never treated as device identity. The live output path and phase sequence are documented in README. This is a test of whether selected-device pointer filtering can be supported on this machine, not an implementation of filtering.

## Pointer identity result: Bluetooth success for ordinary movement

Preserved `captures/pointer_identity_bluetooth.json` from the completed 40-second observer on macOS 15.7.4. There were 2773 observed events, no tap interruptions and no aggregate overflow. All 2686 ordinary mouse-moved events carried an underlying HID event and a nonzero sender ID. Registry ancestry connects each pad's sender to its selected HID interface, independently of the phase labels:

| Device | Sender ID | Selected interface ancestor | Ordinary movement events |
| --- | --- | --- | --- |
| Left pad, serial ending D4:75:6C | 4295108038 | 4295108009 | 740 |
| Right pad, serial ending D5:69:55 | 4295109516 | 4295109487 | 391 |
| Logitech USB receiver mouse | 4295095385 | unrelated USB receiver | 1555 |

Left-only and right-only phases each showed their respective pad's sender. The mixed phase showed distinct left-pad and mouse senders; it does not establish simultaneous right-pad behavior. Pad scroll events also carried their respective sender IDs. Two left-mouse-dragged events during the mouse phase had no attached HID event. Four mouse-button transitions had the receiver sender ID; pad button events were not observed.

This supports a timed next experiment suppressing only positively identified selected-pad ordinary mouse-moved events, using registry ancestry matching rather than hardcoded sender IDs. Unknown/missing-HID events must pass. It does not yet validate suppression, synthesized two-finger movement, drag suppression, USB trackpad identity, reconnect behavior, all gestures, or contact telemetry during filtering. The observer itself did not seize devices or suppress events.

## Mixed USB/Bluetooth movement, scroll, click and drag test

Preserved `captures/pointer_identity_usb_bluetooth.json` (started 2026-10-18T03:17:56Z, macOS 15.7.4). The completed 40-second test had 1695 events, no interruptions and no overflow. Left Bluetooth sender 4295108038 maps to selected HID interface 4295108009; right USB sender 4295137219 maps to selected HID interface 4295137189. Logitech receiver sender remains 4295095385. Selected groups are sorted independently of left/right UI order; registry ancestry and the instructed phases establish the comparison.

| Event type | Left Bluetooth | Right USB | Mouse | Identity outcome |
| --- | ---: | ---: | ---: | --- |
| Ordinary movement, including mixed phase | 345 | 116 | 867 | All had matching nonzero sender IDs |
| Scroll | 100 | 94 | 0 | Both pads had matching IDs; mouse wheel untested |
| Left-button down/up transitions | 4 | 4 | 6 | All had matching IDs |
| Left-button drag during each device's phase | 60 | 18 | 81 | All lacked attached HID events |

All 159 missing-HID events were left-mouse-dragged events. Association with each device in this row describes the user-instructed phase, not recovered identity. Both pads and mouse were distinguishable for ordinary movement in the mixed phase. This supports testing selective ordinary-movement suppression for USB and Bluetooth, plus preserves evidence for identified pad scroll/click events. It does not establish that drag events can be safely attributed during simultaneous-device use. Inferring drag identity from the last button-down or recent contacts would be a heuristic and is not implemented. No filtering is implemented by the observer.

## Selected-pad control wired for physical verification

The checkbox, 30-second test and existing Release Trackpads button/menu/global shortcut now control a CGEvent filter instead of exclusive HID ownership. Raw capture buttons are removed from Config; Test Pointer Sources remains. Only matched mouseMoved and scrollWheel events are suppressed. Buttons, drags, unknown sender events and other mice pass. The existing two-finger interpreter posts tagged movement, pauses while a mouse button is held, and stops on release. Sender mapping is rebuilt from selected interface ancestry, including AppleMultitouchDevice children; service changes stop control.

A read-only run of the production routing functions against the current registry matched both selected groups and their recorded Bluetooth/USB senders (4295108038 and 4295137219), excluding mouse receiver 4295095385. Both script/default Xcode Debug builds passed, as did 48 package tests. No filter was activated by automated verification. Actual suppression, uninterrupted contact data, native clicks/drags, normal mouse passthrough, synthesized two-finger motion and timed/global release remain the next hardware test.

## Native cursor leakage despite event suppression

User reported two-finger movement functioning, native one-finger movement still moving the cursor, and the blocked-moves counter increasing during that leak. This supports successful identification/drop decisions but demonstrates that dropping CGEvents alone did not suppress the visible pointer in this configuration. It does not implicate missing sender identity.

The follow-up implementation anchors the cursor at the last allowed destination and calls CGWarpMouseCursorPosition only for positively matched selected-pad mouseMoved events before discarding them. Other-mouse/unknown/native-drag/tagged synthetic destinations update the anchor. There is no global mouse/cursor disassociation. Synthetic output has its own visible toggle and posted-event count so it can be disabled during isolation testing. GTK's read-only system three-finger-drag preference status is reproduced independently in GesturePad. Physical correction quality, mixed-input behavior and jitter have not been verified by automated tests.

## Cursor correction rejected and removed

The user rejected cursor warping and confirmed the other behavior worked as expected. Removed CGWarpMouseCursorPosition, cursor anchors and correction counters, leaving sender-based event filtering, scroll suppression, synthetic two-finger output, native button/drag passthrough and system drag status intact. UI now explicitly says discarded movement events do not disable the native cursor. An upstream service/driver-level pointer suppression path remains an investigation, not a proven replacement. Do not repeat warp-based or global cursor-dissociation approaches.

## Upstream access probe prepared

Apple's HIDEventSystemClient header documents a private entitlement requirement for event-filter callbacks. A local standalone capability check found all required symbols present and all four requested client types allocatable despite no grants among the queried private HID keys. Thus allocation is not evidence of authorization. The new in-app Test upstream access control checks the running process and registers an always-pass admin-client filter callback for 15 seconds. It writes API/client/entitlement/callback diagnostics to `/tmp/GesturePad-upstream-access.json`. No suppression, mutation, device opens, property changes, entitlement changes or cursor correction are performed. A positive callback count would justify a later selected-source suppression test; zero callbacks remain a negative delivery result rather than a proved cause. The exact event-filter entitlement string is not confirmed and is labeled a candidate in diagnostics.

## Minimum per-device gain probe prepared

A read-only passive-client inspection found `HIDPointerAccelerationMultiplier` equal to 46603 on both currently selected Bluetooth and USB pads. Apple IOHIDPointerScrollFilter source explicitly converts a missing or zero multiplier to 1.0 before setupPointerAcceleration, so setting zero cannot test suppression. The next optional 15-second experiment uses the smallest positive fixed-point value (1) and restores the exact pre-existing numeric values, checking setter/readback results. Service selection uses registry ancestry; missing restorable values abort before any writes. No global properties or acceleration curves are modified. This is a test of whether the service property is writable and affects native motion, not proof of exact suppression. Synthesis remains off for the test. Results go to `/tmp/GesturePad-gain-probe.json`; no automated hardware mutation has been performed.

## Restorable multiplier precheck corrected

The first in-app minimum-gain precheck aborted before writes. Root cause: IOHIDServiceClientGetRegistryID was declared as returning UInt64, but its return is a borrowed CFNumber. Interpreting the tagged/object reference as an integer produced invalid registry lookups. Corrected the runtime declaration to an unmanaged CF object and extract NSNumber.uint64Value. A read-only check now resolves service 4295108038 to Bluetooth interface 4295108009 and service 4295137219 to USB interface 4295137189; both report multiplier 46603. No hardware property was written during diagnosis. Failed prechecks now identify unmatched selected labels and save their diagnostics, rather than returning an unsaved generic message.

## First multiplier-write result

Preserved `captures/gain_probe_first_write.json`. Both pads matched and exposed original multiplier 46603. The Bluetooth service was attempted first: setter returned true for value 1, but the immediate property read returned 46603. The probe immediately restored the original; setter returned true and readback matched 46603. USB was not written because the first mismatch aborted the test. No timed physical-effect interval ran. `active` is false.

This is accepted-call/unverified-change evidence, not a rejected write and not proof the property cannot influence motion. Apple's filter caches property writes and applies setupAcceleration on its filter queue; therefore the public service-property read alone is not established as authoritative for the applied filter state. A subsequent test would need delayed/fresh reads or filter-state evidence and a bounded physical-effect interval; the prior immediate-readback gate must not be described as evidence of a permissions failure.

## Accepted-write physical window

Minimum-gain test now aborts only on a false setter result, not a readback mismatch. If writes to both selected services are accepted, they remain in the 15-second test window while synthesis stays disabled. Diagnostics record immediate, once-per-second delayed, and pre-restoration readbacks. UI explicitly calls the physical effect unverified. Timed/manual/lifecycle restoration is unchanged; write-rejection status preserves whether restoration needs retry rather than claiming it succeeded unconditionally. The previous attempt restored too quickly to assess native pointer speed.

## Full-window gain test: no physical effect

Preserved `captures/gain_probe_full_window.json`. Both Bluetooth and USB service property setters returned true for multiplier 1, but every readback from 0 through 14 seconds and immediately before restoration stayed at the original 46603. Restoration calls returned true and readbacks again matched 46603. User observed normal pointer speed during the full interval. Therefore this property-write experiment did not demonstrate native speed reduction or suppression on either transport. Setter acceptance and matching original readbacks must not be presented as proof that a changed multiplier was applied and subsequently restored. No repeat with the same API/property/value is justified by current evidence.

## Single-interface matrix prepared

User chose the Mac-only selective-seizure investigation and rejected VM/external bridge approaches. Added a picker for individual non-keyboard HID interfaces of the selected pads and a 15-second exclusive-open test. Exactly one interface is held per run; other experiments/synthesis stop first. An independent lock-protected counter at live OMS ingress records total/nonempty contact frames per selected numeric touch-device ID, separate from HID report callbacks. Timed/manual/lifecycle release saves exact interface/open/close/contact evidence under `/tmp/GesturePad-interface-<RID>.json`. Physical pointer/scroll/click suppression and cross-device effects require user observation. No automated physical seize was performed. The minimum-gain controls are removed from UI; Test Pointer Sources remains.

## Single-interface matrix results

User reports one interface per pad stopped both contact data and native motion. Saved nine result files under `captures/single-interface/`. In both transports the combined mouse/digitizer interface (usage 0001:0002) is the boundary: Bluetooth RID 4295108009 had only one contact frame; USB RID 4295137189 had five total/four nonempty frames, versus hundreds during other same-pad interface tests. The few frames do not demonstrate sustained delivery and may be queued/in-flight data. Other non-keyboard interfaces seized successfully and preserved contact callbacks when the tested pad was touched. No tested interface separated native motion suppression from OMS contact suppression.

Important new evidence: USB RID 4295137189 received **319 raw input reports / 2552 bytes**, last report ID 2 and length 8, while exclusively open. This contradicts any blanket assertion that raw HID callbacks never work in this environment. These reports were counted, not payload-captured by this test, and may be ordinary relative mouse packets; they do not prove raw multitouch contacts are available. Bluetooth mouse/digitizer and all other interfaces showed zero raw reports. Next useful raw-HID investigation is bounded USB payload capture and descriptor comparison, potentially device multitouch mode negotiation if justified by observed reports and exact model protocol. No VM, external bridge or cursor-correction solution is proposed.

## USB single-interface byte capture prepared

Single-interface button is now Capture one (15s). Each run primes the existing bounded report buffer before opening exactly the chosen interface and exports a standalone original-byte capture on release, alongside the existing contact/open/close evidence. Automatic files use `/tmp/GesturePad-<transport>-HID-<RID>-<timestamp>.json`; no extra save interaction is required. Capture mode is exclusive-single-interface, with synthesis and other control stopped. This reuses the tested copy/bounds/serialization path; no protocol decoding or mode negotiation is introduced. The eight-byte ID 2 packets observed previously are not yet classified as PTP; Windows confirmed ID 5 / 50-byte format is only a comparison reference.

## USB payload capture: relative mouse reports, not contact frames

Preserved `captures/usb_single_interface_payload.json`. The approximately 15.07-second exclusive single-interface recording contains 384 successful eight-byte reports, all report ID 2, zero dropped reports. Payloads arrived from roughly 0.14s through 6.33s; the remainder of the capture contains no reports.

The captured HID descriptor declares ID 2 as a relative mouse report: byte 0 report ID, byte 1 three button bits plus padding, bytes 2/3 signed eight-bit relative X/Y, bytes 4–7 declared constant padding. Captured byte 1 toggles between 0 and 1; relative X/Y change during movement. Bytes 4–6 are always zero; byte 7 varies between 2 and 3 despite its descriptor declaring constant padding, so its actual meaning remains unknown. It must not be labeled finger count/phase without evidence.

Descriptor additionally advertises vendor input IDs 0x3F (16 bytes payload) and 0x44 (1387 bytes payload), but neither was received. No ID 5 / 50-byte Windows-format reports or contact-coordinate records were captured. This establishes USB mouse-report delivery while seized, not raw multitouch delivery. A next investigation could determine the correct model/transport-specific multitouch-mode negotiation before sending any feature report; blind Linux feature-command transplantation is not justified by this payload alone. Current capture sends no mode-changing commands.

## Exact USB multitouch mode variant prepared

Added a default-off checkbox to the current capture for USB 05AC:0324 usage 0001:0002 only. After a 2s capture baseline, the active main-runloop timer sends one feature report ID02 with payload0201, records relative time/result/pre-command report count, and keeps capturing regardless of result until15s. Eligibility tests exclude Bluetooth/wrong vendor/wrong model/other usages. The Linux source explicitly selects this command for USB-C0324 and parses ID2 multitouch input as12+9N bytes. No reverse mode command is assumed; UI/docs distinguish release of ownership from mode restoration and provide reconnect guidance. No feature command has been sent by automated verification.

## USB feature 02 01 request: no contact reports observed

Preserved `captures/usb_multitouch_mode_request.json`. Exclusive open succeeded; at +2.071s, after 53 baseline reports, the feature request ID02 bytes0201 returned success. The full ~15.07s recording contains 434 successful eight-byte ID2 reports /3472 bytes, zero drops, and no other report ID/length. Packets arrived ~1.47s to8.66s. Thus no12+9N touch packets, ID3F/44 reports or Windows-format contact packets were delivered after the request. Exclusive close succeeded. A successful feature call did not demonstrate a mode transition or raw contact delivery. This result cannot distinguish ignored command, alternate transport/interface routing, or macOS descriptor/report filtering; do not claim mode switched based on return code.

## 2026-10-18: underlying USB access gate

Added `Tools/USBTransportProbe/main.c`, a standalone read-only access probe,
independent of the application. Built with clang and ran against connected
05AC:0324 USB interface 1 (registry 4295137178). Plugin creation and interface
query succeeded. Ordinary USBInterfaceOpen returned 0xe00002c5
(kIOReturnExclusiveAccess, confirmed in the installed SDK). No USB control
request was sent; no seizure, driver detachment, reset or report write occurred.
The ordinary direct-interface path is unavailable while the existing driver owns
it. This is not proof about feature-report forwarding and does not warrant
another identical touch recording. Physical packet tracing or a separately
validated access route remains necessary before a direct USB mode test.

### Follow-up: parent-device access succeeds

Continued beyond the interface access failure. Ordinary USBDeviceOpen on the
parent IOUSBHostDevice succeeded while Apple's interface driver remained attached.
A standard GET_DESCRIPTOR for interface 1's HID report descriptor succeeded,
returning 110 bytes matching the HID-visible descriptor. USBDeviceClose succeeded.
This invalidates the broader inference above that direct USB access is unavailable;
only the ordinary interface open was denied.

Prepared standalone opt-in `Tools/USBTransportProbe/run-test.sh`, which sends one
exact 0201 feature command via USB DeviceRequestTO, interface 1, after a countdown,
while the existing app captures HID input. No feature command was sent by the
agent during preparation. This variant bypasses IOHIDDeviceSetReport and records
wall-clock command timing/result; it does not capture physical interrupt packets.
Build passed with Wall/Wextra and read-only path executed successfully. Next step
requires the user's live app capture and gestures; no driver detachment is needed.

### Direct USB command completed, but no post-command reports captured

User ran the direct transport test. USB DeviceRequestTO returned success and
wLenDone=2 for SET_REPORT 21/09/0302, interface 1, data 0201, at Unix
1792300079.272319. The app capture began at ISO timestamp 2026-10-18T05:07:44Z
(whole-second precision), lasted 15.070939 s, and recorded 603 reports/4824 bytes,
all successful ID02 length8, no drops. Last report was +13.533801 s; even allowing
for the truncated start timestamp, that report preceded the USB command. There
are no captured post-command reports to evaluate. Do not interpret this recording
as proof that direct USB SET_REPORT failed to change the stream.

Preserved as captures/usb_direct_command_capture.json and
captures/usb_direct_command_result.log. Prepared capture-start marker handshake:
updated app writes serial/RID/precise wall clock/uptime after exclusive open;
release removes marker. Script waits for a new, fresh, matching marker; helper
rechecks it after its two-second baseline and before writing. Command log now
includes mach_absolute_time-derived uptime for exact report alignment. No new
hardware command sent during preparation.

### Synchronized direct USB test: unchanged HID stream confirmed

Capture usb_direct_synchronized_capture.json began at uptime452500.034425734.
Direct USB SET_REPORT completed success, two bytes, sent at uptime452502.450059805
(+2.415634071s). Of 870 successful ID02/length8 reports, 102 preceded the command
and 768 followed it; last packet +13.276599209s. No drops, longer reports, or other
IDs. This establishes that direct delivery of this exact command does not expose
multitouch through the captured HID callbacks in this setup. It does not establish
physical interrupt packet contents or rule out driver translation/mode override.

Read-only physical configuration inspection succeeded through parent-device open:
interface0 endpoint81 max16; interface1 endpoint83 max64; interface2 endpoint84
max16 and OUT04 max64; interface3 endpoint85 max64. All interrupt endpoints,
configuration1, alternate0. Therefore endpoint1's capacity does not itself impose
an eight-byte ceiling. No interface detachment or extra feature command attempted.

Checked kernel tracing: `ktrace trace -T 1 -f C05` refused with
"ktrace must be run as root when tracing the current system". Prepared bounded
Tools/USBTransportProbe/run-kernel-trace.sh for human-authenticated sudo execution
of Apple's ktrace only, 20s, IOKit USB/HID subclasses052d/0523 from installed SDK.
This is a trace-availability/evidence check, not a claim that payloads or adequate
release-build tracepoints will be available. No SIP changes requested. User touch
input and administrator authentication are now required for this next check.

## Kernel trace baseline: candidate contact-sized USB completions

Normal ownership trace /tmp/GesturePad-usb-hid-kernel-1792300491.ndjson contains
58,042 parsed events. USB event052d0000, key140f8300, selector10: 471 final values21
and 500 values30. 971 HID_HandleReport events identify registry4295137189. Live
IORegistry confirms physical right pad USB address15 (0x0f), endpoint83 on
interface1; bus/key association is consistent with140f8300. Other endpoint keys
show eight-byte values for ordinary mouse routes. The 21/30 values match Linux
trackpad2 USB layout12+9N, suggesting contact-sized transfers reach the USB driver
under normal ownership. The modern private tracepoint's field layout has not been
independently sourced, so these are candidate completion lengths, not recovered
packet payloads or proven decoded contacts. Preserve this distinction.

Saved baseline and summary in captures/usb_kernel_normal_ownership.ndjson and
usb_kernel_normal_ownership_summary.json. Prepared run-test.sh --kernel-trace:
authenticate sudo first, wait for the app's fresh eligible capture marker, start
18s USB/HID kernel trace, then run the synchronized one-shot direct USB0201 probe.
This should compare seized baseline, post-command, and post-release data without
adding unrelated controls. App need not change/rebuild. Script syntax checked;
this live variant requires the user's capture and gestures. No additional mode
command or seizure was activated during preparation.

## Combined seized USB/HID trace

Synchronized capture started uptime452923.689271788; direct USB command success,
2 bytes, at452926.509383909 (+2.820112121s). App captured916 ID02/8-byte reports.
Candidate endpoint83 USB completion values remained21/30 throughout:
before command (already seized)86x21 +62x30; after command while seized301x21
+467x30; after release76x30. Thus these candidate contact-sized transfers survive
HID seizure; no evidence for an eight-byte transport switch. Source definition
of the private USB tracepoint remains unconfirmed; packet payload not recovered.
Saved usb_kernel_seized_ownership.ndjson, usb_kernel_seized_command.log and
usb_kernel_seized_hid_capture.json. This is evidence for investigating report
handling below the Apple HID presentation, not proof that raw contacts are usable.

Prepared explicit standalone15s USBInterfaceOpenSeize capture for exactly
05AC:0324, tested right serialJ84HMA00H0B0000501, interface1/interruptIN endpoint83
maxPacket64. This is lower than the prior IOHIDDeviceOpen seizure. SDK documents
that it asks the existing client to close and returns ExclusiveAccess if refused.
No detach/terminate/reset or mode command is used. If accepted, async reads copy
bounded packets (2048x4096-byte capacity); logging happens after abort/close.
SIGINT/SIGTERM request early release;15s monotonic deadline, AbortPipe, close.
Tool compiled with Wall/Wextra/Werror; usage-only path checked without activating
hardware. New live test requires user run-interface-capture.sh with app released.

## USB-interface seizure refused; descriptor-sized callback explanation

User's direct interface capture stopped immediately with
USBInterfaceOpenSeize=0xe00002c5 (ExclusiveAccess). No packet read was queued and
no mode command was sent. Preserved captures/usb_interface_seize_refused.log.
Retrying this unchanged open is not a new experiment.

Continued static investigation of installed BootKernelExtensions.kc (read-only
extraction into /tmp, no executable/kernel changes). AppleUSBTopCaseHIDDriver8420.1
only overrides handleStart; its superclass is IOUSBHostHIDDevice. Its static
wrapper has no own report-processing override. Open-source IOHIDElementContainer
creates interrupt-report handler elements using descriptor report->inputBitCount.
IOHIDElementPrivate::processReport copies _reportBits*_reportCount into the queued
element value. Current device InputReportElements declares ID02 ReportSize64bits.
This supplies a concrete explanation for an eight-byte userspace report even if
the underlying transfer is longer. Increasing our callback buffer does not change
this descriptor-sized kernel element. Installed build/source correspondence is
not fully established; do not claim recovered contacts from this analysis alone.
Sources:
https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDElementContainer.cpp
https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDElementPrivate.cpp

Also investigated pre-copy hid_trace hook in IOHIDDevice. It is an empty function
intended for function-boundary tracing, NOT a registered static hid DTrace provider.
Its invocation is gated by boot arg hid_dtrace_debug, read once by
IOHIDFamilyPrivate.h. A simple sudo static-provider listing is therefore not a
prepared capture solution. SIP is enabled. No boot args or security settings were
changed. Source:
https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDFamilyPrivate.h

Read-only direct USB GET_REPORT(input02, interface1, max64) succeeded with8 bytes
0200000000000000 while idle. This is a control-report snapshot, not the interrupt
contact stream. Parent close succeeded. The probe's default diagnostic now logs
this read. Compiled with Wall/Wextra/Werror. No extra live touch test is warranted
for these established eight-byte paths. Remaining raw interrupt paths require
replacing/matching the owning driver or protected kernel instrumentation; neither
is accomplished by root ktrace metadata alone.

### User requests testing the descriptor-truncation theory

Prepared check-kernel-hooks.sh for root-authenticated probe inventory only, matching
hid_trace and potential direct pre-copy IOHIDDevice/USB completion entry points.
Current boot args empty; SIP enabled; unprivileged DTrace cannot initialize. No
security/boot changes made. Script syntax checked. Need human authentication for
this read-only inventory before deciding whether an instrumentation capture can
work under the current security configuration. Presence of hid_trace alone is
insufficient because its call is boot-argument gated.

### Root inventory confirms SIP restriction

User supplied check-kernel-hooks output (log1792301203): all three FBT patterns
explicitly rejected with "System Integrity Protection is on", including
hid_trace, IOHIDDevice handleReportWithTime and USB completion. No probes listed.
Exit0 is not evidence of access: -Z permits unmatched probes. Therefore the
current configuration cannot run the proposed FBT capture even with sudo.
Continuing this specific diagnostic route needs the user's explicit decision
about temporary security configuration changes/reboot. No such changes authorized
or performed; preserve distinction from ordinary root ktrace metadata access.

## SIP-off hook inventory and prepared original-buffer capture

User explicitly disabled SIP in Recovery and returned with available FBT entry
probes for hid_trace, IOHIDDevice::handleReportWithTime and USB completion.
Boot args still empty. Prepared run-original-report-capture.sh without boot-arg
changes: follow selected-device handleReportWithTime input calls and capture
IOMemoryDescriptor::getLength / IOBufferMemoryDescriptor::getBytesNoCopy returns.
Exact current right USB physical driver registry ID resolves dynamically (now
4294968429); filter class to exclude IOHIDInterface descendants with copied keys.
Installed Intel24G517 disassembly verifies registry ID offsets10h/+8 and actual
virtual getLength/getBytesNoCopy calls before report processing. Record64-byte
buffer dump plus actual length<=64 from known1388-byte-capacity USB buffer.
No kernel writes. Bounded15s/2048 reports, compile check before activation, build
and architecture guards. Shell syntax/identity resolution verified; DTrace
compile and live hooks require human-authenticated run. No live test initiated.

### Original-buffer probe compile fix

User's compile check found no FBT getBytesNoCopy entry probe despite a symbol in
the installed kernel. Reworked capture to depend only on available USB completion
entry/return and HID handleReportWithTime entry. Exact Intel24G517 disassembly
verified IOMemoryDescriptor length at50h and IOBufferMemoryDescriptor bytes pointer:
(flags@20h & f0h)==20h -> pointer@b8h, otherwise first range pointer via60h.
Filter USB-success call path and selected physical RID before descriptor reads;
only dump nonzero lengths<=64 and kernel-space buffers. Retain64-byte bound with
actual payload length metadata. No kernel writes, mode commands or new boot args.
Shell syntax checked; compile check remains user-authenticated before activation.

## Original pre-copy report bytes recovered

Successful normal-ownership FBT capture1792304085:442 reports,188 length21 and254
length30. Every payload has ID02 and fits Linux USB Trackpad2 prefix12 +9N.
Decoded contacts using hid-magicmouse.c signed13-bit coordinate packing, tracking
IDs, pressure, dimensions, orientation and state. Pressure range0..32; X-1220..823,
Y-2019..1630;673 state80h down contacts,23 other lifecycle states. Tracking IDs are
identifiers, not anatomical finger labels. Contact payloads are present beyond
byte8 before descriptor-sized user queue processing. This validates the raw-data
lead under normal ownership; usable access with SIP enabled remains unresolved.

Preserved raw log and decoded/truncated actual-length packets as
captures/usb_original_unseized.log and usb_original_unseized.json. Added offline
decode-original-report.py (stdlib, works with systemPython3.9), validated against
all442 real report blocks/end-count. It excludes bytes beyond actual reportlength.
First DTrace timestamp label uptime_ns has not been aligned to system uptime;
new template calls it trace_timestamp_ns and includes walltimestamp unix_ns for
comparison against app capture start/end timestamps.

Prepared --seized variant:30s trace with same exact-device filtering, no firmware
commands, while user starts existing app15s single-interface seizure (mode checkbox
off) after READY. User moves one/two fingers during/after seizure. This is the next
live check of raw pre-copy contacts while OMS/native events are blocked. No new
seizure or trace activated during preparation; no app rebuild required.

## Definitive paired capture: full contacts survive HID seizure

Original FBT trace1792304367 logged1146 valid ID02 packets. App seizure window
Unix1792304374.20816..1792304389.232792 contains668 original packets and exactly668
app callbacks (no app drops). All668 app payloads match the first8 bytes of their
corresponding original packet, in order. Original seized packets:265 length21
(one contact),341 length30 (two),2 length39 (three),60 length48 (four). Decoded
pressure range0..59.478 more original packets arrived after release.

This directly establishes complete packets reach IOHIDDevice during the exclusive
session and userspace receives a truncated8-byte prefix, consistent with the
64-bit report-handler element from the descriptor. Contact data itself is not lost
at the USB transport during seizure. Decoding is Linux Trackpad2 layout, not yet
validated anatomical classification. Capture is kernel tracing with SIP disabled;
this does NOT supply a production SIP-enabled acquisition method.

Preserved usb_original_seized.log, usb_original_seized_app.json,
usb_original_seized.json (actual-length payloads + decoded contacts and paired
summary). No additional touch test is needed to establish this mechanism. No
runtime interpreter or SIP-on driver has been installed by these experiments.

## SIP-enabled DriverKit prototype built; provisioning dependency

Added independent DriverKitProbe receiver + activation/result host. Exact USB
05AC:0324/serial J84HMA00H0B0000501/usage0001:0002 match is enforced twice.
Driver uses IOHIDInterface ordinary Open, preseeded shared report pool, actual
reportLength, one bounded full-packet sample and counts.15s timer closes; Stop and
Start-error cleanup cancel actions and timer. It does not reuse IOHIDDevice seize,
which would block this interface delivery. Native-output control is not yet solved.
Host uses explicit SystemExtensions activate/deactivate requests and reads registry
summary/first packet; no activation on launch. Activation may displace Apple event
handling; Close does not prove native driver rematching. Reconnect/deactivation
may be needed at the eventual live test.

Build validated: IIG generation, DriverKit C++ compile/link (Intel, platform10,
min20.0, SDK25.2), macOS host build (min13), packaging/plist lint, narrow hardware
matching checks, expected DriverKit library load paths. No runtime activation or
packet test. Existing GesturePad app/sibling projects not altered for prototype.

Found two local valid signing identities, team N9XQZJR4EP, but zero provisioning
profiles in standard/local folders. sign.py preflight correctly exits2 before
signing; output remains unsigned. Real dependency is Apple-issued profiles for
ink.ranna.glasstokey.gesturepad.rawhidprobe.driver (driverkit + transport.hid) and
ink.ranna.glasstokey.gesturepad.rawhidprobe (system-extension.install), same team
and authorized installed certificate. No credentials requested/read, driver
installed/activated, or SIP settings changed. User must manage Apple account
capabilities/provisioning before SIP-on deployment can be attempted. Exact steps,
validation and signing commands are in DriverKitProbe/README.md.

## Apple development provisioning completed, SIP-on live test pending

With explicit user confirmation, registered driver AppID with DriverKit development
and HID Transport development capabilities and host AppID with System Extension.
User completed annual device review retaining existing devices, then authorized
sending this iMac UUID to Apple. Registered nap iMac GesturePad Development.
Generated driver/host development profiles with only this iMac selected, downloaded
through the signed-in Apple portal and saved in ignored DriverKitProbe/profiles.
Decoded Apple profiles confirm required Boolean entitlements, matching team/appIDs,
thisMac included, and a common authorized locally installed certificate.
sign.py signed driver then host and strict signature verification passed for both.
Driver profile expires2027-03-01; host2027-10-18. No private key exported, new
certificate created, extension installed/activated, or SIP change performed.
Next step is explicit system-extension activation/hardware test; still no runtime
proof of DriverKit matching/full-report access or native-output suppression.

### First activation rejected before loading: required usage metadata

sysextd logs explicitly rejected the initial driver: category property check
requires OSBundleUsageDescription. No extension remained installed/activated;
this was packaging failure, not matching/report access. Added required explanatory
usage string in generated dext Info.plist. Host now scrolls and emits explicit
NSError domain/code/details to unified logs. Rebuilt host/driver, re-signed with
authorized profiles, verified both signatures and required metadata, reinstalled
host under /Applications and reopened without automatic activation. User must
retry explicit activation/approval before any live packet result is possible.

### SIP-on driver loaded/opened, zero reports

After user approved extension, systemextensionsctl reports activated enabled.
Kernel logs show matching right USB IOHIDInterface, Start success, ordinary parent
HID open, and15s later close0success. Receiver reports0, bytes0, firstFullLength0,
no mapping/malformed errors. Therefore mouse freeze is NOT successful raw-report
acquisition. The default-match receiver displaced the native Apple consumer; its
15s Close does not unload/rematch Apple's driver. Additional Activate presses do
not rearm the already matched receiver. Host deactivation requests later returned
OSSystemExtensionErrorDomain13; cannot assume native restoration. User should
disable the probe in Driver Extensions and reconnect USB before further testing.
Read-only full registry snapshot saved /tmp/gesturepad-dext-current.plist. No new
activation, hardware mode command, or runtime security changes performed.

### Receiver v0.2 prepared: initialization hypothesis

User disabled original receiver and restored native input. Registry DebugState
showed0 ReportAvailableCalls, so first failure occurred before action delivery,
not decoding/map/callback allocation. Receiver replaced native Apple handler;
loss of its report-mode initialization is a hypothesis, not established cause.
Prepared v0.2/build2: first timer at2s sends exact previously tested USB feature
ID02 bytes0201 via IOHIDInterface::SetReport. Records ModeAttempted/ModeResult,
baseline count in log, all callback invocations. Second timer closes at fixed15s
deadline. No guessed commands/retries/reset. DriverKit path still may return an
error; packet recording continues until deadline regardless. Rebuilt, signed and
verified; installed updated host, restarted host only. System extension remains
old build1 activated-disabled until user explicitly requests replacement/approval.
Next live test requires Activate in v2 host and enabling v2 in Driver Extensions,
then gestures. Do not merely re-enable old build1. Matching Apple's native handler
replacement/recovery is still unresolved; disable and reconnect after test.

### Teardown crash investigation and build3 delivery diagnostic

Both crash reports021446/021824 have identical DriverKit asynchronous dispatch
null-pointer faults on Default queue, during deactivation. Source passed nullptr
to OSAction/IOTimerDispatchSource Cancel completion, whose SDK declarations do not
mark completion optional (unlike SetEnableWithCompletion). Replaced all such
cancellation handlers with empty valid blocks. This is a code-level candidate
fix, not runtime-confirmed crash resolution.

Recovered host output confirms build2 actually ran: ModeAttempted1 ModeResult0
Callbacks0. Thus the mode command succeeded through DriverKit but did not unlock
report delivery. Do not describe the failed result solely as stale build1.

Build3 preserves one-shot mode test but adds ProbeBuild3 to registry/host and
visible host version0.3. Built, signed/strict-verified, installed and restarted
host only. Existing extension state: build1 pending reboot removal, build2 waiting
user approval. No new activation requested automatically. Prepared trace-delivery.sh:
45s USB/HID ktrace (sudo), pre/post full registry, extension states and driver logs,
then offline summary comparing exact ancestor provider HID_HandleReport events
against interface DebugState and receiver counters. Script sends no device command;
receiver retains exact0201 at2s and15sclose. User authentication + activation
replacement/approval + touch input is next dependency. Deactivation/recovery should
be checked only after snapshots are saved; disabling already restored nativeinput
without reconnect per user, so reconnect is fallback only.

### Build3 attempt captured approval-wait, not a live driver session

Evidence1792308243 parses137908 metadata events, no receiver in final registry.
Extension remains0.3/3 activated waiting for user; host repeatedly reports pending
request, no build3 Start log. No report-delivery or crash-fix conclusion follows.
The missing step is enabling/approving the pending extension in Driver Extensions,
not pressing Activate again. Increased trace window90s to allow Settings approval,
and made Settings vs host distinction explicit. Script changes only metadata
capture duration/instructions; no driver activation performed by agent.

### Build 3 received full USB contact reports with SIP enabled

2026-10-18 02:31 CDT host Read results identifies ProbeBuild 3, Callbacks/Reports
369, Bytes 9630, Reports8 0, Reports21 160, Reports30 209, Reports39/48 0.
ModeAttempted 1, ModeResult 0, Malformed 0, MappingErrors 0, CloseResult 0.
FirstFullLength 21; first full report:
02000000000000013180ab80ce1b442089881208aa.
This proves actual-length DriverKit delivery of one/two-contact USB packets,
without the earlier userspace eight-byte truncation. It does not yet prove live
OMS replacement, Bluetooth support, or continuous control/release behavior.
At 02:32:50 user-authorized deactivation uninstalled v0.3 successfully. No newer
receiver crash report than 02:18:24 was present when checked at 02:33. The old
v0.1 remains pending reboot removal. Missing Settings row after uninstall is
consistent with no currently installed v0.3, not missing pending approval.
Preserved host/state logs in ignored DriverKitProbe/evidence/build3-success/.

### Build 4 Bluetooth baseline succeeded without mode writes

2026-10-18 02:39:02–02:39:17 CDT, exact left Bluetooth serial
D0:C0:50:D4:75:6C, vendor76/product804 usage1:2, IOHIDInterface0x100000a49.
Kernel confirms successful Start/open and timed Close. User observed native
mouse control being taken. Host Read results at02:39:22 identifies ProbeBuild4:
884 callbacks/reports,14588 bytes;540 length13 and344 length22 packets,
zero malformed or mapping errors, CloseResult0, ModeAttempted0.
First full report13 bytes:319c22810582f42332550e0a6b (Bluetooth ID31,
4-byte prefix + one9-byte contact). No USB0201 or Bluetooth feature command sent.
User subsequently deactivated successfully at02:39:41; registry no longer holds
receiver. Evidence preserved in ignored evidence/build4-bluetooth-success/.
Together USB/build3 and Bluetooth/build4 prove full packet access on both
transports with SIP enabled. Continuous delivery to GesturePad, output synthesis,
reconnection and robust native-handler restoration remain integration work.

### v0.5 integrated GesturePad test prepared (not hardware-verified)

Built signed dual-pad DriverKit receiver/helper and GesturePad integration.
Current helper installed under /Applications; fresh GesturePad Debug launched
with --open-config. No extension activation performed by agent. Normal app build,
strict signatures and58 package tests passed, including transport decode, signed
coordinates, stream wire validation/dedup/gaps, and decoded two-finger movement.
Only unrelated AppIntents metadata-extraction notice in app build.
See ../DriverKitProbe/INTEGRATION_TEST.md for exact steps and remaining limits.
Both tested serials must be selected in their tested transports. Ring snapshots
feed the runtime render/capture path, with duplicate OMS gate, stale/gap reset,
replay suppression and existing pointer interpreter. Hard30s driver deadlines plus
independent signed helper removal watchdog; restoration remains a live-test question.
Session diagnostics save to /tmp/GesturePad-driverkit-session-<UUID>.json.
Continuous ownership and optimized user-client IPC are deliberately pending this
first integrated contact/suppression/pointer/release hardware result.


### v0.6 continuous takeover and GUI cleanup (explicit user request)

Removed the legacy control checkbox/buttons, duplicate synthetic pointer toggle,
OS drag-setting controls, single-interface test and pointer-source observer from
the visible GUI. Kept diagnostic backend/capture schemas. The sole control group
now contains DriverKit Takeover, Release Trackpads, one synthetic pointer toggle
and status. Removed driver30s, helper31s/120s session and app120s session limits.
Owner-process monitoring and lifecycle/device-loss removal remain. Build/profile
identity incremented to0.6/6 so stale bounded drivers cannot appear current.
Continuous operation and restoration still need a live hardware check.


### v0.7 packages driver management inside GesturePad

User rejected the visible standalone probe host. Removed its entire diagnostic UI
and independent controls, made it an LSUIElement/accessory background service,
and embedded it with Xcode Copy Files + CodeSignOnCopy at
GesturePad.app/Contents/Helpers/GesturePadDriverService.app. Retained its existing
provisioned bundle ID and independent watchdog. GesturePad launches it without
activation/focus; no managed arguments means immediate exit without driver activation.
Installer now installs a single /Applications/GesturePad.app and archives/removes
the obsolete standalone probe application. Deep strict signature validation and
Xcode embedded-binary validation passed. Unmanaged service smoke launch exited,
with no driver activated; nested-package activation still needs the live test.


### DriverKit telemetry/visualizer adapter correction

Compared BEFORE_takeover.atpcap and AFTER_takeover.atpcap without modifying them.
Detailed numbers and protocol evidence: DRIVERKIT_TELEMETRY_COMPARISON.md.
The huge ellipse was a units error (median major7.76 vs85), not huge physical
contacts. Recovered dedicated finger bits, full3-bit states and orientation;
added provenance/raw9-byte record preservation and explicitly derived velocity.
Hand/density remain unavailable, raw pressure/size are not Apple-calibrated values.
Build and61 tests pass. Live visual verification remains pending.


### Native Compact V7 telemetry reconstruction and parity oracle

The earlier local native-parser archive provided the actual scalar conversions and
filler. Added a pure Swift reconstruction verified against the current mapped
framework:256 values each for4scalar fields,576 density cases,256 full contacts
on each transport wrapper,96 native two-frame velocity/state cases. All67 tests
and app build pass. Source descriptor checked before takeover. Native pressure,
total,density,hand1,code7→12, clipping, calibration and quantization recovered.
New metadata retains full report/contact bytes and sensor ticks. Read-only capture
validator prepared; synthetic256-contact v5 recording compares with zero errors.
See COMPACT_V7_TELEMETRY_PARITY.md and Tools/TelemetryParity/README.md.
No live takeover/driver activation performed. A fresh hardware capture remains
necessary before claiming complete live telemetry parity; earlier AFTER capture
had already discarded the needed raw bytes.

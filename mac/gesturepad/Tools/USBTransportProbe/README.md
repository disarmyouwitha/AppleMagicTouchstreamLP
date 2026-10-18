# Physical USB transport probe

Standalone diagnostic, independent of the app. Defaults to read-only. It never
seizes/detaches a driver, resets the device, changes configuration, or reads an
interrupt pipe. The opt-in variant sends exactly one Linux-documented multitouch
feature command directly through USB endpoint zero, bypassing IOHIDDeviceSetReport.

## Validated access

On 2026-10-18, ordinary USB interface 1 open returned 0xe00002c5
(kIOReturnExclusiveAccess), but **ordinary parent USB device open succeeded**.
GET_DESCRIPTOR (81 06, value 2200, interface 1) returned the physical 110-byte HID
report descriptor. Parent close succeeded. No mode command was sent during this
preparation. This corrects the earlier conclusion that direct USB access was
unavailable: interface ownership and parent-device access differ.

## Live test

Run `./mac/gesturepad/Tools/USBTransportProbe/run-test.sh` from the repository root.
The script compiles the probe and waits up to two minutes for a **new** eligible
capture in the updated GesturePad app. Select the right USB pad, usage 0001:0002,
with the old HID mode-request checkbox **off**, then click Capture one (15s).
Keep moving one and two fingers throughout. The direct command runs approximately
two seconds after capture starts, with no Terminal countdown to coordinate.

The app writes a diagnostic start marker containing identity, precise wall clock
and uptime after successful seizure, and removes it on release. The script rejects
stale or wrong-pad markers. The helper rechecks the same marker immediately before
sending; a released/replaced capture cancels the command. Both clock forms are
logged for alignment with report timestamps. App capture/release behavior is
otherwise unchanged. Launch the newly built app before this test.

The write variant requires VID 05AC, PID 0324, exact tested right-pad serial
J84HMA00H0B0000501 and a successful mouse report-descriptor read. It issues one
class/interface SET_REPORT: bmRequestType=21, bRequest=09, wValue=0302,
wIndex=1, wLength=2, data=0201, with one-second request timeouts. No retry or
reverse command is sent. Closing restores parent USB ownership, not a proven
firmware mode; reconnect USB if native input does not recover after app release.

Success from USB control completion is stronger evidence than HID API success,
but does not prove contact packets were produced or accepted by the firmware.
Compare capture lengths before/after the recorded command timestamp. This probe
is not a passive physical packet analyzer.

Read-only build/run:

```sh
clang -Wall -Wextra -Wno-deprecated-declarations mac/gesturepad/Tools/USBTransportProbe/main.c -framework IOKit -framework CoreFoundation -o /tmp/GesturePad-USBTransportProbe
/tmp/GesturePad-USBTransportProbe
```

## Synchronized result and kernel trace gate

The synchronized direct command succeeded at +2.416s. All 870 captured reports
were ID02/8 bytes: 102 before and 768 after. This path did not expose contacts.
Physical configuration confirms interface1 endpoint83 permits 64-byte interrupt
packets. Driver translation/override remains unproven.

Next run `./mac/gesturepad/Tools/USBTransportProbe/run-kernel-trace.sh` in Terminal.
It invokes Apple's ktrace with sudo for 20 seconds, limited to USB/HID IOKit
subclasses. Normal trackpad ownership should remain restored; move one and two
fingers on the right USB pad during the trace. Authentication is required because
ktrace refuses current-system tracing as this user. The command writes NDJSON to
/tmp/GesturePad-usb-hid-kernel-*.ndjson. This verifies whether useful tracepoints
exist; kernel tracing is not guaranteed to include packet payloads. No SIP changes,
driver detachments or mode writes are part of this check.

The normal-ownership trace produced a lead: 971 candidate endpoint83 completions,
471 with value21 and 500 with value30, matching Linux's12+9N contact report sizes;
971 HID_HandleReport events identify this pad. Private tracepoint field meanings
remain provisional; no report bytes were decoded from the trace.

For the next combined test, run `run-test.sh --kernel-trace`. Authenticate sudo
first, then start the same right-pad app capture (HID mode checkbox off) and move
one/two fingers for15s. This starts an18s kernel trace on the capture-start marker
and sends the exact direct USB command after its two-second baseline. Outputs:
/tmp/GesturePad-usb-hid-seized-*.ndjson, direct USB result log, and the app's raw HID
capture. It allows comparisons before/after command and after app release.

## Direct USB interface capture (next layer)

Combined trace retained candidate21/30-byte completions while HID seizure yielded
only8-byte app reports. Next use `run-interface-capture.sh` with app control/tests
released. No app rebuild or sudo required. This explicit test tries
USBInterfaceOpenSeize on only the exact right pad/interface1. If Apple refuses,
it exits immediately without detaching/terminating any driver. If accepted, move
one/two fingers for15s; async reads of endpoint83 retain original packet bytes.
Ctrl-C releases early. No mode writes, USB reset/configuration changes, or other
interfaces are used. Data is bounded and written after abort/close to
/tmp/GesturePad-usb-interface-*.log. Reconnect USB if normal input does not recover.

Observed direct-interface result: OpenSeize returned0xe00002c5 immediately; no
packet capture occurred. Current open-source HID implementation sizes the queued
report element from descriptor inputBitCount; the pad declares ID02 as64bits.
That can explain why a4096-byte callback buffer still returns8 bytes. The default
probe also reads input02 via USB GET_REPORT; idle result was8 bytes. This does not
access the interrupt stream. Protected FBT instrumentation and driver replacement
are outside the prepared probes; no security/boot configuration has been changed.

## Kernel instrumentation availability check

`check-kernel-hooks.sh` uses sudo only to list matching DTrace function probes
(hid_trace, IOHIDDevice handleReportWithTime, USB interruptReadComplete). It does
not enable probes, capture input or alter security/boot settings. No touches are
needed. It saves /tmp/GesturePad-kernel-hooks-*.log. Current unprivileged checks
show SIP enabled, no boot arguments, and insufficient DTrace privileges. Root
inventory is required to distinguish an accessible pre-copy entry point from a
security/build restriction. hid_trace itself is boot-argument gated; its presence
alone would not mean the hook is called. This script is not a raw packet capture.

## Original-report FBT capture (SIP-off diagnostic)

After the user explicitly disabled SIP and verified hooks, prepared
run-original-report-capture.sh. It resolves the exact right USB pad's physical
AppleUSBTopCaseHIDDriver registry ID dynamically, restricted to Intel24G517.
Registry entry layout is verified from this installed kernel's disassembly:
IORegistryEntry+10h points to reserved storage, whose+8 holds the registry ID.
The probe tracks descriptor getLength/getBytesNoCopy inside selected input
handleReportWithTime calls. It reads at most64 bytes from the known1388-byte USB
report buffer, logs actual length (only that many bytes are report payload), and
stops at15s/2048 reports. No boot arguments or hid_trace enablement is needed.

Keep app trackpad control released for the initial capture. Run the script,
authenticate, wait for READY, then move one/two fingers on the right USB pad.
It first compile-checks the D program; a missing/inaccessible probe stops the
script. DTrace compilation/live buffer access still need validation on the actual
system. No live tracing was activated during preparation. Output is
/tmp/GesturePad-original-report-*.log. Re-enable SIP after diagnostics finish.

Compile correction: this kernel does not expose getBytesNoCopy to FBT, despite
its binary symbol. Current template uses only the available USB completion and
HID entry hooks, reading the exact installed build's verified length/buffer fields.
Those are build-specific and remain guarded to Intel24G517. Only successful USB
callbacks for the resolved physical right-pad RID can emit bounded raw bytes.

### Full contact reports confirmed

The first successful normal-ownership original-buffer capture contains442 packets:
188 single-contact21-byte packets and254 two-contact30-byte packets. The offline
`decode-original-report.py input.log output.json` validates/decodes all442 using
Linux's USB Trackpad2 format, truncating dumps at the actual report length. It
extracts tracking IDs (not finger labels), signed coordinates, pressure and state.

Next run `run-original-report-capture.sh --seized`. Prepare the app's right USB
0001:0002 Capture one (15s), old mode checkbox OFF. After READY, start that app
capture and move one/two fingers throughout seizure and after release. The raw
trace lasts30s (bounded2048 reports) to cover the app test. This remains a SIP-off
diagnostic; it does not establish SIP-on production access. No firmware writes.

Seized result confirmed:668 full original packets during the app's15s exclusive
window; every app callback matches exactly the first8 bytes of the corresponding
original packet. Contact records continue (1/2/3/4 records), with pressure and
coordinates.478 originals followed release. Evidence is preserved in
RewriteValidation/captures/usb_original_seized*. This validates contact survival
and callback truncation, not a production SIP-on transport implementation.

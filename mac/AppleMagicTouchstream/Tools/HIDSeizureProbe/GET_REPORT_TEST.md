# Explicit Bluetooth input-report request experiment

Prepared 2026-10-19. This is a feasibility test, not an established receive path.
The custom DriverKit code and production app/release are unchanged.

## Why this differs from the earlier tests

The streamed input callback receives descriptor-sized report elements. Seizure
stopped both its callbacks and native contacts. A second Bluetooth channel failed,
and reconnect notifications did not expose the native HID channels.

Apple's IOHIDFamily implementation has a separate GET_REPORT path: the app supplies
an output buffer, the user client forwards the request to `IOHIDDevice::getReport`,
and an asynchronous completion returns the reported size. The inspected code does
not first require a matching descriptor input-report element. This makes an
explicit input report 0x31 request a distinct question from repeating the streaming
callback with a different buffer or scheduler.

Linux registers report 0x31 for these Bluetooth pads and decodes it as 4 bytes plus
9 bytes/contact. Its implementation also requests input battery report 0x90 on
some supported models. That is evidence that input-report requests exist on this
protocol; it does **not** establish that contact report 0x31 is requestable, current,
or available during seizure on macOS. Apple's SDK explicitly recommends the
streaming callback for input reports and describes GET_REPORT as relevant to
output/feature reports. We are deliberately testing behavior beyond that guidance.

Static inspection of this host's `bluetoothd` found native HID queue/GET_REPORT
code and the TrackpadInputDevice creation path, but no verified client ownership
handoff. Private entitlement names on that daemon are not evidence that an app
can use them, nor proof of a specific check on any untested method. No private
privilege is added, no daemon is patched/injected, and no service policy is changed.

## One hardware command

Release DriverKit takeover and quit the trackpad apps. Keep an independent mouse
and keyboard available. Keep the right pad **ON and connected**. From repo root:

```sh
sudo ./mac/AppleMagicTouchstream/Tools/HIDSeizureProbe/run-get-report-test.sh D0:C0:50:D5:69:55
```

When `BASELINE` appears, move several fingers on the right pad and keep moving
through the test. There is a three-second lead-in. The tool makes two requests
with ordinary open. If either fails or lacks the known framing, it stops without
seizing the pad. If both are framed, it closes ordinary access, opens exclusive
access, makes four requests about a second apart, then closes to release.

Send the entire output and state whether native movement stopped during `SEIZED`
and returned after `CLOSE`. The wrapper saves a private session log and returns
its ownership to the invoking sudo user. Do not retry unchanged failures.

## Bounds and interpretation

- Exact explicit Bluetooth address, exactly one eligible model0324 mouse/digitizer
  IORegistry service; active custom DriverKit takeover is refused.
- Only input GET_REPORT for 0x31, with 4096-byte zero-initialized buffers. No stream
  callback, native contact monitor, feature initialization, SET_REPORT calls,
  Bluetooth channel opens/delegates or firmware commands are issued by this probe.
  macOS itself remains responsible for translating the GET_REPORT request.
- At most six requests, a requested 1000 ms API timeout per request, and a 2.5-second
  completion observation limit. A missing callback aborts further requests. A
  35-second process alarm also bounds a stalled API/close; forced exit releases
  process connections but native restoration still requires observation.
- Only one request at a time. Request buffers/contexts and device stay retained
  through immediate process exit, even if a callback is missing. Do not free a
  pending request or reuse its buffer. Memory is bounded by six requests.
- Ctrl-C/termination requests cleanup through the run loop. Normal/error paths
  close the opened HID device. Suspension is ignored while running.
- Output includes status, size, elapsed time, diagnostic contact count, and up to
  256 raw bytes per response. Recognized reports are at most 139 bytes, so their
  entire bytes fit in the log. Unknown larger replies have a marked display limit.
- Callback report ID is the requested ID carried through Apple's completion
  context, not an independent on-wire identity. Framing is diagnostic evidence.
  Successful framing alone does not establish fresh, correct contact tracking.

If baseline fails, this request route is not established and no seizure is needed.
If baseline works and seized requests fail, it cannot supply the desired hybrid
in this form. If both work, compare changing bytes/contact counts while fingers
move, then evaluate freshness, coordinate agreement and latency before integration.
A low-rate diagnostic is not evidence of keyboard-quality sampling performance.

## Offline checks

`test.sh` covers argument rejection and the baseline gate, in addition to existing
packet parsers and fake-object Bluetooth ABI tests. `build.sh` builds a separate
universal Developer ID-signed HIDGetReportProbe bundle with no restricted
entitlements or provisioning profile. It is not notarized or integrated into the
production build. Default/help are the only smoke paths exercised by the agent;
no actual report request or seizure has been run.

Sources inspected:

- [Apple app GET_REPORT implementation](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDLib/IOHIDDeviceClass.m)
- [Apple HID user client](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDLibUserClient.cpp)
- [Linux Magic Mouse/Trackpad driver](https://github.com/torvalds/linux/blob/master/drivers/hid/hid-magicmouse.c)
- Installed SDK `IOKit/hid/IOHIDDevice.h`, IOHIDDeviceGetReportWithCallback discussion.
- [Independent Bluetooth HID implementation's native-host limitations](https://github.com/jqssun/darwin-bt-remote#macos-hidp). This independently reports daemon HID-port ownership, not a tested solution for our pad. No implementation code was copied.

## Hardware result: 2026-10-19

Capture: `/tmp/amt-get-report.N1XFSH/session.log`.

- Ordinary IOHID open succeeded as root.
- First input 0x31 request submission succeeded, but the asynchronous completion
  failed after 53 ms with `0xe00002bd` (`kIOReturnNoMemory`), zero bytes.
- Baseline gate stopped the test; no exclusive open/seizure was attempted.
- Ordinary close succeeded. Native pointer behavior was not explicitly reported.

Unified logs for the same run (probe PID 83015) resolve more of the path:

```text
22:01:48.001 getReportWithKeyhole type = 0, reportID = 0x31, max reportLength = 4096, keyholeID = 0xf1
22:01:48.050 getReportResponse for handle 0xc40a success 0
22:01:48.050 getReportWithKeyhole 0x31 with keyholeID 0xf1 failed: 0xe00002c7
```

`0xe00002c7` is `kIOReturnUnsupported`. The failure exposed to the application
therefore differs from the native transport's logged unsupported failure. This
is not evidence that a 4096-byte allocation exhausted memory or that a smaller
buffer would fix the input request. We have not determined the exact translation
point between these two status codes. Do not repeat with guessed buffer sizes.

The native bridge wrapped this request through its F1 keyhole mechanism; this was
not a verified plain on-wire HIDP GET_REPORT for 0x31. It establishes failure of
this request path, not a firmware-wide statement that report 0x31 is never
requestable. Runtime registry inspection confirms the selected pad's mouse/
digitizer IOHIDUserDevice carries KeyholeReportID 241 (F1); additional virtual
interfaces have other keyholes. We did not write any of these properties.

Further static inspection found a `kCBMsgIdDeviceSetHIDPropertiesMsg` handler name
and `KeyholeReportID` in bluetoothd. That is a research lead only: no callable
client interface, accepted properties, ownership transfer, or authorization was
established. Runtime class metadata inspection of IOBluetoothDevice, CBClassicPeer,
CBClassicManager and IOBluetoothCoreBluetoothCoordinator did not expose a method
named setHIDProperties. Selector names/string presence do not establish safe
behavior, and no such method/message was invoked. Do not guess XPC messages or
edit the virtual device's properties expecting transport ownership to change.

No unchanged hardware retry is needed. The report-request experiment has not
provided a usable contact source. Native Bluetooth-to-HID ownership/descriptor
configuration remains an unvalidated research target.

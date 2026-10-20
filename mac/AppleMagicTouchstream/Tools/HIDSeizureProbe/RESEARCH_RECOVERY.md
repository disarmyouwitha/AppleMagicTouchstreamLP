# Recovered research and the next Bluetooth boundary

> Correction (2026-10-19): later unified logs showed the private `l2capChannels`
> accessor initiating connections. Earlier claims that channel-proxy enumeration
> was read-only are withdrawn. See [the hardware result](BLUETOOTH_TEST.md).

2026-10-19. This investigation retrieved archived conversations and examined
saved captures, our driver, Apple/Linux/BlueZ/hidapi source, installed SDK headers,
IORegistry and cached Bluetooth service metadata. It did not seize hardware,
activate a driver, open Bluetooth channels, change delegates, issue SDP queries,
disconnect devices, or change security settings.

## The earlier conversation was found

Archived Codex thread: **Create stripped-down Mac projects**, ID
`01a1477c-bb77-7442-ab3a-f411d4003f4d`.

Relevant turns include `01a14daa-e15d-7032-a053-6a33208003ca` (paired capture
confirmation), `01a14dac-c3ae-7c12-9435-71ac0a2f7833` (eight-byte prefix is not a
separate mouse packet), and `01a14db3-8025-7d61-a638-df20fc7b5b0d` (user rebooted
with SIP restored). The earlier SIP-off step was a bounded kernel-tracing
diagnostic, not a deployable acquisition backend.

The original evidence survives locally:

- `mac/gesturepad/RewriteValidation/HID_CAPTURE_FINDINGS.md`
- `mac/gesturepad/RewriteValidation/captures/usb_original_seized.json`
- `mac/gesturepad/RewriteValidation/captures/usb_original_seized_app.json`
- `mac/gesturepad/Tools/USBTransportProbe/decode-original-report.py`
- `mac/gesturepad/RewriteValidation/DRIVERKIT_TAKEOVER_CHECKPOINT.md`

The old pair was independently rechecked in this investigation. During its
seizure window, all 668 full original reports match the 668 app callbacks in order:
each callback is exactly the first 8 bytes of its corresponding full report.
Original report lengths are 21/30/39/48 bytes; every callback is 8 bytes. There were
265 one-contact, 341 two-contact, 2 three-contact and 60 four-contact reports.

Thus the old result was **eight bytes**, including signed 8-bit mouse-like fields,
not proof that the device transmitted only 8 bits or only a mouse packet. The
contact records survived outside the app callback's truncated prefix. This exact
paired capture was USB, not Bluetooth; it is relevant to the common queue boundary
without establishing a successful Bluetooth seizure-and-raw-read combination.

## How the sources line up

### Apple report-element queue

`IOHIDElementContainer` creates input-report handler elements using the descriptor's
`inputBitCount`. `IOHIDElementPrivate::processReport` determines its copy size from
`_reportBits * _reportCount`. A larger application callback buffer does not
reconstruct bytes excluded by that kernel element. This supports the measured USB
prefix result. On the Bluetooth mouse/digitizer service, input IDs 02/3F/44 are
advertised while the actual working driver contact report is 31: a related but
different delivery problem (absent report element rather than just a short one).
[Container](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDElementContainer.cpp)
[Element copy](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDElementPrivate.cpp)

This is not evidence that a malicious callback hides contacts or that changing a
function pointer in our process would fix it. The relevant boundary includes
kernel report-element processing. Published source is not a trace through the
exact installed Bluetooth binary, so the detailed Bluetooth cause remains a
source-backed explanation to verify.

### Existing receiver

Our `AMTRawHIDReceiver` uses a different receive boundary: preallocated 4096-byte
buffers on `IOHIDInterface`, ordinary interface Open, actual-length
`ReportAvailable` callbacks, and buffer return to the pool. Apple's matching
implementation copies the incoming descriptor's actual length before publishing
that callback. It does not rely on the app's descriptor-sized report-element queue.
[Apple interface implementation](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDInterface.cpp)

The saved Bluetooth build 4 result had 884 reports, including 540 thirteen-byte and
344 twenty-two-byte packets, zero malformed/mapping errors, and no mode command.
That proves our Bluetooth model/protocol can produce complete contacts and our
decoder has a real reference. It does not remove DriverKit distribution gating.

### Linux and BlueZ

Linux `hid-magicmouse.c` explicitly registers `TRACKPAD2_BT_REPORT_ID` (31) via
`hid_register_report`, and decodes it in its raw-event path as 4 bytes plus 9 bytes
per contact. USB uses a different prefix. The code therefore does not rely on an
ordinary advertised mouse report alone. That is a kernel-driver facility on
Linux, not a drop-in macOS user-space API.
[Linux driver](https://github.com/torvalds/linux/blob/master/drivers/hid/hid-magicmouse.c)

BlueZ's HID input implementation handles separate L2CAP control and interrupt
channels. This is a useful reference for receiving reports before the macOS HID
element queue; porting a Linux driver or calling BlueZ APIs is not itself a Mac
solution. Protocol facts can guide an independent implementation; copying GPL
implementation code into product code would require a licensing decision.
[BlueZ input transport](https://github.com/bluez/bluez/blob/master/profiles/input/device.c)

`hidapi` on macOS opens an IOHIDDevice and registers the same application input
report callback. Switching to it would not provide an independent lower transport.
[hidapi Mac backend](https://github.com/libusb/hidapi/blob/master/mac/hid.c)

## A concrete new Bluetooth lead

A small temporary metadata reader used `getServiceRecordForUUID` on each exact
tested address. This API reads previously cached SDP records without starting a
query. Both have cached Classic HID service 1124 with:

| SDP attribute | Channel |
| --- | --- |
|0004 ProtocolDescriptorList|L2CAP PSM 17 decimal (0011 hex), HID control|
|000D AdditionalProtocolDescriptorLists|L2CAP PSM 19 decimal (0013 hex), HID interrupt|

System Profiler also labels them HID ACL devices. This is concrete evidence for
investigating Classic HID transport on these pads, rather than guessing BLE
characteristics or generic serial channels.
[Cached service API](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice/getservicerecord(for:))

Installed public IOBluetooth headers expose channel opening, channel-open
notifications and delegate-based data delivery. Runtime introspection also found
the undocumented selectors `l2capChannels` and
`openL2CAPChannel:findExisting:newChannel:` on IOBluetoothDevice. Only selector
availability was checked: neither selector was invoked. Presence does not prove
authorization, cross-process access, or safe sharing of the system's HID channel.
[Public channel API](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice/openl2capchannelsync(_:withpsm:withconfiguration:delegate:))
[Delegate API](https://developer.apple.com/documentation/iobluetooth/iobluetoothl2capchannel/setdelegate(_:))

The next distinct experiment should investigate channel ownership and the raw
interrupt-data delivery boundary before HID report-element processing. First
establish whether a listener can receive data on the selected pad without stealing
the native channel's delegate or disconnecting it. If exclusive channel ownership
is necessary, design a separate bounded test with explicit restoration/reconnect
behavior. Do not assume IOHID seizure releases bluetoothd's transport ownership.
Validate any framing against the existing Bluetooth driver samples/decoder.

Undocumented APIs are in research scope. A viable distributed implementation
still needs to work with ordinary system protections enabled; process injection,
kernel patching or protected tracing is not the product plan. No working direct
Bluetooth acquisition implementation has been established by this investigation.

## Avoid repeating established dead ends

- Do not repeat unchanged shared/seized IOHID callbacks, run-loop-vs-dispatch,
  permissions, larger buffers or feature initialization as new discoveries.
- Native contacts plus mouse/digitizer seizure failed on the right Bluetooth pad.
- Earlier isolated-interface tests did not separate native movement from OMS.
- Cursor warping was explicitly rejected; prior gain writes did not take effect.
- No USB-only, VM, or external bridge result meets the user's current goal.
- Karabiner supplies virtual output, not missing raw Bluetooth contact input.

The goal remains selected Bluetooth trackpad ownership, complete contacts,
application interpretation and reliable restoration, without dependence on approval
of our own DriverKit distribution entitlement. Preserve the existing driver as
the working protocol/behavior reference and optional backend.

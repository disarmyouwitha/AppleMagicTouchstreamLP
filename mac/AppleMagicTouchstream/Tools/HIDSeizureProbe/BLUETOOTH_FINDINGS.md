# Bluetooth report-delivery investigation

2026-10-19. Registry inspection only in this investigation; no new live seizure.

## Established hardware results

The user confirmed seizure and native restoration on the right Bluetooth pad.
Its native monitor recorded317 frames/315 contact-bearing frames before seizure,
zero native frames and zero raw HID callbacks during seizure, and411 frames/410
contact-bearing frames after close. The earlier test of both Bluetooth pads also
showed successful seizure but zero raw callbacks. Right-pad feature initialization
F1/payload0201 returned success without enabling raw callbacks. We do not infer
that a successful feature operation establishes its effect inside the device.

The selected right-pad registry ID was4294998142. Read-only IORegistry inspection
confirmed that its IOHIDUserDevice publishes both mouse and digitizer usage pairs,
and its IOHIDInterface has Apple's multitouch driver/device beneath it. It is not
merely an unrelated mouse. Its mouse-facing top-level usage does not mean that
we selected the wrong physical pad or omitted a separate digitizer interface.

## Report-path mismatch: a hypothesis with concrete evidence

The selected Bluetooth service advertises input report elements with IDs:

| ID | Advertised report bits |
| --- | ---: |
|02|64|
|3F|136|
|44|11104|

Our working AMTRawHIDReceiver accepts raw Bluetooth contact packets with ID31.
That ID is absent from the inspected service's advertised input-report elements.
The probe's raw callback counts every delivered packet, so the absence of all
callbacks is not caused by its CompactV7 decoder rejecting a delivered packet.

In Apple's published IOHIDLib implementation, input-report callbacks are backed
by a queue of input-report elements. IOHIDDeviceClass.initQueue creates that queue
and adds its report elements; registering a callback initializes and starts it.
Registration before Open is handled by Open starting the existing report queue,
so that ordering alone is not an established bug in this probe.
[Apple IOHIDDeviceClass implementation](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDLib/IOHIDDeviceClass.m)

Apple's published kernel IOHIDDevice.handleReportWithTime separately processes
descriptor elements and forwards input reports to its IOHIDInterface. It explicitly
allows a single interface to receive reports with undefined IDs. That forwarding
is suppressed when a client seizes the device. This is consistent with native
contacts stopping during seizure and with the driver receiving reports outside
the user-space report-element queue.
[Apple IOHIDDevice implementation](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDDevice.cpp)

This is a plausible explanation, not a verified trace through this Mac's exact
installed kernel/framework build. It does not prove Bluetooth hardware stops
transmitting, that report31 is the only report sent, or that every user-space
access method must fail. The next investigation must establish an actual means
of receiving these undeclared/raw reports without our own restricted extension;
changing only the decoder or substituting Karabiner output cannot do that.

The user has explicitly ruled out USB-only success as useful. Further tests must
target Bluetooth. The native-contacts-plus-seizure combination has failed on the
tested right pad and should not be represented as a working alternative.

# First raw HID capture findings

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

# Apple contact HID layout

The recovered model 0324 Compact V7 report/contact specification is preserved in
[GesturePad's APPLE_CONTACT_HID_LAYOUT.md](../gesturepad/APPLE_CONTACT_HID_LAYOUT.md).
It includes Bluetooth/USB framing, all nine contact bytes, coordinate calibration,
scalar unpacking, sensor-clock/velocity reconstruction and reference evidence.

The custom DriverKit implementation has been removed from both applications.
AppleMagicTouchstream uses native contact capture; the native FLTR test remains
in GesturePad only. Existing optional capture provenance is retained for replay.

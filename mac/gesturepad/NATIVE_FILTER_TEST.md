# Native Trackpad Takeover acceptance

The user confirmed the original 15-second FLTR test works through both Bluetooth
and USB. GesturePad now has continuous selected-pad **Trackpad Takeover** and
**Release Trackpads**. [Implementation details](TRACKPAD_TAKEOVER.md).

1. Keep another mouse/keyboard available. Open GesturePad and select the intended
   Left/Right trackpads. Check their transport and serial in the selectors.
2. Click **Trackpad Takeover**. Move one finger on each selected pad. Contacts and
   paths should keep updating while its native pointer movement is suppressed.
3. Continue past 15 seconds: the full feature has no test deadline.
4. Verify an unselected pad/other mouse remains usable. Test one selected pad,
   both pads, and the same pad in both selectors (one physical takeover).
5. Click **Release Trackpads**, or press **Ctrl–Option–R**. Confirm native input
   and contact callbacks both work. Release before refreshing/changing selection.
6. Repeat a start/release cycle. Test scrolling, click/drag and gestures separately;
   movement success is not proof of every native behavior.
7. Close and reopen Config; takeover should remain active. Select Restart while
   active; Config should rebuild with contact delivery and suppression preserved.
   This keeps the same owning process alive. Check sleep/replay/Exit release,
   including sleep with Config closed. Reopen/reselect manually after a reconnect;
   no automatic takeover is performed.

Start validates all selected pads before changing any. Unsupported selections or
existing filter owners fail preflight. Failed partial starts attempt rollback.
Status identifies captured transports/serials and aggregate contact-frame counts;
release reports recovery results. Copy it if something fails. A failed release
keeps the remaining owned pads active in the UI so Release can be retried.

USB requires VID05ac/PID0324; Bluetooth requires VID004c/PID0324. Both require
native driver type4. These are the tested model gates, not support for all Apple
trackpads. No new driver, mode write, USB seizure or synthetic output is involved.

Individual Bluetooth/USB trials were hardware-confirmed. Continuous multi-pad
operation and the lifecycle matrix above still require physical acceptance.

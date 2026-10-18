# Selected-trackpad takeover lifecycle

Accepted direction, 2026-10-18: enable Driver Takeover once per app session if
necessary, keep the extension enabled across pad loss, Sync and the app's Restart
command, and tear it down on actual Exit. Persistent installation across sessions
is a later goal. Never cycle the entire extension to recover one pad.

## Behavior implemented for v20 testing

- Driver Takeover requests activation; Sync Trackpads applies current Left/Right
  selections without an activation/deactivation request. Zero, one and two distinct
  selected pads are valid. An unchanged source keeps its stream cursor, sensor
  clock and two-finger baseline when the other source changes/disconnects.
- USB/Bluetooth Magic Trackpad2 product0324 matching no longer contains personal
  serial numbers. Runtime identities come from the interfaces. The existing surface
  descriptor check and CompactV7 decoder remain; other AMT generations are not
  declared supported without reports/calibration/hardware testing.
- An IOUserResources-backed, control-only service shares the extension process.
  It opens no pad and keeps the per-device handoff command endpoint/provider cache
  alive when zero HID receivers remain. HID personalities have no IOMatchCategory;
  the coordinator has its own private category so it does not compete for resources.
- The signed internal helper enforces its selected-serial policy on newly matched
  receivers. Unselected receivers close/terminate individually; after disappearance,
  the coordinator requests matching on their retained providers. Activation can
  initially attach matching receivers before this helper policy is applied. This
  bootstrap window still needs hardware measurement; do not describe matching as
  exclusively selected-device attachment from the first instant.
- A reconnected/replaced selected stream waits for explicit Sync before the app
  accepts its frames. No pad-presence/count watchdog removes the extension. No
  transport-switch guessing or automatic whole-driver recovery was added.
- Sync requests retake for a previously handed-off selected provider. RegisterService
  success is not evidence it displaced an already-running Apple handler. That
  reverse transition remains unproven and may still need a per-pad reconnect after
  selecting it and pressing Sync. The other selected pad must stay controlled.
- Restart transfers the live helper session using a single-use nonce and bounded
  owner lease. The helper verifies the replacement app's running code against its
  Apple signing anchor, team and bundle identity. Original owner death is tolerated
  for at most20s during an explicit handoff; the replacement must claim within the
  lease. Restart does not activate/deactivate the extension. A failed replacement
  ultimately triggers ordinary owner-loss cleanup rather than permanent capture.
- Driver metadata and routing survive Restart even while Apple's touch services
  are absent. These selector entries are explicitly supplemental DriverKit sources,
  not fabricated native listener handles. Old shared-memory references do not cross
  processes; the new app reads the live registry stream again.
- Actual Exit and Release Trackpads request full removal and wait for confirmation.
  Authorization may still be required by macOS. The owner watchdog also removes
  the extension after an unexpected app exit, except during the bounded transfer.
  Config-close, sleep and replay release safeguards remain.

## Required physical acceptance checks

1. Both pads controlled: power Bluetooth off; USB continues visualizing and remains
   captured. Restore Bluetooth, verify selectors, Sync; USB must remain unaffected.
2. Restart from the app menu while both controlled: no deactivation/password prompt,
   same helper and extension process, new GesturePad PID, both live views resume.
3. Select one pad / Sync: only the other pad returns to native input. Then select
   neither / Sync: both native, coordinator remains enabled. Do not infer restored
   native input from a successful RPC; test movement and scroll physically.
4. Reselect a handed-off pad / Sync: observe whether it actually retakes. If native
   ownership persists, record that limitation; do not silently cycle the extension.
5. Exit: native input returns and no live current-build receiver/coordinator remains.
6. Repeat a transport change and test another supported-model serial when available.

Offline validation:76 Swift app tests and7 driver/signing tests pass; Xcode and
DriverKit builds succeed, signed integration bundle verified. These checks do not
prove matching, native handoff, process transfer or crash recovery on hardware.

Scope: gesturepad only. AppleMagicTouchstream / GlassToKey integration and permanent
helper/driver identity remain subsequent work. Production entitlement approval is
still separate from the development permission used for these tests.

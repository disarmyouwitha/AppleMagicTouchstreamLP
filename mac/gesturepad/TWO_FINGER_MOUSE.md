# Opt-in two-finger mouse test

Added 2026-10-20, GesturePad only. This is the small live movement test after the
[acceleration investigation](POINTER_ACCELERATION.md), using fixed sensitivity
rather than claiming a calibrated Apple transfer function.

## Use

1. Launch GesturePad and select the pads to use.
2. Enable **Trackpad Takeover**.
3. Check **2-finger mouse**. If requested, grant GesturePad Accessibility permission
   in System Settings and check the box again.
4. Move two fingers together on a selected pad. The status reports movement events
   posted. A separate mouse/keyboard is useful for clicking during this test.

Uncheck **2-finger mouse** to stop synthetic movement while keeping takeover.
Uncheck **Trackpad Takeover**, or press **Ctrl-Option-R**, to release native input.
The mouse checkbox then waits for takeover rather than posting through ordinary
native input. If it remains checked, enabling takeover again resumes the test.

The mouse checkbox is **off on a new process launch**; it is not saved in defaults.
Closing/reopening Config preserves the current process state. The existing
in-process Restart while takeover is enabled also preserves that test state.
The takeover checkbox retains its own existing persistent preference.

## Behavior and boundaries

- Exactly two active (`making`/`touching`) contacts on the same pad supply centroid
  deltas. Hover/start-in-range alone is insufficient. Classified palm contacts are
  rejected. One, three or four active contacts reset the baseline and do not move
  the pointer.
- Sensitivity is provisionally **6 Quartz points per mm**, using the app's existing
  160 × 114.9 mm surface dimensions. X/Y come from successive two-contact centroids;
  Y is inverted for Quartz coordinates. This is the earlier tracker's fixed-gain
  behavior, not the Apple-source acceleration model.
- First contact pair establishes a baseline. Contact-ID/count changes, selection
  changes, stale/non-increasing timestamps, release and oversized deltas prevent
  carry-over jumps. Baselines are independent per native numeric device ID.
- Only the intersection of the current selected IDs and actually owned FLTR IDs
  can produce movement. A failed transition's extra retained ownership is not an
  output source. No reusable device-index slot is used to choose a source.
- Output is stopped before native transitions/release. Successful transitions can
  resume a checked test after ownership/selection reconcile. A failed transition
  leaves output paused; toggle the mouse checkbox off/on after inspecting status
  if you intentionally want to resume the retained selected pads.
- Sleep, replay, quit and refresh use the existing takeover/runtime cleanup. Replay
  never posts movement. Sleep/replay restoration can resume the checkbox's current
  in-process opt-in after takeover succeeds.
- Output pauses while any primary mouse button is held and re-anchors afterward.
  This test does not synthesize a mouse button, dragging, scroll, pinch, keyboard
  or haptic output. Symmetric spreading has no centroid movement; asymmetric pinch
  may move the centroid because no pinch recognizer is enabled yet.
- Posted mouseMoved CGEvents are tagged with the existing interpreter tag and
  clamped to the nearest active display's bounds. There is no cursor-warp loop,
  cursor dissociation, acceleration-property write or additional event blocker.
  The surrounding OS/event pipeline still needs hardware verification.

Accessibility checks, native ownership snapshots and display enumeration happen
on control/status updates, outside raw contact callbacks. The existing live-only
input path feeds the tracker; capture/replay file formats are unchanged. Existing
selected-device native FLTR validation, rollback and emergency release remain.

## Hardware acceptance

With another input device available, check:

- One finger does not move the pointer; two coherent fingers do.
- Lifting/replacing fingers or switching to three/four fingers does not jump.
- The same pair works independently on each selected pad.
- Changing BT/USB selection stops the old source and anchors the new one.
- Unchecking the mouse checkbox stops movement immediately; unchecking takeover
  or Ctrl-Option-R restores normal native input.
- Config close/reopen, sleep/recovery and replay do not leave unexpected output.
- Compare slow precision and fast travel; report sensitivity and cursor behavior.

These checks have not been automated on hardware. `./test.sh` covers tracker
translation/direction/reset behavior, hover/count/ID rejection, pinch centroid,
large jumps and pure ownership/permission/selection gating without posting events.

Calibrated Apple-style acceleration should be a separately testable change after
this gesture/input/output path works well. See POINTER_ACCELERATION.md for the
remaining unit-conversion, timing and event-posting questions.


## Accessibility appears enabled but the checkbox refuses

A verified local failure was a stale TCC code requirement: the approved identity
was `Apple Development`, while `/Applications/GesturePad.app` was now signed with
Developer ID Application by the same developer. The TCC log explicitly reported
`Failed to match existing code requirement` for `ink.ranna.gesturepad` and
`kTCCServiceAccessibility`. Enabled-looking duplicate rows did not grant the new
signing identity access. This is distinct from a missing DriverKit entitlement.

The targeted repair is to quit GesturePad, reset only its Accessibility approval
with `tccutil reset Accessibility ink.ranna.gesturepad`, then add/enable the current
`/Applications/GesturePad.app` in System Settings > Privacy & Security >
Accessibility and relaunch. The reset does not grant permission; the user approves
the current app in System Settings. Do not reset all apps, edit the TCC database,
or add private TCC entitlements. Keep installed builds signed consistently with
the existing Developer ID identity to avoid repeating the development/release
identity mismatch. Other historical bundle identifiers may have separate rows.

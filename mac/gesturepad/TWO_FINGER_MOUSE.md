# Two-finger mouse with Trackpad Takeover

Added 2026-10-20, GesturePad only. The user confirmed the accelerated response
on hardware and accepted it as the default alongside Trackpad Takeover. The
contact-to-count conversion remains a measured experiment, not a claim that all
native Apple processing has been reconstructed.

## Use (accepted defaults)

1. Launch GesturePad and select the pads to use.
2. Enable **Trackpad Takeover**. **2-finger mouse** defaults on and uses the
   accepted Apple-source acceleration automatically, starting at **1.00×**.
3. Move two fingers together on a selected pad. Adjust **Sensitivity** alongside
   the mouse checkbox. No Response picker or normal status counter is displayed;
   actionable permission/profile/waiting messages remain visible below the row.

Uncheck **2-finger mouse** to stop synthetic movement while keeping takeover.
That override survives selection, Config rebuild, sleep and replay in the same
process. A fresh explicit takeover enable checks it again. Restored takeover on
a new process launch also uses the default enabled mouse behavior. There is no
movement without current selected-and-owned FLTR devices, successful transition
arming and Accessibility approval. Missing permission pauses output; checking
the mouse/takeover control can request the existing Accessibility permission.
Startup does not show an unsolicited permission prompt.

Uncheck **Trackpad Takeover**, or press **Ctrl-Option-R**, to release native input.
The takeover checkbox retains its existing persistent opt-in preference (default
off for a new user). Config close/reopen and the existing in-process Restart
preserve the current state. Sensitivity remains process-local and starts at 1.00×.
The previous Fixed response is retained in the pure offline diagnostic model,
without a production response selector. The numerical model is unchanged from
the hardware-accepted release. The four-finger scroll addition introduces a shared
0.2 mm initial movement threshold to choose a two/four-finger chord before latching;
see [FOUR_FINGER_SCROLL.md](FOUR_FINGER_SCROLL.md). Added fingers never switch an
already latched mouse gesture into scroll.

## Behavior and boundaries

- Exactly two active (`making`/`touching`) contacts start a per-pad mouse latch.
  After activation, either remaining finger continues mousing until all fingers
  lift. One finger alone cannot start a new mouse session. Hover/start-in-range
  alone is insufficient; classified palms cancel the session.
- Once latched, any positive active finger count continues mousing, including
  2→3→4→1. Match IDs across frames and average continuing fingers' displacement.
  New fingers establish a baseline before participating; lifted fingers are
  excluded immediately. Stable membership equals centroid motion, while changes
  do not add landing-position jumps or pause output. Only all-up or explicit
  cancellation ends the mouse session; additional fingers do not start a new
  gesture.
- Both modes use the existing 160 × 114.9 mm surface-size assumption and
  successive two-contact centroids, with Y inverted for Quartz coordinates.
  Fixed produces **6 Quartz points per mm × sensitivity**. Apple mode converts
  mm to experimental counts using **resolution / 25.4 × sensitivity**, then
  evaluates the independent parametric model documented below. That conversion
  is an explicit hypothesis, not a recovered native multitouch algorithm.
- First contact pair establishes a baseline. Contact-ID/count changes use continuing contacts; oversized deltas re-anchor motion. All-up,
  explicit resets, invalid/palm data and stale/non-increasing timestamps cancel
  the latch. No shared contact IDs also cancels it, covering a missed
  all-up frame. Sessions are independent per native numeric device ID.
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

- One finger alone cannot start mousing; two coherent fingers do.
- Start with two, lift either one, and continue moving with the survivor.
- Add fingers through two, three and four: continuous movement without landing jumps.
- Lift all, then place one: it cannot resume until a two-finger chord starts again.
- Remove fingers from four down to one: continue without count-change jumps.
- The same pair works independently on each selected pad.
- Changing BT/USB selection stops the old source and anchors the new one.
- Unchecking the mouse checkbox stops movement immediately; unchecking takeover
  or Ctrl-Option-R restores normal native input.
- Config close/reopen, sleep/recovery and replay do not leave unexpected output.
- Compare slow precision and fast travel; report sensitivity and cursor behavior.

These checks have not been automated on hardware. `./test.sh` covers tracker
translation/direction/reset behavior, hover/count/ID rejection, pinch centroid,
large jumps and pure ownership/permission/selection gating without posting events.

## Apple acceleration experiment (2026-10-20)

`Runtime/PointerAcceleration.swift` ports the numerical parametric equations
studied in [POINTER_ACCELERATION.md](POINTER_ACCELERATION.md), independently of
Apple's implementation files. It includes signed 16.16 decoding, indexed curve
interpolation, polynomial/linear/root regions, floored radial magnitude, pointer
report-rate normalization and the non-unit fixed-multiplier branch.

Each selected pad's registry entry supplies resolution, curves, multiplier and
report rate; trackpad tracking index falls back to IOHIDSystem HIDParameters when
absent on the provider. User parametric curves take precedence over provider
curves. Reads happen on selection and mouse enable, outside callbacks.
Toggle the mouse checkbox off/on to reload changed system settings. Unsupported
or missing parametric settings pause output with a status message; there is no
silent fixed-gain fallback. Table curves,
algorithm overrides and third-party service-filter effects are not reproduced.

Timing/baseline history is independent per pad. Changing sensitivity re-anchors
before producing movement; existing release/transition gates remain. Membership
changes use matched-contact displacement to preserve smooth continuation. Physical jumps of 25 mm per axis and output
jumps of 150 points per axis are rejected and re-anchored, not accumulated.
Sensitivity is a pre-acceleration input scale in Apple mode; it changes curve
engagement as well as travel. It does not write macOS tracking settings.

### New user capture

`RewriteValidation/captures/left_normal_right_takeover.atpcap` is a version-5
capture with 328 frames over 4.995 seconds, all from native device
`288230377507875157` (right Bluetooth pad). 309 frames contain two contacts,
13 contain one and 6 contain none. It contains neither a left-pad comparison
stream nor native cursor ground truth, despite the filename.

Before latching was added, the production pure motion engine was replayed offline with the installed
400-resolution/index-3/fixed-multiplier-0.740737915 profile at 1.00×:

| Response | Accepted movement frames | Integrated path (points) | Peak vector (points) |
| --- | ---: | ---: | ---: |
| Fixed 6 pt/mm | 285 | 2020.00 | 15.36 |
| Apple acceleration (test) | 282 | 13703.68 | 147.82 |

Apple mode's additional three rejected frames hit the output jump guard. The
large gain difference motivates the sensitivity slider and retained offline
Fixed comparison; these figures do not establish native equivalence. Start
with short slow strokes when testing, then compare faster travel. If it is too
fast, reduce sensitivity and report the chosen value.

`ApplePointerAccelerationTests` checks analytic region boundaries, independent
Python reference vectors, timing/multiplier behavior, interpolation, reset
behavior and this capture through the same pure engine used live. Optional
`POINTER_PROFILE_REGISTRY_ID=<id> ./test.sh --filter ApplePointerAccelerationTests`
adds a read-only registry-profile check. Set `POINTER_REPLAY_REPORT` to an output
JSON path to save capture metrics. No test opens a FLTR session or posts events.
The local capture test skips when that unbundled recording is unavailable.

The user confirmed the live accelerated feel works well. The later latching
change has offline regression coverage and awaits hardware acceptance. See
[GESTURE_ENGINE.md](GESTURE_ENGINE.md) for the shared session rule. Further cross-device
calibration of the contact-to-count hypothesis remains separate work. See
POINTER_ACCELERATION.md for remaining unit-conversion and event-posting questions.


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

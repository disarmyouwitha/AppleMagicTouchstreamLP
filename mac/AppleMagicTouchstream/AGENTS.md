# AppleMagicTouchstream development policy

Scope: this app only unless the user requests broader work. It is the maintained
macOS implementation. Use `project.env` for identity, the local Xcode project and
scheme AppleMagicTouchstream, `./build.sh`, `./test.sh` and `./release.sh --check`.
Build/sign universal Release and install in Applications when requested; leave
closed for hardware testing. Create DMGs only on request. Do not launch or activate
live input, takeover, haptics or login registration as part of offline verification.

## Current contracts

- [GESTURE_ENGINE.md](GESTURE_ENGINE.md) defines the current gesture rules.
  [../FINDINGS.md](../FINDINGS.md) distinguishes recovered firmware evidence from
  app policy. Keep these documents current rather than appending superseded rules.
- Native selected-pad FLTR is the input takeover mechanism. Preserve exact USB
  VID05ac/BT VID004c, PID0324/type4 validation, preflight, retained clients,
  rollback, release retry and own-PID checks. No custom DriverKit/helper dependency.
- The persistent takeover checkbox defaults off. After opt-in reconcile selection
  at startup/wake/replay exit. Emergency Ctrl-Option-R/menu release disables opt-in;
  sleep/replay/quit preserve it. Config close and active Restart keep the owner
  process/clients. Serialize transitions and await keyboard cleanup before release.
- Route by native numeric identity, not bridge slots. Deduplicate selection;
  commit UI/keyboard selection only after successful preparation. Refresh suspends
  and reconciles; auto-resync pauses during ownership/transitions.
- Recognition, candidate reservation, activated session and output ownership are
  distinct. Shared continuous latches and directional logic serve all supported
  counts. Preserve first-activated ownership through all-up, identity rebasing,
  independent pads, Both handoff and balanced cleanup. Do not add gesture-specific
  global resets or duplicate lifecycle paths as shortcuts.
- Established MO/modifier chords and committed key holds retain same-pad keyboard
  priority. Unresolved local candidates retain bounded keyboard proposals while
  gesture recognition runs on the original frames. A winning gesture discards
  those proposals; never resurrect typing from an activated/cancelled owner.
  Never-activated rollover can resolve to typing at partial lift or all-up.
  Invalid, stale, overflowed and reconfigured proposals cancel without output.
  The terminating frame must reach cleanup. Two-finger movement excludes the
  pre-cohort interval at a pending membership change; retain existing three-finger
  staggered drag activation and all activated count-change latches.
- Synthetic gesture output is live-only and selected/owned/armed/Accessibility
  gated, with pointer/scroll profile gates. Open Config is app-local. Replay never
  posts native input. Shared drag button ownership must preserve other-pad owners.
- One-finger gesture Hold is unavailable; keyboard key holds remain. Corner inputs
  are Hold-only. Existing per-pad/Both Outer Corners default to Open Config; Both
  Inner Corners and mirrored top/bottom inner/outer pairs default to None. Preserve
  the legacy fourCorners serialized identity. Corner geometry and coordinated
  lifecycle are shared; pending pairs may grow into enabled full corner chords,
  retaining original IDs and settling limits, but never replace a fired owner.
  All gesture Holds default to 500 ms and
  have independently saved thresholds (per hand/count or coordinated chord),
  editable from 100–5000 ms. Ordinary counts 2–5 and Thumb+2 Hold are independent
  inputs. Keyboard shortcuts on Hold can fire once or remain held until release;
  preserve recognition geometry and cleanup. Legacy retired assignments decode
  but stay inert.
- Saved Rotate Left/Right slots appear only for Thumb+2 and five contacts, default
  None. Other shape pages show only Pinch/Spread. Five Fingers has a full Tap and
  Move cross, sharing Tap/movement/directions/repeat/cleanup with other counts; new
  Tap and Movement bindings default None.
  Rotation recognition is live for these two families: thumb-to-fingertip-group
  angular evidence feeds the shared continuous latch and discrete dispatcher.
  Preserve angular/radial competition, thumb activation, all-up ownership and
  selected/owned/armed/AX/live gates; other rotation counts remain inactive.
- Pinch and Spread activation for counts 2–5 requires a recognized thumb. Once
  activated retain ownership through relabeling/count changes until all-up.
- Every new gesture needs explicit activation, continuation, arbitration,
  completion/cancellation, output and verification rules. Preserve hardware-accepted
  acceleration/feel unless changing it is part of the request.

## Keyboard, profiles and interface

Preserve key/modifier/shortcut output, Hyper, layers, key holds/repeat, capture/replay,
TouchStream reference and stable key identities. Unreserved contacts default to
keyboard input. Do not introduce global Force Min/Max or motion-to-typing cancellation.
Keep per-key Force instead of hold. Unassigned holds stay None, without catalog fallback.
App/file/folder/URL actions use the shared catalog and dispatch queue, fire once,
and remain recording-only in replay. Other unsupported legacy action kinds stay
inert through primary/hold/custom-button paths.
Preserve existing serialized keys/enums, old capture parsing and preference migration.

Autocorrect and Snap Radius are live Keyboard Mode Toggles, retaining their saved
profile keys. Snap uses shared tap eligibility/timing and cached per-key radii;
gesture reservation cannot become snapped typing. Autocorrect observes posted live
keys only, with bounded worker publication and generation cancellation. Keep AX and
spellchecking off the input/output queues, require verified focus/text before
replacement, and never fall back to blind backspacing. AX access must run on the
main actor because self-targeted AX calls enter AppKit directly; spellchecking
stays on its worker. Replay stays output-free.
See [TYPING_ASSISTANCE.md](TYPING_ASSISTANCE.md).

Voice is restored as an explicit toggle dictation action in Keymap and gesture
menus. Speech/microphone permission and audio start occur only on invocation.
Use token-gated permission/chunk callbacks, a focused-target check before Unicode
insertion, and cancellation on suspend/ownership loss/reset. Never start speech,
record audio, request permissions or emit transcript output in tests/replay.

Import/Export Settings include independent per-hand and Both gestures, direction
modes/actions/repeat and gains under the Mac host extension. Missing fields preserve
preferences. Takeover opt-in stays local. Known retired labels remain decode-only;
unknown labels fail import. Do not alter on-disk names as part of prose cleanup.

Keyboard is the default workspace; keep visible trackpad controls, visualizers,
keymap/column inspectors, pressure labels, paths and the monochrome hand menu icon.
TouchStream uses fixed independent traced geometry, per-key overrides and automatic
reference background; column tuning stays disabled. Contact palette is unknown black,
thumb orange, index blue, middle green, ring purple, pinky pink, palm gray. No contact
legend or display toggles. Keep resizable gesture columns, searchable actions,
Left/Right, Mirror Edit and coordinated Both as distinct concepts. Keyboard and
Gesture actions share Shortcut Builder/catalog identities. Gesture custom shortcuts
and held-key lifetimes round-trip through settings; only Hold accepts held output.
Preserve shared key ownership, other-pad/keyboard modifiers and key-up cleanup on
all-up, invalid/stale input, handoff and lifecycle transitions.

Run at Startup uses SMAppService.mainApp, defaults off and reflects actual service
state; imports may apply an included preference. Never register during tests/build.
Typing haptics use waveform 6, level 0–2 / 0.01 steps, saved level ×100. Force uses
fixed waveform 6 / 0.25. Target the originating pad, throttle per pad and keep replay
recording-only. Haptic changes alone must not pulse hardware.

## Source and validation boundaries

`Engine/TouchProcessorEngine.swift` owns keyboard recognition; `EngineActorBoundary`
owns serial execution/replay; `Runtime` owns ingestion and live adapters. Keep
recognition pure where possible and observable without hardware. No allocation,
logging or I/O added to hot input paths. Domain/UI extraction is incremental work,
not permission for an unrequested architecture replacement.

Swift bridge sources live in `Sources/OpenMultitouchSupport`, native implementation
in `Framework/OpenMultitouchSupportXCF`. Rebuild with `./build_framework.sh` after
native edits; never hand-edit generated frameworks. Register new app source files
in Xcode and SwiftPM. Use meaningful offline regression tests and preserve deterministic
fixtures; baseline updates require intentional behavior changes. Keep captures and
firmware evidence intact. Do not weaken SIP or entitlement enforcement.

Do not stage/commit, alter concurrent notes/keymaps, or change Windows/Linux code
without user direction. Never commit provisioning profiles, credentials or secrets.

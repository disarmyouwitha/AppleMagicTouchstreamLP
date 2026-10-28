# Windows gesture engine

Current reference: [Mac gold-standard parity and hardware checklist](MAC_GOLD_PARITY.md).
The sections below are historical notes for the initial 2026-10-23 port. They
describe earlier scope controls and action menus; current behavior takes precedence.

Current Windows pointer controls: movement and drag always use the accepted Apple reference acceleration profile. Pointer response selection and Mac-profile import have been removed from the inspector; older saved response choices are overridden by Windows policy. Shared profile fields and numerical models remain for compatibility and offline verification. The import instructions below describe the earlier research UI and are no longer an available Windows workflow.

Pointer and scroll sensitivity use sliders from 0.25× to 2×, with the current multiplier shown beside each label. Left/Right/Both scoping is preserved; differing values show Mixed until adjusted. Slider updates preserve the active control through synchronous settings refreshes. Natural scrolling uses the inspector's light foreground color.

Implemented 2026-10-23 from `mac/AppleMagicTouchstream`'s current gesture implementation. Hardware validation of this new output path is still required. Earlier Mouse Takeover hardware results establish retained contacts and hook suppression; they do not validate this new recognizer/output integration.

## Inputs and factory actions

| Input | Default action | Windows availability |
|---|---|---|
| Two-finger movement | Move Pointer | Implemented |
| Two-finger tap | Primary Click | Implemented |
| Close, aligned three-finger movement | Drag / Select | Implemented |
| Three-finger tap | Double-Click | Implemented |
| Four-finger movement | Scroll / Pan | Implemented, including momentum |
| Spread thumb + two known fingertips tap | Secondary Click | Recognizer ported; unavailable with current Windows PTP contacts |

Continuous input menus offer None, Move Pointer, Drag / Select, and Scroll / Pan. Tap menus offer None, Primary Click, Double-Click, and Secondary Click. For example, assign Secondary Click to two-finger tap if desired. These inputs do not dispatch arbitrary keyboard shortcuts.

The Gestures panel replaces the former gesture tuning controls and the separate 3-Finger Drag checkbox. Left, Right, and Both select the scope of assignments and pointer/scroll sensitivities. Both displays Mixed when the two hands differ; choosing a value applies it to both. New preferences live in `UserSettings.HandGesturesV1`; factory assignments are mirrored. Existing legacy assignments are retained in the shared settings format for Linux compatibility but are not activated by the Windows runtime. They are not migrated into the new bindings.

## Mac recognition rules retained

- Two/three-finger movement activates at 0.35 mm; four-finger movement at 0.2 mm.
- Recognition uses shared tracking IDs for each interval. Landing/lifting a distant finger cannot shift a centroid and jump the cursor.
- A continuous owner keeps its action through changes in finger count until all-up. Finger count changes cannot convert pointer movement into scrolling or drag.
- Three-finger movement requires a compact row: every pair 2–60 mm apart, middle finger within 8 mm of the longest pair's line, and within 35 mm of each endpoint. Geometry gates activation, not continuation.
- Taps allow 500 ms total duration, 80 ms landing/lifting skew, at least 20 ms overlap, 1 mm travel per finger, stable identities, and no intervening continuous owner.
- Invalid or discontinuous input cancels output. Non-increasing time, lost identity continuity, invalid coordinates, duplicate IDs, 150 ms frame gaps, and large motion jumps cannot create a click or cursor jump.
- Configured multi-finger candidates reserve the whole pad cycle immediately, including its all-up frame. A failed candidate cannot fall back into typing. Reservation survives added/lifted fingers and output suspension. None disables reservation for that input family.
- Claiming a pad cancels its pending key taps, held keys/modifiers, repeats, and momentary layers. The other pad's keyboard touches remain available. Previously emitted key presses cannot be undone.
- Only one pad can own a primary drag. Other-pad gestures cannot click or move through that held button. Other-pad keyboard input remains independent.
- Scroll momentum uses the Mac eight-sample/80 ms release estimate, 30 points/s minimum, 6000 points/s cap, exponential decay with 0.325 s time constant, 2.5 s maximum coast, and 5 points/s stop threshold. Retouch brakes the coast without also clicking.

Source references: Mac `Engine/GestureSessionEngine.swift`, `Engine/GestureKeyboardArbitration.swift`, `Runtime/TapClick.swift`, `Runtime/ScrollGesture.swift`, `Runtime/HandGestureSettings.swift`, and `Runtime/InterpretedTrackpadPointer.swift`.

## Windows adaptations and limits

**Eligibility:** gesture output requires active Mouse Takeover and live selected-trackpad ingress. Replay has no gesture output runtime. Native Windows three/four-finger shell actions can still fire; turn conflicting actions off in Windows Settings. AppleMagicTouchstream does not change those settings. Mouse Takeover continues to block all physical mice, as previously accepted.

**Motion (updated after hardware feedback):** movement and drag now default to the same parametric Apple acceleration equations as Mac, with the recorded reference coefficients from Mac `ApplePointerAccelerationTests.installedExample()`: resolution 400, acceleration index 3, multiplier 48545/65536, linear 1, parabolic 123208/65536, cubic 23593/65536, linear tangent 7 and root tangent 12. These are a reference preset, not a query of this user's active Mac/Windows tracking setting. The Mac cross-language golden vectors pass against the C# model to 1e-9 tolerance. It retains the Mac contact-mm-to-count hypothesis (resolution/25.4, with sensitivity before acceleration), rate/multiplier behavior, 96/67 output scale, and finite-value safeguards. The Windows screen-space limit differs as described in the fast-motion fix below.

The Pointer response menu offers Apple acceleration (Mac reference), Fixed 6 px/mm, and an imported Mac profile when present. Both pointer movement and dragging use the selected response. Imported profiles are validated and persisted per hand; Both applies the selection to both hands. This does not reproduce proprietary upstream processing or guarantee identical visual travel across Mac points/Windows pixels and display scales.

Pointer injection uses absolute virtual-desktop coordinates to avoid adding Windows relative-mouse acceleration. Subpixel remainders are retained; drag positions accumulate from the last queued destination and clamp to the nearest display.

**Scrolling:** fixed 6 scroll points/mm precedes the same momentum model. The per-hand **Natural scrolling** checkbox reverses both axes and momentum; Both displays an indeterminate state when hands differ. Existing direction is preserved by default (checked); uncheck to use the opposite direction. Ten points map to one Windows wheel detent (120 units); fractional units are retained. Vertical sign follows natural scrolling; horizontal sign is reversed for Windows' wheel convention. The current SendInput wheel adapter does not expose macOS pixel-scroll phase/momentum fields, and application handling of small wheel deltas varies. Test direction, pan, speed, and momentum in actual Windows applications.

**Anatomy:** PTP tracking IDs identify contacts, not fingers. The current decoders provide no positive thumb/fingertip/hand classification. The spread-thumb recognizer therefore cannot safely choose Secondary Click. Its assignment menu remains editable (None and all mouse click actions), with a visible unavailability note; its inactive effective binding does not reserve three-finger input by itself. Unknown three-contact taps use the ordinary three-finger tap action, matching Mac's unknown-identity fallback. No guessed thumb classification or speculative driver report was added.

**Reset:** changes to settings/routes stop output and require a clean all-up boundary before recognition resumes. Lift all fingers once after enabling or changing settings. This also prevents a contact already down during a change from becoming an accidental click or drag. Cancelled/discontinuous cycles remain blocked until all-up rather than attempting an in-cycle recovery.

**Routing:** with the same physical path selected in both slots, only one frame reaches the gesture/keyboard actor. An active Left binding wins, with Right used when Left is None; Left gains win. Both visualizers may observe the frame. Selecting separate paths gives independent per-hand sessions.

**Output and cleanup:** the existing actor serializes recognition and keyboard arbitration. A bounded, separate output worker performs SendInput without holding the actor/configuration locks: SendInput can call the UI thread's low-level hook. Queue generations discard cancelled work; stale queued commands are not injected. Takeover is rechecked before posting. Button-up cleanup passes even when takeover is off. The worker also releases a held drag on takeover loss or an input stall. Output failure/overflow requests fail-open takeover release. External injected button-down events, distinguished from our own tagged output, cancel gesture ownership; no marker is treated as a hardware device identity.

Sleep/session changes, emergency release, timeout, decoder faults, disconnect handling, and shutdown continue to use the existing Mouse Takeover lifecycle. Native hook removal/timeouts and SendInput restrictions against higher-integrity applications remain platform limitations. An active status is not proof of device-exclusive ownership.

## Files

- Core `Engine/ApplePointerAcceleration.cs`: Mac numerical model, reference preset, validated snapshot import.
- Core `Engine/HandGestureEngine.cs`: recognition, reservation, anatomical tap classification, momentum; no platform I/O.
- Core `Runtime/HandGestureSettings.cs`: trigger/action validation, per-hand defaults, gains, duplicate-device merge.
- Core `Engine/TouchProcessorCore.cs`: opt-in replacement seam, per-pad keyboard cancellation, actor integration. Legacy recognizers remain enabled by default for existing Linux callers; Windows explicitly disables them in both live and replay composition.
- Windows `WindowsHandGestures.cs`: live contact conversion, eligibility, settings, native output adapter, button interference.
- Windows `WindowsGestureOutput.cs`: bounded native-output worker and cancellation.
- Windows `HandGesturePanel.cs`, `MainWindow.xaml/.cs`: replacement controls and status.
- Windows `TouchRuntimeService.cs`: tray/live composition and routing.
- Windows `WindowsDiagnostics/HandGestureTests.cs`: offline vectors adapted from Mac production tests; included in `--selftest`.

## Verification and hardware check

The offline tests cover activation/travel, ownership through count changes, no joining-finger jump, row geometry, staggered taps and timing rejection, cancellation/stale cleanup, keyboard reservation, independent other-pad typing, reused contact IDs, settings validation/round-trip, per-hand actions, duplicate-device precedence, known/unknown anatomy, and numerical momentum. The existing self-tests also exercise the retained shared legacy behavior for regression coverage.

Verified locally on 2026-10-23:

- Normal Windows Release build: success, zero warnings/errors.
- Release `--selftest`: all tests passed, including engaged-modifier cancellation and suppression of saved legacy five-finger actions.
- Patch whitespace check: clean.
- New live gesture output: not hardware-tested by the agent; the check below is still required.

For the first live check:

1. Open the Release EXE, choose the trackpads/decoders, and inspect Gestures. Disable conflicting native three/four-finger actions yourself if necessary.
2. Choose **30sec test**, lift all fingers once, then try two-finger pointer movement and a two-finger primary tap.
3. Try a close three-finger row drag; lift one/two fingers while dragging, then release all fingers. The button must release. Try a stationary three-finger tap for double-click.
4. Try four-finger scrolling/panning and coast; touch again to brake. Check both directions in your actual applications.
5. Type with the other pad during a gesture. Change a tap action to Secondary Click and verify the assignment. Repeat on each selected pad/transport as available.
6. Use **Ctrl+Alt+R** during drag/coast and verify immediate release/status update. Verify the 30-second expiry too. Keep takeover off until these checks are satisfactory.

No driver/device/input-setting changes or speculative hardware commands are part of this port.


## Follow-up findings: 2026-10-23 user feedback

The user reports that four-finger scrolling and the three-finger recognition feel good; scrolling runs opposite their preference, and the initial fixed pointer/drag response feels poor. This update adds configurable direction and Apple reference acceleration. The three-finger activation geometry is unchanged from Mac; the visible label is now simply "3-finger movement" with the compact-row explanation in its tooltip.

### Importing the user's Mac settings later

No driver binaries are required. From the repository root on the Mac, run the existing read-only snapshot helper:

```sh
# Preserved Apple acceleration equations and provenance: mac/RESEARCH_ARCHIVE.md
```

Copy `pointer-settings.json` to Windows, choose Left/Right/Both in Gestures, and use **Import Mac tracking profile…**. When the snapshot contains multiple devices, select the desired profile. Successful import selects the imported response; later choose Mac reference or Fixed to compare. The app stores only profile parameters/device ID, not the snapshot's serial/OS metadata. Snapshot values are provider/global observations and may differ from user/service overrides used by the live Mac reader; if the imported response differs, a targeted export through the live reader is the next check. No Mac access is needed to use the reference preset now.

### Richer Windows scrolling: promising, separate experiment

Microsoft documents fine wheel deltas smaller than 120, so "wheel-based" does not mean notch-only. Our current adapter emits high-resolution deltas and supplies its own momentum; application handling still varies. [WM_MOUSEWHEEL documentation](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-mousewheel).

There is also a newer touchpad-specific route: [CreateSyntheticPointerDevice2](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-createsyntheticpointerdevice2) supports PT_TOUCHPAD with physical dimensions, unlike the older creation API. Microsoft's [Precision Touchpad Programming Guide](https://learn.microsoft.com/en-us/windows/win32/input-precisiontouchpad/precision-touchpad-guide) shows a gesture-only synthetic touchpad plus InjectSyntheticPointerInput. The guide is marked pre-release; the creation API lists Windows 11 without identifying an exact build floor.

A read-only module/export check on this computer (reported OS 10.0.26300.0) found `CreateSyntheticPointerDevice2`, `InjectSyntheticPointerInput`, `InjectTouchpadAction`, and `RegisterTouchpadCapableWindow` in user32.dll. No synthetic device was created and no pointer/touchpad input was injected by this research check. Export presence does not prove successful creation, usable privileges, correct routing, or compatibility with Mouse Takeover.

This is worth an isolated, opt-in scrolling experiment. Convert AppleMagicTouchstream's recognized Scroll action into a synthetic two-contact pan on a gesture-only touchpad, then measure target-app behavior, direction, inertia, hook treatment of synthetic output, emergency release and cleanup. Native inertia must be reconciled with our own coast to avoid double momentum. Keep the currently accepted wheel path available while evaluating it. This is a user-mode API candidate, with no new .sys or Zadig binding proposed; successful operation without elevation remains unverified. No production scrolling transport was changed in this update.


## Fast pointer/drag continuity fix

User hardware feedback: Apple reference acceleration improved the feel, but fast two-finger movement began moving and then stopped/skipped until release. Code review found that the 150-pixel per-frame screen-space guard rejected legitimate accelerated output: Millimetres returned no delta and the router cancelled/blocked the entire contact cycle. The native output adapter also rejected steps at this threshold. This is a concrete code path matching the symptom, independently reproduced by offline slow/fast/slow vectors; the corrected build still needs the user's live check.

The 150-pixel rejection is removed from pointer movement and drag. Large finite accelerated deltas preserve ownership and flow through to output. Pathological gains are bounded to 4096 pixels per frame with direction preserved, without dropping a frame or cancelling ownership. Non-finite values, contact-ID discontinuities, stale input, physical contact jumps of 25 mm or more per axis, emergency release and all-up cleanup retain their protections. Scroll behavior is unchanged.

Regression coverage includes two-finger pointer and three-finger drag sequences with successive 5 mm accelerated intervals exceeding 150 pixels, then a slow interval without lifting. All motion intervals must be delivered; drag must remain held until all-up, with exactly one final release and no tap. Bounds are also checked for large/extreme finite values. Apple numerical golden vectors remain unchanged.

Fast-motion fix verification: Release build and all self-tests passed (zero warnings/errors). The running app locked the normal Release output, so the complete corrected application was built to `bin/FastMotionFix/AppleMagicTouchstream.exe`. Exit the existing tray instance before opening this build. The next hardware check is slow/fast/slow two-finger movement and three-finger dragging without lifting in between.


## Two-finger tap landing fix

The user capture exposed two short taps whose first finger shifted as the second landed. The pending router incorrectly counted that interval toward two-finger activation. With a tap assigned, a newly formed pair now establishes its own movement baseline. Already-latched motion and tap=None behavior remain unchanged; no timer or threshold increase was added. Full capture replay repairs both taps and preserves all 14 longer movement activation frames. See [capture analysis and verification](WindowsDiagnostics/TapCaptureAnalysis/FINDINGS.md).

## Three-finger drag versus four-finger scroll settling

The user reported unintended folder dragging while landing four fingers to scroll. Previously, three contacts moving 0.35 mm could latch PrimaryDrag before the fourth contact arrived. Once latched, ownership correctly stayed with drag until all-up, making that early classification hazardous.

When a hand assigns three-finger movement to PrimaryDrag and four-finger movement to Scroll, an unowned three-finger chord now waits 120 ms with stable contact identities before drag can activate. Early travel is discarded rather than replayed as a cursor jump. Movement must still cross the existing 0.35 mm threshold after settling; elapsed time alone never presses the button. Contact count or identity changes restart settling. Seeing four or more contacts before ownership prevents three-finger drag for the remainder of that touch cycle, including when fingers lift before scroll has activated.

A newly formed four-finger chord establishes a fresh motion baseline, like the two-finger tap landing fix. Its existing 0.2 mm activation threshold, direction, sensitivity and momentum remain unchanged. The three-finger tap recognizer receives every frame with its original timing and slop. No delay applies when the drag/scroll assignment conflict is absent. An already-owned drag still latches until all-up; a fourth finger arriving after activation does not change its action.

Offline regressions cover both hands, staggered moving landings, four-to-three lifting without scroll ownership, fresh movement after settling, balanced drag release, three-finger taps, contact replacement, stale pending input, and the existing recorded two-finger tap capture. Release build and the full self-test suite pass. The 120 ms duration is an initial tuning choice, not a hardware-proven guarantee; a fourth finger arriving after the deadline and drag activation can still arrive too late.

Live check: use a blank test surface to alternate four-finger scrolling and deliberate three-finger dragging, then verify three-finger taps. If unintended dragging remains or the delay feels wrong, capture those alternating actions for timing analysis. No new capture is required before trying this build. The separate Release executable is `bin/ScrollSettle/AppleMagicTouchstream.exe` because the running application locked the previous output folder.

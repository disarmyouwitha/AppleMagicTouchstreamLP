# Tomorrow's GlassToKey capture session

**Latest native-input takeover research:** [DriverKit USB/Bluetooth checkpoint, 2026-10-18](DRIVERKIT_TAKEOVER_CHECKPOINT.md). Full contact delivery succeeded with SIP enabled on both transports; integration remains pending.

For the next session after native-parser research, use the [AMT follow-up test plan](AMT_FOLLOWUP_TEST_PLAN.md). It prioritizes independent scalar preservation, strength/area, coordinate/velocity calibration, ellipse orientation, and contextual label revisions. The instructions below document the earlier session.

Use **GesturePad** for this first session. The new `RewriteProbe` tool reads saved `.atpcap` files offline; it never posts keys, moves the pointer or changes recognizer settings. Native macOS trackpad movement can still happen while recording.

The goal is to check the assumptions a rewrite would depend on: stable contact lifetimes, usable raw identity/pressure data, ordinary hold drift, staggered landings and partial lifts. These are input-observation checks. They do not yet test a new typing recognizer, native mouse suppression or exact TouchStream behavior.

The [setup verification](VERIFICATION.md) records the original prepared build and tests. The first human session is now recorded: read [CAPTURE_FINDINGS.md](CAPTURE_FINDINGS.md) for the seven-capture review, label revisions and gesture-latching distinction. The current package has28 passing tests.

The second session is also reviewed: [partial lift, palm-held cohorts and independent-pad rearm](LIFECYCLE_CAPTURE_FINDINGS.md). It provides four more replay fixtures, including a continuous palm-like contact whose raw code changes6↔1 and includes unknown12. These are input observations for the next shadow-owner implementation, not gesture decision tests.

## 1. Start the raw-contact application

Quit the keyboard/reference GlassToKey apps first so they do not also process the same touches. Open the gesture playground's Xcode project and run its **GlassToKey** scheme, or use the Debug app prepared for this session if present:

```text
/Users/nap/Library/Developer/Xcode/DerivedData/GlassToKeyRewriteValidation/Build/Products/Debug/GesturePad.app
```

In Config, select the trackpad we will test and confirm its dots/traces respond. Use one pad for the initial six captures. The playground is intentionally not a typing app and has no new recognizer to enable.

Create this folder if it does not exist. In a save dialog, Command-Shift-G jumps directly to it:

```text
/Users/nap/Documents/AppleMagicTouchstreamLP/mac/gesturepad/RewriteValidation/captures
```

## 2. Record one short trial per file

From the menu bar choose **Capture...**, save under the exact name below, and wait about a second with all fingers off. Perform the task, lift everything, wait another second, then choose the menu's stop-capture action. The quiet start/end helps distinguish a complete contact from a recording cut through a touch.

| Filename | Task |
| --- | --- |
| `01-index-taps.atpcap` | Ten separate index-finger taps, at a comfortable pace. Lift fully between taps. |
| `02-thumb-taps.atpcap` | Ten separate thumb taps in the same area. Lift fully between taps. |
| `03-stationary-hold.atpcap` | Put one index finger down, hold still for two seconds, then lift. |
| `04-one-finger-motion.atpcap` | One index finger slides about 3 cm over roughly a second; then lift. |
| `05-staggered-partial-lift.atpcap` | Index down; wait about 200 ms; middle down. Hold/move both. Lift index while middle remains for half a second; then lift middle. |
| `06-palm-observation.atpcap` | Rest a comfortable edge of your palm for two seconds, then lift. No forceful pressure needed. |

Do not adjust thresholds to make reports pass. These files record what actually happened. If a trial is interrupted, keep it under a different filename and repeat the planned one. For a later held-out evaluation, copy the plans into a new session folder and use new captures, rather than tuning on the same six recordings indefinitely.

The plan assumes the tested pad is capture **deviceIndex 0**. Confirm this after the first recording:

```sh
cd /Users/nap/Documents/AppleMagicTouchstreamLP/mac/gesturepad
swift run RewriteProbe --inspect RewriteValidation/captures/01-index-taps.atpcap --device-index 0
```

If `activeSamples` is zero, repeat with `--device-index 1`. Put the active index into every trial in `session.json` and `session.movement.json`. If neither has activity, check device selection/capture before continuing. An index identifies capture routing, not anatomical left/right.

## 3. Run the checks

Double-click **Run Checks.command**, or run:

```sh
cd /Users/nap/Documents/AppleMagicTouchstreamLP/mac/gesturepad
swift run RewriteProbe --plan RewriteValidation/session.json --output RewriteValidation/reports
```

Read `RewriteValidation/reports/report.md`. Detailed lifetimes and pressure ranges are in `report.json`; capture SHA-256 values bind results to the input files. The report's plan hash binds its exact assertions and dimensions too.

- **pass** means the recorded contact pattern meets that stated observation check.
- **fail** means it differs: for example, ten intended taps did not yield ten tracked lifetimes, or a raw identity code changed during the hold. We inspect the capture before deciding whether this is a tracker issue, a mistaken trial or an invalid hypothesis.
- **inconclusive** means the required recording, selected-device activity, metadata or physical calibration is unavailable, or a continuity problem prevents a reliable check. It never counts as a pass.

Exit codes are 0 for all checks passing, 1 for an observed mismatch, 3 for missing/inconclusive data, and 2 for invalid input. Before you record, exit3 is expected. A corrupt/unsupported capture is an input error, not a passing trial.

## 4. Calibrate before testing millimetres

Raw normalized coordinates are not verified physical distances. `widthMM` and `heightMM` are intentionally null. Supply independently verified **active sensing-area** width and height, not outer case dimensions, in `session.movement.json`; use the same calibration for `session.json` if desired. Do not infer millimetres from the telemetry's unverified `absoluteX/Y` fields.

Then run:

```sh
swift run RewriteProbe --plan RewriteValidation/session.movement.json --output RewriteValidation/reports-movement
```

This checks whether the hold stays within the current keyboard experiment's 3 mm boundary and the deliberate slide exceeds 10 mm. Three millimetres is the existing experimental boundary; 10 mm is a stimulus check. Neither is established as an optimal setting. Without both dimensions, the movement results remain inconclusive.

## 5. What we will look at together

First compare intended index/thumb/palm trials with `rawFingerIDs`. The UI convention 1=thumb through 6=palm is not independent proof that Apple's raw codes have those meanings. Check within-contact relabeling, ID reuse, and how a palm is segmented.

Then inspect pressure range/peaks and hold drift. Pressure is a raw device metric; no FingerWorks pressure coefficient is used. Staggered landing and partial lift observations tell us which contact timelines a cohort state machine must handle. We can then build shadow typing/chord proposals and test explicit intent labels, before enabling new output.

The analyzer counts `starting`, `making`, and `touching` as active, matching this playground. An explicit inactive-state record closes a contact; disappearing from a frame closes it as **uncertain**. Gaps over 100 ms while active, regressing timestamps, duplicate IDs and invalid samples make checks inconclusive. The gap budget is a declared data-quality hypothesis, not a recovered firmware debounce constant. A contact present at recording start or still down at the end is censored. Identity changes do not manufacture a fresh contact. A new lifetime after absence receives a new generation.

Landing spread is measured within an uninterrupted nonempty episode; it is not a recovered chord-acquisition rule. A failing finger-label-stability check does not itself imply a bug: it can show that identity must remain soft evidence. Native event suppression/delivery, output balancing and actual intended-key accuracy remain separate integration tests.

## Optional terminal-only capture

The existing capture tool can record without the app UI:

```sh
swift run ReplayFixtureCapture --duration 12 --max-frames 10000 \
  --output RewriteValidation/captures/01-index-taps.atpcap
```

It selects the first two available devices and does not capture the app's layout/settings. Prefer the app flow for the first session so device routing is explicit. Wait for the tool to begin before touching; verify a nonzero frame count and correct device index afterward. No scheduled or automatic recording was installed.

# Move–tap capture analysis

2026-10-20. User recording: `captures/2finger_tap.atpcap`.
SHA-256: `b2a420be66d2de32b022c8e53fa49053c116ee492c05e634bc2e5aac95351002`.

The reported task was rapid left-move/click/right-move/click, with missed taps
and a less immediate feel than FingerWorks. Replay confirms an arbitration
problem: small tap drift crosses the mouse-start threshold before release.

## Evidence and limits

The capture contains 1559 frames over 25.672 seconds from right-pad native ID
`288230377507875157`, with 55 nonempty-to-all-up cycles. Production replay uses
`ReplayFixtureParser` and the actual `TrackpadGestureRouter` and
`TwoFingerTapRecognizer`, without posting events. Contact timing/state used by
the parser supplies the table below; raw container records can have different
release/hover timing than the parser's canonical frames.

This recording contains contacts, not actual posted click timestamps, application
responses, native mouse-button suppression state, or a per-tap intention label.
Consequently these are **predicted recognizer outcomes**, not proof of how many
clicks the application delivered. A small-motion cycle is not inherently a tap;
we compare the independent tap recognizer and retain conservative motion rejection.

| Mouse initiation threshold | Predicted clicks | Clear movement cycles (> 8 mm individual travel) | Clicks during those movement cycles |
| --- | ---: | ---: | ---: |
| 0.20 mm, old | 19 | 29 | 0 |
| 0.35 mm, new test | 25 | 29 | 0 |
| 0.50 mm | 25 | 29 | 0 |
| 0.75 mm | 25 | 29 | 0 |
| 1.00 mm | 25 | 29 | 0 |

The independent tap recognizer, without movement arbitration, accepts 25 cycles.
At 0.20 mm, six of these are instead claimed by mouse recognition:

| Cycle | Start relative to capture | Canonical duration | Largest individual displacement |
| --- | ---: | ---: | ---: |
| 12 | 4.520 s | 58 ms | 0.313 mm |
| 14 | 5.275 s | 100 ms | 0.264 mm |
| 16 | 6.062 s | 248 ms | 0.496 mm |
| 26 | 9.662 s | 44 ms | 0.294 mm |
| 40 | 14.847 s | 90 ms | 0.221 mm |
| 44 | 16.388 s | 67 ms | 0.463 mm |

The 500 ms tap maximum is not the main problem. These cycles satisfy all tap
limits and are rejected because the old 0.20 mm common-motion threshold claims
mouse first. Cycle 30 remains ambiguous and rejected: about 234 ms with 1.164 mm
individual motion, beyond the 1 mm tap limit. The change does not relabel it a tap.

## Next test build

Set **only mouse initiation to 0.35 mm**, the smallest tested value that recovers
all six otherwise-valid tap cycles. Scroll stays at 0.20 mm. Keep the 500 ms
maximum, finger timing/slop rules, existing latches, accelerated response and
no-click-after-recognized-mouse rule. Do not retroactively click when a short
recognized mouse gesture ends.

This is an input-distance threshold, not a fixed wait. In the 29 clear movement
cycles here, median mouse initiation moves from about 22.3 to 33.8 ms after the
first active contact. Once latched, fine movement and acceleration are unchanged.
A click still fires at all-up, not after waiting for the 500 ms maximum. Earlier
click-on-contact would be a different gesture commitment/output design and has
not been implemented by this tuning.

## Reproduction

Run from the repository root with the local recording available:

```sh
mkdir -p mac/gesturepad/build/TapCaptureAnalysis
TAP_CAPTURE_REPORT="$PWD/mac/gesturepad/build/TapCaptureAnalysis/threshold-comparison.json" \
  ./mac/gesturepad/test.sh --filter TapCaptureAnalysisTests
```

`TapCaptureAnalysisTests.swift` checks the old/new click counts and that every
clear movement cycle still claims mouse with no tap clicks. It writes per-cycle
JSON when requested; it skips if the unbundled local recording is missing.
The local analysis also saved `build/TapCaptureAnalysis/cycles.csv` for inspection.
Synthetic unit tests separately verify that 0.24 mm landing drift can remain a
tap while 0.48 mm common motion claims mouse and prevents a click on release.
No tests open a FLTR session or post clicks.

## Better hardware follow-up

The user's existing move–tap recording is already a useful test. On the updated
build, one capture with three separated blocks will make failures easier to label:

1. Ten stationary two-finger taps at a comfortable pace; leave a clear all-up gap.
2. Ten repetitions of move left, lift all, tap; move right, lift all, tap, at the
   same fast pace as this capture. Do not deliberately slow down to help it.
3. Ten short mouse strokes followed by lift, with **no intended tap**. These must
   not click.

Leave about two seconds untouched between blocks. Report intended tap counts,
observed clicks/misses in each block and whether mouse initiation feels worse.
Use a blank document area or an on-screen click counter to distinguish event
count from multi-click selection behavior. A small screen recording alongside
the contact capture would help locate any remaining individual misses, but it
is not required for the next test.

Do not use a new tap to stop momentum in this particular comparison: braking is
intentionally excluded from clicks. Hardware button presses or a pad that never
reaches all-up can also legitimately prevent a tap. Those conditions cannot all
be established from this file alone.


## Follow-up: 2finger_tap_test2.atpcap

The user reported that the updated build feels substantially better. The follow-up
contains 1352 frames across 31.126 seconds from the same right pad, with 45
completed active-contact cycles. SHA-256:
`a33a652e5e61aa6944246f98c4eb3cb00ed8336f282cdffa88fe940f50dfc50f`.

| Mouse threshold | Predicted clicks | Cycles classified as movement |
| --- | ---: | ---: |
| Old 0.20 mm | 17 | 28 |
| Current 0.35 mm | 22 | 23 |
| 0.50, 0.75 or 1.00 mm | 22 | 23 |

The temporal pattern is consistent with the requested test blocks:

| Apparent block | Time relative to capture | Replay result at 0.35 mm |
| --- | --- | --- |
| Stationary taps | 0.009–5.724 s | 10 cycles, 10 predicted clicks |
| Alternating move/tap | 7.784–17.042 s | 12 move cycles and 12 predicted tap clicks |
| Mouse strokes without tapping | 18.706–30.947 s | 11 movement cycles, zero predicted clicks |

The block labels are inferred from the contact pattern, not an embedded intention
annotation. Every cycle accepted by the independent tap recognizer is also
accepted with current movement arbitration. None of the 23 cycles classified as
movement produces a click. The older threshold would lose five of the successful
tap cycles. Larger tested thresholds recover no additional taps, so **retain
0.35 mm**; no runtime behavior change is warranted by this capture.

These results predict recognition, not actual application click delivery. The
capture still does not record posted button events or physical suppression state.
The user's improved-feel observation supports this tuning; it does not prove
all application/lifecycle edge cases are resolved.

The follow-up is now covered by
`testFollowupCaptureAcrossMouseInitiationThresholdsWithoutPosting`: initial ten
taps, final eleven no-click strokes, 22 accepted clicks and no loss against the
isolated tap recognizer. To export the detailed local report:

```sh
TAP_CAPTURE_REPORT2="$PWD/mac/gesturepad/build/TapCaptureAnalysis/test2-threshold-comparison.json" \
  ./mac/gesturepad/test.sh --filter TapCaptureAnalysisTests
```

No app rebuild or reinstall is needed for this analysis-only follow-up.

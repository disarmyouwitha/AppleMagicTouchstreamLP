# Mac touch telemetry investigation

The config visualizer can inspect the raw identity, position, and velocity
fields supplied by the private Mac MultitouchSupport callback. These are
measurements to investigate, not verified anatomical finger classifications.

## Live inspection

1. Open Config with the intended left/right devices selected.
2. Enable **Inspect touch data** above the visualizer. Each contact shows its
   tracking ID (`#`), raw finger code (`F`), and raw hand code (`H`). Color follows
   tracking ID, not inferred anatomical identity. Arrows show the direction of
   supplied normalized velocity; their lengths do not indicate speed.
3. Open **Live values…** for the full contact list, including contact states,
   normalized position and velocity, absolute position and velocity, source
   frame/time, axes, angle, total capacitance, density, and pressure.
4. Use **Freeze in 3s** to place both hands on the pads before taking a snapshot.
   **Freeze/Resume** controls immediate sampling; **Copy JSON** copies the
   displayed snapshot, including raw telemetry, for comparison.
5. Use the existing menu **Capture…** workflow for sequences spanning multiple
   frames. Display inspection samples at 10 Hz; Capture records processed input
   frames independently of the inspector display rate. The visualizer itself
   continues to use its existing throttled rendering path.

## Suggested experiments

- Place just the left index finger on one pad, lift, and repeat. Then do the
  same for each other finger. Record which pad, actual finger, and raw F/H codes.
- Keep one finger down and add the other fingers. Watch whether its tracking ID
  remains stable while F/H codes change.
- Repeat with the opposite hand on the same pad. This distinguishes hand codes
  from pad identity. A device assigned as the left pad is not proof that the
  contact is from the left hand.
- Slide horizontally and vertically. Check supplied velocity signs and whether
  absolute position scales linearly with normalized position.
- Compare hovering, first contact, resting, pressing, and lift-off states.
- Repeat after lifting/replugging and on each available device model.

Raw zero IDs are retained as zero. We do not label them "thumb", "left hand",
or "unknown" until observed behavior supports that interpretation. A missing
telemetry object means the source did not record the fields. Absolute units,
velocity scaling, and identity meanings are not yet calibrated. FingerWorks
SDK enum values are not assumed to apply to Apple's private API.

## Data path and recording compatibility

`MTTouch` → `OMSRawTouch.telemetry` → runtime capture / render snapshot →
`OMSTouchData.telemetry` → config visualizer and inspector.

The optional `telemetry` object includes `fingerID`, `handID`, `velocityX/Y`,
`absoluteX/Y`, `absoluteVelocityX/Y`, `sourceFrame`, and `sourceTimestamp`.
It is copied as value data before callback memory is released. The Objective-C
bridge ABI and generated XCFramework are unchanged.

New app captures and ReplayFixtureCapture recordings include the optional
object in the existing v5 JSON contact records. Older recordings still decode;
their missing fields appear as unavailable. ReplayFixtureKit reads and writes
the same additive object, including when transcoding captures. Older software
may ignore/drop the additional fields when rewriting a file.

The telemetry does not change key dispatch, gesture decisions, or the engine's
existing velocity calculation. No finger names or new gesture behavior are
inferred from these fields.

## Verification

`swift test` covers callback-field copying, zero/signed identities, old-record
compatibility, capture round-trip preservation, and committed replay baselines.
Build the Mac app with:

```sh
xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey \
  -configuration Debug -destination 'platform=macOS' build
```

Live identity semantics must still be established using the experiments above.

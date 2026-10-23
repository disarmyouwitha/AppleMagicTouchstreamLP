# Force-click haptic investigation

2026-10-22. Scope: AppleMagicTouchstream only. No firmware writes or live actuator
sweeps were performed. The user reported that the first one-finger force-click
experiment worked, but its feedback felt as loud as typing.

## Why the old strength control was misleading

`Sources/OpenMultitouchSupport/OMSManager.swift` maps a normalized strength `s` to
an actuation ID `1 + round(5s)`, then calls `MTActuatorActuate` with first float
`10 + 20s` and second float zero. The previous force-click strength 0.15 therefore
selected ID 2 and sent **13**, while typical typing settings sent 18–30. Neither
was a calibrated amplitude percentage. Changing strength also changes waveform,
which confounds comparisons.

The user's archive contains Apple's actual native-framework disassembly:

`/Users/nap/Documents/new_code/touchstream-archive/driver-analysis/mac-native-15.7.4-24G517/rea-native-2026-10-17/framework-inventory/MultitouchSupport-disassembly.txt`

The archived and currently installed x86_64 MultitouchSupport UUID both equal
`B172DB85-9E88-3A4E-AB6E-B458FD373A58`. Relevant functions/unslid addresses:

- `MTActuatorActuate`, `0x7FF81278B148` (archive line 28494): checks ID <= 36,
  looks up a loaded actuation, and passes both float arguments into
  `MTActuationActuate`. An ID in range does not guarantee a loaded waveform.
- `MTActuationCalculateWaveform`, `0x7FF81278C49C` (line 29748): duplicates the
  first float, optionally applies actuation-specific factors selected by flag
  bits 1/2/4, then uses `minps` against an upper-bound vector. Negative components
  are treated as zero. The app keeps flags zero, as before.
- The bound at `0x7FF8127905E0` is **[2.0, 2.0, 0, 0]**. Verified by read-only
  memory inspection after loading the matching installed framework and resolving
  `MTActuatorActuate`; no actuator/device function was called for this inspection.
- `MTActuationFillParametricBufferWithWaveform`, `0x7FF812786E56` (line 24052),
  applies those scales, then actuator-specific lower/upper limits and integer
  waveform encoding. Quantization and device minimums can flatten nearby values.
- `MTActuationActuate`, `0x7FF81278C6FD` (line 29921), builds a maximum-60-byte
  waveform and sends it via `MTActuatorSetWaveform`, report 0x53.

This establishes that the old 13–30 values exceed the same 2.0 framework ceiling
on this inspected build. It explains why lowering the old setting could make
little difference. It does **not** establish a linear relationship between this
argument and acoustic volume, vibration strength or perceived click intensity.
Earlier code called the argument “sharpness”; that name was not verified.

## Final settings after hardware testing

The user confirmed the bounded controls worked and selected these settings:

- Force clicks: **waveform 6, level 0.25**, hardcoded for every finger count/action.
  Waveform/level controls and the test button are removed. Old saved experimental
  values remain decodable but cannot change live force-click feedback.
- Typing: fixed **waveform 6**, with **Haptic Strength** adjustable from 0 to 2 in
  0.01 steps. Zero is off. This replaces the Off/Weak/Medium/Strong slider.
- Existing profile/defaults field naming and level ×100 encoding are retained;
  old strength 60 resolves to 0.60 and a new level 1.50 saves as 150. This is a
  waveform parameter scale, not calibrated loudness percent. The engine and
  dispatcher both allow the full 0–2 scale. Replay remains recording-only.

## Initial bounded-control experiment (historical; controls now removed)

Gestures → each finger-count section contains Force-click feedback controls:

- Waveform: IDs 1–6, the existing app's range, now independent of level.
- Level: 0–2 in 0.01 increments. Zero skips the pulse entirely.
- Default: waveform 2, level 0.50. This is a hardware-test starting point.
- Test haptic: one user-requested pulse per selected/owned pad, deduplicated, with
  a 250 ms test cooldown. Requires active, armed takeover. Moving a control never
  pulses hardware. Success means the API accepted the request, not that the user
  must have felt it.

Values persist per hand with gesture settings. Editing Both preserves the other
parameter independently on each hand. The live force-click path requests at most
one pulse per touch cycle, with a per-device 50 ms minimum interval, and executes
feedback outside the gesture-state lock. Typing feedback is unchanged. Replay
never calls this live output path. This is an existing private framework API,
not a newly supported/public amplitude interface.

## Comparison procedure used for the experiment (historical)

1. Keep one waveform selected (start with 2). Compare levels 0.25, 0.50, 1.00 and
   2.00 using Test haptic. Then refine nearby levels with the slider. Compare on
   each transport/trackpad independently; no “half as loud” claim is made yet.
2. Try level 0 and physically force press. If a click sensation remains, that is
   evidence of a separate native/hardware contribution; compare the isolated
   test-button pulse with the physical press before adding more software feedback.
3. If levels all feel alike, record waveform, level, model, transport, API result
   and whether this was a test-button pulse or a pressure-triggered pulse. Compare
   another waveform rather than assuming every valid ID has the same semantics.
4. Next research target if needed: trace actuator-specific min/max calibration and
   its actuation dictionaries in the native framework/driver. FingerWorks firmware
   is a different device and is not evidence for Apple actuator parameters.

The archive also contains `MagicTrackpad2ForWindows/.../Device.c` functions that
program firmware down/up reports 0x22/0x23. Those configure a different path from
our one-shot host pulse; their byte settings were not transplanted or written.
We do not need a new firmware implementation to test the exposed bounded scale.

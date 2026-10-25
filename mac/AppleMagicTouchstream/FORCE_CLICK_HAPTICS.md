# Haptic feedback

## Current settings

- Force clicks: fixed waveform **6**, level **0.25**, for all counts/actions.
- Typing: fixed waveform **6**, Haptic Strength **0–2** in **0.01** steps; zero is off.
- Saved strength retains level ×100 encoding: 60 → 0.60, 150 → 1.50.
- Old experimental force-feedback fields remain readable but inactive.
- Feedback targets the originating selected pad. Force pulses are once per owned
  cycle and at least 50 ms apart per pad; replay is recording-only.

The level is a bounded waveform parameter, not calibrated volume or force. Nearby
settings can feel similar because device quantization and minimum limits also apply.
Waveform and level are independent parameters in the live path.

## Native framework evidence

The research archive contains Apple's actual native-framework disassembly:

`/Users/nap/Documents/new_code/touchstream-archive/driver-analysis/mac-native-15.7.4-24G517/rea-native-2026-10-17/framework-inventory/MultitouchSupport-disassembly.txt`

The archived and inspected installed x86_64 MultitouchSupport UUID both equal
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


This inspected framework clamps the waveform scale at 2.0. It does not establish
a linear relationship between level and acoustic volume or perceived click intensity.
The disassembly and read-only bound inspection did not write firmware or activate
an actuator. Future calibration would need waveform-specific device measurements.

The archive also contains native Windows device code for firmware down/up reports
0x22/0x23. Those reports configure a different path from the host pulse and are not
applied by the app.

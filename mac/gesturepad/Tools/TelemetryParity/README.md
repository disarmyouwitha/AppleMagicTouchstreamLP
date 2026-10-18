# Compact V7 telemetry parity research tools

These tools are offline reference/validation tools, **not shipped inside GesturePad**.
They require Intel macOS with installed MultitouchSupport UUID
`B172DB85-9E88-3A4E-AB6E-B458FD373A58` (8440.5, tested macOS15.7.4/24G517).
They refuse a different UUID. SIP remains enabled. No HID seizure, report write,
mode command, MTDeviceStart, kernel hook, or driver activation occurs.

## Validate a fresh takeover capture

```sh
python3 mac/gesturepad/Tools/TelemetryParity/compare-capture.py \
  mac/gesturepad/RewriteValidation/captures/telemetry_parity_takeover.atpcap \
  --out /tmp/GesturePad-telemetry-parity-result.json
```

The script bounds-checks the v5 container and reads conversionVersion2 contact
bytes/timestamps. It compiles the native oracle into a temporary directory and
feeds the **same bytes** through Apple's mapped unpack/fill/velocity routines.
It compares every currently exposed contact scalar and identity/state/position/
velocity vector. It never rewrites the capture. Exit0 means no numeric mismatches
within0.00002 float tolerance; exit1 reports mismatches. Earlier takeover captures
without conversionVersion2 bytes cannot establish this comparison retrospectively.

The native reference shares the app's selected sensor parameters and reset decisions
(first contact, packet gap, stale frame), because those are explicit host safety
boundaries. This is a same-packet numerical decoder comparison, **not** a simultaneous
native OMS callback recording or proof of every native lifecycle/filter behavior.
Per-session frame counter origins naturally differ from the old native listener.

## Regenerate the independent test fixture

```sh
xcrun clang mac/gesturepad/Tools/TelemetryParity/native-reference.c \
  -framework CoreFoundation -o /tmp/GesturePad-native-reference
/tmp/GesturePad-native-reference > /tmp/CompactV7NativeReference.json
```

The default reference mode evaluates256 values for each scalar byte,576 density
cases,256 complete filled contacts and96 two-frame velocity/state/extra-bit/edge
cases. It also creates private MTDevice references and initializes only its own
userspace algorithm state to read device calibration; it never starts listeners.
Native library initialization prints are redirected during that local initialization.
The checked-in numeric fixture lives in
`Tests/ProductionEngineTests/Fixtures/CompactV7NativeReference.json` and is exercised
by `CompactV7NativeParityTests`. The test fixture contains output data, not Apple
executable bytes. Runtime GesturePad uses a Swift reconstruction and never calls
these private addresses.

The `--stream` mode used by compare-capture does not create device references or
initialize algorithms: it uses synthetic contact structs and known calibration.

## Native provenance

Earlier analysis retained the full installed-framework disassembly in the local
research archive:
`/Users/nap/Documents/new_code/touchstream-archive/driver-analysis/mac-native-15.7.4-24G517/rea-native-2026-10-17/framework-inventory/MultitouchSupport-disassembly.txt`.
The UUID and native anchors, relative to the framework Mach header, are:

| Function | Offset | Purpose |
| --- | --- | --- |
| MTCompactV7BinaryContactUnpack | 0xe7b4 | Nonlinear scalar and bitfield unpacking |
| alg_ComputeContactDensityFromRadii | 0x1ac59 | Integer density |
| mt_FillMTContactDirectFromBinary | 0x16628 | Callback layout and scalar/vector conversions |
| mt_CalculateMTBinaryContactVelocity | 0x164fe | Quantized velocity |
| mt_InitializeAlgorithmsForDevice | 0x4599 | Reference-only local calibration state |

The decoder entry prefix is checked before invoking any native reference function.
These offsets are research fixtures pinned to this framework UUID, not an API or
portable production technique. The portable Swift implementation and tests should
be reviewed if a future OS changes native behavior.

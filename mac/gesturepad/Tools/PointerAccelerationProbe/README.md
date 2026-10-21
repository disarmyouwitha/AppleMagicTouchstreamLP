# Pointer acceleration experiment

Standalone research tools for measuring how closely Apple's published parametric
acceleration can explain this Mac's native trackpad movement. No app features,
FLTR implementation, preferences or input output paths are changed by this tool.
See [the complete findings](../../POINTER_ACCELERATION.md) for Apple-code notes
and the first native recording analysis. See [SOURCES.md](SOURCES.md) for audited equations, pinned upstream sources,
installed-property findings and limits.

## First hardware recording

1. Uncheck **Trackpad Takeover**. Quit other pointer modifiers such as BTT for an
   isolated native baseline. Keep the chosen pad connected; leave tracking speed
   unchanged during the recording.
2. Run from the repository root (choose the serial/MAC shown in the pad selector):

   ```sh
   ./mac/gesturepad/Tools/PointerAccelerationProbe/record-baseline.sh D0:C0:50:D5:69:55
   ```

3. When BASELINE appears, use **one finger** on that pad for 20 seconds: slow,
   medium and fast strokes, lifting between strokes. Avoid display edges. Do not
   click, use other mice or change settings. Ctrl-C ends early and still saves data.
4. Send the printed `build/PointerAccelerationProbe/native.XXXXXX` session folder
   (settings.json, native.jsonl, session.log). No capture has been run automatically.

The recorder compiles locally, uses ordinary MTDeviceStart(...,0), refuses an
existing/unreadable filter owner on the selected pad, and installs a **listen-only**
session event tap. It never opens FLTR, seizes HID, posts input, warps the cursor,
changes acceleration, requests sudo or disables security. Enable Input Monitoring
for the terminal/Recorder in System Settings if its preflight reports it missing;
it does not request permissions automatically. Other native clients can coexist,
but quit competing input modifiers to obtain a useful baseline.

Why one finger: with native input enabled, two fingers normally scroll or pinch;
they do not provide a baseline for native cursor pointing. Once the downstream
transfer function is measured, a separate experiment can feed it two-contact
centroid deltas under FLTR. No pointer/scroll/pinch/drag output is implemented here.

## Offline use

Requires Python 3 (stdlib only); macOS/Xcode command-line tools for the recorder.

Read currently installed registry curves/settings, without opening a device:

```sh
python3 -B mac/gesturepad/Tools/PointerAccelerationProbe/acceleration.py snapshot \
  --output /tmp/pointer-settings.json
```

Build only, without recording or device enumeration:

```sh
./mac/gesturepad/Tools/PointerAccelerationProbe/build-recorder.sh
./mac/gesturepad/build/PointerAccelerationProbe/Recorder --help
```

Convert a recorder session to contact displacement in mm plus observed native
cursor deltas. Width/height must describe the normalized contact surface; 160 by
114.9 mm are the app's current assumptions and can be overridden:

```sh
PROBE=mac/gesturepad/Tools/PointerAccelerationProbe
SESSION=mac/gesturepad/build/PointerAccelerationProbe/native.REPLACE_ME
python3 -B "$PROBE/acceleration.py" prepare \
  --input "$SESSION/native.jsonl" --output "$SESSION/deltas.csv" \
  --width-mm 160 --height-mm 114.9
```

Predict from recorded deltas and score against the native movement:

```sh
python3 -B "$PROBE/acceleration.py" predict \
  --settings "$SESSION/settings.json" --device-id REPLACE_WITH_SESSION_DEVICE_ID \
  --input "$SESSION/deltas.csv" --units mm --counts-per-mm 15.7480314961 \
  --output "$SESSION/predicted.csv" --summary "$SESSION/comparison.json"
```

**The scale above is an explicit hypothesis: 400 / 25.4 counts per mm.** It has not
been established as Apple's conversion from OMS contacts. Supply a different
measured/fitted value when appropriate. `--acceleration` overrides the curve index
(e.g. 3.0), not a UI slider position. Never apply the same acceleration twice when
later designing an output path; these tools do not post events at all.

For external data, provide CSV columns `t,dx,dy` (seconds and pointer counts with
`--units counts`, or physical mm with an explicit scale). Optional `segment`
resets timing between strokes. Optional `native_dx,native_dy` enables scoring.
Output contains predicted floating cursor deltas and gain, plus sample vector
RMSE and per-segment cumulative displacement/error. It is a model result, not a
validated native-equivalence rating. File schemas/settings keys are not app
capture formats and are versioned independently.

## Measurement details and limits

Contact and pointer callbacks use the same receipt-time monotonic clock; original
native contact and CGEvent timestamps are retained for timing inspection. Events
include both their global Quartz positions and sampled current cursor positions.
`prepare` compares **event positions**, interpolated at contact receipt times, with
an optional explicit `--latency-ms` offset. It does not claim zero-latency pairing
or measure a display with a camera. It avoids pointer gaps over 100 ms, contact
gaps over 50 ms and samples within two points of display edges. It resets strokes
on contact-ID/count changes and uses only active single-contact frames.

The tap sees all session mouseMoved events. It does not establish physical-device
attribution for them, hence the isolated-pad protocol. Additional mice, synthetic
movement, pointer modifiers, screen clipping, run-loop latency and event coalescing
can contaminate a trial. Retain raw JSONL and inspect it rather than treating one
RMSE value as proof. Compare stroke totals and held-out trials as well as per-frame
errors; changing latency/scale can improve the fit without proving the algorithm.

Buffers are bounded; capture lasts at most 60 seconds. Data is written after
ordinary monitoring stops, outside the contact callback. Dropped samples, a disabled
tap or a failed native session invalidate `prepare`. Recorder paths are not overwritten.
Settings snapshots are provider/global values; an effective HID service override
may differ. Current pads expose parametric curves, so table fallback remains
outside this experiment. See the source audit for additional limits.

## Verification

```sh
cd mac/gesturepad/Tools/PointerAccelerationProbe
python3 -B -m unittest -v
```

Tests use analytic vectors for the polynomial/line/root branches and interpolation,
check fixed-multiplier/timing behavior, negative acceleration, units, subpixel/zero
movement, failure handling and synthetic recording alignment. They never access
hardware or change settings. Native fidelity still needs the user's recording.

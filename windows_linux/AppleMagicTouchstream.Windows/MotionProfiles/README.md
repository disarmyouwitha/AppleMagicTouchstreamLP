# Captured Mac motion response

`mac-motion.json` contains the live pointer and scroll curves read from both selected
Magic Trackpads on the source Mac, plus AMT's per-hand sensitivity and scrolling
direction. It excludes serial numbers, device paths, registry IDs and host names.
Both pads currently use pointer index 3, scroll index 0.5, 400-count resolution,
67 Hz scroll algorithm rate, sensitivity 1×, and non-natural scrolling.

## Try it on Windows

Build normally, open Gestures, select a Pointer/Drag or Scroll assignment, and enable
**Use captured Mac pointer and scroll** in the Action inspector. Turn on Mirror Edit
first to enable both hands together. This is an opt-in experiment: uncheck it to
restore the previous reference pointer curve and fixed 6-point/mm scrolling.

Enabling restores the captured sensitivity and natural-scrolling direction for
that hand. The existing sensitivity sliders and Natural scrolling checkbox then
remain adjustable. The choice saves/exports with settings. STENO pointer movement
also uses the selected hand's pointer profile and sensitivity.

Pointer and drag share one acceleration model. Captured scrolling adds Mac's
independent per-axis history and acceleration before the existing release-momentum
model. Touching either pad brakes released scrolling without clicking. Fractional
pointer and wheel output remains intact. No Windows mouse/driver settings change.

Pointer/Drag startup uses the same curve on each original movement sample while
recognition is pending. The resulting output is retained privately and published
once movement acquires; the accumulated physical distance is never accelerated
again as one fast sample. This prevents a nonlinear startup jump without changing
the curve, movement threshold, tap eligibility or an activated gesture's response.
New cohorts and cancelled/losing candidates discard pending output.

Windows wheel messages do not carry macOS pixel-scroll phases. Application wheel
handling, lines-per-detent settings and display scaling still affect the result;
this ports AMT's numerical response, not Apple's entire private input stack.

## Recreate the capture and parity fixtures

From the repository root on the source Mac, with both saved selected pads connected:

```sh
swift mac/AppleMagicTouchstream/Tools/MotionProfiles/export.swift windows_linux/AppleMagicTouchstream.Windows/MotionProfiles/mac-motion.json
python3 mac/AppleMagicTouchstream/Tools/MotionProfiles/generate-vectors.py windows_linux/AppleMagicTouchstream.Windows/MotionProfiles/mac-motion.json windows_linux/AppleMagicTouchstream.Windows/WindowsDiagnostics/Fixtures/CapturedMacMotionVectors.json
```

The exporter uses the same service/ancestor/HIDParameters precedence as the live
Mac readers. It reads settings only: it never opens a device, starts AMT, acquires
input, changes preferences, posts events or pulses haptics. It fails rather than
substituting another device if either saved selected pad is absent.

The generated fixture runs Mac's actual pure production models on both profiles
at three gains, including slow/subpixel travel, reversals, mixed-axis motion,
variable intervals and idle gaps (192 samples, four expected outputs each).

## Verification

Portable, no native input (Mac/Windows/Linux with .NET 10):

```sh
dotnet run --project windows_linux/AppleMagicTouchstream.Windows/WindowsDiagnostics/MotionProfilesOffline/MotionProfilesOffline.csproj -c Release
```

Windows build and full UI/recognition tests:

```sh
dotnet build windows_linux/AppleMagicTouchstream.Windows/AppleMagicTouchstream.Windows.csproj -c Release
dotnet run --project windows_linux/AppleMagicTouchstream.Windows/AppleMagicTouchstream.Windows.csproj -c Release -- --selftest
```

For hardware testing compare slow precision, quick sweeps, drag, vertical/horizontal
scroll, reversals, release coast and braking with the other pad. Test your browser
and editor separately. Confirm the option and per-hand gains survive restart and
settings export/import. Linux receives the shared model but its UI/runtime does
not automatically select the captured Windows resource.

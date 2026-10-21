# Acceleration source audit

The numerical experiment is informed by Apple's published IOHIDFamily source at
commit `777ccd9698845aadf711e32d843c8c9b777431d9`, retrieved 2026-10-20. Upstream
source files are not bundled or linked into the app. This is an independent,
small mathematical model plus a diagnostic recorder, not a claim that this source
revision is the exact implementation running on the installed OS.

Primary sources:

- [IOHIDAcceleration.cpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDEventSystemPlugIns/IOHIDAcceleration.cpp): `IOHIDPointerAccelerator::accelerate` floors the Euclidean delta magnitude, applies a timing factor **only when fixedMultiplier equals 1**, clamps velocity to at least 1/65536, then scales X/Y by accelerated velocity / input velocity.
- [IOHIDAccelerationAlgorithm.cpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDEventSystemPlugIns/IOHIDAccelerationAlgorithm.cpp): parametric coefficient interpolation, polynomial, tangent line and square-root continuation. The actual polynomial uses `(parabolicGain*x)^2`, `(cubicGain*x)^3`, `(quarticGain*x)^4`; treating these gains as ordinary polynomial coefficients changes the result. Follow the executable source, including its root-only case, rather than assuming its introductory comments are exact.
- [IOHIDAccelerationAlgorithm.hpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDEventSystemPlugIns/IOHIDAccelerationAlgorithm.hpp): cursor scale 96/67.
- [IOHIDAcceleration.hpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDEventSystemPlugIns/IOHIDAcceleration.hpp): nominal algorithm frame rate 67. This differs from a device's report-rate property; zero report rate disables timestamp normalization in the pointer accelerator.
- [IOHIDPointerScrollFilter.cpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDEventSystemPlugIns/IOHIDPointerScrollFilter.cpp): uses user curves before driver curves; normally tries parametric acceleration before table fallback, subject to explicit algorithm overrides. Pointer resolution and multiplier are service properties; tracking acceleration is selected through the device's acceleration type and fallbacks.

## What was actually inspected locally

Read-only IORegistry snapshots found three AppleMultitouchDevice services, each
with ten HIDAccelCurves entries, HIDPointerResolution=26214400 (400 in 16.16),
HIDPointerAccelerationMultiplier=48545 (about 0.7407379), and
HIDPointerReportRate=0. IOHIDSystem's HIDTrackpadAcceleration was 196608 (3.0).
These are a point-in-time observation, not constants to hardcode into an app.
The generated snapshot is under build/PointerAccelerationProbe/installed-settings.json;
run `snapshot` or `record-baseline.sh` to get current settings.

Provider/global properties do not prove the effective user/service overrides,
filter algorithm, additional third-party changes, proprietary multitouch motion
conditioning, display scaling or WindowServer processing. The probe currently
implements the parametric branch exposed by these pads, not Apple's table
fallback, scroll acceleration, subpixel accumulation/rounding or a native output
injection path. It rejects missing parametric curves rather than substituting a
made-up curve. The model initializes first-sample timing deterministically instead
of reproducing unspecified/uninitialized state in the published C++ constructor.

OMS coordinates are normalized contact positions, not unaccelerated HID pointer
counts. Resolution alone does not establish their conversion. Millimetre inputs
therefore require an explicit counts-per-mm assumption. `resolution / 25.4` is a
useful initial hypothesis, not a measured fact. Do not label a fitted model
"Apple Default" until held-out native recordings at several speeds/settings
support that claim. Do not fit and validate solely on the same strokes.

## Other projects

- [INRIA libpointing](https://github.com/INRIA/libpointing): relevant comparison framework; its README describes OS transfer-function replication and references the UIST 2011 characterization work. Its stated license is GPLv2-or-later, with alternative licenses available by request. No dependency or source from it was added.
- [Mac Mouse Fix PointerSpeed.m](https://github.com/noah-nuebling/mac-mouse-fix/blob/master/Helper/Core/PointerSpeed/PointerSpeed.m): useful evidence that acceleration parameters can be selected through HID service properties. The file is under the project's MMF License and contains unfinished paths; it is not a drop-in ready trackpad engine. No code from it was imported and none of its setting-changing operations is performed.

The two-finger pointing / three-finger dragging / four-finger scrolling proposal
is a separate recognition/output task. Pinch can coexist with centroid translation,
but gesture formation, typing/chord overlap and latching need separate tests.
This harness neither implements those gestures nor verifies the pasted chat's
claims about exact historical FingerWorks semantics.

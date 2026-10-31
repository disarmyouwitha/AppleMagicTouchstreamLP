# AppleMagicTouchstream

A TouchStream-style keyboard and configurable gesture workspace for Apple Magic
Trackpads, with native selected-pad takeover, capture/replay and optional haptics.

## Features

- Persistent, default-off Trackpad Takeover; selected BT/USB pads, editable selection,
  recovery/rollback, and Ctrl-Option-R emergency release.
- Independent left/right gestures, Mirror Edit, and coordinated Both chords.
- Latched pointer, drag/select, precise scrolling with momentum, thumb-required
  Pinch/Spread, taps, configurable Force/Hold and directional actions/repeats.
- Keys, modifiers/Hyper, shortcuts, layers, per-key Primary/Hold, repeat and Force
  instead of hold. Unreserved contacts default to typing.
- Traced TouchStream layout, automatic reference background, per-key overrides,
  visualizers with anatomical contact colors, pressure and paths.
- Asterisk-style STENO and staggered STENO 6x3 layouts, rolling two-pad
  chords, selectable 2F/1F mouse modes and a Gemini PR virtual serial port for Plover.
- Import/Export Settings including gesture assignments and gains. Native device
  selection and takeover opt-in stay app-local.
- Run at Startup through the macOS service manager, default off.

[Gesture rules](GESTURE_ENGINE.md) define exact behavior and defaults.
[Native takeover](TRACKPAD_TAKEOVER.md) defines supported hardware and lifecycle.
[Firmware findings](../FINDINGS.md) and the [implementation plan](../FINGERWORKS_IMPLEMENTATION_PLAN.md)
distinguish original-device research from app policy. Full original arrangement
scoring, language-based spelling correction and variable-speed typematic remain
research goals.

## Haptics and compatibility

Typing uses waveform 6 with a 0–2 Haptic Strength slider in 0.01 steps. Force clicks
use fixed waveform 6 / level 0.25. Feedback targets the originating pad; replay
records without vibrating hardware. See [native haptic evidence](../../../new_code/touchstream-archive/AppleMagicTouchstream-research-2026-10-26/notes/FORCE_CLICK_HAPTICS.md).

Existing profile/capture fields and preference migration are preserved. Unsupported
legacy actions remain inactive, and unknown imported labels report errors. Document
cleanup does not rename internal package targets, serialized keys or preference domains.
The app bundle ID remains `ink.ranna.applemagictouchstream`.

## Build and test

```sh
./build.sh
./test.sh
./build_framework.sh
./release.sh --check
```

Open `AppleMagicTouchstream/AppleMagicTouchstream.xcodeproj`, scheme
**AppleMagicTouchstream**. Scripts work from any current directory. The test wrapper
runs offline native ownership checks and Swift tests without accessing live input.
[Production replay](TESTING.md) provides deterministic keyboard transcripts.

Normal delivery is a signed universal Release app installed in Applications, left
closed for hardware testing. Generate a DMG when requested. See [macOS commands](../README.md)
and [bundle identity](../BUNDLE_IDENTITIES.md).

Shortcut Builder supports modifier-only shortcuts and App targets (applications,
files, folders, or URLs). Browse or enter a target, then Apply it to Primary/Hold,
or save it to the Shortcuts library. App targets open once when triggered and are
included in Import/Export Settings. Replay records them without opening anything.

## Documentation

- [AGENTS.md](AGENTS.md): development constraints, commands and preserved contracts.
- [GESTURE_ENGINE.md](GESTURE_ENGINE.md): recognition, arbitration and gesture settings.
- [TRACKPAD_TAKEOVER.md](TRACKPAD_TAKEOVER.md): native ownership, release and recovery.
- [RUNTIME.md](RUNTIME.md): keyboard/shortcuts, layout, typing assistance, Voice/Dictation, haptics and startup.
- [TESTING.md](TESTING.md): offline tests/replay, capture format and hardware validation.
- [Probe guide](Tools/HIDSeizureProbe/README.md): standalone diagnostic boundaries.

Detailed research, past audits, old probe reports and GUI design studies are preserved
in the [external research archive](../../../new_code/touchstream-archive/AppleMagicTouchstream-research-2026-10-26/README.md).
It is outside this checkout, under `~/Documents/new_code/touchstream-archive/`.
The archive index and hash manifest preserve each document's original location.
Current development does not require loading those historical reports.

## Icon source

`Artwork/AppIcon.svg` contains the traced white hand on a shaded graphite tile,
based on the supplied `mac/Hand.jpg`. It is an editable source, not a runtime asset.
Regenerate the ten icon sizes from the repository root:

```sh
swift mac/AppleMagicTouchstream/Tools/AppIcon/render.swift
```

Generated PNGs and `Contents.json` live in `Assets.xcassets/AppIcon.appiconset`;
Xcode's AppIcon setting compiles them into `AppIcon.icns`.

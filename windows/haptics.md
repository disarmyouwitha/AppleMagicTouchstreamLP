• mac haptics in this framework is a thin wrapper over private MultitouchSupport actuator calls,
  then GlassToKey triggers it from key-dispatch events.

  - Low-level private API surface is declared in Framework/OpenMultitouchSupportXCF/
    OpenMTInternal.h:196 (MTActuatorCreateFromDeviceID, MTActuatorOpen, MTActuatorActuate, etc.).
  - The Objective-C manager resolves a target device, caches/open actuator refs, and calls
    MTActuatorActuate(...) in Framework/OpenMultitouchSupportXCF/OpenMTManager.m:766.
  - Device selection fallback is: explicit deviceID -> primary actuator -> scan IORegistry for
    ActuationSupported in Framework/OpenMultitouchSupportXCF/OpenMTManager.m:675.
  - Swift wrapper maps normalized strength 0...1 to actuationID 1...6 plus a “sharpness” float,
    then forwards to raw trigger in Sources/OpenMultitouchSupport/OMSManager.swift:318.
  - App hot path throttles haptics to 20ms per side and routes by left/right device ID in
    GlassToKey/GlassToKey/Engine/TouchProcessorEngine.swift:2984, then dispatches through
    GlassToKey/GlassToKey/KeyEventDispatcher.swift:570.

  For portability to ../windows/glasstokey:

  - Direct API portability: no (macOS private API calls are not available on Windows).
  - Behavioral portability: yes (same trigger policy, strength setting, side routing,
    throttling).
  - In fact, Windows haptics is already implemented in this repo: ../windows/glasstokey/Core/
    Haptics/MagicTrackpadActuatorHaptics.cs:10.
  - Windows implementation uses a separate actuator HID interface and sends an output report via
    HidD_SetOutputReport (../windows/glasstokey/Core/Haptics/
    MagicTrackpadActuatorHaptics.cs:152), with payload builder at ../windows/glasstokey/Core/
    Haptics/MagicTrackpadActuatorHaptics.cs:405.
  - It also solves multi-trackpad routing via ContainerId matching (../windows/glasstokey/Core/
    Haptics/MagicTrackpadActuatorHaptics.cs:67) and is wired into dispatch at ../windows/
    glasstokey/Core/Dispatch/SendInputDispatcher.cs:232.
  - The repo’s own Windows note confirms this path (last updated February 15, 2026): ../windows/
    glasstokey/OFFICIAL_HAPTICS.md:1.

  Reverse engineering on Windows:

  - Yes, possible, and this codebase already reflects that work.
  - Remaining uncertainty is mainly firmware-specific tuning/parity (strength curve is empirical/
    nonlinear), called out in ../windows/glasstokey/OFFICIAL_HAPTICS.md:49.
  - Practically, this means “works” is achievable, but exact macOS feel needs per-device
    calibration.
# Prepared-session verification

**Subsequent capture review:** [CAPTURE_FINDINGS.md](CAPTURE_FINDINGS.md) documents the real recordings and28 passing package tests after adding label-revision timelines. The27-test build below is the original setup checkpoint.

2026-10-17. This records software setup, not a successful human capture session.

- `swift test`: **27 tests passed**, including **12 new RewriteProbe tests**. These cover identity relabeling versus lifetime, ID reuse, partial lift/staggered landing, separate taps, capture gaps/boundaries, missing telemetry/calibration, device filtering, physical-axis scaling, invalid data, plan validation and `.atpcap` round-trip.
- Debug Xcode build: **BUILD SUCCEEDED** for the gesture playground at the path in [START_HERE.md](START_HERE.md). No app recognition or output path was changed.
- CLI integration: an existing 28-frame capture parses and produces lifetime tables. A passing observation returns0, a deliberately mismatching observation returns1, missing physical calibration returns3, and invalid CLI input returns2. This existing capture is a smoke test, not labeled human evaluation.
- The real six-trial plan returns **inconclusive** for every missing recording, as expected. No human observations were fabricated to make it pass.
- The double-click runner passes `zsh -n`; captures and generated report folders are ignored by Git.

Source tests are in `Tests/RewriteProbeTests`; the runner is `swift run RewriteProbe`. Physical captures, feature/anatomy validation, calibrated motion, native-event suppression and actual recognizer accuracy remain to be tested. The keyboard project and reference app were not modified by this setup.

# Production recognition replay

`swift test` now compiles the same `TouchProcessorEngine.swift` used by the Mac
app into the `GlassToKeyRuntime` package target. It runs recognition without
starting GlassToKey, listening to trackpads, posting native events, launching
apps, playing haptics, or starting dictation. UI declarations are compiled to
satisfy the existing model/geometry dependencies; the UI model is not created.

## Run

From `mac/`:

```sh
swift test
swift run ReplayHarness --fixture ReplayFixtures/production_typing.atpcap \
  --expected-transcript ReplayFixtures/production_typing.engine.transcript.jsonl
```

For a new recording:

```sh
swift run ReplayHarness --fixture /absolute/path/session.atpcap \
  --output /tmp/session.production.jsonl
```

The harness uses the captured configuration when present. `--profile path.json`
overrides it with an AppKeymapProfile JSON or portable exported keymap. Captures
without configuration use a deterministic factory profile; the transcript labels
that choice explicitly. Device routing is reported in its metadata. For typing
accuracy comparisons, use a capture with its intended configuration.

Transcripts include per-frame production decisions/rejections, target keys,
intent, output commands, timestamps, modifier flags, and source sequence IDs.
The final record includes timer events during a 250 ms tail and releases from
reset. System dispatch is replaced by a synchronous recorder, so the tests
verify intended output commands rather than OS event delivery.

## Clock and behavior coverage

The app uses the live serial-queue scheduler. Tests inject a virtual scheduler
and advance its deadlines before processing the next frame. Equal deadlines
run in insertion order; simultaneous repeats retain registration order. Tests
require no sleeps, physical input, Accessibility permission, or GUI session.
Voice-session transitions are recorded rather than invoking speech recognition.

Production tests cover plain F, shifted F, modifier cleanup after missing release,
drag cancellation, two-pad overlapping input, multi-finger suppression, repeats
between frames, repeat cancellation, typing-grace expiry, deterministic repeat
ordering, and capture/configuration replay with a committed transcript.

`production_typing.atpcap` is explicitly synthetic, not a physical accuracy
study. It contains an embedded blank-layout profile with F, Shift, and Left
buttons and 18 correctly timed frames. Separate assertions check the F strokes,
Shift flags, and repeated arrow output in addition to transcript parity.

## Historical fixture and baseline

`macos_first_capture_2026-02-20.atpcap` remains a parser fixture. Its arrival times
jump backward (record 6 returns to zero), so production replay rejects it.
The old contact-count transcript is retained as `.contact-count.baseline.jsonl`;
it is not a production recognition baseline. The package's simplified model is
now named `ContactCountSmokeEngine` and must be selected explicitly. The CLI
always uses production recognition.

## Deliberately regenerate fixtures

Review the test's generated input and explicit output assertions before updating:

```sh
UPDATE_PRODUCTION_REPLAY_FIXTURES=1 swift test \
  --filter ProductionEngineTests.testReplayTranscriptMatchesProductionBaselineAndIsDeterministic
```

This writes the synthetic capture and its production transcript. Ordinary test
runs never rewrite committed fixtures. Capture bytes may include a fresh meta
date; recognition output is checked independently and is deterministic.

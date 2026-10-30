# Testing and capture reference

`swift test` compiles the same `TouchProcessorEngine.swift` used by the Mac
app into its engine package target. It runs recognition without
starting the app, listening to trackpads, posting native events, launching
apps, playing haptics, or starting dictation. UI declarations are compiled to
satisfy the existing model/geometry dependencies; the UI model is not created.

## STENO verification

`GeminiPRTests`, `StenoChordTests` and `StenoLayoutTests` check canonical Plover
wire vectors, every wire bit, rolling two-pad all-up, arbitrary selected device
indices, cancellation, seam combinations, mode transitions and settings round-trip.
The transport test opens only its own private PTY, configures a raw reader as
Plover does, verifies exact packets (including CR bytes), disconnect/drop behavior
and path cleanup; it never uses the live singleton or native input. Optional
`STENO_PREVIEW_DIR=/tmp ./test.sh --filter StenoLayoutTests` renders both layouts.
Hardware acceptance still requires Plover connection, real chords/rolls and
comparison of translated strokes, takeover and cleanup. No offline test establishes
physical comfort or Plover delivery.

## Run

Start with `./test.sh`: it runs native takeover lifecycle checks, then Swift tests.
No live input, synthetic OS output, haptics, microphone or login registration is
needed. Optional local captures/registry checks can skip; report them separately.
A passing offline suite does not prove native takeover or external app delivery.

Ordinary UI smoke tests render every gesture page, each cardinal Movement mode,
a narrow mirrored editor, the coordinated pages and one shared diagonal layout.
Pure recognizer/settings tests still exercise every direction. They do not compare
golden screenshots, so a successful render is not proof of visual correctness.
The full page × width × Mirror Edit × Movement-mode matrix is for explicit visual
inspection, not routine recognition validation:

```sh
AMT_WORKSPACE_PREVIEW_DIR=/tmp/amt-workspace-previews ./test.sh \
  --filter 'GestureWorkspaceTests|ThumbDiagonalWorkspaceTests|SearchableGestureActionTests'
```

This exports all workspace variants, four diagonal previews, and animation strips
without opening a visible app or activating input. Inspect the resulting PNGs.

Seven optional checks may skip in a normal checkout: five depend on original local
pointer/scroll, Hold and rotation captures that are not bundled. Two read installed
registry profiles only when `POINTER_PROFILE_REGISTRY_ID` or
`SCROLL_PROFILE_REGISTRY_ID` is supplied. These supplement the committed numerical
vectors, synthetic sessions and extracted capture regressions; skips are not proof
that hardware or external application behavior passed. Do not delete useful
regressions merely to reduce the reported test count.

### Production keyboard replay

From `mac/AppleMagicTouchstream/`:

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
two-pad overlapping input, multi-finger reservation, repeats
between frames, repeat cancellation, deterministic repeat
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

Live captures optionally include `gestureOutput` on each processed frame: logical
drag ownership, combined/HID/private button masks, observer health, and the last
32 mouse-button edges observed from this process. Each edge stores type, source
ID, timestamp and interpreter-tag presence; it records no cursor/key content.
The observer uses fixed storage, and only capture serialization copies its bounded
history. Mouse edges optionally retain their actual event modifier flags; live
frame snapshots also retain combined/HID flags, the app's owned keyboard flags,
and an eight-bit L/R Shift/Option/Control/Command key-down mask. These additions
record no ordinary key contents. Missing older fields mean unknown, not zero.
Replay never polls live button/modifier state or emits these recorded edges. Old
records without this optional evidence remain readable; the v5 envelope is unchanged.
This evidence distinguishes an omitted release from state remaining down after an
observed release. Offline event-construction tests alone cannot prove native recovery.

Saved-text tests use an injected in-memory store and a hidden editor. They verify
opaque settings/gesture/library round trips, single-fire primary/Hold/custom-button
replay, silent Keychain query policy, text size/Unicode handling and exactly-once
cancellation. They never read/write the user's Keychain or clipboard and never
post a paste. Native acceptance requires user-triggered checks in the signed app:
save and relaunch, paste multiline/Unicode text, cancel during focus/lifecycle
changes, verify an unchanged clipboard item clears while a newer copy survives,
and verify a locked Keychain skips without an authentication dialog.

## Capture format (`.atpcap`)

Canonical replay captures use `.atpcap` (`ATPCAP01`) with a versioned binary layout.

### File Header (20 bytes)

1. `magic` (8 bytes ASCII): `ATPCAP01`
2. `version` (Int32 LE): current macOS writer version is `5`
3. `tickFrequency` (Int64 LE): ticks per second (macOS currently writes `1_000_000_000`)

### Record Header (34 bytes, repeated)

1. `payloadLength` (Int32 LE)
2. `arrivalTicks` (Int64 LE)
3. `deviceIndex` (Int32 LE)
4. `deviceHash` (UInt32 LE)
5. `vendorID` (UInt32 LE)
6. `productID` (UInt32 LE)
7. `usagePage` (UInt16 LE)
8. `usage` (UInt16 LE)
9. `sideHint` (UInt8): `0 unknown`, `1 left`, `2 right`
10. `decoderProfile` (UInt8): reserved on macOS writer (`0`)

### Record Payloads (v5)

- Meta record: `deviceIndex == -1`, payload is UTF-8 JSON:
  - `type: "meta"`
  - `schema: "g2k-replay-v1"`
  - `capturedAt`, `platform`, `source`, `framesCaptured`
- Processed frame record: `deviceIndex == -5`, payload is UTF-8 JSON:
  - `type: "processedFrameRecord"`
  - `record.frame`:
    - `sequence`
    - `timestamp`
    - `deviceNumericID`
    - `deviceIndex`
    - `contacts`
    - `rawTouches`
  - `record.arrivalTicks`
  - `record.dispatchEvents`

The committed replay fixtures use the lean v5 subset:
- no render snapshot payload
- no ingress payload
- no diagnostics payload
- no dispatch events unless the source capture actually had them

### Canonical States

`0 notTouching`, `1 starting`, `2 hovering`, `3 making`, `4 touching`, `5 breaking`, `6 lingering`, `7 leaving`.

### Compatibility

- Capture fixtures are `.atpcap` only.
- Transcript artifacts may remain `.jsonl` for parity/debug output.
- Legacy v3/v4 captures are migrated with `swift run ATPCaptureTranscode`; normal replay parsing is v5-only.

## Hardware validation

Only run these intentionally with the user. Keep a separate keyboard/mouse for
native acquisition tests; do not activate probes as build validation.

- Takeover: selected USB/BT pads, unselected-pad isolation, release/restoration,
  Config close/reopen, active Restart, sleep/wake and replay. See
  [TRACKPAD_TAKEOVER.md](TRACKPAD_TAKEOVER.md).
- Keyboard/gestures: fast typing, two-finger mouse/tap, independent pad output,
  Hold/drag cleanup, Both handoff and modifier shortcuts. Capture reproductions
  with their intended settings. See [GESTURE_ENGINE.md](GESTURE_ENGINE.md).
- Autocorrect: disposable TextEdit and built-in editor, misspelling+Space, fast
  continued typing, Backspace, shortcuts, caret/app changes and secure fields.
  AX compatibility and undo need external-app testing.
- Snap: short taps just outside a key with Snap off/on; timed-out taps and activated
  gestures must not type. Recheck two-finger mouse/tap.
- Voice: focus a test document, trigger, speak, trigger again; check Config closed,
  cancellation, focus-change discard, takeover release and a fresh session. Do not
  start the microphone in offline tests.
- Dictation/Emoji: verify the macOS shortcut matches, native UI opens and subsequent
  typing/clicks inherit no borrowed modifiers.
- Run at Startup: registration approval and login launch on the installed signed
  app; never register a login item during build/tests.

## Offline visual previews

```sh
TOUCHSTREAM_PREVIEW_PATH=/tmp/amt-touchstream-preview.png ./test.sh
```

The test suite's offscreen hosts render without taking over trackpads or posting
input. For available gesture-workspace preview hooks, inspect the corresponding
`Tests/ProductionEngineTests` renderer test before choosing its environment flag.

# Runtime reference

Current keyboard, assistance, output and profile contracts. Recognition and
arbitration rules live in [GESTURE_ENGINE.md](GESTURE_ENGINE.md); native ownership
and lifecycle rules live in [TRACKPAD_TAKEOVER.md](TRACKPAD_TAKEOVER.md).
Historical evidence and source-port investigations are indexed in the external
research archive linked from [README.md](README.md#documentation).

## Keyboard and shortcuts

Unreserved contacts default to typing. Primary/Hold assignments, layers, modifier
ownership, key repeat and Force instead of hold use the shared keyboard engine.
An unassigned Hold stays None; there is no fallback to a legacy label-based Hold
table. Preserve existing profile names, preference keys and serialized identities.

Keyboard and Gesture inspectors share the searchable action catalog, Shortcut
Builder and saved library. Names are presentation metadata: `NAMED_SHORTCUT:`
envelopes preserve the underlying command. App/file/folder/URL targets open once;
replay records their commands without opening anything. Import/Export Settings
include library entries and gesture assignments; missing fields preserve existing
preferences. Takeover opt-in and native device selection remain local.

Screenshot, Dictation and Emoji appear as built-in Shortcuts without
rewriting the saved library. Modifiers appear there only when saved by the user.
The builder permits modifier toggles with Key=None. The entirely empty combination
is disabled; all four generic modifiers display as Hyper. Modifier keys are not
repeated as final-key choices. Legacy modifier-as-key labels still decode.

Hyper means Command+Option+Control+Shift. Keyboard modifier combinations expand
into reference-counted components. Overlapping owners must not release each other's
modifiers. Modifier actions on Hold start after the key's hold/force threshold,
remain down until that contact ends, and never repeat. Missing terminal records,
cancellation and reset release ownership. Gesture Hold can fire once or keep a
shortcut down until release, using the same shared output ledger.

Balanced keystrokes restore pre-shortcut modifier flags on key-up. Emoji maps
Globe to Control–Command–Space through that factory; it must not leave borrowed
Control/Command flags on subsequent clicks or typing.

## TouchStream layout

TouchStream uses independent traced left/right regions. Delete and Enter corner
regions widen inward from their original outer edges with their original vertical
positions and heights, leaving roughly four display points of clearance from Backspace and Space at the standard
432×310.23 surface. The layout is resolved by
`ContentView.makeTouchStreamKeyLayout` for the editor, startup and production
replay. The bundled `Resources/LHS_TOUCHSTREAM_layout.png` and
`Resources/RHS_TOUCHSTREAM_layout.png` are shown automatically on their respective
pads for this preset, beneath the sensor grid, outlines and contacts. It is visual
only and does not affect hit testing. No reference checkbox is needed.

The 88 regions are traced independently from the 1320×940 left image and
1314×936 right image, expressed in a 260×196 coordinate space and scaled to the
trackpad surface. Centers, sizes and rotations follow the printed borders, not
physical sensor calibration. Thumb regions use rotated
rectangular bounds around oval artwork. Saved per-key overrides still apply.
Column tuning stays disabled for this fixed independent geometry.
Keymap Tuning keeps its labels and options in side-by-side 50/50 columns even at
narrow sidebar widths. Column Tuning uses the same 50/50 label/control split.
At normal widths Mode Toggles uses two rows: Run at Startup / Snap Radius, then
Autocorrect / Hold Repeat. Narrow sidebars use one full-width label/switch pair per
row instead of wrapping labels into narrow columns. Switches align at the right
edge of their row or half-column; Autocorrect status stays below its own control.
Layout and Layer selectors fill the right half of their rows beside their labels,
including at narrow sidebar widths. Shortcut Builder aligns its Key and App fields
and the Apply/Browse buttons in shared columns.
Import Settings and Export Settings share one row with equal-width buttons.

Letters, numbers, modifiers, navigation and function keys use the action catalog.
Unsupported hand-logo/PC-only legends remain editable inactive placeholders until
assigned a supported action. Changing layouts does not replace saved mappings.

## Snap radius

Keyboard → Mode Toggles uses `GlassToKey.snapRadiusPercent`, also retained in
settings exports. Direct hits win. A near miss selects the nearest eligible key
on the same pad/layer/current binding index. Radius is the smaller key dimension
times the saved percentage, bounded 0–100%. Toggling on sets 100%, off sets zero;
existing nonzero percentages are honored until toggled.

Centers and squared radii are cached on geometry/settings changes; release lookup
does not allocate. Ambiguity retains edge-distance tie-breaking and alternate ASCII
hints for autocorrect. Final-lift timing, tap eligibility and missing-contact
cleanup are shared with direct typing. Snap cannot rescue a timed-out tap or an
activated gesture cycle, and does not change mouse/scroll activation or latches.

## Autocorrect

Keyboard → Mode Toggles uses `GlassToKey.autocorrectEnabled`, retained in exports.
Only posted live keys feed correction. Raw contacts, pending typing proposals,
cancelled output and replay do not. ASCII words are limited to 64 bytes with a
1,024-byte context. Exclude unambiguous two-letter words, all-caps and identifiers
with digits/underscores. Navigation, unknown keys and non-text shortcuts invalidate
the word. Keycode-to-ASCII conversion retains its US-keyboard limitation.

A bounded 2,048-event buffer publishes to a utility worker; overflow cancels context.
`NSSpellChecker` supplies corrections/language detection and may use snap's alternate
key hints for dictionary guesses. No bundled dictionary/network service is added.
New output, clicks, system actions, app launches, resets or disabling correction
invalidate pending edits through generation checks.

All Accessibility reads/writes run asynchronously on the main actor, outside the
recognition/output queues. Self-targeted AX can enter AppKit directly, so worker
AX calls are invalid. Spellchecking stays on its worker. For readable AX text,
require the original focused non-secure element, an empty
selection, and the complete original word plus delimiter immediately before the
caret. A mismatch retries at most three times at 15 ms for event-delivery lag,
then reports a skip. It never authorizes an unverified keyboard fallback.

Ordinary corrections use one keyboard replacement path, even when AX validation
succeeds: delete the tracked word and printable delimiter, then type the correction
and delimiter. AX is used for verification, without changing selection/value.
When AX caret/text support is unavailable before any edit, use the same output
path as a fallback, retaining foreground PID and any exposed focused element from
the first letter. No app-specific adapters or browser changes.

Words are bounded ASCII (2–64 bytes). Return/Tab cannot use the fallback because
they may submit or move focus. Those delimiters retain verified AX range editing;
check the resulting text before reporting success, and never fall back after an
AX selection/edit attempt. Never replace the entire document.

Prebuild balanced Delete and mapped keyboard edges and post on the existing live
dispatch queue. Recheck candidate generation, active app, secure input, Accessibility
permission and held modifiers before posting. Skip with held modifiers. Retyping
uses the same ASCII/keycode mapper as normal AMT typing, including
shifted letters/punctuation, rather than placeholder Unicode keycodes. Each
stroke has a 2 ms gap before the next stroke; no gap splits a down/up pair. The
batch finishes once begun and later AMT keys wait behind it. No replay output,
semantic republication, clipboard use or changed spelling rules.

Only AMT-dispatched input feeds word tracking and cancellation. No physical
keyboard/mouse event monitors. App activation invalidates context; disabling
correction removes that focus observer. Fallback cannot verify unexposed text,
caret or password state; detected secure fields/Secure Event Input are excluded.
Physical input can still race OS delivery. No new restricted entitlement is needed.

Keyboard → Mode Toggles shows the last original word → replacement beneath the
Autocorrect switch, with actionable validation/output errors when present. Routine
statuses (waiting, no suggestion, sent, ordinary input/focus cancellation) and the
output method remain in session diagnostics but are hidden in the compact readout.
“Replacement sent” confirms dispatch, not the receiver's resulting DOM/editor
state. Last replacement survives a later skipped attempt. No word history is
persisted, exported or written to logs; text-free debug logs use Autocorrect.

## Voice and Apple Dictation

Voice is a built-in option in the keyboard Shortcuts menu and the Shortcuts section
of compatible discrete gesture assignments, alongside Dictation, Screenshot and
Emoji. Saved Voice aliases deduplicate with the built-in entry. Continuous movement
assignments do not offer Voice. Menu presentation never rewrites saved assignments
or seeds the user's shortcut library.

Voice is the app-managed `AVAudioEngine`/`SFSpeechRecognizer` toggle: invoke once
to listen, again to finish and insert Unicode text. A gesture Hold starts it at
the threshold; lifting does not stop dictation. Mode Toggles has no Voice status
or Cancel Voice row; invoke the assigned Voice action again to finish. Internal
status and lifecycle cancellation remain available. No audio, permission request or recognizer starts at app launch,
settings editing, offline tests or replay.

On first invocation, request Speech Recognition and Microphone access asynchronously.
Keep both purpose strings and the standard audio-input entitlement. Recognition
prefers the current locale with en_US fallback, and on-device recognition when
supported; otherwise Apple's service may process audio remotely. Session/chunk
tokens reject stale permission results, cancelled callbacks and delayed completion.
Finished chunks restart with bounded error retries. Stopping ends audio immediately,
then allows up to 600 ms for the final transcript. Never log transcripts.

Voice captures the foreground process independently of Config, using a dedicated
main-actor AX query with a bounded 200 ms timeout. An exposed focused field/window
must still match at insertion; otherwise the app identity is the available focus
boundary and cannot distinguish unexposed fields. Reject secure input, changed
apps, changed exposed targets or loss of a previously exposed target. Insert through
the Unicode dispatcher, without clipboard replacement or ASCII normalization.
Closing Config preserves the app/session; suspend, ownership loss, processing resets
and replay transitions cancel without insertion. The publication generation also
invalidates queued toggles. Directional Voice should have Repeat off.

`Voice`/`VOICE` key labels use `.voice`; gestures use `voice`. Capture records
`systemKey("voiceToggle")` without starting speech in replay.

Dictation sends Apple's Fn–D command for macOS's own microphone UI and live text
entry. It does not start this app's recorder or change system preferences. It
exports/imports as the stable `Dictation` key action. Old named shortcuts retain
their literal command; remove/reassign an old Option–Command–D Dictation entry
manually. There is no migration or compatibility rewrite for that assignment.
Option–Command–D conflicts with the Dock, even when also saved as a custom
Dictation hotkey. Do not infer a conflict-free command from that preference alone.

## Haptics

Typing uses waveform 6 and Haptic Strength 0–2 in 0.01 steps; zero disables it.
Saved strength is level×100. Force clicks always use waveform 6 / 0.25; old
experimental force-feedback fields decode but stay inactive. Target the originating
selected pad, once per owned force cycle and at least 50 ms apart per pad. Replay
records commands without touching hardware. Level is a bounded waveform parameter,
not calibrated volume/force; device limits and quantization can flatten nearby levels.

## Run at Startup

Mode Toggles uses `LaunchAtLoginManager` and `SMAppService.mainApp`, without a helper.
Default off; reconcile the saved preference at launch and reflect actual service
status on config load, changes and errors. Imports may apply an included startup
preference and report failure; exports include it. Build/tests never register
login items. Login launch and registration approval require a user hardware test.

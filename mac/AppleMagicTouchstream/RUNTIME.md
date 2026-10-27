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

TouchStream uses independent traced left/right regions, resolved by
`ContentView.makeTouchStreamKeyLayout` for the editor, startup and production
replay. The bundled `Resources/TouchStreamReference.gif` is shown automatically
for this preset, beneath the sensor grid, outlines and contacts. It is visual
only and does not affect hit testing. No reference checkbox is needed.

The 88 regions use a 260×196 canvas per half of the supplied 520×196 reference,
scaled to the trackpad surface. Centers, sizes and rotations are visual estimates
from that image, not physical sensor calibration. Thumb regions use rotated
rectangular bounds around oval artwork. Saved per-key overrides still apply.
Column tuning stays disabled for this fixed independent geometry.

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
the word. Physical key-to-ASCII conversion retains its US-keyboard limitation.

A bounded 2,048-event buffer publishes to a utility worker; overflow cancels context.
`NSSpellChecker` supplies corrections/language detection and may use snap's alternate
key hints for dictionary guesses. No bundled dictionary/network service is added.
New output, clicks, system actions, app launches, resets or disabling correction
invalidate pending edits through generation checks.

All Accessibility reads/writes run asynchronously on the main actor, outside the
recognition/output queues. Self-targeted AX can enter AppKit directly, so worker
AX calls are invalid. Spellchecking stays on its worker. A correction requires the
original focused non-secure AX element, an empty selection, and the complete
original word plus delimiter immediately before the caret. Recheck focus, caret
and generation before range replacement; adjust by the UTF-16 length difference.
Never replace the entire document. Failure after a selection attempt restores the
caret where possible and never falls back. Text mismatch, nonempty selection,
changed focus or generation also reject replacement.

The delimiter may not yet have reached the destination app after CGEvent posting:
retry at most three times at 15 ms, with the same generation checks. External app
focus/caret changes are not transactional.

When AX text/range/setter support is unavailable before any edit, use a shared
backspace/retype fallback. Track the original foreground PID and any exposed
focused element from the first letter; recheck on correction. Replace only the
tracked ASCII word (2–64 bytes) plus a printable delimiter. Return/Tab never fall
back because they may submit or move focus. Prebuild balanced Delete and Unicode
key edges, then post the batch on the existing live dispatch queue, checking the
candidate generation, active app, secure input, Accessibility permission and held
modifiers again before posting. Skip with held modifiers. No replay output, word
republication, clipboard use, new spelling rules or app-specific adapters.

Only AMT-dispatched input feeds word tracking and cancellation. No physical
keyboard/mouse event monitors are installed. App activation changes invalidate
context; disabling autocorrect removes that focus observer. Text-free debug
messages use the Autocorrect logging category.

Fallback cannot verify unexposed text/caret/password state; detected secure fields
and Secure Event Input are excluded. It cannot roll back once deletion has begun,
so the balanced batch finishes rather than leaving a partial replacement. Physical
input can still race OS event delivery. Existing Accessibility permission is
required; no new restricted entitlement is needed.

## Voice and Apple Dictation

Voice is hidden from keyboard and gesture assignment menus, including saved
library entries. Its implementation and existing assignments remain intact; this
is a menu-only change, with no migration or settings rewrite.

Voice is the app-managed `AVAudioEngine`/`SFSpeechRecognizer` toggle: invoke once
to listen, again to finish and insert Unicode text. A gesture Hold starts it at
the threshold; lifting does not stop dictation. Mode Toggles shows status and
Cancel Voice. No audio, permission request or recognizer starts at app launch,
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

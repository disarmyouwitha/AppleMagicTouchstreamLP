# Autocorrect and snap radius

Both controls live in Keyboard → Mode Toggles. They use the existing
`GlassToKey.autocorrectEnabled` and `GlassToKey.snapRadiusPercent` preference keys
and existing profile fields. Import/Export Settings preserves both. No gesture
assignments, takeover preferences, keymap geometry or timing defaults change.

## Recovered source

The maintained implementation was compared with the final macOS GlassToKey tree
before retirement, at [347d182](https://github.com/disarmyouwitha/AppleMagicTouchstreamLP/tree/347d182/mac/GlassToKey).
Its `GlassToKey/GlassToKey/AutocorrectEngine.swift`, `KeyEventDispatcher.swift`,
`ContentView.swift` and `Engine/TouchProcessorEngine.swift` supplied the behavior.
Earlier autocorrect work includes
[77ec78a](https://github.com/disarmyouwitha/AppleMagicTouchstreamLP/commit/77ec78a),
[db92632](https://github.com/disarmyouwitha/AppleMagicTouchstreamLP/commit/db92632), and
[cc2a8de](https://github.com/disarmyouwitha/AppleMagicTouchstreamLP/commit/cc2a8de).
This is a source port into the maintained runtime; the old project is not restored
and unrelated historical commits are not cherry-picked.

## Snap radius

- Direct key hits retain priority. A near miss can choose the nearest eligible
  key on the same pad, layer and current binding index.
- Each radius is the smaller key dimension multiplied by the saved percentage.
  The engine bounds it to 0–100%; zero disables it. As in the recovered UI,
  switching Snap Radius on sets 100%, and switching it off sets zero. Existing
  nonzero saved percentages are honored until the toggle is changed.
- The key centers and squared radii are cached when geometry/settings change.
  Release processing searches those existing arrays without a new allocation.
- Ambiguous near misses retain the original edge-distance tie-break and alternate
  ASCII key hint, which autocorrect can use at a later word boundary.
- Final-lift timing remains available through the release frame. Snap uses the
  same tap-duration and typing-eligibility checks as direct typing, including
  missing-contact cleanup. It cannot rescue a timed-out tap or gesture-owned cycle.
  Gesture activation distances, latches and pointer/scroll acceleration stay intact.

## Autocorrect

Only posted live keyboard output is observed. Raw contacts, uncommitted typing
proposals, cancelled dispatches and replay/recording sinks never drive correction.
The worker tracks ASCII words, backspaces, delimiters and a bounded 1,024-byte
context. Words are limited to 64 bytes. It preserves the old minimum of two
letters, exclusion of unambiguous two-letter words, all-caps and identifiers
containing digits/underscores. Navigation, unknown keys and non-text shortcuts
invalidate the word rather than guessing the new caret location.

The worker uses macOS
[NSSpellChecker.correction](https://developer.apple.com/documentation/appkit/nsspellchecker/correction(forwordrange:in:language:inspelldocumentwithtag:))
and its context language detection. If there is no proposed correction, dictionary
guesses may use the exact alternate-key hints supplied by snap radius. There is no
network service or bundled dictionary dependency. The physical key-to-ASCII
mapping retains the original US-keyboard limitation.

Keyboard output publishes to a lock-protected, bounded 2,048-event buffer. An
overflow cancels context instead of continuing a truncated word. New key output,
clicks, system actions, app launches, output-queue resets and disabling autocorrect
invalidate pending edits. Spellchecking runs on a separate utility worker. AX
reads and writes are enqueued asynchronously on the main actor, outside gesture
recognition and the output pump. Self-targeted AX calls can enter AppKit directly:
the built-in test editor's selection operation traps if it runs on a worker.
The source uses a
generation check before an edit; continued typing can therefore skip a correction
instead of editing a word whose output is already stale.

### Replacement and compatibility

The old blind backspace/retype fallback is not carried forward. A correction must
find the same focused AX element captured for the word, outside Secure Input and
secure-text fields, with an empty selection and the exact complete original word
plus delimiter before the caret. It checks nearby text through AX range queries,
using the element's value as a compatibility fallback. It rechecks output
generation, focus and caret before selecting/replacing the word, and adjusts the
caret by the replacement's UTF-16 length difference. It never rewrites a document's
entire value. AX failures leave the original text intact; failure after selecting
the word attempts to restore the original caret without retyping.

CGEvent posting precedes application delivery. A not-yet-visible delimiter can
be retried three times at 15 ms intervals, each with the same generation checks.
New output cancels these retries. Existing Accessibility authorization is required;
there is no additional entitlement request. Fields without readable/writable AX
text support are skipped. Individual applications' undo and text-change handling
still require hardware/application testing. AX selection and replacement are
separate system calls, so external focus/physical-input changes cannot be made
transactional; checks reduce this race rather than promising atomic cross-app edits.

## Verification

`TypingAssistanceTests.swift` exercises word/context boundaries, backspace,
command/navigation cancellation, short-word/caps/identifier exclusions, overflow,
alternate-key restrictions, UTF-16 replacement ranges, generation invalidation,
and production keyboard near-miss behavior on each pad. Production replay sinks
remain output-free. The full existing gesture/typing suite protects accepted
movement, tap, layer, Hold and paired-hand behavior.

`AutocorrectEditorThreadTests` exercises worker-to-main text access against an
offline NSTextView, including selection, replacement and caret restoration. Crash
reports `AppleMagicTouchstream-2026-10-25-214243.ips` and `...-214320.ips` confirmed
the original AppKit main-thread assertion under `VerifiedAutocorrectReplacement.setRange`.

For hardware validation, use a disposable TextEdit document and the built-in test
editor. Toggle Autocorrect, type a clear misspelling followed by Space, and compare
with it disabled. Check ordinary typing, fast continued typing, Backspace, Cmd+S,
caret moves, app switches and a password field. For Snap Radius compare short taps
just outside a key with the option off/on, then recheck two-finger mouse/tap. Some
words will not be changed because macOS does not propose a correction, and some
applications do not expose suitable AX text attributes.

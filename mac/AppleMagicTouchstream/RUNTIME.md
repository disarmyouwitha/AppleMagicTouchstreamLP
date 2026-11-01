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

## Saved text shortcuts

Keyboard and Gesture Shortcut Builders share an inline Text box below App, with
the “Text Encrypted in Keychain” placeholder and the eye button on its right.
The shared Apply button saves/assigns text when the Text field contains a draft
or an existing protected reference; otherwise it applies the key/app shortcut. Names
are optional; a successful text save displays confirmation. Assigned text starts
masked and is not read from Keychain until the eye button is clicked. Hiding it
removes the loaded plaintext from editor state; an unsaved draft remains editable
while masked. The compact field grows to at most three lines, with the eye on
its right and the action preview below. Both builders use the shared searchable
grouped chooser for Key, including the saved Shortcuts group; the gesture header directly opens
the same saved-shortcut manager as Keymap Tuning. The Custom Buttons section follows Shortcut
Builder, and Primary/Hold choosers omit steno keys outside STENO layouts without
changing stored assignments. The Text box stores content as a
generic-password item in the
local login Keychain. A calling-app-only access list protects the item. The signed
app reads its own unlocked items without repeated approval; authentication UI is
forbidden, so locked/unavailable items fail closed. Keychain operations run on
workers, outside input processing and the main actor. The legacy login-Keychain
interaction flag is serialized and restored around each operation; no new access
group, provisioning profile or entitlement is required.

Key actions, custom buttons, gestures, the saved library, settings exports and
capture transcripts carry `TEXT_SHORTCUT:<UUID>` references only. Content is never
serialized there. Optional display names remain ordinary settings metadata. On
another Mac, a missing Keychain item must be re-entered and reassigned. Editing
creates a new reference so other assignments keep their original text; removing a
library entry preserves its assigned actions and their Keychain item.

Text is one-shot, including on Hold; held-key output is unavailable for it.
Replay records only the reference through the existing system-event envelope,
without reading Keychain, touching the clipboard or posting native keys. Live
text output retains the shared dispatch order while a worker reads the item, then
revalidates the focused destination on the main actor before every character.
It emits paced, balanced HID key-down/up pairs (5 ms between Unicode scalars),
with Return/Tab key events and CRLF treated as one Return. Down events clear
shortcut modifiers; up events restore existing keyboard/gesture modifiers. Saved
text is allowed in Secure Input fields, while Voice keeps its existing exclusion.
No lock-screen compatibility is assumed by offline tests; hardware verification
remains required. The clipboard is never read or written by saved-text output.
Reset/ownership cleanup cancels pending reads and the remaining typing steps,
and resumes queued release edges exactly once. No AX call runs on input/output
queues. Serialized `textPaste` kinds, `TEXT_SHORTCUT` references and recording
identities remain unchanged for existing profiles/captures.

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
The traced geometry is the editable template seed; Layout Editor can author independent
positions, sizes and groups without changing the reference image.
Keymap Tuning keeps its labels and options in side-by-side 50/50 columns even at
narrow sidebar widths. Layout Editor replaces the old Column Tuning panel.
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

## Layout authoring

Layout Editor replaces the keyboard visualizer in the same workspace while editing.
Both trackpads remain visible side by side. Its inspector uses the normal resizable
settings column. Apply saves one geometry update and returns to the visualizer;
Cancel returns without publishing the staged document. Undo, Redo and Reset remain
available in the editor header. Device/takeover controls remain available above it.

Keys support click/drag, Shift-add selection and box selection by dragging empty
space. Every selection has one shared frame and square resize handle per pad;
individual member handles, group selection mode and the key-selection dropdown are
absent. Width/Height fields resize selections in millimeters, and Smaller/Larger
5% buttons scale keys and spacing. Selection spacing X/Y sets gaps between aligned
bands of keys in the selection’s shared axes, translating keys without resizing them.
Negative gaps allow overlap. The first band anchors each pad; Mirror Edit reflects
these translations. A single band or mixed-angle selection has no editable gap on
that axis. Numeric geometry fields retain incomplete drafts and validate on Return
or focus loss, producing one undo transaction per committed field edit.
Shift or Keep proportions locks the aspect ratio.
Keys with shared axes can resize independently; mixed rotations scale uniformly.
Each pad uses its own anchor. Fixed STENO overlap allowances, key identities,
existing group metadata, bindings and counterpart links are retained.

Trackpad canvases cap at the same size as the visualizer (physical dimensions ×
displayScale) and shrink together when needed. Tool buttons retain their compact
90-point width and wrap into up to three columns, with Rotate Right below Rotate Left.
The editor selects individual keys regardless of saved group metadata; Group/Ungroup
controls are removed. Mirror Edit sits beside the Layout Editor title. The column count sits beside Add
Column. Dragging and shared frame resizing always use a 1 mm grid, independently of
typing Snap Radius; no grid selector is shown.

Editor legends resolve the active layer’s actual per-hand mappings, including staged
duplicate sources, without rewriting the document’s fallback labels. Reset seeds
geometry from bundled DEFAULT_KEYMAP.json, including per-layout column dimensions,
row spacing, padding, key overrides, base-layer fallback labels and any authored
default documents. Current
action assignments remain independent of geometry reset. Mirror Edit uses a blue enabled
button with the same split-pad icon in Layout Editor and Gesture Editor.

Tool buttons visibly press blue and shrink while clicked, then pulse a blue border
for about 0.8 seconds. Spacing −5%/+5% precede Delete in Arrange; they scale the
selected center-to-center pitch while preserving key dimensions, so touching keys
can gain a gap. The first band anchors each pad, with Mirror Edit and undo retained. While editing a STENO
layout, the live runtime is temporarily configured with empty non-STENO key regions
and no custom buttons. This uses normal gesture recognition without steno chords or
force-mouse interception. Apply/Cancel restores the selected STENO runtime through
the shared reconfiguration/cleanup path; no gesture or STENO preferences are changed.

Keymap Tuning no longer offers the separate Custom Buttons creation, deletion or
geometry editor. New keys and columns are authored in Layout Editor. Existing saved
custom buttons still load, render and dispatch their assigned actions; their
serialized representation remains supported.

Mirror Edit defaults on for each edit session. Existing counterpart keys are paired
once by mirrored geometry and persist their UUID relationship through later edits.
Movement, size and angle deltas are reflected across the pair while preserving
existing asymmetry, each side's legends and layer assignments. Dashed outlines
preview the affected counterparts. Added keys/columns create pairs; deletion and
duplication include existing counterparts. Unmatched keys stay independent, including STENO Single's right-only geometry.
Mirror Edit off allows independent edits; turning it back on does not realign keys.
Mirrored edits undo/redo together as one document transaction. Pair relationships
round-trip with the document through settings and captures.

The editor snapshots the seed/template only when opened and draws staged geometry
with Canvas instead of the live contact visualizer. Labels are cached and validity
is checked at transaction boundaries, not on every drag frame. Dragging never
reconfigures recognition or posts output; only Apply compiles/publishes geometry.

Documents use UUID identities with immutable opaque binding slots. Physical position
never depends on that slot; deletion never renumbers neighboring keys. Added keys
receive fresh slots, and duplicated keys copy each layer's assignments at Apply.
Per-template documents are saved under `AMT.LayoutDocuments`, exported in the Mac
host extension and recorded in capture profiles. Production replay compiles those
same documents. Invalid geometry is rejected. The spatial index chooses bucket
density from physical key count, independent of sparse binding addresses.

STENO documents explicitly store the template's visible edge extensions. Moving
keys preserves that authored shape instead of inferring new overlaps from row
neighbors. Existing STENO hit allowances, chord accumulation, force/mouse behavior
and output transport remain unchanged. Normal keyboard hit testing retains its
single-winner overlap rule. Structural editing does not add work to live frames.

## STENO layouts and Gemini PR

`STENO` follows the [Asterisk v2](https://stenokeyboards.com/products/asterisk-v2)
arrangement: broad number bars, two consonant rows, tall inner star keys and A/O,
E/U thumb pairs. `STENO 6x3` uses the supplied Voyager image's staggered 6×3
main grid plus those thumb pairs. All STENO variants are editable in Layout Editor.
The Asterisk template key bounds follow the
[maker’s layout drawing](https://docs.stenokeyboards.com/images/keyboard-layouts/asterisk.svg),
calibrated to the published 234 mm board width and centered independently on each
pad without stretching. For stationary row chords, both consonant rows extend
into their middle gap until they touch. Number bars extend downward
to touch the upper keys beneath them. Steno Single uses the same touching-row
and number-bar treatment. Both layouts’ bottom vowel/thumb bars extend downward
to a 0.8 mm pad-edge margin, preserving their top edges. Asterisk and Single’s
consonant keys are exactly 25 mm tall per row, placed edge-to-edge; stars span
both rows at 50 mm. Number bars stay fixed and the row seam stays closed.
The renderer extends both row outlines 1.5 mm into the neighboring row, showing
the existing 3 mm shared hit band on Asterisk and Single. Highlights and selection
use the same display outlines. This does not expand recognition a second time;
The same display overlap applies equally above/below the number-bar seam. A/O
and E/U base rectangles widen toward their pair midpoint, with the same 3 mm
shared hit/display band between each pair. Outer pair edges stay fixed during widening. Single then translates all four
thumbs together to place A beneath R- and U beneath -R, preserving thumb
widths, pair overlap and horizontal spacing. Single’s thumbs extend upward to
the same top edge and height as Asterisk’s thumbs, retaining their bottom margin. Stars
and the 6x3 layout keep their own outlines. Key widths remain from the drawing. Snap Radius does not participate in STENO; the fixed 1.5 mm steno key
edge allowance remains independent of the keyboard toggle. The
maker does not publish separate v2 copper-pad dimensions in that drawing. `STENO single` packs both
Asterisk halves on the RHS only; the LHS key surface is blank. It has two number
bars, 10 upper keys, 9 lower keys and A/O/E/U thumbs. One tall central star spans
both consonant rows. Each letter bank moves 3.2 mm outward, leaving 0.8 mm outer
margins; the star gains the freed 6.4 mm (about 26.1 mm total width). The nine
letter columns have equal width (about 13.1 mm on a 160 mm pad). Gemini PR's star
slots all map to the same `*` in Plover's default keymap; this layout emits star1.
All wire identities remain supported for older profiles/captures.

The main layout menu groups these under **STENO**. The STENO panel's **Layout**
selector, directly above Connection and the STENO Mouse controls, offers Steno Asterisk, Steno 6x3 and Steno
Single. It changes the existing saved preset binding, preserving per-layout
settings and transport behavior. Returning to STENO within the sidebar recalls
its last selected variant. All presets retain per-key edits and separate saved
layout namespaces. `STENO single` uses the existing chord/Gemini PR engine,
mouse/force controls, haptics and lifecycle gates with no new recognizer or live
transport. The displayed `STENO 6x3` preserves the
serialized `STENO Voyager` name; both names resolve on import. `STN_*` catalog actions identify the 42
Gemini PR wire positions; they are inert in ordinary keyboard layouts.

STENO replaces ordinary typing and pauses ordinary gestures except Outer Corners → Open Config. Selected
pads retain the normal live routing, listening and lifecycle admission.
Making/touching non-palm contacts accumulate every intersected steno key; key edges
expand 1.5 mm to permit upper/lower row combinations under one fingertip. Keys roll
into one shared stroke while either pad has contacts, including contacts between
keys. Both-pad all-up sends exactly one stroke. Invalid coordinates, non-monotonic
or stale active delivery (>250 ms), overflow (>16 non-palm contacts per frame),
device loss, reset and layout/mapping/layer changes cancel the partial stroke and
wait for remaining contacts to lift. Switching into or out of STENO cannot turn
held contacts into a new stroke or ordinary key press.

STENO has one fixed mouse behavior and no mode dropdown: two-finger movement,
two-finger force left-click, three-finger force right-click, and one-finger force
left-button hold/drag, plus four-finger force scroll. The retired Off/1F mode values remain decodable in settings;
all saved choices resolve to the fixed behavior. Existing profile and capture
identities remain unchanged.

The shared continuous session/coherence engine requires 2 mm of coherent
translation by two contacts to activate ordinary mouse movement. Light single
fingers, stationary contacts and motion by only one finger of a two-finger chord
remain steno. Before activation, exceeding two contacts excludes movement through
local all-up, so larger strokes cannot become a mouse at partial lift. If both
pads participate before a mouse/drag activates, the cycle retains steno priority.
A mouse/drag win discards the pending whole stroke and owns that cycle through
both-pad all-up; subsequent contacts cannot resurrect typing. Once activated,
the other pad may share the cursor or join the held drag.

The STENO panel exposes a Force Threshold slider with a numeric value (1–500, default 130), shared by 1F drag,
2F left-click, 3F right-click and 4F scroll activation. Higher values require more pressure. The slider previews its value during tracking
and commits on release so adjusting it with 1F drag cannot cancel its own drag. It is saved
and exported under the existing Mac gesture settings; missing imported thresholds
preserve the current value. Editing it cancels pending strokes/held output and
waits for held contacts to lift before using the new value. Non-finite values
resolve to 130 and out-of-range values clamp to the supported range. Ordinary
gestures retain their existing force threshold. Two contacts emit one balanced
primary click; three emit one balanced secondary click, stationary or moving.
One contact presses the primary button once and holds it until that pad's all-up:
motion by that finger drags without requiring two fingers or continued pressure.
Pre-force movement is excluded from drag activation so pressing cannot jump the
cursor by replaying earlier single-finger travel.
Additional contacts and partial lifts retain the owner. A stationary force-press
and lift is a click; a light single-finger slide remains steno. The shared drag
ledger lets either pad move the cursor and releases the system button only after
the last drag owner lifts. A force owner cannot fire another force action until
all-up. Force recognition retains identity, count and validity checks, so larger
chords cannot turn into force clicks during partial lift.

Four-finger Force uses the same STENO threshold to latch scroll on its originating
pad. After activation, pressure may drop and contacts may reduce to one or rejoin;
the scroll owner remains until that pad's all-up. Pre-force travel is discarded.
The shared contact-motion tracker follows matched identities, avoiding centroid
jumps when membership changes. An invalid sample, stale gap, complete identity
replacement, disconnect or lifecycle/configuration reset cancels, and surviving
contacts cannot reacquire scroll before all-up. Larger pending chords cannot turn
into force scroll during partial lift. A previous force owner stays first until
all-up, so adding fingers to a held drag cannot change it into scroll.

Scroll uses the ordinary FourFingerScrollEngine/PreciseScrollOutput with the pad's
saved sensitivity and natural-scrolling preference and existing Apple scroll profile.
Native selected/owned/armed/AX/profile gates remain. Normal all-up hands recent velocity to the shared ScrollMomentum engine; a pause
before lifting produces no stale fling. Invalid input, generation changes and
lifecycle cancellation stop its phase and momentum. A new contact on either selected
pad brakes released momentum without reserving the new steno chord. Reserved cleanup survives queue
reset/generation changes and cannot release another pad's drag/scroll. Gesture
feedback reads “4F force scroll.” Replay records scrollBegin/scroll/scrollEnd under
the existing StenoMouse system-event envelope and posts no native events. Winning
scroll cancels the pending chord, key highlight and pending typing haptics.

STENO uses the same retained drag source, button observer, stale-owner timer,
acceleration and per-pad cleanup as ordinary drag gestures. Native button
interference, stale/invalid input, disconnect, layout/mapping/layer changes,
suspend and reset release acquired ownership; cleanup survives output-queue
cancellation and mode changes. A disconnected pad releases its ownership without
releasing another pad's hold. Drag-down is edge-triggered and cannot restart from
continuing contacts after native output cancellation. Other gestures except the configuration corner chord remain paused.

Pointer and click commands use the shared output queue, native numeric device ID,
Apple tracking profile/sensitivity, cursor bounds and existing discrete click
builder. Selected/owned/armed/takeover/Accessibility and profile gates control live
output; reconfiguration/lifecycle cancellation invalidates queued commands and
partial strokes. Replay records `StenoMouse:` intentions in the existing system
event envelope without posting input. Other saved gestures are
restored on leaving STENO. STENO does not change ordinary keyboard arbitration.

STENO force activation uses the ordinary fixed Force haptic (waveform 6, level
0.25) once on the originating pad for 1F drag, 2F left-click, 3F right-click and 4F
scroll. It is independent of the typing touch/release checkboxes and Typing Tuning
strength. The live, selected/owned/armed/AX-gated output adapter applies the same
50 ms per-pad Force throttle; held pressure, motion and all-up never retrigger it.
Replay records intentions only and never enters the hardware haptic adapter.

Two independent STENO checkboxes enable **Haptic on touch** and **Haptic on release**,
both off by default. They use the existing Typing Tuning strength, waveform 6 and
per-pad throttle. Touch feedback queues on a new key contact edge, without repeats for held keys.
It waits through an 80 ms settling window so early mouse/force acquisition can
cancel it; a valid shorter tap flushes its touch feedback at completion. Release feedback pulses the pads that contributed keys when the
whole valid stroke finishes. Pointer/force activation, invalid/stale input and
cancellation discard pending touch and release feedback. Mouse acquisition also
invalidates queued native feedback independently of completed stroke packets.
Pulses that already played cannot be recalled if motion begins after the settling
window. Very short touch/release pulses coalesce under the shared per-pad throttle.
Configuration changes alone never pulse.
These events use generation-gated output commands and the existing capture haptic
envelope; replay records them without touching hardware. Missing imported options
preserve saved values.

Per-pad and coordinated Both **Outer Corners** remain Hold → Open Config in
STENO, using the shared geometry, stagger, saved hold threshold, timer and cleanup.
Other coordinated/corner actions stay paused. The shared live runtime reserves
these contacts before steno dispatch; a pending or fired corner chord cannot emit
steno keys. Activated mouse/drag owners keep priority until all-up. Configuration
is app-local and does not require an acceleration profile or Accessibility for
its own action; normal selected/owned/armed/takeover gates remain. Leaving STENO
restores the ordinary gesture assignments.

The Connection selector offers the existing Gemini PR Serial endpoint and a
**Plover Plugin** loopback connection. The plugin is the default for missing/new preferences; an explicitly saved serial
choice stays serial. Plugin mode listens only on `127.0.0.1:31572`, with the same HELLO/READY
handshake and six-byte Gemini PR frames as the Windows plugin. It automatically
reconnects, bounds setup time/output buffering, rejects invalid setup or commands,
and drops disconnected/full output rather than storing strokes for reconnect.
Switching transports invalidates queued output and closes the previous transport;
only one sends at a time. Lifecycle reset closes the plugin reader so buffered
partial packets cannot carry into the next connection. Replay opens neither.

**Install Plugin / Update Plugin** uses the bundled deterministic wheel and the
installed Plover.app's Python/plugin installer. Installation is explicit-button
only, offline (`--no-index --no-deps`, reinstalling the bundled wheel), and scoped to Plover's user-plugin directory.
It does not launch Plover or edit its machine/output settings. Status/error output
is visible. The green/red connection status sits in the left half below Connection; the
install button occupies the right half below the transport picker. Touch/release
haptic checkboxes share an equal-width row. A read-only probe checks Plover's actual plugin environment,
entry point and installed source against the bundled wheel. Matching installations
disable the button as “Plugin Installed”; missing or modified copies keep Install
or Update available. Detection refreshes on panel entry, app activation and after
installation, without starting Plover's GUI or changing its settings.
After installation, restart Plover and choose AppleMagicTouchstream
under Configure → Machine. The source/builder and usage are in
[PloverPlugin](PloverPlugin/README.md); the Windows copy remains intact.

The shared output queue sends six-byte packets using
[Plover's Gemini PR wire order](https://github.com/openstenoproject/plover/blob/main/plover/machine/gemini_pr.py).
In Gemini PR Serial mode, choosing STENO opens a private user-space PTY and
displays a Copy Port path. In
Plover, Configure → Machine → Gemini PR, paste this path into Port and select
9600 baud, 8 data bits, no parity, 1 stop bit, no flow control; enable Plover output.
Plover configures its serial reader in raw mode. No driver/helper is installed.
Switching between STENO variants preserves the port; leaving STENO or
quitting removes it. A fresh serial session has a fresh path and needs reconnection;
the plugin connection instead reconnects automatically.
Disconnected/full output drops strokes rather than queuing them for later;
interrupted partial writes close the stream and show a reconnect error. Lifecycle
cleanup invalidates queued strokes and flushes the port. Replay records intended
packets as `GeminiPR:` plus twelve hex digits in the existing system-event envelope;
it never opens the live port or sends serial/native keyboard output.

Key highlights follow accepted keyboard actions, including snapped keys, custom
buttons and completed STENO chords. Candidate contacts and gesture-owned contacts
never highlight keys. STENO feedback waits for the completed valid stroke, so a
mouse/force/cancelled chord cannot flash keys. A bounded UI history fades each
accepted key's green fill/outline over 1.2 seconds; accepting it again restarts its
fade. Geometry retains key rotation. The 30 Hz animation stops when empty or closed.
This display does not change recognition, output timing or inspector selection.

Recognized gestures appear beside Peak on the originating pad for two seconds
since the latest recognition update. Both gestures report on both pads. Candidates
do not appear. Feedback is observational and never becomes recognition evidence;
it expires or clears on interpreter stop, without altering ownership/cleanup.

The Plover plugin listener retries a failed bind once per second while enabled.
SO_REUSEADDR permits rapid reuse after an earlier TCP session, while exclusive live
listener ownership is retained (no SO_REUSEPORT). Retry Connection attempts the same
listener without disturbing an established client. Stop disables retries atomically;
no UI refresh can reopen a disabled transport. The plugin still owns client reconnect,
and disconnected strokes are dropped rather than buffered.

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

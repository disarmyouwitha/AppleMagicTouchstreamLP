# Windows Mac-parity rewrite

Implemented against the current maintained Mac app. Mac source and personal
keymaps are untouched. Existing enum values and raw ATPCAP bytes are preserved.

## Implemented

- Authored layout documents with stable key/mirror identities, independent hand
  actions, sparse rows, per-layer visibility, physical-mm rotation, visual/hit
  overlap, settings import/export and startup compilation. Mac bundled DEFAULT
  geometry/label snapshots seed templates; they do not read a Mac installation.
- Inline both-pad Layout Editor: fixed 1 mm snap, default Mirror Edit, marquee/
  Shift selection, move and one selection resize frame, numeric dimensions and
  X/Y spacing, scale/rotate/align/distribute, spacing ±5%, duplicate/delete,
  add key/column and layer, undo/redo/reset/cancel/apply, button pulses, Show
  Contacts on a separate 30 Hz overlay, Layer0 on exit. Legacy custom buttons
  migrate into drafts with primary/hold/force assignments. Apply alone commits.
- STENO main picker and Asterisk / 6x3 / RHS Single variants. Current Asterisk
  25 mm consonants, #/row/vowel overlaps, and Single thumb geometry. STENO 6x3
  uses the Mac DEFAULT authored geometry snapshot. STENO menus show steno codes.
- Fixed STENO 2F coherent pointer, 1F force held drag/select, 2F primary force
  click, 3F secondary force click, latched 4F force scrolling and momentum.
  Independent pads share the cursor/button; the last drag owner releases.
  Force threshold slider and independent touch/release haptics; touch feedback
  settles for 80 ms and cancels with pending chords. Force feedback is fixed.
  Configurable gestures stay inactive; per-pad/Both Outer Corners opens Config.
  Editor temporarily restores ordinary gestures; Show Contacts excludes 4F/5F.
- Both 3+3 / 4+4 force actions: reported force on each pad, 150 ms crossing skew,
  1 second cohort join, once through both-all-up. Old owners block late takeover.
  Pending corner pairs can grow before activation, never replace fired owners.
- Built-in Javelin (Lapwing) default, Built-in Javelin (Plover), or existing Plover
  plugin. Bundled public dictionaries and native DLL ship with the app. Dictionary
  manager loads/creates/exports/edits JSON, controls priority/enabled state and
  records strokes. Editing bundled data requires Save As; removing a custom source
  does not silently enable another. Mouse activity resets translation history.
- Saved Text in keyboard/gesture Shortcut Builder: hidden until revealed, no name
  required, DPAPI CurrentUser encrypted files and opaque TEXT_SHORTCUT references.
  Incremental Unicode typing uses the existing output pump, never the clipboard.
  Focus, lifecycle and gesture-generation cancellation; visible output errors.
  Physical/owned modifiers cancel text output rather than releasing other owners.

## Storage and limits

Saved text is under the app user-data directory's `text-vault`. DPAPI encrypts
for the Windows account; another program running as that account can decrypt it.
Exports/captures carry references only, so another computer/account needs text
re-entry. Plain JSON translation dictionaries intentionally remain editable.
Windows secure desktop and higher-integrity targets cannot be bypassed by SendInput.

Captures have an additive `.atpcap.settings.json` companion for the initial
profile/documents. Keep it beside the capture. This is not Mac's mid-capture
configuration timeline; older captures still use explicit/default configuration.
Replay never reads the secret vault or posts native input.

Windows PTP remains limited to five contacts per pad and has no positive finger
anatomy. Thumb-dependent gestures retain existing conservative availability rules.
Built-in Javelin supports text dictionaries/formatting/undo, not Python dictionaries,
Plover plugins/modal commands or raw-key commands. The bundled DLL is Windows x64;
see JavelinNative/README.md for rebuild/provenance and licenses.

## Verification completed on the Mac host

- Windows Release cross-build with Windows targeting enabled.
- Portable existing hand-gesture regressions, STENO core/actor tests, dynamic
  template/mirror/layer/history/migration tests, shared force/mouse ownership,
  Both force timing, text reference semantics and capture companion round-trip.
- Captured Mac pointer/scroll vectors and momentum/braking regression suite.
- Host native Javelin: formatting, replacement, undo, aliases, priority, inert
  unsupported commands, Lapwing/Plover content checksums and Record interception.
- Private ephemeral plugin socket handshake/wire/generation/takeover tests.

No live input, takeover, haptic output, personal vault writes or live Plover port
were used. The DLL PE exports/imports were inspected; actual Windows DLL loading,
WPF rendering, DPAPI, SendInput and trackpad feel require Windows acceptance.

## First Windows run

Build Release, then run `--selftest` before enabling input. Test all three STENO
variants, both built-ins and the plugin; force 1/2/3/4F, shared-pad drag release,
scroll momentum and Outer Corners. In the editor test Mirror on/off, each layer,
legacy buttons, undo/cancel/apply/reset, Show Contacts and exit to Layer0. Test
Both force within/outside timing windows. Save a nonsensitive Text assignment,
restart, reveal/type it, confirm clipboard preservation, and confirm export has
only its reference. Exercise emergency release and device loss with keys held.

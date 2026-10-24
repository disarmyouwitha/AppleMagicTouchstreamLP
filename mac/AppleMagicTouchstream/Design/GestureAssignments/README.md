# TouchStream gesture map and assignment editor study

Research and design only, 2026-10-24. No recognizers, settings, app UI or installed
applications were changed by this study.

## Recommendation

Use **one assignment workspace**, replacing the visualizer area while editing
Gestures. Keep a narrow, optional live-contact preview in the inspector, with an
obvious return to the normal Keyboard/trackpad view. The current small gesture
sidebar cannot comfortably hold the full TouchStream vocabulary.

Browse by **chord**, grouped by contact count, with Thumb as an explicit part of
the name. Within a chord, expose **Motion**, **Tap**, **Hold**, and **Lift** as
assignment slots. The motion panel adapts to XY movement, directional movement,
scale, and rotation; these do not need three unrelated editors. Use the same
action picker and output/behavior inspector everywhere.

A chord is more than its count. Its identity includes hand, fingertip/thumb roles,
compact/spread arrangement, optional zone and active context/set. For example:

| Chord | Arrangement/context | Motion | Result in the guide |
|---|---|---|---|
| Three fingertips | Compact, mouse hand | XY | Drag |
| Three fingertips | Compact, left hand | Four directions | Text selection |
| Thumb + three fingertips | Compact, mouse hand | Rotate CCW | Open |
| Thumb + three fingertips | Spread, mouse hand | Rotate CCW | Show Desktop |
| Thumb + two fingertips | Compact, left, Formatting | Move up | Bold |
| Thumb + two fingertips | Spread, left, Formatting | Move up | Justify |

**Do not organize the primary navigation by output** (Mouse, Editing, Files).
Those are useful search filters/presets, but users will remap the outputs. “Drag &
Double Click” is a friendly preset subtitle, not the permanent recognition ID.

## Deliverables

- [Full map](GESTURE_MAP.md): 165 rows covering every named operation/variant on
  the four Quick Guide pages, including game and optional modes. Rows split
  directions and button-state variants; this is **not 165 independent recognizers**.
- [CSV](gesture-inventory.csv) and [JSON](gesture-inventory.json): searchable data.
- [Mockup source](mockups.html): standalone, inspectable UI with three local
  scenarios and hand/chord selectors. All changes are temporary to the preview.
- Screenshots: [XY + lifecycle](01-motion-lifecycle.png),
  [directions](02-directions.png), [scale + rotation](03-scale-rotation.png).
- [Source hashes](source-provenance.json).

## What the references tell us

The original utility puts direction buttons spatially around a chord, then opens
an event editor. Kara's examples preserve that spatial map while making the
trigger and output easier to read. Her Drag page and Text Selection page differ
because XY is one continuous action, while up/down/left/right can have independent
outputs. The comparison PDF also shows a list-based chord page with a shared
inspector. These are presentation choices around the same underlying model.

The supplied examples establish two spatial layouts; the comparison PDF establishes
a third useful motion family (scale/rotation). They do **not** establish a need
for three different action-editing systems. Retain a common header, scope control,
assignment cards, lifecycle row and inspector; adapt only the motion arrangement.

## Proposed workspace

- Toolbar: Keyboard / Gestures; Left / Right / Both; per-hand takeover state.
- Left: search and chord list grouped by contact count. Show “3 fingertips” apart
  from “thumb + 2 fingertips”, despite both having three contacts.
- Center: chord title, anatomy dots, arrangement and context. Assignment cards
  for the available motion channels; tap/hold/lift remain in a consistent row.
- Right: selected trigger's Action, Behavior, sensitivity, and conditions. Keep
  “None” visible for unused slots instead of silently hiding them.
- Both: a mixed assignment must display Mixed, with left/right values visible.
  Changing it edits both; inspecting must never silently copy one side.
- Unsupported/future recognizers: visible only in a clearly marked catalog or
  disabled state, not presented as working controls. Mockups explicitly say
  “Design preview”; guide presets are not current app defaults.
- A compact “Show contacts” preview is optional; it should not consume the large
  canvas needed for assignments.

## Behavior belongs beside the action

| Behavior | Meaning | Example |
|---|---|---|
| Follow motion | Continuous delta stream | Pointer, dragging, pan, native zoom |
| Repeat with motion | Discrete steps proportional to motion | Arrow keys, word navigation |
| Once | Fire once when motion commits | Cut, Save, Open |
| Quick stroke | Historical fast-shot policy; exact timing requires implementation research | Tab, application switching |
| Hold until lift | Balanced down/up lifetime | Shift chord, Hotbox, mouse drag |

Sensitivity is not an action. Chord shape is not motion. “Spread arrangement” is
a starting posture; “Spread motion” means increasing scale after landing. Keep
those words distinct in labels: **Arrangement: Spread** versus **Motion: Spread**.
The original sensitivity dialog edits a shared template; our current pointer and
zoom settings already have shared scopes. Show that scope explicitly rather than
pretending a slider belongs only to the selected assignment.

Lift normally ends the active session and releases its held keys/buttons. Cleanup
is an engine guarantee, not an optional user macro. A future Lift assignment may
add output, but must never replace mandatory cleanup. Likewise cancellation,
disconnect, stale frames and emergency release must balance held output.

## Recognition implications and rollout

1. Introduce chord/trigger/action presentation around **working** app gestures;
   preserve serialized bindings and thresholds. Mockups are not authorization to
   implement new recognition or migrate defaults.
2. Extend recognition deliberately: thumb role, arrangement competition, direction,
   rotation and per-hand context are distinct additions. Generic count-only
   dispatch would collide with typing, modifiers and compact/spread chords.
3. Add reusable keyboard actions, hold lifetimes and motion-step behavior to the
   common assignment picker. Keep raw sequences in an advanced editor.
4. Add optional preset sets and conflict explanations. Historical Photoshop,
   Maya, Emacs and Desktop sets are alternative contexts, not all-on defaults.
5. Defer special palm/knuckle/game and two-hand modes until capture support and
   recognition semantics are validated. A game chord can add button contacts
   while continuing motion; an all-up-only count latch alone is insufficient.

## Current implementation versus source

AppleMagicTouchstream currently supports configurable pointer/drag/scroll, taps,
thumb+two-fingertip right tap, 1–5 force clicks, thumb-required 2–5-contact
pinch/spread, and selected system/media actions. It does **not** implement the
entire guide. Force-click is our Apple pressure extension, not a Quick Guide
trigger. Our current mirror-friendly per-hand assignments are intentionally not
the original left-navigation/right-pointer defaults.

Historical guide diagrams recommend finger sets. They are not a complete firmware
whitelist. Existing research found count fallback and arrangement competition;
do not turn each illustration into an exact-only rule without corroboration.
The 2001–2003 card and shipped 1.60 templates also differ. We mark XML-only
clarifications rather than silently adding them to the guide inventory.

## Sources inspected

- Quick Guide, all four PDF pages: core; optional applications; programmer/Emacs,
  modifiers/two-hand; game. Local original:
  `/Users/nap/Documents/new_code/touchstream-archive/docs/TouchStream_QuickGuides.pdf`.
  Public mirror: https://images-na.ssl-images-amazon.com/images/I/91xS3iP3tHL.pdf
- Installation/Operation booklet, particularly PDF pages 4 (gesture basics), 6–8
  (modifiers), 11–12 (optional sets/game). Printed page numbers differ from PDF
  indices. Local `docs/TouchStreamBooklet.pdf` in the same archive.
- `TouchStream_for_Mac_vs_Utility_1.60.pdf`, 24 pages; visually reviewed PDF pages
  6–10 for chord, event, slide/sensitivity and adding-gesture UI. Its prose is the
  comparison author's assessment, not independently proven firmware behavior.
- Both supplied Kara JPGs, read visually.
- Original `FW_chord_macros.xml`, `FW_stealth_chords.xml` and
  `FW_parameter_macros.xml` preserved under the archive's
  `firmware-analysis/rea-investigation/right-click-2026-10-21/`.
- Existing local `FINDINGS.md`, `mac/FINDINGS.md`, and current app
  `GESTURE_ENGINE.md`, used to distinguish historical facts from current policy.

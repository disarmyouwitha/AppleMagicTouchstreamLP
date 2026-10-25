# TouchStream gesture / action map

Research map, 2026-10-24. **165 inventory rows**, not 165 recognition engines.
Directional variants and simultaneous game-button states are intentionally split.
The scope is all four pages of the Quick Reference Guide, not every possible
custom macro or undocumented 1.60 gesture.

## Reading the map

Contacts include the thumb unless the chord explicitly says fingertips only.
T = thumb, I = index, M = middle, R = ring, P = pinky. “Thumb + 3” means **four**
contacts. “Both” means coordinated two-hand input, not the same gesture enabled
independently on both pads. Q1–Q4 are Quick Guide PDF pages. B is the operation
booklet (PDF page indices); X names an original 1.60 XML template. XML is used to
clarify direction and context, not to claim the guide documents every extra slot.

Guide artwork gives recommended anatomy/arrangement. Specific TMR examples are
not proof that firmware rejects every alternate fingertip pair. Hands labeled
“shown” come from the illustration; the card alone does not prove exclusivity.
Default right mouse / left navigation comes from the shipped mapping. Optional
sets can remap the same chord, and OS/layout context changes output shortcuts.

## General trigger rules and restrictions

- Initial anatomy and movement select the gesture. The operation booklet allows
  adding unused contacts or lifting all but one after some motion gestures begin.
  This is evidence for continuation latching, not a universal policy for every
  tap, modifier, game, or configuration chord.
- Maintain contact during movement; all-up ends the operation. Crisp taps are
  distinct from holds and motion. The guide does not supply universal numeric
  tap duration, movement threshold, spread distance or rotation-angle limits.
- Keep fingers comfortably separated and the thumb apart from fingertips.
  Compact/spread describes the starting geometry, while pinch/spread describes
  a change of scale. They must remain separate dimensions in the editor.
- Quick strokes can generate single steps. Longer motions may repeat according
  to the selected template. Once, quick-shot, repeat-with-motion and continuous
  output must not be collapsed into a single “move” toggle.
- Left optional sets start disabled. Photoshop, Maya and Desktop/Tools overlap;
  the booklet explicitly warns against enabling incompatible combinations.
- Historical Ctrl/Meta examples are not universally valid current macOS commands.
  The application guide notes Ctrl→Cmd in Mac mode, but Emacs and mixed-modifier
  sequences need their own mappings. Preserve source labels and choose modern
  outputs explicitly.
- P:130 force clicks, momentum tuning, present app tap timing and Apple
  haptic parameters are **not** guide facts. They belong in current-engine policy.

## Source coverage and uncertainty

All guide sections appear below, including specialized modes that are not planned
for immediate implementation. Maya's combined zoom/rotate card, XWinder's external
window protocol, and exact palm/knuckle sensing are incomplete specifications.
No timings or hard geometric classifier thresholds are invented for those cases.
Named XML clarifications are explicitly marked. For layout recommendations,
current implementation status and source provenance, see [README](README.md).

## Inventory

### Core / Mouse

| ID | Contacts / chord | Hand / arrangement | Trigger | Action | Restrictions / evidence |
|---|---|---|---|---|---|
| G001 | 2 — 2 adjacent fingertips | Mouse hand (right by default); Adjacent | Move XY | Point | Begin with the required adjacent fingertips; tap is light and brief. [Q1] |
| G002 | 2 — 2 adjacent fingertips | Mouse hand (right by default); Adjacent | Tap | Primary click | Begin with the required adjacent fingertips; tap is light and brief. [Q1] |
| G003 | 3 — 3 adjacent fingertips | Mouse hand; Adjacent | Tap | Double click | One three-finger tap; not a double tap. [Q1] |
| G004 | 3 — Thumb + middle + ring | Mouse hand; Thumb separated | Tap | Secondary click | Pictured recommendation, not a proven exact-only firmware whitelist. [Q1] |
| G005 | 3 — 3 fingertips | Mouse hand; Row / relaxed | Move XY (slide or roll) | Drag / select | Held mouse action needs a balanced release at gesture end. [Q1] |
| G006 | 4 — 4 fingertips | Mouse hand; Relaxed | Move up / down (slide or roll) | Scroll | The core card shows vertical scrolling; horizontal pan also exists in 1.60 XML. [Q1] |
| G007 | 5 — Thumb + 4 fingertips | Mouse hand; Whole hand | Spread / pinch | Zoom in / out | Source zoom is a scale gesture; original output may be hotkeys/wheel, not our native magnification events. [Q1] |

### Core / Text navigation

| ID | Contacts / chord | Hand / arrangement | Trigger | Action | Restrictions / evidence |
|---|---|---|---|---|---|
| G008 | 2 — 2 fingertips | Left; Adjacent | Move up | Arrow up |  [Q1] |
| G009 | 2 — 2 fingertips | Left; Adjacent | Move down | Arrow down |  [Q1] |
| G010 | 2 — 2 fingertips | Left; Adjacent | Move left | Arrow left |  [Q1] |
| G011 | 2 — 2 fingertips | Left; Adjacent | Move right | Arrow right |  [Q1] |
| G012 | 3 — 3 fingertips | Left; Row / relaxed | Move up | Select up | Typically Shift + arrow; map semantic actions for modern macOS. [Q1] |
| G013 | 3 — 3 fingertips | Left; Row / relaxed | Move down | Select down | Typically Shift + arrow; map semantic actions for modern macOS. [Q1] |
| G014 | 3 — 3 fingertips | Left; Row / relaxed | Move left | Select left | Typically Shift + arrow; map semantic actions for modern macOS. [Q1] |
| G015 | 3 — 3 fingertips | Left; Row / relaxed | Move right | Select right | Typically Shift + arrow; map semantic actions for modern macOS. [Q1] |
| G016 | 4 — 4 fingertips | Left; Relaxed | Move left | Home | Home/End semantics are OS dependent; do not assume a Windows keycode is the Mac equivalent. [Q1] |
| G017 | 4 — 4 fingertips | Left; Relaxed | Move right | End | Home/End semantics are OS dependent; do not assume a Windows keycode is the Mac equivalent. [Q1] |
| G018 | 4 — 4 fingertips | Left; Relaxed | Move up | Page Up | Home/End semantics are OS dependent; do not assume a Windows keycode is the Mac equivalent. [Q1] |
| G019 | 4 — 4 fingertips | Left; Relaxed | Move down | Page Down | Home/End semantics are OS dependent; do not assume a Windows keycode is the Mac equivalent. [Q1] |
| G020 | 2 — Thumb + 1 fingertip | Either (exception to left-hand heading); Thumb separated | Move right | Tab | A quick stroke gives one step; longer motion may repeat. Guide illustrates thumb + middle. [Q1] |
| G021 | 2 — Thumb + 1 fingertip | Either (exception to left-hand heading); Thumb separated | Move left | Back Tab | A quick stroke gives one step; longer motion may repeat. Guide illustrates thumb + middle. [Q1] |

### Core / Editing

| ID | Contacts / chord | Hand / arrangement | Trigger | Action | Restrictions / evidence |
|---|---|---|---|---|---|
| G022 | 2 — Thumb + pinky | Shown on right; Wide / spread | Tap after spreading | Enter | The spread arrangement is established before the tap; not a pinch-to-Enter gesture. [Q1] |
| G023 | 2 — Thumb + middle | Shown on right; Thumb separated | Pinch | Cut | Undo/Redo: quick stroke for one step. XML confirms up = Undo, down = Redo. [Q1] |
| G024 | 2 — Thumb + middle | Shown on right; Thumb separated | Tap | Copy | Undo/Redo: quick stroke for one step. XML confirms up = Undo, down = Redo. [Q1] |
| G025 | 2 — Thumb + middle | Shown on right; Thumb separated | Spread | Paste | Undo/Redo: quick stroke for one step. XML confirms up = Undo, down = Redo. [Q1] |
| G026 | 2 — Thumb + middle | Shown on right; Thumb separated | Move up | Undo | Undo/Redo: quick stroke for one step. XML confirms up = Undo, down = Redo. [Q1] |
| G027 | 2 — Thumb + middle | Shown on right; Thumb separated | Move down | Redo | Undo/Redo: quick stroke for one step. XML confirms up = Undo, down = Redo. [Q1] |
| G028 | 3 — Thumb + middle + ring | Shown on right; Thumb separated | Pinch | Find | Guide gives a pictured finger set; selection policy may be broader. [Q1] |
| G029 | 3 — Thumb + middle + ring | Shown on right; Thumb separated | Rotate (CW shown) | Group / search again | Application-dependent label. Core card does not label both rotation directions; 1.60 XML adds Group CW and Ungroup CCW. Do not invent a universal Group hotkey. [Q1] |

### Core / Files and browsing

| ID | Contacts / chord | Hand / arrangement | Trigger | Action | Restrictions / evidence |
|---|---|---|---|---|---|
| G030 | 4 — Thumb + 3 fingertips | Shown on right; Compact | Rotate CCW | Open | Use the pictured arrangement; keep thumb away from fingertips for browser motions. Refresh/replace is the card wording, not one universal app command. [Q1] |
| G031 | 4 — Thumb + 3 fingertips | Shown on right; Compact | Rotate CW | Close | Use the pictured arrangement; keep thumb away from fingertips for browser motions. Refresh/replace is the card wording, not one universal app command. [Q1] |
| G032 | 4 — Thumb + 3 fingertips | Shown on right; Compact | Pinch | Save | Use the pictured arrangement; keep thumb away from fingertips for browser motions. Refresh/replace is the card wording, not one universal app command. [Q1] |
| G033 | 4 — Thumb + 3 fingertips | Shown on right; Compact | Spread | New | Use the pictured arrangement; keep thumb away from fingertips for browser motions. Refresh/replace is the card wording, not one universal app command. [Q1] |
| G034 | 4 — Thumb + 3 fingertips | Shown on right; Compact | Move left | Back | Use the pictured arrangement; keep thumb away from fingertips for browser motions. Refresh/replace is the card wording, not one universal app command. [Q1] |
| G035 | 4 — Thumb + 3 fingertips | Shown on right; Compact | Move right | Forward | Use the pictured arrangement; keep thumb away from fingertips for browser motions. Refresh/replace is the card wording, not one universal app command. [Q1] |
| G036 | 4 — Thumb + 3 fingertips | Shown on right; Compact | Move down | Refresh / replace | Use the pictured arrangement; keep thumb away from fingertips for browser motions. Refresh/replace is the card wording, not one universal app command. [Q1] |

### Core / Application control

| ID | Contacts / chord | Hand / arrangement | Trigger | Action | Restrictions / evidence |
|---|---|---|---|---|---|
| G037 | 4 — Thumb + 3 outer fingertips | Shown on right; Spread; start near surface edges | Rotate CCW | Show / open desktop | Spread the chord BEFORE motion. Application switching: quick for a single step. This is distinct from compact file operations. [Q1] |
| G038 | 4 — Thumb + 3 outer fingertips | Shown on right; Spread; start near surface edges | Move left | Previous application | Spread the chord BEFORE motion. Application switching: quick for a single step. This is distinct from compact file operations. [Q1] |
| G039 | 4 — Thumb + 3 outer fingertips | Shown on right; Spread; start near surface edges | Move right | Next application | Spread the chord BEFORE motion. Application switching: quick for a single step. This is distinct from compact file operations. [Q1] |
| G040 | 4 — Thumb + 3 outer fingertips | Shown on right; Spread; start near surface edges | Rotate CW | Exit application | Spread the chord BEFORE motion. Application switching: quick for a single step. This is distinct from compact file operations. [Q1] |

### Configuration

| ID | Contacts / chord | Hand / arrangement | Trigger | Action | Restrictions / evidence |
|---|---|---|---|---|---|
| G041 | 4 — Thumb + index of BOTH hands | Both together; Four surface corners | Hold all four corners for 1 second | Enter manual configuration | Historical device configuration, followed by a setting key. Not an ordinary per-hand action assignment. [Q2/Q4; B PDF p8] |

### Optional / Text formatting

| ID | Contacts / chord | Hand / arrangement | Trigger | Action | Restrictions / evidence |
|---|---|---|---|---|---|
| G042 | 3 — Thumb + 2 fingertips | Left; Compact | Move up | Bold (Ctrl+B) | Enable Text Formatting (configuration then Shift+F). Card says Cmd replaces Ctrl in Mac mode; application bindings still matter. [Q2; X Font Styles] |
| G043 | 3 — Thumb + 2 fingertips | Left; Compact | Move down | Underline (Ctrl+U) | Enable Text Formatting (configuration then Shift+F). Card says Cmd replaces Ctrl in Mac mode; application bindings still matter. [Q2; X Font Styles] |
| G044 | 3 — Thumb + 2 fingertips | Left; Compact | Move left | Insert link (Ctrl+K) | Enable Text Formatting (configuration then Shift+F). Card says Cmd replaces Ctrl in Mac mode; application bindings still matter. [Q2; X Font Styles] |
| G045 | 3 — Thumb + 2 fingertips | Left; Compact | Move right | Italics (Ctrl+I) | Enable Text Formatting (configuration then Shift+F). Card says Cmd replaces Ctrl in Mac mode; application bindings still matter. [Q2; X Font Styles] |
| G046 | 3 — Thumb + 2 fingertips | Left; Compact | Pinch | Font dialog (Ctrl+D) | Enable Text Formatting (configuration then Shift+F). Card says Cmd replaces Ctrl in Mac mode; application bindings still matter. [Q2; X Font Styles] |
| G047 | 3 — Thumb + 2 fingertips | Left; Compact | Spread | Select all (Ctrl+A) | Enable Text Formatting (configuration then Shift+F). Card says Cmd replaces Ctrl in Mac mode; application bindings still matter. [Q2; X Font Styles] |
| G048 | 3 — Thumb + 2 fingertips | Left; Compact | Rotate CCW | Single spacing (Ctrl+1) | Enable Text Formatting (configuration then Shift+F). Card says Cmd replaces Ctrl in Mac mode; application bindings still matter. [Q2; X Font Styles] |
| G049 | 3 — Thumb + 2 fingertips | Left; Compact | Rotate CW | Double spacing (Ctrl+2) | Enable Text Formatting (configuration then Shift+F). Card says Cmd replaces Ctrl in Mac mode; application bindings still matter. [Q2; X Font Styles] |
| G050 | 3 — Thumb + 2 fingertips | Left; Spread | Move up | Justify (Ctrl+J) | Same optional set; spread vs compact distinguishes alignment from font styles. Names of spacing/indent actions corroborated by XML. [Q2; X Paragraph Alignment] |
| G051 | 3 — Thumb + 2 fingertips | Left; Spread | Move down | Center (Ctrl+E) | Same optional set; spread vs compact distinguishes alignment from font styles. Names of spacing/indent actions corroborated by XML. [Q2; X Paragraph Alignment] |
| G052 | 3 — Thumb + 2 fingertips | Left; Spread | Move left | Align left (Ctrl+L) | Same optional set; spread vs compact distinguishes alignment from font styles. Names of spacing/indent actions corroborated by XML. [Q2; X Paragraph Alignment] |
| G053 | 3 — Thumb + 2 fingertips | Left; Spread | Move right | Align right (Ctrl+R) | Same optional set; spread vs compact distinguishes alignment from font styles. Names of spacing/indent actions corroborated by XML. [Q2; X Paragraph Alignment] |
| G054 | 3 — Thumb + 2 fingertips | Left; Spread | Rotate CCW | Hanging indent (Ctrl+T) | Same optional set; spread vs compact distinguishes alignment from font styles. Names of spacing/indent actions corroborated by XML. [Q2; X Paragraph Alignment] |
| G055 | 3 — Thumb + 2 fingertips | Left; Spread | Rotate CW | Indent (Ctrl+M) | Same optional set; spread vs compact distinguishes alignment from font styles. Names of spacing/indent actions corroborated by XML. [Q2; X Paragraph Alignment] |
| G056 | 3 — Thumb + 2 fingertips | Left; Compact (spread also in XML) | Hold | Maya Hotbox: hold Space | Requires Text Formatting for the card example; release Space on lift. It is a held action, not repeated Space taps. [Q2; B PDF p11; X Font Styles] |

### Optional / Photoshop

| ID | Contacts / chord | Hand / arrangement | Trigger | Action | Restrictions / evidence |
|---|---|---|---|---|---|
| G057 | 4 — Thumb + 3 fingertips | Left; Compact | Move up | Fit / zoom window (Ctrl+0) | Enable Photoshop (configuration then Shift+Z). Outputs are historical app shortcuts; do not silently translate every Ctrl in mixed modifier combos. [Q2; X Photoshop View] |
| G058 | 4 — Thumb + 3 fingertips | Left; Compact | Move down | Zoom 100% (Ctrl+Alt+0) | Enable Photoshop (configuration then Shift+Z). Outputs are historical app shortcuts; do not silently translate every Ctrl in mixed modifier combos. [Q2; X Photoshop View] |
| G059 | 4 — Thumb + 3 fingertips | Left; Compact | Move left | Send back (Ctrl+[) | Enable Photoshop (configuration then Shift+Z). Outputs are historical app shortcuts; do not silently translate every Ctrl in mixed modifier combos. [Q2; X Photoshop View] |
| G060 | 4 — Thumb + 3 fingertips | Left; Compact | Move right | Bring forward (Ctrl+]) | Enable Photoshop (configuration then Shift+Z). Outputs are historical app shortcuts; do not silently translate every Ctrl in mixed modifier combos. [Q2; X Photoshop View] |
| G061 | 4 — Thumb + 3 fingertips | Left; Compact | Spread | Magnify (Ctrl+Space+click) | Enable Photoshop (configuration then Shift+Z). Outputs are historical app shortcuts; do not silently translate every Ctrl in mixed modifier combos. [Q2; X Photoshop View] |
| G062 | 4 — Thumb + 3 fingertips | Left; Compact | Pinch | De-magnify (Alt+Space+click) | Enable Photoshop (configuration then Shift+Z). Outputs are historical app shortcuts; do not silently translate every Ctrl in mixed modifier combos. [Q2; X Photoshop View] |
| G063 | 4 — Thumb + 3 fingertips | Left; Compact | Rotate CCW | Close / refresh window (Ctrl+W) | Enable Photoshop (configuration then Shift+Z). Outputs are historical app shortcuts; do not silently translate every Ctrl in mixed modifier combos. [Q2; X Photoshop View] |
| G064 | 4 — Thumb + 3 fingertips | Left; Compact | Rotate CW | Make (Ctrl+M) | Enable Photoshop (configuration then Shift+Z). Outputs are historical app shortcuts; do not silently translate every Ctrl in mixed modifier combos. [Q2; X Photoshop View] |
| G065 | 5 — Thumb + 4 fingertips | Left; Whole hand | Spread | Zoom in (Ctrl + plus) | Photoshop set; discrete zoom commands, not generic native magnification. [Q2] |
| G066 | 5 — Thumb + 4 fingertips | Left; Whole hand | Pinch | Zoom out (Ctrl + minus) | Photoshop set; discrete zoom commands, not generic native magnification. [Q2] |
| G067 | 4 — Thumb + 3 fingertips | Left; Spread | Move XY | Space + primary drag | Photoshop set; keep Space/button held through movement and release on lift. [Q2; X Photoshop Space Drag] |

### Optional / Maya

| ID | Contacts / chord | Hand / arrangement | Trigger | Action | Restrictions / evidence |
|---|---|---|---|---|---|
| G068 | 4 — Thumb + 3 fingertips | Left; Compact | Move XY | Pan: Alt + middle drag | Enable Maya (configuration then Shift+Y). [Q2; X Maya Pan] |
| G069 | 4 — Thumb + 3 fingertips | Left; Spread | Move XY | Orbit: Alt + primary drag | Maya set; arrangement chooses a different action for the same XY motion. [Q2; X Maya Orbit] |
| G070 | 5 — Thumb + 4 fingertips | Left; Whole hand | Pinch / spread | Maya zoom | Maya set. Card names a combined Zoom/Rotate gesture without spelling out every output edge. [Q2; X Maya Zoom/Rotate] |
| G071 | 5 — Thumb + 4 fingertips | Left; Whole hand | Rotate CW / CCW | Maya rotate / orbit | Maya set; release all held modifiers/buttons at end. [Q2; X Maya Zoom/Rotate] |

### Optional / Desktop and tools

| ID | Contacts / chord | Hand / arrangement | Trigger | Action | Restrictions / evidence |
|---|---|---|---|---|---|
| G072 | 4 — Thumb + 3 fingertips | Left; Compact | Move up-left | Meta+F7 | Enable Desktop/Tools (configuration then Shift+D). Designed for configured desktop/window-manager bindings, not macOS defaults. [Q2] |
| G073 | 4 — Thumb + 3 fingertips | Left; Compact | Move up | Meta+F8 | Enable Desktop/Tools (configuration then Shift+D). Designed for configured desktop/window-manager bindings, not macOS defaults. [Q2] |
| G074 | 4 — Thumb + 3 fingertips | Left; Compact | Move up-right | Meta+F9 | Enable Desktop/Tools (configuration then Shift+D). Designed for configured desktop/window-manager bindings, not macOS defaults. [Q2] |
| G075 | 4 — Thumb + 3 fingertips | Left; Compact | Move left | Meta+F4 | Enable Desktop/Tools (configuration then Shift+D). Designed for configured desktop/window-manager bindings, not macOS defaults. [Q2] |
| G076 | 4 — Thumb + 3 fingertips | Left; Compact | Move right | Meta+F6 | Enable Desktop/Tools (configuration then Shift+D). Designed for configured desktop/window-manager bindings, not macOS defaults. [Q2] |
| G077 | 4 — Thumb + 3 fingertips | Left; Compact | Move down-left | Meta+F1 | Enable Desktop/Tools (configuration then Shift+D). Designed for configured desktop/window-manager bindings, not macOS defaults. [Q2] |
| G078 | 4 — Thumb + 3 fingertips | Left; Compact | Move down | Meta+F2 | Enable Desktop/Tools (configuration then Shift+D). Designed for configured desktop/window-manager bindings, not macOS defaults. [Q2] |
| G079 | 4 — Thumb + 3 fingertips | Left; Compact | Move down-right | Meta+F3 | Enable Desktop/Tools (configuration then Shift+D). Designed for configured desktop/window-manager bindings, not macOS defaults. [Q2] |
| G080 | 4 — Thumb + 3 fingertips | Left; Compact | Pinch | Meta+F5 | Pinch is the center/F5 action; do not fabricate a tap-to-F5 assignment. [Q2] |
| G081 | 4 — Thumb + 3 fingertips | Left; Compact | Spread | Meta+F10 | Pinch is the center/F5 action; do not fabricate a tap-to-F5 assignment. [Q2] |
| G082 | 4 — Thumb + 3 fingertips | Left; Compact | Rotate CCW | Meta+F12 | Pinch is the center/F5 action; do not fabricate a tap-to-F5 assignment. [Q2] |
| G083 | 4 — Thumb + 3 fingertips | Left; Compact | Rotate CW | Meta+F11 | Pinch is the center/F5 action; do not fabricate a tap-to-F5 assignment. [Q2] |
| G084 | 4 — Thumb + 3 fingertips | Left; Spread | Move left | Previous desktop (Shift+Ctrl+Tab) | Quick horizontal strokes for single steps. Conflicts with Photoshop/Maya chord use; choose one profile. [Q2; B PDF p12] |
| G085 | 4 — Thumb + 3 fingertips | Left; Spread | Move right | Next desktop (Ctrl+Tab) | Quick horizontal strokes for single steps. Conflicts with Photoshop/Maya chord use; choose one profile. [Q2; B PDF p12] |
| G086 | 4 — Thumb + 3 fingertips | Left; Spread | Rotate CCW | Ctrl+W | Quick horizontal strokes for single steps. Conflicts with Photoshop/Maya chord use; choose one profile. [Q2; B PDF p12] |
| G087 | 4 — Thumb + 3 fingertips | Left; Spread | Rotate CW | Ctrl+M | Quick horizontal strokes for single steps. Conflicts with Photoshop/Maya chord use; choose one profile. [Q2; B PDF p12] |
| G088 | 5 — Thumb + 4 fingertips | Left; Whole hand | Move up | Meta + equals | Desktop/Tools five-contact actions are distinct from its four-contact compass. [Q2] |
| G089 | 5 — Thumb + 4 fingertips | Left; Whole hand | Move down | Meta + minus | Desktop/Tools five-contact actions are distinct from its four-contact compass. [Q2] |

### Optional / Programmer tools

| ID | Contacts / chord | Hand / arrangement | Trigger | Action | Restrictions / evidence |
|---|---|---|---|---|---|
| G090 | 2 — Thumb + middle | Right; Thumb separated | Spread | Paste (Ctrl+V) / Emacs Execute (Alt+X) | Programmer set: configuration then Shift+P; Emacs mode: configuration then 7. Outputs differ by mode. [Q3] |
| G091 | 2 — Thumb + 1 fingertip | Left; Compact | Move up | Complete previous (Ctrl+<) | Programmer/Emacs set. Exact app integration and shortcut meanings are historical. [Q3; X Word Completion] |
| G092 | 2 — Thumb + 1 fingertip | Left; Compact | Move down | Complete next (Ctrl+>) | Programmer/Emacs set. Exact app integration and shortcut meanings are historical. [Q3; X Word Completion] |
| G093 | 2 — Thumb + 1 fingertip | Left; Compact | Move left | Delete previous word (Ctrl+Backspace) | Programmer/Emacs set. Exact app integration and shortcut meanings are historical. [Q3; X Word Completion] |
| G094 | 2 — Thumb + 1 fingertip | Left; Compact | Move right | Complete line (Ctrl+Shift+Space) | Programmer/Emacs set. Exact app integration and shortcut meanings are historical. [Q3; X Word Completion] |
| G095 | 2 — Thumb + 1 fingertip | Left; Compact | Rotate CCW | Emacs shell command (Alt+Shift+1) | Programmer/Emacs set. Exact app integration and shortcut meanings are historical. [Q3; X Word Completion] |
| G096 | 2 — Thumb + 1 fingertip | Left; Compact | Rotate CW | Go to line / Emacs indent (Ctrl+J) | Programmer/Emacs set. Exact app integration and shortcut meanings are historical. [Q3; X Word Completion] |
| G097 | 3 — Thumb + 2 fingertips | Left; Compact | Tap | Ctrl+C | Shown as a shortcut without an action name; do not automatically label it Copy in Emacs. [Q3] |
| G098 | 3 — Thumb + 2 fingertips | Left; Compact | Pinch | Cut / Emacs prefix (Ctrl+X) | Shown on programmer card; output may start a multi-key prefix. [Q3] |
| G099 | 2 — 2 fingertips | Right shown; Spread | Move left / right / up / down | Ctrl + arrow | Programmer/Emacs context; spread arrangements distinguish these from ordinary mouse chords. [Q3] |
| G100 | 3 — 3 fingertips | Right shown; Spread | Move left / right / up / down | Ctrl + Shift + arrow | Programmer/Emacs context; spread arrangements distinguish these from ordinary mouse chords. [Q3] |
| G101 | 4 — 4 fingertips | Right shown; Spread | Move left / right / up / down | Ctrl + Home/End horizontally; Ctrl + PageUp/PageDown vertically | Programmer/Emacs context; spread arrangements distinguish these from ordinary mouse chords. [Q3] |

### Optional / Emacs

| ID | Contacts / chord | Hand / arrangement | Trigger | Action | Restrictions / evidence |
|---|---|---|---|---|---|
| G102 | 3 — Thumb + 2 fingertips | Left; Compact | Move left | Keyboard quit (Ctrl+G) | Emacs mode (configuration then 7) and touchstream.el. Commas separate sequence steps, not simultaneous modifiers. [Q3; X Emacs IDE (Neutral)] |
| G103 | 3 — Thumb + 2 fingertips | Left; Compact | Move right | Set mark (Ctrl+Space) | Emacs mode (configuration then 7) and touchstream.el. Commas separate sequence steps, not simultaneous modifiers. [Q3; X Emacs IDE (Neutral)] |
| G104 | 3 — Thumb + 2 fingertips | Left; Compact | Move down | Universal argument (Ctrl+U) | Emacs mode (configuration then 7) and touchstream.el. Commas separate sequence steps, not simultaneous modifiers. [Q3; X Emacs IDE (Neutral)] |
| G105 | 3 — Thumb + 2 fingertips | Left; Compact | Rotate CCW | Comment region (Ctrl+;) | Emacs mode (configuration then 7) and touchstream.el. Commas separate sequence steps, not simultaneous modifiers. [Q3; X Emacs IDE (Neutral)] |
| G106 | 3 — Thumb + 2 fingertips | Left; Compact | Rotate CW | Uncomment region (Ctrl+U, Ctrl+;) | Emacs mode (configuration then 7) and touchstream.el. Commas separate sequence steps, not simultaneous modifiers. [Q3; X Emacs IDE (Neutral)] |
| G107 | 3 — Thumb + 2 fingertips | Left; Compact | Pinch | CVS diff (Ctrl+X, V, =)  | Emacs mode (configuration then 7) and touchstream.el. Commas separate sequence steps, not simultaneous modifiers. [Q3; X Emacs IDE (Neutral)] |
| G108 | 3 — Thumb + 2 fingertips | Left; Compact | Spread | Check in/out (Ctrl+X, Ctrl+Q) | Emacs mode (configuration then 7) and touchstream.el. Commas separate sequence steps, not simultaneous modifiers. [Q3; X Emacs IDE (Neutral)] |
| G109 | 3 — Thumb + 2 fingertips | Left; Spread | Move up | Previous compile error (Alt+minus, Ctrl+X, grave) | Same Emacs integration; quick one-step vs repeated motion is separate trigger behavior. [Q3; X Emacs IDE (Spread)] |
| G110 | 3 — Thumb + 2 fingertips | Left; Spread | Move down | Next compile error (Ctrl+X, grave) | Same Emacs integration; quick one-step vs repeated motion is separate trigger behavior. [Q3; X Emacs IDE (Spread)] |
| G111 | 3 — 3 fingertips | Left shown; Compact | Tap | Escape | Emacs mode; do not confuse with the two-handed enhanced Escape chord. [Q3] |
| G112 | 2 — 2 fingertips | Right shown; Spread | Move horizontally / vertically | Transpose: Ctrl+B horizontally, Alt+B vertically (as printed) | Those are the card labels; do not replace them with assumed modern Emacs defaults. [Q3] |
| G113 | 4 — 4 fingertips | Right shown; Spread | Move left/right/up/down | Scroll other windows: Alt+Home/End/PageUp/PageDown | Requires Emacs integration; directions follow the matching navigation keys. [Q3] |

### Modifier and two-hand chords

| ID | Contacts / chord | Hand / arrangement | Trigger | Action | Restrictions / evidence |
|---|---|---|---|---|---|
| G114 | 4 — 4 fingertips, no thumb | Either; Compact row; anywhere | Hold; lift all to release | Shift | Basic modifier chords. Booklet permits partial lifts while at least one original finger remains; do not switch to scrolling mid-cycle. [Q3; B PDF pp6-7] |
| G115 | 4 — 4 fingertips, no thumb | Either; Spread (pictured) | Hold; lift all to release | Ctrl / Cmd (OS dependent) | Basic modifier chords. Layout and OS context affect output. [Q3] |
| G116 | 4 — 4 fingertips, no thumb | Either; Above home row | Hold; lift to release | Ctrl (US), Cmd (US Mac), AltGr (International) | Enhanced chords: configuration then Shift+C (US) or Ctrl+C (International). Shift is no longer anywhere; zone matters. [Q3] |
| G117 | 4 — 4 fingertips, no thumb | Either; On home row | Hold; lift to release | Shift | Enhanced chords: configuration then Shift+C (US) or Ctrl+C (International). Shift is no longer anywhere; zone matters. [Q3] |
| G118 | 4 — 4 fingertips, no thumb | Either; Below home row | Hold; lift to release | Left Alt (US), Shift+AltGr (International) | Enhanced chords: configuration then Shift+C (US) or Ctrl+C (International). Shift is no longer anywhere; zone matters. [Q3] |
| G119 | 4 — Thumb + 3 fingertips | Either; Relaxed / compact | Simultaneous landing, then hold | AltGr (US); Ctrl (International); Cmd (International Mac) | Enhanced chords; picture distinguishes compact from spread. [Q3] |
| G120 | 4 — Thumb + 3 fingertips | Either; Spread | Simultaneous landing, then hold | Win (US Windows), Meta (US Linux/Emacs), Ctrl (US Mac), Left Alt (International) | Enhanced chords; not a directional motion gesture. [Q3] |
| G121 | 6 — 3 fingertips on EACH hand | Both together; Above home row | Synchronized tap | Escape | Enhanced two-hand chord; zone required. [Q3] |
| G122 | 6 — 3 fingertips on EACH hand | Both together; On home row | Synchronized tap | Enter | Same contacts as Escape, different zone. [Q3] |
| G123 | 8 — 4 fingertips on EACH hand | Both together; Above home row | Synchronized tap | CapsWord | CapsLock for next word; ends on Space or punctuation. Not a permanent CapsLock toggle. [Q3] |
| G124 | 6 — 3 fingertips on EACH hand | Both together; Paired hands | Slide | XWinder window manipulation | Guide names the two-hand gesture but does not enumerate direction/output bindings. External XWinder documentation needed. [Q3] |
| G125 | 4 + 1 typical — Left AltGr chord + right key | Both, different roles; US right-side punctuation positions | Hold left chord, tap right key | Programmers punctuation pad | Configuration then Shift+U; Enhanced chords required. Replaces AltGr accent-symbol use. This is a layer/key interaction, not one new gesture per symbol. [Q3] |

### Game / Mode changes

| ID | Contacts / chord | Hand / arrangement | Trigger | Action | Restrictions / evidence |
|---|---|---|---|---|---|
| G126 | 2 heel patches — Two palm heels | Each surface independently; Center of selected surface | Move forward / backward | Enter / leave game mode | Enable master game mode first (configuration then Shift+G or Pause as card notes). Palm patches are not two fingertips. Normal gestures replaced per surface. [Q4; B PDF p12] |

### Game / Point and fire

| ID | Contacts / chord | Hand / arrangement | Trigger | Action | Restrictions / evidence |
|---|---|---|---|---|---|
| G127 | 3 — Index + middle + ring | Right / mouse hand; Base pointing chord | Move XY; add/lift trigger contacts | Point only | Game mode only. These are simultaneous button states during movement, not separate tap actions; pinky button is configurable. [Q4] |
| G128 | 4 — Index + middle + ring + Thumb | Right / mouse hand; Base pointing chord | Move XY; add/lift trigger contacts | Point + hold Mouse1 | Game mode only. These are simultaneous button states during movement, not separate tap actions; pinky button is configurable. [Q4] |
| G129 | 4 — Index + middle + ring + Pinky | Right / mouse hand; Base pointing chord | Move XY; add/lift trigger contacts | Point + hold Mouse2 | Game mode only. These are simultaneous button states during movement, not separate tap actions; pinky button is configurable. [Q4] |
| G130 | 5 — Index + middle + ring + Thumb + pinky | Right / mouse hand; Base pointing chord | Move XY; add/lift trigger contacts | Point + hold Mouse1 and Mouse2 | Game mode only. These are simultaneous button states during movement, not separate tap actions; pinky button is configurable. [Q4] |
| G131 | 3 — Thumb + middle + ring | Right / mouse hand; Base pointing chord | Move XY; add/lift trigger contacts | Point only | Game mode only. These are simultaneous button states during movement, not separate tap actions; pinky button is configurable. [Q4] |
| G132 | 4 — Thumb + middle + ring + Index | Right / mouse hand; Base pointing chord | Move XY; add/lift trigger contacts | Point + hold Mouse1 | Game mode only. These are simultaneous button states during movement, not separate tap actions; pinky button is configurable. [Q4] |
| G133 | 4 — Thumb + middle + ring + Pinky | Right / mouse hand; Base pointing chord | Move XY; add/lift trigger contacts | Point + hold Mouse2 | Game mode only. These are simultaneous button states during movement, not separate tap actions; pinky button is configurable. [Q4] |
| G134 | 5 — Thumb + middle + ring + Index + pinky | Right / mouse hand; Base pointing chord | Move XY; add/lift trigger contacts | Point + hold Mouse1 and Mouse2 | Game mode only. These are simultaneous button states during movement, not separate tap actions; pinky button is configurable. [Q4] |

### Game / Arrow joystick

| ID | Contacts / chord | Hand / arrangement | Trigger | Action | Restrictions / evidence |
|---|---|---|---|---|---|
| G135 | 3 — Index + middle + ring | Left; Base navigation chord | Directional motion; add/lift trigger contacts | Hold directional arrows | Game mode only; supports diagonal arrow combinations. Do not interpret added contacts as a new chord owner. [Q4] |
| G136 | 4 — Index + middle + ring + Thumb | Left; Base navigation chord | Directional motion; add/lift trigger contacts | Arrows + End | Game mode only; supports diagonal arrow combinations. Do not interpret added contacts as a new chord owner. [Q4] |
| G137 | 4 — Index + middle + ring + Pinky | Left; Base navigation chord | Directional motion; add/lift trigger contacts | Arrows + Home | Game mode only; supports diagonal arrow combinations. Do not interpret added contacts as a new chord owner. [Q4] |
| G138 | 5 — Index + middle + ring + Thumb + pinky | Left; Base navigation chord | Directional motion; add/lift trigger contacts | Arrows + End + Home | Game mode only; supports diagonal arrow combinations. Do not interpret added contacts as a new chord owner. [Q4] |
| G139 | 3 — Thumb + middle + ring | Left; Base navigation chord | Directional motion; add/lift trigger contacts | Hold directional arrows | Game mode only; supports diagonal arrow combinations. Do not interpret added contacts as a new chord owner. [Q4] |
| G140 | 4 — Thumb + middle + ring + Index | Left; Base navigation chord | Directional motion; add/lift trigger contacts | Arrows + End | Game mode only; supports diagonal arrow combinations. Do not interpret added contacts as a new chord owner. [Q4] |
| G141 | 4 — Thumb + middle + ring + Pinky | Left; Base navigation chord | Directional motion; add/lift trigger contacts | Arrows + Home | Game mode only; supports diagonal arrow combinations. Do not interpret added contacts as a new chord owner. [Q4] |
| G142 | 5 — Thumb + middle + ring + Index + pinky | Left; Base navigation chord | Directional motion; add/lift trigger contacts | Arrows + End + Home | Game mode only; supports diagonal arrow combinations. Do not interpret added contacts as a new chord owner. [Q4] |
| G143 | 2 — Index + ring | Left; Middle lifted from original IMR base | Lift middle; keep navigation contact | Arrows + PageDown | Inverted PageDown must be enabled. Adding middle back releases PageDown. Requires contact-role transitions, not count alone. [Q4; B PDF p12] |
| G144 | 3 — Index + ring + Thumb | Left; Middle lifted from original IMR base | Lift middle; keep navigation contact | Arrows + PageDown + End | Inverted PageDown must be enabled. Adding middle back releases PageDown. Requires contact-role transitions, not count alone. [Q4; B PDF p12] |
| G145 | 3 — Index + ring + Pinky | Left; Middle lifted from original IMR base | Lift middle; keep navigation contact | Arrows + PageDown + Home | Inverted PageDown must be enabled. Adding middle back releases PageDown. Requires contact-role transitions, not count alone. [Q4; B PDF p12] |
| G146 | 4 — Index + ring + Thumb + pinky | Left; Middle lifted from original IMR base | Lift middle; keep navigation contact | Arrows + PageDown + End + Home | Inverted PageDown must be enabled. Adding middle back releases PageDown. Requires contact-role transitions, not count alone. [Q4; B PDF p12] |

### Game / Extra actions

| ID | Contacts / chord | Hand / arrangement | Trigger | Action | Restrictions / evidence |
|---|---|---|---|---|---|
| G147 | 2 — Thumb + middle | Left; Separated | Tap | Space | Game Compass; 1.60 XML confirms the tap shown at compass center. [Q4; X Game Compass] |
| G148 | 2 — Thumb + middle | Left; Separated | Move up-left | N + W | Game compass key outputs; diagonal labels mean combined letter keys, not a text string. [Q4; X Game Compass] |
| G149 | 2 — Thumb + middle | Left; Separated | Move up | N | Game compass key outputs; diagonal labels mean combined letter keys, not a text string. [Q4; X Game Compass] |
| G150 | 2 — Thumb + middle | Left; Separated | Move up-right | N + E | Game compass key outputs; diagonal labels mean combined letter keys, not a text string. [Q4; X Game Compass] |
| G151 | 2 — Thumb + middle | Left; Separated | Move left | W | Game compass key outputs; diagonal labels mean combined letter keys, not a text string. [Q4; X Game Compass] |
| G152 | 2 — Thumb + middle | Left; Separated | Move right | E | Game compass key outputs; diagonal labels mean combined letter keys, not a text string. [Q4; X Game Compass] |
| G153 | 2 — Thumb + middle | Left; Separated | Move down-left | S + W | Game compass key outputs; diagonal labels mean combined letter keys, not a text string. [Q4; X Game Compass] |
| G154 | 2 — Thumb + middle | Left; Separated | Move down | S | Game compass key outputs; diagonal labels mean combined letter keys, not a text string. [Q4; X Game Compass] |
| G155 | 2 — Thumb + middle | Left; Separated | Move down-right | S + E | Game compass key outputs; diagonal labels mean combined letter keys, not a text string. [Q4; X Game Compass] |
| G156 | 2 — Thumb + middle | Left; Separated | Pinch | X | Game compass one-shot actions; distinct from the mouse-hand wheel mappings. [Q4; X Game Compass] |
| G157 | 2 — Thumb + middle | Left; Separated | Spread | Z | Game compass one-shot actions; distinct from the mouse-hand wheel mappings. [Q4; X Game Compass] |
| G158 | 2 — Thumb + middle | Right; Separated | Spread | Wheel up | Game Wheel/Buttons. XML also assigns Mouse3 to CCW rotation; card illustrates CW only. [Q4; X Game-mode Wheel/Buttons] |
| G159 | 2 — Thumb + middle | Right; Separated | Pinch | Wheel down | Game Wheel/Buttons. XML also assigns Mouse3 to CCW rotation; card illustrates CW only. [Q4; X Game-mode Wheel/Buttons] |
| G160 | 2 — Thumb + middle | Right; Separated | Rotate CW | Mouse3 click | Game Wheel/Buttons. XML also assigns Mouse3 to CCW rotation; card illustrates CW only. [Q4; X Game-mode Wheel/Buttons] |
| G161 | 2 — Thumb + middle | Right; Separated | Move left | Mouse4 click | Game Wheel/Buttons. XML also assigns Mouse3 to CCW rotation; card illustrates CW only. [Q4; X Game-mode Wheel/Buttons] |
| G162 | 2 — Thumb + middle | Right; Separated | Move right | Mouse5 click | Game Wheel/Buttons. XML also assigns Mouse3 to CCW rotation; card illustrates CW only. [Q4; X Game-mode Wheel/Buttons] |

### Three-button and pen modes

| ID | Contacts / chord | Hand / arrangement | Trigger | Action | Restrictions / evidence |
|---|---|---|---|---|---|
| G163 | 3 — Thumb + 2 fingertips | Mouse hand; Compact; thumb about 2 inches from tips | Tap / hold and drag | Middle click / drag | Linux/Unix or three-button mode. Distance is card advice, not a calibrated Apple threshold. [Q2] |
| G164 | 3 — Thumb + 2 fingertips | Mouse hand; Spread | Tap / hold and drag | Secondary click / drag | Spread distinguishes secondary from middle in Linux/Unix or three-button mode. [Q2] |
| G165 | 2 tips + knuckle contacts — Thumb + index tip + folded knuckles | Mouse hand; Pen grip | Contact / drag | Middle click / drag | Middle/ring/pinky knuckles curled under; always enabled per card. Apple palm/knuckle classification support is not established. [Q2] |

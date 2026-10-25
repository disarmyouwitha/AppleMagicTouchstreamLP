# TouchStream action gaps

Reviewed 2026-10-25 against all four pages of the original
`/Users/nap/Documents/new_code/touchstream-archive/docs/TouchStream_QuickGuides.pdf`,
the preserved 1.60 `FW_command_macros.xml` and `FW_chord_macros.xml` under
`firmware-analysis/rea-investigation/right-click-2026-10-21/`, and current
`GestureAction`, `GestureActionChooser`, `GestureShortcutAssignment` and
`ShortcutActionHelper` source. This inventory concerns **outputs/actions**, not
missing finger arrangements or recognizers. The existing
[gesture inventory](Design/GestureAssignments/GESTURE_MAP.md) maps their triggers.

## What “missing” means

- **Preset:** absent as a named built-in gesture action, but its key combination
  can already be assigned using Shortcut Builder and saved in the shortcut list.
  User-created library entries are not considered missing built-in support.
- **Output:** needs output/lifetime machinery beyond the current single-key-plus-
  modifiers builder, not merely another picker label.
- **Device/context:** original firmware mode, profile or external integration;
  not a portable host key command.

Current built-ins already cover pointer movement, primary drag, primary and
secondary click, double-click, scroll/pan and their directional actions, native
zoom, Show Desktop and Open Config. Modifier-only Shift/Ctrl/Option/Cmd/Hyper
and arbitrary held keyboard shortcuts are supported. These are not missing.
Open Config is our counterpart to the configuration gesture, not an emulator of
the original firmware's following configuration-key commands.

Commands below are historical source mappings, not a claim of universal current
application behavior. Cmd denotes the original Mac mapping of AutoCmd/GUI.
AutoAlt is retained symbolically where its platform translation has not been
verified here. A comma between chords means **sequential**, not simultaneous.

## Core presets absent from the built-in action menu (guide page 1)

| Action | Command from original Mac mapping / source | Current gap |
| --- | --- | --- |
| Cut | Cmd+X | Preset |
| Copy | Cmd+C | Preset |
| Paste | Cmd+V | Preset |
| Undo | Cmd+Z | Preset |
| Redo | Shift+Cmd+Z | Preset |
| Find | Cmd+F | Preset |
| Find next / search again | Cmd+G | Preset; Polar Search XML |
| Find previous | Shift+Cmd+G | Preset; Polar Search XML clarification |
| Group | Cmd+G | Preset; meaning depends on target application |
| Ungroup | **Cmd+Y in the original Mac XML** | Preset; XML counterpart, not a modern universal shortcut |
| Open document | Cmd+O | Preset; different from the existing App/file launch builder |
| Close document/window | Cmd+W | Preset |
| Save | Cmd+S | Preset |
| New document/window | Cmd+N | Preset |
| Browser back | AutoAlt+Left | Preset; historical Back macro |
| Browser forward | AutoAlt+Right | Preset; historical Forward macro |
| Reload / refresh | Cmd+R | Preset; Reload macro |
| Replace | Cmd+D | Preset; Replace macro; guide's “Refresh/Replace” is context-dependent |
| Previous application | Shift+AutoAlt+Tab | Preset; shortcut is expressible, sustained switcher session is separate behavior |
| Next application | AutoAlt+Tab | Preset; same distinction |
| Exit application | Cmd+Q | Preset |
| Move text cursor | Left / Right / Up / Down | Preset family |
| Select text | Shift+Left / Right / Up / Down | Preset family |
| Beginning of line | Cmd+Left | Preset; XML resolves the guide's horizontal Home label this way on Mac |
| End of line | Cmd+Right | Preset; XML resolves the guide's horizontal End label this way on Mac |
| Page Up / Page Down | PageUp / PageDown | Preset family |
| Tab / Back Tab | Tab / Shift+Tab | Preset family |
| Enter | Enter | Preset |

The guide labels Show/Open Desktop; our existing Show Desktop covers the intent.
The original command library's Show Desktop has a historical Mac Win+H mapping;
do not substitute that for our existing working desktop action.

Native Zoom is already present, but **hotkey Zoom In / Zoom Out** are separate
missing presets: original Mac XML uses Cmd+= and Cmd+-. They can already be built.

## Text formatting presets (page 2)

These are the guide's Ctrl combinations. Page 2 explicitly says Cmd replaces
Ctrl in Mac mode. They remain application-specific; naming a preset does not
make every editor implement the command.

| Action | Printed command | Current gap |
| --- | --- | --- |
| Bold | Ctrl+B | Preset |
| Underline | Ctrl+U | Preset |
| Italic | Ctrl+I | Preset |
| Insert link | Ctrl+K | Preset |
| Font dialog | Ctrl+D | Preset |
| Select all | Ctrl+A | Preset |
| Align left / right | Ctrl+L / Ctrl+R | Preset |
| Center / justify | Ctrl+E / Ctrl+J | Preset |
| Single / double spacing | Ctrl+1 / Ctrl+2 | Preset; names corroborated by XML |
| Hanging indent / indent | Ctrl+T / Ctrl+M | Preset; names corroborated by XML |
| Maya Hotbox | Hold Space until lift | Named preset only; Hold until release already supports this |

## Photoshop, Maya and desktop/tool actions (page 2)

Keep the printed Ctrl/Alt notation for optional application profiles. Mixed
combinations must not be mechanically translated and advertised as current app
defaults. XML uses AutoCmd for several Photoshop commands.

| Action | Printed command / original output | Current gap |
| --- | --- | --- |
| Fit/zoom window | Ctrl+0 | Preset |
| Zoom 100% | Ctrl+Alt+0 | Preset |
| Send back / bring forward | Ctrl+[ / Ctrl+] | Preset |
| Zoom in / out | Ctrl+plus / Ctrl+minus | Preset; equals key plus modifiers can express needed bindings |
| Close/refresh window | Ctrl+W | Preset; original named macro actually sends W, not Reload |
| Make | Ctrl+M | Preset; XML name, target-dependent |
| Magnify | Ctrl+Space+primary click | **Output:** ordered key + mouse compound action |
| De-magnify | Alt+Space+primary click | **Output:** ordered key + mouse compound action |
| Space drag | Hold Space + primary drag | **Output:** combined key/button/motion lifetime in one assignment |
| Maya pan | Alt + middle-button drag | **Output:** modifier plus middle drag |
| Maya orbit | Alt + primary-button drag | **Output:** configurable modified drag |
| Maya zoom/dolly | XML: scale becomes horizontal mouse motion with Alt+primary+middle held | **Output:** shape-to-drag conversion and combined button lifetime |
| Maya rotate/orbit | XML: rotation becomes horizontal motion with Alt+primary held | **Output:** shape-to-drag conversion; not native Zoom |
| Desktop/tool commands | Meta+F1 through Meta+F12; Meta+= and Meta+- | Preset family; commands depend on configured desktop tools |
| Previous / next desktop | Shift+Ctrl+Tab / Ctrl+Tab | Preset; historical commands, not verified current macOS Space switching |
| Middle click | Mouse button 3 | **Output:** available in keyboard catalog, not accepted as a gesture shortcut or listed as a gesture built-in |
| Middle drag | Mouse button 3 down + motion + release | **Output** |
| Secondary drag | Mouse button 2 down + motion + release | **Output:** Secondary Click alone does not provide this |

The guide's XWinder action (page 3) is external two-handed window manipulation.
It supplies no portable maximize/move/resize command list. No specific modern
window-management API or shortcut is inferred from that label.

## Programmer and Emacs commands (page 3)

Preserve Ctrl and Alt exactly; the page has explicit Emacs semantics. These are
historical integrations, including `touchstream.el`, not promises of current
default Emacs bindings.

| Action | Printed command | Current gap |
| --- | --- | --- |
| Execute | Alt+X | Preset |
| Complete previous / next | Ctrl+< / Ctrl+> | Preset; US key builder can express shifted comma/period |
| Delete previous word | Ctrl+Backspace | Preset |
| Complete line | Ctrl+Shift+Space | Preset |
| Shell command | Alt+Shift+1 | Preset |
| Go to line / indent | Ctrl+J | Preset |
| Raw Ctrl+C / prefix Ctrl+X | Ctrl+C / Ctrl+X | Preset; do not rename every Ctrl+C to Copy |
| Word/navigation variants | Ctrl+arrows; Ctrl+Shift+arrows; Ctrl+Home/End/PageUp/PageDown | Preset families |
| Keyboard quit | Ctrl+G | Preset |
| Set mark | Ctrl+Space | Preset |
| Universal argument | Ctrl+U | Preset |
| Comment region | Ctrl+; | Preset |
| Uncomment region | Ctrl+U, Ctrl+; | **Output:** sequential macro; 1.60 XML instead references Alt+- before Ctrl+; |
| CVS diff | Ctrl+X, V, = | **Output:** sequential macro |
| Check in/out | Ctrl+X, Ctrl+Q | **Output:** sequential macro |
| Next compile error | Ctrl+X, grave accent | **Output:** sequential macro |
| Previous compile error | Alt+-, Ctrl+X, grave accent | **Output:** sequential macro |
| Escape | Esc | Preset |
| Transpose, as printed | Ctrl+B horizontally / Alt+B vertically | Preset; retain card labels rather than replacing with assumed defaults |
| Scroll other windows | Alt+Home/End/PageUp/PageDown | Preset family |
| Caps Word | Enable capitals for next word, end at space/punctuation | **Output:** text-aware mode, not ordinary Caps Lock |
| Programmer punctuation pad | AltGr chord + mapped punctuation key | **Device/context:** layer/key mapping, not one key shortcut or a new action per symbol |

Shift, Ctrl, Cmd and Alt/Option held actions already work. The guide's AltGr and
international variants describe layout-specific modifier/alternate-symbol
behavior; reproducing a layout is separate from exposing another gesture label.

## Game actions (page 4)

| Action | Command / output | Current gap |
| --- | --- | --- |
| Point and fire | Pointer movement while independently holding Mouse1, Mouse2 or both | **Output:** dynamic multi-button ownership, not a repeated click |
| Arrow joystick | Hold directional arrows, including diagonal pairs | **Output:** directional held-key lifetime; timed key strokes are not equivalent |
| Additional game keys | Add Home/End/PageDown while directional arrows stay held | **Output:** independent simultaneous key ownership/contact-role transitions |
| Compass commands | N, W, E, S, Space, X, Z | Presets for individual keys |
| Diagonal compass commands | N+W, N+E, S+W, S+E simultaneously | **Output:** multiple nonmodifier keys in one assignment; also needs diagonal recognition |
| Wheel up/down | Wheel events | Existing Scroll Up/Down covers directional motion intent; a discrete wheel-click preset on tap/rotation is separate |
| Mouse3 | Middle click | **Output:** gesture action missing |
| Mouse4 / Mouse5 | Extra mouse-button clicks | **Output:** gesture action missing |
| Enter/leave game mode | Switch selected surface between normal/game configuration | **Device/context:** no corresponding app game mode |

Configuration-following commands (Shift+F/Z/Y/D/P/U/G, mode 7, modifier C variants,
game period/comma toggles) change original firmware sets. They are not commands
to synthesize into the focused Mac application.

## Suggested order, with no implementation authorized by this audit

1. Add named Editing, Navigation, Files and Application presets using the current
   keyboard shortcut dispatcher and serialized shortcut identities. No new output
   engine is needed for those presets.
2. Add middle click and explicit primary/secondary/middle drag capabilities, then
   a reusable key/modifier + mouse action specification with balanced cleanup.
3. Consider sequential macros, directional held-key behavior and Caps Word as
   separate features with explicit lifetime and focus semantics.
4. Keep historical app profiles opt-in; verify target-app commands before shipping
   a modern preset. Preserve distinctions between native zoom, hotkey zoom and
   shape-driven modified drag.

No app code, saved settings, or installed builds were changed for this inventory.

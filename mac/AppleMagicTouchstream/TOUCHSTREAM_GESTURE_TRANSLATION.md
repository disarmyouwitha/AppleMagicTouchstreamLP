# FingerWorks TouchStream gesture template

Import [TOUCHSTERAM_KEYMAP.json](AppleMagicTouchstream/AppleMagicTouchstream/TOUCHSTERAM_KEYMAP.json) using **Import Settings**.
The requested filename spelling is intentional. This is a practical approximation
for the current AppleMagicTouchstream app, not a firmware-equivalent port.

## What importing changes

- Selects TouchStream, base layer, and replaces the global Left/Right/Both gesture
  assignments. Gesture assignments currently apply across keyboard layouts; they
  are not scoped to TouchStream. STENO still pauses ordinary configurable gestures.
- Includes the complete keyboard-mapping collection from a read-only snapshot of
  `AppleMagicTouchstream/AppleMagicTouchstream/MY_KEYMAP.json`, SHA-256
  `35ca5a134dc8d9673974273c342a8cafbf58d474d37afe65b5089897203c50d1`.
  This is necessary because the importer replaces that collection. Export your
  current settings first if you have changed keyboard mappings since that snapshot.
- Does not import device selection, takeover opt-in, login registration, typing
  timing/haptic/assistance preferences, column settings, or authored layout documents.
  Existing local STENO connection/haptic/threshold preferences are preserved.
- Explicitly disables unassigned Tap/Force/shape/Hold slots, including ordinary
  one-finger force click (the original gestures did not use pressure). Outer
  Corners still opens Config; its Hold is 1 second, matching the guide.
- No preference changes, app installation, firmware changes, or native input were
  performed to generate/validate the file. It is ready for you to import and test.

## Sources and interpretation

Primary source: [TouchStream Quick Reference Guide, four pages](</Users/nap/Documents/new_code/touchstream-archive/docs/TouchStream_QuickGuides.pdf>).
The illustrated pages cover core gestures, alternate application sets,
programmer/Emacs/modifier gestures, and game mode respectively.

The requested research directory has moved. The available XML copies are in
[the preserved right-click investigation](</Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/right-click-2026-10-21/>):
`FW_stealth_chords.xml` associates hand/finger combinations with templates;
`FW_chord_macros.xml` defines motion/tap/hold behavior; `FW_command_macros.xml`
resolves Mac-context output. These are preserved extracted configuration files,
not an assertion that all optional templates were enabled simultaneously. The
SDK's archived hand-tracking/XWinder samples are separate from these definitions.

The guide permits alternate application gesture sets. The app cannot enable those
sets by following Config with a letter. It also cannot distinguish every original
compact/spread arrangement, row zone, thumb+pinky pair, or particular fingertip.
Current rotation is available only for Thumb+2 and five contacts. `Thumb+2` below
means the app's recognized thumb plus two fingertips; diagonal swipes must have
coherent travel. Pinch/spread requires a thumb for all counts.

**Direct** means a supported input family with the source action. It does not
promise identical thresholds/recognition, firmware acceleration, or application
semantics. **Relocated** means a different input was chosen to avoid an unavailable
slot or a collision. **Proposal only** entries below are not assigned by this JSON.

## Active core map (guide page 1 and XML)

| FingerWorks input / action | App assignment in this file | Status / difference |
| --- | --- | --- |
| RHS 2 fingertips move: point | RHS 2F Move → Pointer | Direct; app recognizes count/cohort rather than arbitrary adjacent-finger identity |
| RHS 2 fingertips tap: click | RHS 2F Tap → Primary Click | Direct |
| RHS 3 fingertips move/roll: drag/select | RHS 3F Move → Drag/Select | Direct; uses existing app latch |
| RHS 3 fingertips tap: double-click | RHS 3F Tap → Double Click | Direct |
| Thumb+middle+ring tap: right-click | RHS Thumb+2 Tap → Secondary Click | Direct family; exact middle/ring identities not required |
| Thumb+2 right-button hold/drag (XML) | Not assigned | Secondary drag/held mouse button is not an assignable gesture action |
| RHS 4 fingertips move: scroll/pan | RHS 4F Move → Scroll/Pan | Direct; keeps app momentum/system scroll preference |
| Thumb+4 expand/contract: zoom | Both independent hands, 5F Spread/Pinch → Zoom | Direct family; app zoom adapter rather than original wheel/context macros |
| LHS 2 fingertips slide: arrows | LHS 2F directions → Left/Right/Up/Down | Direct; repeats with motion |
| LHS 3 fingertips slide: select text | LHS 3F directions → Shift+Left/Right/Up/Down | Direct; repeats with motion |
| LHS 4 fingertips left/right: Home/End | LHS 4F Left/Right → Cmd+Left/Cmd+Right | Source Mac-context beginning/end-of-line macros; one shot |
| LHS 4 fingertips up/down: PageUp/PageDown | LHS 4F Up/Down → PageUp/PageDown | Direct; repeats with motion |
| Thumb+middle pinch: Cut | Independent LHS/RHS 2F Pinch → Cmd+X | Direct family; recognized thumb+one fingertip, not middle-only |
| Thumb+middle spread: Paste | Independent LHS/RHS 2F Spread → Cmd+V | Direct family, same identity limitation |
| Thumb+middle tap: Copy | Independent LHS/RHS 2F Hold → Cmd+C | Relocated to 500 ms stationary Hold; RHS 2F Tap is needed for mouse click |
| Spread thumb+pinky tap: Enter | Both 3F Tap → Enter | Relocated; source's neutral two-hand Enter chord is also supported (page 3), without row-zone restriction |
| RHS thumb+middle up/down: Undo/Redo | RHS Thumb+2 Up-left/Down-left → Cmd+Z/Shift+Cmd+Z | Relocated, extra fingertip and diagonal required |
| RHS thumb+middle right/left: Tab/BackTab | RHS Thumb+2 Up-right/Down-right → Tab/Shift+Tab | Relocated; one shot |
| RHS thumb+2 pinch: Find | RHS 3F Pinch → Cmd+F | Direct thumb/count family |
| RHS thumb+2 spread: Replace (XML) | RHS 3F Spread → Cmd+D | Exact **legacy Mac XML** chord; application-dependent, may be Bookmark/Duplicate rather than Replace in modern apps |
| RHS thumb+2 clockwise: Group / Search Again | RHS Thumb+2 Rotate Right → Cmd+G | Exact source command; app decides Group versus Find Next |
| RHS thumb+2 counter-clockwise: Ungroup (XML) | RHS Thumb+2 Rotate Left → Cmd+Y | Exact source Mac chord; application-dependent, often Redo rather than Ungroup |
| RHS thumb+3 contract: Save | RHS 4F Pinch → Cmd+S | Direct family; source thumb+three shares app count with ordinary 4F gestures |
| RHS thumb+3 expand: New | RHS 4F Spread → Cmd+N | Direct family |
| RHS thumb+3 rotate CCW/CW: Open/Close | RHS 5F Rotate Left/Right → Cmd+O/Cmd+W | Relocated: 4F rotation is inactive; five contacts supported |
| RHS thumb+3 left/right: Back/Forward | RHS 5F Left/Right → Cmd+Left/Cmd+Right | Relocated to preserve RHS 4F Scroll; source AutoAlt Mac interpretation is approximated by command-arrow navigation |
| RHS thumb+3 down: Reload | RHS 5F Down → Cmd+R | Relocated, one shot |
| RHS thumb+3 up: Parent Directory (XML) | RHS 5F Up → Cmd+[ | Relocated; exact source Mac chord, often Back in modern apps, not a universal parent-directory command |
| Spread thumb+3 CCW/CW: Desktop/Exit | Not assigned | Source arrangement collides with File Operations; Show Desktop exists but full modifier-aware window manipulation does not |
| Spread thumb+3 left/right: Previous/Next App | Not assigned | No independent compact/spread 4F direction slots; could substitute Cmd+Shift+Tab/Cmd+Tab for the 5F browser directions |
| Four outer corners, hold 1 second: Configure | Per-pad Outer Corners and Both Outer Corners Hold → Open Config, 1000 ms | Shared existing corner recognition; no original subsequent-letter command interpreter |

A plain LHS 2F Tap, LHS 3F Tap and other unused count taps remain None so they do
not unexpectedly turn text-navigation contacts into mouse clicks.

## Modifiers (guide page 3)

| Source gesture | Translation | Status |
| --- | --- | --- |
| Stationary LHS four fingertips: hold Shift | LHS 4F Hold → Shift, held until all-up | Assigned, 500 ms activation; source timing was regular modifier/chord timing |
| Stationary RHS four fingertips: hold Ctrl/Cmd | RHS 4F Hold → Cmd, held until all-up | Assigned, Mac interpretation, 500 ms activation |
| Above-home-row four-finger chord: Ctrl/Command/AltGr | Same 4F Hold slot as above | Cannot distinguish row zones; proposal only for different modifier choice |
| Home-row four-finger chord: Shift | Same 4F Hold slot | LHS neutral Shift assigned; no row-zone dependency |
| Below-home-row four-finger chord: Alt/Shift+AltGr | Could use held Option in 4F Hold | Proposal only, conflicts with neutral Shift/Cmd |
| Thumb+3 neutral/spread: AltGr/Win/Ctrl/Command variants | Could use held Option/Ctrl in another Hold slot | Proposal only; no compact/spread distinction, and 4F Hold already used |
| Both 4F above home: CapsWord | None | Stateful CapsWord-until-space action not implemented; Caps Lock is not equivalent |
| Both 3F above home: Escape | Could assign Both 4F Tap → Escape | Proposal only; no row-zone detection; no spare Both 3F Tap because Enter uses it |
| Both 3F on home: Enter | Both 3F Tap → Enter | Assigned without row-zone restriction |
| Both 3F move: XWinder | None | No coordinated two-hand movement/transform action |
| AltGr plus RHS sublegend: Programmer's Pad | Existing per-key/layer editor could author a custom layer | Not assigned: exact original AltGr/sublegend state machine is not a gesture binding |

## Alternate formatting sets (guide page 2)

These share source gesture slots with text navigation or other application sets.
The following compatible subset is included; the rest are proposals, not enabled
in parallel through a fake application detector.

| Source gesture/action | Available app translation | Included? |
| --- | --- | --- |
| Thumb+2 up: Bold | LHS Thumb+2 Up-left → Cmd+B | Yes, relocated to diagonal |
| Thumb+2 right: Italics | LHS Thumb+2 Up-right → Cmd+I | Yes, relocated |
| Thumb+2 down: Underline | LHS Thumb+2 Down-left → Cmd+U | Yes, relocated |
| Thumb+2 left: Insert Link | LHS Thumb+2 Down-right → Cmd+K | Yes, relocated |
| Thumb+2 pinch: Font Dialog | LHS 3F Pinch → Cmd+D | Yes, legacy source chord; actual dialog depends on focused app |
| Thumb+2 spread: Select All | LHS 3F Spread → Cmd+A | Yes |
| Thumb+2 rotate CCW/CW: single/double line spacing | LHS Thumb+2 Rotate Left/Right → Cmd+1/Cmd+2 | Yes, legacy source chords; app-dependent |
| Spread thumb+3 CCW: Hanging Indent | LHS 5F Rotate Left → Cmd+T | Proposal only; modern apps may use New Tab |
| Spread thumb+3 CW: Indent | LHS 5F Rotate Right → Cmd+M | Proposal only; modern apps may minimize window |
| Spread thumb+3 up/down: Justify/Center | LHS 5F Up/Down → Cmd+J/Cmd+E | Proposal only |
| Spread thumb+3 left/right: Align Left/Right | LHS 5F Left/Right → Cmd+L/Cmd+R | Proposal only; modern apps may focus location/reload |
| Spread thumb+index pinch/spread: Font Dialog/Select All | Same 2F shapes as Cut/Paste | Not included: conflicts with core clipboard gestures |
| Thumb+2 stationary: Maya Hotbox, held Space | LHS Thumb+2 Hold → held Space | Proposal only; global Hold would affect every app |
| Spread thumb+2 clockwise: Ctrl+M | Thumb+2 Rotate Right → Cmd+M | Proposal only; collides with included line-spacing action |

## Photoshop and Maya sets (guide page 2)

| Source action / gesture | Possible current-app assignment | Limitation |
| --- | --- | --- |
| Photoshop thumb+3 CCW: close view (Ctrl+W) | LHS 5F Rotate Left → Cmd+W | Proposal only, extra finger required |
| Photoshop thumb+3 CW: source Ctrl+M | LHS 5F Rotate Right → Cmd+M | Proposal only; original app-specific key meaning |
| Photoshop thumb+3 left/right: send back/bring forward | LHS 5F Left/Right → Cmd+[/Cmd+] | Proposal only |
| Photoshop thumb+3 up: fit window | LHS 5F Up → Cmd+0 | Proposal only |
| Photoshop thumb+3 down: actual pixels | LHS 5F Down → Option+Cmd+0 | Proposal only |
| Photoshop thumb+3 pinch/spread: demagnify/magnify with modified click | None faithfully | Single shortcut does not sequence modifier-held mouse clicks |
| Photoshop thumb+4 pinch/spread: zoom out/in | LHS 5F Pinch/Spread → Cmd+-/Cmd+= | Proposal only, replaces included native Zoom; source keyboard mapping may require Shift |
| Photoshop spread thumb+3: Space drag | None faithfully | No composite held-Space + primary-drag action |
| Maya thumb+3 vertical pan: Alt+middle-drag | None faithfully | Modified middle-drag output not available |
| Maya spread thumb+3 horizontal/vertical orbit: Alt+left-drag | None faithfully | No combined modifier+drag gesture assignment |
| Maya thumb+4 zoom/rotate | 5F Pinch/Spread → Zoom; rotation to shortcuts if application supports them | Only the included generic zoom is assigned; no continuous rotational axis output |

## Desktop/tool-selection set (guide page 2)

The Meta+function-key compass was application-specific, not a universal macOS tool
API. Each row below is a proposal requiring a separate alternate preset/application
mapping. The JSON does not emit these commands globally.

| Source gesture | Suggested slot / shortcut | Why not included |
| --- | --- | --- |
| Thumb+3 compass left/up/right/down: Meta+F4/F8/F6/F2 | LHS 5F Left/Up/Right/Down → Cmd+F4/F8/F6/F2 | Conflicts with potential formatting/desktop variants; Meta interpretation app-specific |
| Thumb+3 diagonal NW/NE/SW/SE: Meta+F7/F9/F1/F3 | Thumb+2 Up-left/Up-right/Down-left/Down-right → Cmd+F7/F9/F1/F3 | Changes count and conflicts with included formatting shortcuts |
| Thumb+3 pinch: Meta+F5 | LHS 4F Pinch → Cmd+F5 | Proposal only |
| Thumb+3 spread: Meta+F10 | LHS 4F Spread → Cmd+F10 | Proposal only |
| Thumb+3 rotate CCW: Meta+F12 | LHS 5F Rotate Left → Cmd+F12 | Extra finger needed |
| Thumb+3 rotate CW: Meta+F11 | LHS 5F Rotate Right → Cmd+F11 | Extra finger needed |
| Spread thumb+3 up/down: Meta+=/Meta+- | LHS 5F Up/Down → Cmd+=/Cmd+- | Same count/direction slots collide |
| Spread thumb+3 left/right: previous/next desktop | LHS 5F Left/Right → Ctrl+Left/Ctrl+Right | Approximate macOS desktop-switching intent, not original Ctrl+Shift+Tab/Ctrl+Tab |
| Spread thumb+3 CCW: Ctrl+W | 5F Rotate Left → Cmd+W | Extra finger and conflicting rotation slot |
| Spread thumb+2 CW: Ctrl+M | Thumb+2 Rotate Right → Cmd+M | Conflicts with included line spacing |

## Third mouse button / stylus (guide page 2)

| Source input | Translation |
| --- | --- |
| Compact Thumb+2 middle click/drag | No assignable middle-click or middle-drag gesture action; leave unassigned |
| Spread Thumb+2 right click/drag | Right tap is assigned; right drag is unsupported |
| Pengrip: thumb+index plus curled knuckles, middle click/draw | Knuckle/pen-grip classifier and middle-drag lifecycle unavailable; leave unassigned |

## Programmer / Emacs sets (guide page 3)

These are optional source modes, not active in this core preset. Simple single
shortcuts can be authored in existing slots as shown. Multi-command macros and
prefix state cannot be represented by one Shortcut Builder action.

| Source action/gesture | Possible app translation | Status |
| --- | --- | --- |
| Thumb+index spread: Paste / Emacs Execute | 2F Spread → Cmd+V / Option+X | Paste already assigned; Emacs alternative not included |
| Thumb+index left: Delete Word | Thumb+2 Up-left → Option+Backspace | Relocation proposal; conflicts with Undo/Bold |
| Thumb+index CW: Goto Line / Emacs Indent | Thumb+2 Rotate Right → Ctrl+J | Relocation proposal; Cmd versus Ctrl must follow editor binding |
| Spread thumb+index up/down: completion previous/next | Another Thumb+2 diagonal pair → Ctrl+Shift+, / Ctrl+Shift+. | Extra finger/direction substitution; not included |
| Spread thumb+index tap: Ctrl+C | 2F Hold → Ctrl+C | Conflicts with Copy and is not a faithful tap |
| Spread thumb+index CCW: Emacs Shell Cmd (Alt Shift 1) | Thumb+2 Rotate Left → Option+Shift+1 | Relocation proposal |
| Spread thumb+index right: Complete Line | Thumb+2 diagonal → Ctrl+Shift+Space | Relocation proposal |
| Spread thumb+index pinch: Cut / Emacs Prefix | 2F Pinch → Cmd+X / Ctrl+X | Cut already assigned; prefix state is not implemented |
| Spread 2F arrows: Ctrl+Arrows | LHS 2F directions → Option+Arrows for word intent, or Ctrl+Arrows literally | Replaces included character navigation; no compact/spread discriminator |
| Spread 3F select: Ctrl+Shift+Arrows | LHS 3F directions → Option+Shift+Arrows | Word-selection alternative, not included |
| Spread 4F document/page navigation: Ctrl+PgUp/PgDn/Home/End | LHS 4F → document-specific shortcuts (e.g. Cmd+Up/Down) | Replaces included line/page navigation |
| Emacs Thumb+3 CCW: uncomment region (Ctrl+U, Ctrl+;) | None as one action | Multi-stroke command sequence unsupported |
| Emacs Thumb+3 left: keyboard quit | 5F Left → Ctrl+G | Relocation proposal |
| Emacs Thumb+3 right: set mark | 5F Right → Ctrl+Space | Relocation proposal |
| Emacs Thumb+3 up/down: previous/next compile error | 5F Up/Down → editor-configured shortcuts | Literal source uses punctuation/control chords; requires per-editor validation |
| Emacs Thumb+3 CW: comment region | 5F Rotate Right → Ctrl+; | Relocation proposal |
| Emacs Thumb+3 pinch: CVS diff (Ctrl+X,V,=) | None as one action | Sequence unsupported |
| Emacs Thumb+3 spread: check in/out (Ctrl+X,Ctrl+Q) | None as one action | Sequence unsupported |
| Emacs spread Thumb+3 down: universal argument | 5F Down → Ctrl+U | Relocation proposal |
| Emacs 3F tap: Escape | LHS 3F Tap → Escape | Available unused slot, proposal only |
| Emacs spread 2F transpose, horizontal/vertical: Ctrl+B / Alt+B | Would require independent 2F directional set | Conflicts with normal navigation; no spread discriminator |
| Emacs spread 4F scroll other window: Alt+PgUp/PgDn/Home/End | LHS 4F directions with Option modifier | Replaces core set; proposal only |

## Game mode (guide page 4)

| Source family (each listed variation) | Current equivalent / gap |
| --- | --- |
| Config + Shift+G/Pause; config + period/comma options | App Open Config exists; original game-mode toggle and subsequent-letter parser do not |
| Palm heels forward/back: enable/disable per-hand game mode | No palm-direction mode-switch gesture; not assigned |
| RHS thumb-trigger 3 fingertips, plus thumb / pinky / both: pointer, mouse1, mouse2, mouse1+mouse2 | Pointer and primary drag exist separately; cannot differentiate these finger-identity combinations or independently add simultaneous buttons |
| RHS index-trigger thumb+middle+ring, plus index / pinky / both | Same limitation; no independent button triggers while pointing |
| LHS thumb-trigger 3 fingertips, plus thumb / pinky / both: arrows with End / Home / End+Home | Directional arrow shortcuts exist, but no per-finger additional held keys/joystick owner; core left arrows are motion steps, not held joystick arrows |
| LHS index-trigger thumb+middle+ring, plus index / pinky / both | Same finger-specific trigger and simultaneous held-key limitation |
| LHS alternate 4 fingertips plus thumb/pinky: arrows with PgDn, End, Home combinations | No simultaneous directional held keys plus extra finger-specific outputs |
| Thumb+index NW/N/NE/W/E/SW/S/SE: extra game keys | App has only Thumb+2 diagonals plus ordinary 2–5F cardinals; no independent eight-way thumb+index compass |
| Thumb+index tap Space, pinch X, spread Z | Could substitute 2F Hold→Space, 2F Pinch→X, 2F Spread→Z in a separate game preset; conflicts with clipboard in this file |
| Thumb+index expand/contract: wheel up/down | 2F Spread/Pinch → Scroll Up/Down are not legal shape actions in the current catalog; directional scroll actions require movement slots |
| Thumb+index CW: Mouse3 | Middle-click is not an assignable gesture action |
| Thumb+index left/right: Mouse4/Mouse5 | Extra mouse-button gesture actions unavailable; browser shortcut substitutes in this file use 5F movement |

## Reproduction and checks

`python3 Tools/build_touchstream_template.py` regenerates the JSON from the current
MY_KEYMAP keyboard snapshot. Use `--base /path/to/export.json` to preserve a newer
keyboard export. It reads but never changes the source export or app preferences.

`./test.sh --filter TouchStreamTemplateTests` validates the actual portable importer,
all gesture/shortcut actions, held modifiers, unsupported-slot normalization,
STENO-preference preservation, and export/import round-trip. This does not simulate
physical recognition of every remapped chord. Hardware testing should start with
RHS point/click/drag/scroll, LHS arrows/select, Copy Hold, Cut/Paste pinch/spread,
and Outer Corners. Then test the relocated file/search/formatting chords in a
noncritical document. The app's current thresholds, thumb classification and motion
repeat feel remain unchanged.

The Xcode app target explicitly copies `TOUCHSTERAM_KEYMAP.json` into
`Contents/Resources`. Future release DMGs include it inside the app bundle. The
file remains an optional import and does not replace DEFAULT_KEYMAP.json or load
automatically. The generator and offline import checks use its relocated path.

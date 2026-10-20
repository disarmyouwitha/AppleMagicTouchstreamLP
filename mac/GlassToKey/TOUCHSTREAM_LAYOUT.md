# TouchStream LP reference layout

Added 2026-10-20 for creating a TouchStream keymap in GlassToKey.

Choose **TouchStream** from the Layout picker. The preset has separate traced
left/right key regions, including the number row, letters, F1–F12, modifiers,
navigation cluster and angled Backspace/Space thumb regions. It is based on the
supplied `mac/left_layout.jpeg` and `mac/full_layout.gif`; the GIF is the common
coordinate reference for both pads. The photo helps identify the left legends.

The reference background appears automatically while the **TouchStream** layout
is selected and disappears when another layout is selected. The original GIF's
corresponding half sits underneath each sensor grid, key outlines, highlights
and contacts. There is no separate reference checkbox or saved visibility setting.
The unchanged supplied image is bundled at `Resources/TouchStreamReference.gif`.
Its original attribution remains in the image.

Key actions, per-key size/rotation edits and saved mappings use the existing
editor. This preset has fixed independent positions rather than column tuning.
Positions are scaled to each full trackpad surface; rectangular hit regions are
an initial approximation of the printed rounded/oval keys, not measured hardware
geometry. Backspace/Space use rotated rectangular regions. Existing presets,
saved selections and mappings are not replaced automatically.

Normal letters, numbers, modifiers, navigation and function keys use the existing
Mac action catalog. Hand-logo, Caps Lock, Scroll Lock, Num Lock, Popup, Print Screen
and Pause legends are editable inactive placeholders where that catalog has no
corresponding action. No proprietary FingerWorks hand/gesture behavior or PC-only
system behavior is invented. Use the action inspector to assign supported actions.

The editor, app startup and deterministic production replay all resolve the same
geometry through `ContentView.makeTouchStreamKeyLayout`. The background is visual
only and never affects hit testing, capture data or native takeover.

Run `./test.sh`. Tests check independent labels/regions, per-key edit isolation,
actual typed letters at traced key centers on both pads and inert placeholder
bindings. For an offline rendered preview, without opening trackpads:

```sh
TOUCHSTREAM_PREVIEW_PATH=/tmp/glasstokey-touchstream-preview.png ./test.sh
```

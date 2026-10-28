# TouchStream LP reference layout

Added 2026-10-20 for creating a TouchStream keymap in AppleMagicTouchstream.

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

On 2026-10-22, all 88 rectangles were realigned against the bundled 520 × 196
reference after reviewing `mac/misaligned.jpg`. Each dark printed key region was
matched to its existing label, then fitted with a rotated rounded rectangle to
recover its center, width, height and angle. Coordinates use a 260 × 196 canvas
per half. The thumb regions use bounding rectangles around their oval artwork;
their corners therefore extend beyond the printed oval. These remain visual
estimates from a low-resolution image, not physical sensor calibration. Key
order, actions and saved overrides are preserved; existing per-key size/rotation
overrides still apply on top of the revised base trace. Column tuning stays off.

Normal letters, numbers, modifiers, navigation and function keys use the existing
Mac action catalog. Hand-logo, Caps Lock, Scroll Lock, Num Lock, Popup, Print Screen
and Pause legends are editable inactive placeholders where that catalog has no
corresponding action. No proprietary FingerWorks hand/gesture behavior or PC-only
system behavior is invented. Use the action inspector to assign supported actions.

The editor, app startup and deterministic production replay all resolve the same
geometry through `ContentView.makeTouchStreamKeyLayout`. The background is visual
only and never affects hit testing, capture data or native takeover.

Hold actions are opt-in per key. An unassigned Hold/None in the inspector produces
no alternate action; the engine does not use the legacy label-based hold table.
Explicit holds saved in a layout still execute and appear in its inspector and
key labels. This keeps TouchStream independent of the holds in other layouts.

Run `./test.sh`. Tests check independent labels/regions, per-key edit isolation,
actual typed letters at traced key centers on both pads and inert placeholder
bindings. For an offline rendered preview, without opening trackpads:

```sh
TOUCHSTREAM_PREVIEW_PATH=/tmp/amt-touchstream-preview.png ./test.sh
```

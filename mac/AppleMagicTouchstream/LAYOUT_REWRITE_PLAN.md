# Free layout authoring rewrite

## Design

Replace Column Tuning with a document editor for every template, including TouchStream
and all STENO variants. Templates seed editable documents; columns become optional
selection groups rather than geometric constraints. Keys have stable identities,
independent positions, dimensions and rotations. Existing tuned geometry is the seed.

An inline edit session replaces the visualizer and shows both pads together.
Apply compiles and publishes one
layout update through the existing engine boundary; Cancel leaves live geometry alone.
Recognition, gesture arbitration, STENO transport and output ownership remain shared.
The runtime consumes rectangles and cached hit geometry, never editor state.
Mirror Edit defaults on, reflecting geometry and structural changes through stable
counterpart identities while retaining independent actions on each pad. Unmatched
keys remain independent. Canvas renders the local preview without live telemetry;
seed/template snapshots, labels and validation avoid work on every drag frame.

## Implementation checklist

- [x] Document model, stable binding slots, group membership and pure editing operations.
- [x] Editor with key/group dragging, multi-selection, numeric geometry, structural
      edits, alignment, undo/redo and template reset.
- [x] Every template uses authored documents; preserve STENO visible overlap explicitly.
- [x] Save documents locally and include them in settings and capture/replay profiles.
- [x] Decouple hit-test bucket density from logical row/column storage.
- [x] Regression tests for transforms, structural identity, round-trip and compilation;
      full offline suite, Release build and release preflight.

## Storage and runtime

UUIDs identify editable keys and groups. Immutable row/column binding slots are opaque
runtime addresses, not physical positions. Removing a key never renumbers another key;
new slots are append-only, so layers and held-output ownership keep a stable address.
Sparse deleted slots compile to zero-area rectangles with None labels. The tested
recognizer remains the runtime adapter rather than gaining a second hit-test system.

Physical dimensions use the existing pad calibration. Drawn STENO overlaps are captured
as explicit edge extensions, so moving a key does not recompute its shape from row
neighbors. STENO hit allowances and multi-key accumulation stay independent of typing
Snap Radius. Editing snap is a separate millimeter grid.

## Verification and hardware follow-up

Offline checks must cover deleted slots, duplicated keys, group rotation, bounded
geometry, undo/redo, document encoding and replay profile propagation. Hardware follow-up
should compare edited STENO chords, ordinary typing, layers and gesture reservation.
Do not launch input takeover or post native events during offline verification.

## Delivered validation

- `./test.sh`: 518 tests executed, seven hardware-dependent skips, zero failures;
  native takeover offline checks also passed.
- Offscreen AppKit/SwiftUI rendering inspected at 1140 × 460, 1384 × 520 and
  1600 × 720 without launching the app or native input. Both pads fit beside the
  resizable inspector; key selection exposes exact geometry without applying it.
  Compact tools and shared selection resizing also render at 220/450-point inspector
  widths. Temporary selections, member pivots, rotated frames, constraints, mirrored
  resizing and no-op edits have offline regression coverage.
- Universal arm64/x86_64 Release built, Developer ID signature verified, and
  `./release.sh --check` confirmed bundle identity.
- Assignment reconciliation is part of Apply: removed keys lose their saved
  mappings; duplicates copy every layer before obsolete slots are pruned.
- Layout documents are decoded once into UI state and compiled at Apply rather
  than during input frames or visualizer refreshes.

### Hardware review

Open Layout Editor, move a column, then move/resize one key independently and Apply.
With Mirror Edit on, check reflected movement/resizing/rotation and dashed partner
previews. Turn it off and verify each half stays independent. Test click and box
selection with individual keys only. Resize a temporary selection with the shared
frame handle, exact dimensions and 5% buttons, including mirrored and mixed-rotation
selections. Check segmented Off/1 mm/5 mm snap beside the title, compact tools capped at three
columns, the count beside Add Column and visualizer size caps. Apply/Cancel return to the
visualizer; Cancel must leave geometry unchanged. Check Undo/Redo/Reset and then
check typing at the new positions and switching layers. Duplicate an assigned key,
remove it, reset the template and add another key; an old action must not reappear.
For STENO Asterisk and Single, check the accepted overlapping chords after moving
keys. Try settings export/import and capture/replay with the edited geometry.
Live gesture arbitration, STENO mouse/force behavior and transport were not changed.

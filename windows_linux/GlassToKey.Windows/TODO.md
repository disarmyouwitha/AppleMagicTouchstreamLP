## CURRENT:
- Can I implement an `App Launcher` into Custom Shortcuts?: Calculator.. VSCode.. Chrome? You decide!
- DECIDE: Do I like Custom Buttons as a collapsable? 

## User Issues:
- `chording with more than 3 keys doesn't register`: I think I should be able to "fix" rolling by exposing a slider for tuning tap cadence (ms). Marking 3+ finger chords as "won't fix: use Custom Shortcuts"
- Test: `momentary layer not working when used as a hold action` Backspace / MO(1) with custom button underneath makes input go crazy (interaction with another layer?)
- Try: `left click every time I press a key` I think you actually pointed out one avenue I haven't explored and that is setting that taps windows Mouse events and eats them if they are under Force Min. (This way you could set an Actuation Force basically that determines if you are mouse tapping(lighter) or key tapping (harder))

## TODO:
- `Keyboard / Mouse` mode should just be about state machine
- `Suppress Mouse in Keyboard mode` should be an OPTION
---
- caps lock button?
- What other actions could we add??
- Can we add 3-finger tap? this one should be easy to differentiate between typing fast, right?
- Can we add a small checkbox next to each action which when clicked would make that gesture "continuous" so it will repeat if the gesture is held?
- Tune velocity / drag cancel on windows /w codex
- When the config opens, it opens maximized Can we have it opened windowed, unless the user maximizes it — and then remember their choice? Or would we have to add a bunch of nonsense to track that? (It wont be worth it in that case)

## ICONIC:
- Need a logo for glasstokey!
- Start transition from Circles to Triangles


## FUTURE:
- `Resting Fingers` Mode: allow ppl to put their fingers on the keyboard and tap 1 at a time to emit the key.
- ^ In this mode we ignore gesture intent, etc so that dispatch is based only on force (TRY IN KEYBOARD MODE?!)
- ^ In this mode can we ignore touches under X Force *as if* they were not contacts on the keyboard? That would allow what they want I think!
- `Gesture as a modifier state`: 5-finger hold RHS (Gesture State) + 3-finger swipe LHS moves arrow keys L/R (settable)
- `Handed Gestures`: Create Gestures (Left) and Gestures (Right) and make the gestures handed, instead of duplicate
- `Advanced Gestures Config` as it's own GUI like Config? (more breathing room to make the GUI more usable)
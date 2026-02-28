## TODO:
- Remove Mobile layout from layout dropdown, remove from MY and DEFAULT .json keymaps
- If "memory saver" toggle is enabled: When Config is closed to Tray can we restart the entire app to save memory? (60mb)
---
- LINUX WHEN?
-------
- Can we add 3-finger tap? this one should be easy to differentiate between typing fast, right?
- Is there any way to add a "click and drag gesture that would start on Hold and Release when you release your fingers? [3 finger "grasp" to 1 finger] [Can we try 5-finger hold to activate - gesture stays active until 0 fingers so I can drag around until I release??]
- What other actions could we add??
- caps lock button?
---
- *SINGLE FINGER MOUSE DRAG TO 2 FINGER HOLD CLICK WOULD GO SO HARD WE MUST MAKE THIS HAPPEN!!*
- ** Mention Auto-Splay for Windows in readme!
- Tune velocity / drag cancel on windows /w codex
---
- Can we add a small checkbox next to each action which when clicked would make that gesture "continuous" so it will repeat if the gesture is held?
- 2/3 finger tap gestures~
-------
- `Resting Fingers` Mode: allow ppl to put their fingers on the keyboard and tap 1 at a time to emit the key.
- ^ In this mode we ignore gesture intent, etc so that dispatch is based only on force (TRY IN KEYBOARD MODE?!)
- ^ In this mode can we ignore touches under X Force *as if* they were not contacts on the keyboard? That would allow what they want I think!
---
- REFACTOR

## FUTURE:
- `Gesture as a modifier state`: 5-finger hold RHS (Gesture State) + 3-finger swipe LHS moves arrow keys L/R (settable)
- `Handed Gestures`: Create Gestures (Left) and Gestures (Right) and make the gestures handed, instead of duplicate
- `Advanced Gestures Config` as it's own GUI like Config? (more breathing room to make the GUI more usable)
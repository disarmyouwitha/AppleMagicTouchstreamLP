## TODO:
- Can we add 3-finger tap? this one should be easy to differentiate between typing fast, right?
- Is there any way to add a "click  and drag gesture that would start on Hold and Release when you release your fingers?
- What other actions could we add??
---
- *SINGLE FINGER MOUSE DRAG TO 2 FINGER HOLD CLICK WOULD GO SO HARD WE MUST MAKE THIS HAPPEN!!*
- ** Mention Auto-Splay for Windows in readme!
- Tune velocity / drag cancel on windows /w codex
---
- Can we add a small checkbox next to each action which when clicked would make that gesture "continuous" so it will repeatif the gesture is held?
---
- Can we make the max scaling of the Trackpad devices in the GUI match the physical diminsions of the apple magic trackpad2? (Look it up) I think that will give us more room to add to the GUI!
------- 
- Autocorrect: spelljam? symjam? **ISpellCheckerFactory → ISpellChecker**
- Is typing... bad? lol. Try Keyboard mode and see if it's any better.. Snap radius on first hit?
- 2/3 finger tap gestures~
-------
- `Resting Fingers` Mode: allow ppl to put their fingers on the keyboard and tap 1 at a time to emit the key.
- ^ In this mode we ignore gesture intent, etc so that dispatch is based only on force (TRY IN KEYBOARD MODE?!)
- ^ In this mode can we ignore touches under X Force as if they were not contacts on the keyboard? That would allow what they want I think!
---
- REFACTOR

## FUTURE:
- `Gesture as a modifier state`: 5-finger hold RHS (Gesture State) + 3-finger swipe LHS moves arrow keys L/R (settable)
- `Handed Gestures`: Create Gestures (Left) and Gestures (Right) and make the gestures handed, instead of duplicate
- `Advanced Gestures Config` as it's own GUI like Config? (more breathing room to make the GUI more usable)
## User Issues:
- momentary layer not working when used as a hold action
- Allow User-set key-combos
- test 3-finger holds like ctrl+alt+del
- allow option to override "3+ finger = gesture" rule:
{ Every other gesture is modeled inside the engine. TouchProcessorCore.ProcessFrame runs swipes,
    multi-finger holds, clicks, corner/triangle/force gestures, then intent arbitration in one place
    in TouchProcessorCore.cs:681. The engine also reserves 3+ finger contact sets for
    GestureCandidate, and there are tests that explicitly assert that in SelfTestRunner.cs:1036.}

## TODO:

nessisary now?
-   4. Add arbitration rules so stationary 3-finger hold/click are no longer stolen.
  5. Retune thresholds.
  6. Delete obsolete controller code.
  Add and/or update tests in SelfTestRunner.cs and LinuxSelfTestRunner.cs:
- Great! My only complaint about the 3-finger grab logic is that it's eating 3-finger holds and 3-finger clicks when I would consider that I am not moving my fingers. Maybe we need to up the mm for drag? Please analyze and advise. 
---
- `Memory Saver` toggle to gate restart logic.. can I have hover-text explain "restarts GTK when config is closed"
- `Keyboard / Mouse` mode should just be about state machine
- `Suppress Mouse in Keyboard mode` should be an OPTION
---
- caps lock button?
- What other actions could we add??
- Can we add 3-finger tap? this one should be easy to differentiate between typing fast, right?
- Can we add a small checkbox next to each action which when clicked would make that gesture "continuous" so it will repeat if the gesture is held?
- Tune velocity / drag cancel on windows /w codex

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
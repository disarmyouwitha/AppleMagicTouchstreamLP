## TODO:
- Implement 3-Finger Drag (Like Mac!) for Windows / Linux: 
On Mac you can 3-finger drag to move windows, or select files. It's perfect. Windows does not expost this functionality, infact, if you drag with 3 fingers the mouse's X, Y are not moved AT ALL by the operating system. I have downloaded an app from the Microsoft App store `ThreeFingerDragOnWindows` which is installed on this computer if you need a look. 

What I think this program is doing is:
1. Taking raw x,y data from the trackpad and synthesizing mouse movement.
2. Allowing 3-finger holds to trigger a mouse-down and then full release of fingers is mouse up.

Does this seem conceptually sound? I need you to analyze the codebase, check references on the web, and give me your best implementation for GlassToKey Windows. 

3-Finger drag should be exposed as a Mode Toggle checkbox.


-------
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
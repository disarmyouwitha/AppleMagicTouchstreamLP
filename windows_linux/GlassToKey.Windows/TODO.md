## Current:
`Shortcut Builder`: Add "Dropdown" radio option [Primary, Hold, Dropdown] 
If the new option `Dropdown` is selected it should save to the User Settings, and to the keymap when imported/exported in a cross-complatible way with Linux.

- Can we add `3-finger tap` Gesture? this one should be easy to differentiate between typing fast, right? (Do you need an .atpcap?). If no 3-finger tap is set, it should not try to determine if an action is a 3-finger tap, so the hot path can stay hoter if no action is set.
- Take another look at `FingerWorks` Gestures, like `PINCH` for copy!


## TODO:
- `Keyboard / Mouse` mode should just be about state machine
- `Suppress Mouse in Keyboard mode` should be an OPTION *******
- `Click & Drag Columns` allow user to drag columns around if "edit keymap" is enabled. Show different toggles if `edit keymap` is enabled? (more consistent GUI /w mac?)
---
- When the config opens, it opens maximized Can we have it opened windowed, unless the user maximizes it — and then remember their choice? Or would we have to add a bunch of nonsense to track that? (It wont be worth it in that case)



## ICONIC:
- Need a logo for glasstokey!
- Start transition from Circles to Triangles


## FUTURE:
- `Resting Fingers` Mode: allow ppl to put their fingers on the keyboard and tap 1 at a time to emit the key.
- ^ In this mode we ignore gesture intent, etc so that dispatch is based only on force (TRY IN KEYBOARD MODE?!)
- ^ In this mode can we ignore touches under X Force *as if* they were not contacts on the keyboard? That would allow what they want I think!
- `Handed Gestures`: Create Gestures (Left) and Gestures (Right) and make the gestures handed, instead of duplicate
- `Gesture as a modifier state`: 5-finger hold RHS (Gesture State) + 3-finger swipe LHS moves arrow keys L/R (settable)
- `Tune` velocity / drag cancel on windows /w codex
- `Typing Test`: Generate random words to type? lol.



# unrelated:
- `AI Tamagachi`: Something like a controlled openclaw.. It runs in the background and you take care of it and interact with it and feed it until it hatches. As it grows, it can learn skills.. Maybe it starts to talk one day.. maybe it notices that the the user has a mic and it asks for permission to use the mic to `hear` you? (lol) 
- `Controlled Growth` and aquisition of `skills` at certain levels.. Maybe it learns to Text-to-speach (functionally by giving it an .md in the harness) one day and starts talking to you unexpectedly! Maybe before that it starts having `desires` to speak to the user and instruct the AI express it with `emoji` or.. ?? (unexpected AI surprises might be the fun!)
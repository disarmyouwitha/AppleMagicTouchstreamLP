## Current:
- I think bottom-left and bottom-right triangles are implemented backwards? lol. Let me think about it and get you a pcap



Add more `Force Click` options:
- Add `2-Finger click` (Force above 125 should cancel `2-finger hold`?)
- Add `3-Finger click`
- Add `4-Finger click`

- Are Triangles Corner swipes? (Maybe, if I can describe it clearly with a picture?)
- For `Triangle` swipes can we have them trigger regardless of which direction you turn, as long as you start on the right corner? That would go hard for me
-------
- New branch to test Accelerator bright / vol/ L / R
- Under `Hold Action` add an option: `Use Force: (text area for pressure)` 0 would be off and X would be the force to trigger a "Hold" action. If Pressure > 0 don't fire hold action after X(ms) but only after X(force)
-------
- Can we add `3-finger tap` Gesture? this one should be easy to differentiate between typing fast, right? (Do you need an .atpcap?). If no 3-finger tap is set, it should not try to determine if an action is a 3-finger tap, so the hot path can stay hoter if no action is set.
- New gestures from FRAN!
- Take another look at `FingerWorks` Gestures, like `PINCH` for copy!
---
- `Handed Gestures`: Create Gestures (Left) and Gestures (Right) and make the gestures handed, instead of duplicate
- `Advanced Gestures Config` as it's own GUI like Config? (more breathing room to make the GUI more usable)
- Can we add a small checkbox next to each action which when clicked would make that gesture "continuous" so it will repeat if the gesture is held? Or maybe a small textarea with [ms] placeholder text, that if above 0 it will repeat at that cadence? Please advise on the best UX for this.

## TODO:
- `Keyboard / Mouse` mode should just be about state machine
- `Suppress Mouse in Keyboard mode` should be an OPTION *******
- `Click & Drag Columns` allow user to drag columns around if "edit keymap" is enabled. Show different toggles if `edit keymap` is enabled? (more consistent GUI /w mac?)
---
- `Force Dependant keymap` make a key variable output depending on the force used (similar to hold)
- When the config opens, it opens maximized Can we have it opened windowed, unless the user maximizes it — and then remember their choice? Or would we have to add a bunch of nonsense to track that? (It wont be worth it in that case)
- Tune velocity / drag cancel on windows /w codex

## User Issues:
- Test: `momentary layer not working when used as a hold action` Backspace / MO(1) with custom button underneath makes input go crazy (interaction with another layer?)

## ICONIC:
- Need a logo for glasstokey!
- Start transition from Circles to Triangles


## FUTURE:
- `Resting Fingers` Mode: allow ppl to put their fingers on the keyboard and tap 1 at a time to emit the key.
- ^ In this mode we ignore gesture intent, etc so that dispatch is based only on force (TRY IN KEYBOARD MODE?!)
- ^ In this mode can we ignore touches under X Force *as if* they were not contacts on the keyboard? That would allow what they want I think!
- `Gesture as a modifier state`: 5-finger hold RHS (Gesture State) + 3-finger swipe LHS moves arrow keys L/R (settable)


# unrelated:
- AI Tamagachi: something like a controlled openclaw.. It runs in the background and you take care of it and interact with it and feed it it will grow. As it grows, it can learn skills.. Maybe it starts to talk one day.. maybe it notices that the the user has a mic and it learns to listen? 
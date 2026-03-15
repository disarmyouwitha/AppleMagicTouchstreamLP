## Current:
- Can we move Column Spacing to the top of Column Tuning?
- Can we make it when you click "choc spacing" it tries to calculate the horizontal padding to match the vertical, like it does for "mx spacing?
---
- Can we move "mx spacing" and "choc spacing" above "Autosplay" and "e v e n s p a c e"
- Can we rename "mx spacing" > "mx size" and "choc spacing" > "choc size"
- Can we rename "e v e n s p a c e" > "e v e n s p a c i n g"
---
- Can we add `3-finger tap` Gesture? this one should be easy to differentiate between typing fast, right? (Do you need an .atpcap?). If no 3-finger tap is set, it should not try to determine if an action is a 3-finger tap, so the hot path can stay hoter if no action is set.
---
- `Handed Gestures`: Create Gestures (Left) and Gestures (Right) and make the gestures handed, instead of duplicate
- `Advanced Gestures Config` as it's own GUI like Config? (more breathing room to make the GUI more usable)
- Can we add a small checkbox next to each action which when clicked would make that gesture "continuous" so it will repeat if the gesture is held? Or maybe a small textarea with [ms] placeholder text, that if above 0 it will repeat at that cadence? Please advise on the best UX for this.

## TODO:
- `Keyboard / Mouse` mode should just be about state machine
- `Suppress Mouse in Keyboard mode` should be an OPTION *******
- `Click & Drag Columns` allow user to drag columns around if "edit keymap" is enabled. Show different toggles if `edit keymap` is enabled? (more consistent GUI /w mac?)
---
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


# Unicode send??

  Rework
  If you want ñ to work regardless of Windows layout, the right rework is direct text injection, not
  more AltGr logic.

  What that would involve:

  - Add a new action type for literal text, likely single-character first, instead of only VK/semantic
    key actions.
  - Extend parsing/storage/UI so a key can map to something like a text action rather than a shortcut
    chord.
  - Add a Windows dispatch path using Unicode SendInput instead of virtual-key/scancode injection.
  - Decide semantics for hold/repeat. My recommendation: text actions should be tap-only at first.
  - Add tests for parsing, engine dispatch, and Windows Unicode injection behavior.

  In practice, Windows-only first is a moderate change, not huge. The existing system is VK/chord-
  centric, so this is additive rather than a one-line fix. If you want the smallest useful version,
  I’d implement:

  - single-character Unicode text actions
  - Windows dispatch only
  - no shortcut-builder changes yet
  - simple UI entry in the Primary/Hold action model
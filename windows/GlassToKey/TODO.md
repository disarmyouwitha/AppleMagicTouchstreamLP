## TODO:
- FIX DEFAULT KEYMAP NOW THAT EVERYTHING IS FINALLY NORMALIZED!
- Width is not fully displayed in trackpad GUI  (-20px?)
- Add actions like VOL_UP VOL_DOWN BRIGHT_UP BRIGHT_DOWN to the dropdown (cool separator)
- Revisit tap-click.. it feels awful. Settings? Maybe 2-finger and 3-finger hold to trigger click??
- Autocorrect: spelljam? symjam? **ISpellCheckerFactory → ISpellChecker**
- Voice mode: "windows siri/dictation" (Win+H Dictation) + ESC to close window
- Resting Fingers: allow ppl to put their fingers on the keyboard and tap 1 at a time to emit the ky
- REFACTOR
---
## Gesture Config:
- Shows available gestures: ("Tap Gestures") 2-finger tap, 3-finger tap ("Swipe Gestures") 5-finger swiper L/R ("Hold Gestures") 4-finger hold
- Allow user to select their own action for a gesture from a pre-formed list: Typing Toggle, Chordal Shift, or allow them to select a regular Action from the drop-down

## Worth it?
- Add force cut off into GUI and settings. Make pressure over cutoff disqualify key dispatch
- Only worth persuing Pressure if we can get Haptics to work, I think
- I think maybe on OSX I can tell if user is resting fingers or tapping by pressure?? (Move TODO)

## CURSED:
- HAPTICS: Not sure if I can get codex to figure it out, I certainly cant. 

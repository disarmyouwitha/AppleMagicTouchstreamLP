## TODO:
- Cant hold Left/Right/Up/Down for repeat.
- MO layer should be able to fire even during Mouse mode (or keyboard mode)
- Revisit tap-click.. it feels awful. Settings? Maybe 2-finger and 3-finger hold to trigger click??
- Autocorrect: spelljam? symjam? **ISpellCheckerFactory → ISpellChecker**
- Voice mode Gestue (Outer Corners): "windows siri/dictation" (Win+H Dictation) + ESC to close window
- Resting Fingers: allow ppl to put their fingers on the keyboard and tap 1 at a time to emit the ky
- REFACTOR
---
## Gesture Config:
- Shows available gestures: ("Tap Gestures") 2-finger tap, 3-finger tap ("Swipe Gestures") 5-finger swiper L/R ("Hold Gestures") 4-finger hold ("Corners") Outer corners, Inner corners
- Allow user to select their own action for a gesture from a pre-formed list: Typing Toggle, Chordal Shift, or allow them to select a regular Action from the drop-down
- If I make a recording of a gesture, can Codex understand it enough to write the logic to catch the gesture? 

## Worth it?
- Add force cut off into GUI and settings. Make pressure over cutoff disqualify key dispatch
- Only worth persuing Pressure if we can get Haptics to work, I think
- I think maybe on OSX I can tell if user is resting fingers or tapping by pressure?? (Move TODO)
- "force click" mode — it only emits keystrokes on "click" [Can I tell tap/click in the PTP?] (for people who really want to press a key? it should force Keyboard mode.)

## CURSED:
- HAPTICS: Not sure if I can get codex to figure it out, I certainly cant. 

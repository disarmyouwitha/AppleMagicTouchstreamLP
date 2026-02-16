## TODO:
- Revisit tap-click.. it feels awful. Settings? Maybe 2-finger and 3-finger hold to trigger click??
- ^^^ This has to be next bro, lol.
- Double check intent state on Windows for Mixed
- Autocorrect: spelljam? symjam? **ISpellCheckerFactory → ISpellChecker**
- Voice mode Gestue (Outer Corners): "windows siri/dictation" (Win+H Dictation) + ESC to close window
- REFACTOR
- [Resting Fingers mode]: allow ppl to put their fingers on the keyboard and tap 1 at a time to emit the key.
- ^ In this mode we ignore gesture intent, etc so that dispatch is based only on force (TRY IN KEYBOARD MODE!)

## Gesture Config:
- If I make a recording of a gesture, can Codex understand it enough to write the logic to catch the gesture? 

Working: 5-finger swipe left/right; 2/3finger tap

Working: Inner corners 
Not Working: Outer corners
(This seems to be because my inner corners land on custom buttons or os there )

ALSO: 4-finger hold is only working for chordal shift. For other actions it should fire like a normal key/toggle/etc. from the action menu.

**Gestures**  
**Ph  based:** Force click1 (ph:1), Force Click2 (ph:2)
**corners** upper-left,upper-right,lower-left,lower-right corner taps holds
**corners** Inner corners hold, Outer Corner Hold
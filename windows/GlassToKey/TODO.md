## TODO:
- 2 / 3 finger tap should not happen if drag cancel is triggered! (scrolling/swiping, not holding)
- Can we add 2-finger and 3-finger hold gestures to the "Hold Gestures" section? 2 and 3 finger hold gestures should trigger when the user keeps the specified number of fingers on the board for Hold(ms) multifinger_hold.atpcap
- Can we add "double-click" action that fires 2 clicks quickly? 
- What other actions could we add?? 
- 2 and 3-finger taps do not trigger well.. can you help me out? Stagger? Recording?
- Revisit tap-click.. it feels awful. Settings? Maybe 2-finger and 3-finger hold to trigger click??
- ^^^ This has to be next bro, lol.
-------
- Autocorrect: spelljam? symjam? **ISpellCheckerFactory → ISpellChecker**
- `Voice mode` Gesture:  (Win+H Dictation) + ESC to close window on closing gesture.
- `Resting Fingers` Mde: allow ppl to put their fingers on the keyboard and tap 1 at a time to emit the key.
- ^ In this mode we ignore gesture intent, etc so that dispatch is based only on force (TRY IN KEYBOARD MODE?!)
---
- REFACTOR

## FUTURE:
- `Gesture as a modifier state`: 5-finger hold RHS (Gesture State) + 3-finger swipe LHS moves arrow keys L/R (settable)
- `Handed Gestures`: Create Gestures (Left) and Gestures (Right) and make the gestures handed, instead of duplicated

Actually, I would like to decouple all Hold Gestures from Drag Cancel as well and give them their own cancel logic. For all Hold gestures if the fingers move even a little like they are being dragged or swiped we should not trigger the hold. Hold gestures are for stationary fingers. I have recorded hold_good.atpcap and hold_bad.atpacp examples for you.

You can download the executables here but please read the <github link>README</a> for Usage and Install instructions!
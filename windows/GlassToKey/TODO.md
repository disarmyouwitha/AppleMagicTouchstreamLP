## TODO:
- Revisit tap-click.. it feels awful. Settings? Maybe 2-finger and 3-finger hold to trigger click??
- ^^^ This has to be next bro, lol.
^^ Tap clicks don't put us in `gest` ??
- Double check intent state on Windows for Mixed
- Autocorrect: spelljam? symjam? **ISpellCheckerFactory → ISpellChecker**
- Voice mode Gestue (Outer Corners): "windows siri/dictation" (Win+H Dictation) + ESC to close window
- REFACTOR
- [Resting Fingers mode]: allow ppl to put their fingers on the keyboard and tap 1 at a time to emit the key.
- ^ In this mode we ignore gesture intent, etc so that dispatch is based only on force (TRY IN KEYBOARD MODE!)

## Gesture Config:
[1] If 3+ fingers are on the touchpad we are in gesture mode, even if we are on keys. When this happens we should consume all keys so no keys are dispatched on release. This is currently happening on 3finger tap and holds on keys and 4-finger hold on keys (except for chordal shift, which works exactly how I want it to work for the rest of them) 3plus_finger_gesture_dispatch.atpcap

[2] CORNERS: You did something intersting, but wrong. You made each corner an individual hold that triggers individually but the actual gesture is like this: Inner: BOTH top and bottom corners are held at the same time for the inner corners. Outer: BOTH top and bottom corners are held at the same time for the outer corners. Right now, Tap-click also interferes with this gesture. 

[3] Can Capture and Replay open in Fullscreen mode?


- If I make a recording of a gesture, can Codex understand it enough to write the logic to catch the gesture? 

Working: 5-finger swipe left/right is perfect!

Observation: [1] Corner gestures should only fire after hold duration [2] Both Inner and Outer Corner gestures only fire when at least 1 finger is on a custom button, and not when both fingers are off key [3] 2+ Finger holds, and 3+ Finger gestures should take priority over Key/Custom Button hits!


**Gestures**  
**Ph  based:** Force click1 (ph:1), Force Click2 (ph:2)
**corners** upper-left,upper-right,lower-left,lower-right corner taps holds
**corners** Inner corners hold, Outer Corner Hold

- Rename Column Settings> Column Tuning, Keymap Editor > Keymap Tuning, Gesture Config > Gesture Tuning in the GUI. Make Gesture Tuning collapsed by default. 
- After we get 4-finger hold working we can remove chordal shift, tap click from the Mode checkboxes (they can just set/unset them in the Gesture menu)
- Move Keyboard/Mouse mode on top of the 3 remaining options. 


Inner Corners: I have custom buttons on the corner and those
  are taking priority, we are in typing mode and it does the
  custom button action. 
  
Outer Corners: I have no custom buttons
  or actions and I can see we go into `gest` however no action
  ever fires. 
  
4-finger hold: is only being considered a `gest`
  if none of my fingers are on a key or custom button, otherwise it dispatches keys. 
  
  Anything assigned to this gesture should work like Chordal Shift does: If 4-finger hold is triggered, no regular keys or custom button actions should disptch, only the 4-finger hold action.
  *(Chordal Shift is a special gesture that allows you
  to type on the other side!). 
  
  Currently when 4-finger hold hits any keys they all trigger on release - they should not.

  ---

  If 4-finger hold is triggered it should block normal key
  dispatch and only send the gesture keycode. Re:corners, You
  have it backwards.. I want to be able to trigger the corner
  gestures regardless of if they are on a key, or a custom
  button or nothing at all. If one of the "two finger" corner
  gestures triggers it should take priority over the key/button
  it hit and only output the gesture action.
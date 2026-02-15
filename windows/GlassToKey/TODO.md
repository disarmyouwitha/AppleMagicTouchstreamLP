## TODO:
-------
- Revisit tap-click.. it feels awful. Settings? Maybe 2-finger and 3-finger hold to trigger click??
- Autocorrect: spelljam? symjam? **ISpellCheckerFactory → ISpellChecker**
- Voice mode Gestue (Outer Corners): "windows siri/dictation" (Win+H Dictation) + ESC to close window
- REFACTOR
- [Resting Fingers mode]: allow ppl to put their fingers on the keyboard and tap 1 at a time to emit the key.
- ^ In this mode we ignore gesture intent, etc so that dispatch is based only on force (TRY IN KEYBOARD MODE!)
---
## Gesture Config:
- Shows available gestures: ("Tap Gestures") 2-finger tap, 3-finger tap ("Swipe Gestures") 5-finger swiper L/R ("Hold Gestures") 4-finger hold ("Corners") Outer corners, Inner corners    
- Allow user to select their own action for a gesture from a pre-formed list: Typing Toggle, Chordal Shift, or allow them to select a regular Action from the drop-down
- If I make a recording of a gesture, can Codex understand it enough to write the logic to catch the gesture? 
**Gestures** "click"(btn47), **Ph:** Force click1, Force Click2.


## Notable Drift / Health
- Are we currently failing any of our self tests?:
  - Self-test baseline is currently failing locally: Engine intent tests failed: expected
    mouseCandidate->mouseActive transitions were missing (dotnet run --project
    GlassToKey\GlassToKey.csproj -c Release -- --selftest).
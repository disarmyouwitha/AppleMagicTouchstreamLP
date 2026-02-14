## TODO:
- When accessing MO() layer I can hit some number 1,3 but I cant hit 2 - what I noticed is when I try to hit 2 the indexes floating on my fingers change.. why would this affect if I can press a key on a MO() layer and can it be fixed?
 
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


## CURRENT CONTEXT:
  Notable Drift / Health

  - Docs say key/mouse candidate buffer is fixed at 40ms (GlassToKey/README.md:45), but runtime config
    currently hardcodes 20ms (GlassToKey/RuntimeConfigurationFactory.cs:13).
  - Self-test baseline is currently failing locally: Engine intent tests failed: expected
    mouseCandidate->mouseActive transitions were missing (dotnet run --project
    GlassToKey\GlassToKey.csproj -c Release -- --selftest).

  If you want, I can next do one of these:

  1. Implement the allocation-free stable session ID tracker for lifecycle continuity.
  2. Add per-frame CSV/JSON XY+slot-byte diagnostics to RawCaptureAnalyzer.
  3. Triage and fix the current self-test failure first.  
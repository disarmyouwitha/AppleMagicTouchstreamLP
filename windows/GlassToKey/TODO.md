## TODO:
- Code to prevent you from opening up multiple instances: alert -> close duplicate instance.
---
*When I have LHS:USB, RHS:Bletooth it's failing on the bluetooth side but playing on the LHS over USB
- USB-only haptics as the supported path, and degrade gracefully on BT.
[] When using 1 device over USB and 1 over Bluetooth, both on the official drivers, if I connect to USB first, then I can no longer select the Bluetooth device from the list.. it immediately swaps to USB. 

[] when I have 1 official and 1 opensource plugged in via USB I can only see the opensource one? Seems like there are device list inconsistencies?? When this happens the Opensource device will trigger haptics on the other device ** lets check this after we figure out per-device haptics
[] I got an extension of this bug where I was getting haptics on the Opensource driver, which indicates we may be able to enable Haptics for open source driver ??
-------
- Can we make capture/replay work with opensource/legacy decoders or will it be a pain in the ass? =x do the .atpcap understand which decoder they were recorded from? Ideally it could be recorded on either, like one official and one opensource and it would recognize which decoder to use for which side. (mention it in INSTALL if we can!)
- Test with opensource drivers
-------
- When I am holding a MO() button it should allow you to bypass Mouse-only ans Keyboard-only mode.
- Re-write Pressure as Force throughout the readme
- Can we wire a "force cap" slider into the GUI? (using new variable) /test
- Can we wire a "force min" slider into the GUI? (using new variable) /test
^ These will both be in phase1, so, slider can be 0-255
^ Resting Fingers: allow ppl to put their fingers on the keyboard and tap 1 at a time to emit the ky
-------
- Revisit tap-click.. it feels awful. Settings? Maybe 2-finger and 3-finger hold to trigger click??
- Autocorrect: spelljam? symjam? **ISpellCheckerFactory → ISpellChecker**
- Voice mode Gestue (Outer Corners): "windows siri/dictation" (Win+H Dictation) + ESC to close window
- REFACTOR
---
## Gesture Config:
- Shows available gestures: ("Tap Gestures") 2-finger tap, 3-finger tap ("Swipe Gestures") 5-finger swiper L/R ("Hold Gestures") 4-finger hold ("Corners") Outer corners, Inner corners    
- Allow user to select their own action for a gesture from a pre-formed list: Typing Toggle, Chordal Shift, or allow them to select a regular Action from the drop-down
- If I make a recording of a gesture, can Codex understand it enough to write the logic to catch the gesture? 
**Gestures** "click"(btn47), **Ph:** Force click1, Force Click2.


## Notable Drift / Health

  - Docs say key/mouse candidate buffer is fixed at 40ms (GlassToKey/README.md:45), but runtime config
    currently hardcodes 20ms (GlassToKey/RuntimeConfigurationFactory.cs:13).
  - Self-test baseline is currently failing locally: Engine intent tests failed: expected
    mouseCandidate->mouseActive transitions were missing (dotnet run --project
    GlassToKey\GlassToKey.csproj -c Release -- --selftest).
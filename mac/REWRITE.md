===
## TELL CODEX:
> `?` Can you use gesturepad or AppleMagicTouchstream for your reverse engineering efforts? What would allow you to do that? The trackpads are a little smaller but I set up a scaled down keymap that matches ('TouchStream' layout)
> I want to see if you can confirm any of the assumptions we made about the gestures we have implemented so far, the gesture engine, latching, or any timings!

> I really want to get the spellchecker logic out of the touchstream. 

> Can we go through all of the .md files and remove the parts where you infer that I'm an idiot. xD 
=== 

> Lets ask Kara if we can borrow her menu idea!

> Make a cool icon (FingerWorks Hand-like?) in mac White, since we wont need green/red modes.

> NEED TO FIGURE OUT HOW TO TYPE DURING LOCK SCREEN (like BetterTouchTool)

===

`AppleMagicTouchstream`:
0. I want to add configurable Gestures like in Gesturepad - lets implement everything we have so far!
===
1. For AppleMagicTouchstreamLP to make it the default layout loaded.. do I just need to save it as `GLASSTOKEY_DEFAULT_KEYMAP.json?`
2. Is "Trackpad Takeover" saved with the keymap settings? Should it be? 
3. Fix touchstream Layout (space) and test!
4. Copy touchstream Layout from AMT to GTK!
===

`GlassToKey`:
===
1. Remove all gestures/gesture logic
2. Start by adding Touchstream Gestures / Updates
3. Remove `3-finger drag`, `keyboard/mouse` options and logic from the program.
3. Start building up from there what I miss from GTK (Edges, Triangles, *circle keys)
4. DecalGirl left and right pads
7. After Gestures are in we can start ripping out `Typing Tuning` features 1 at a time.
===


`Gesturepad`:
===
- Build more Gestures!
===



=======
- Update GTK `Windows` Driver instructions they should be dead simple now.
- Do you see any inefficiencies of how the dynamic keys work right now? If we could start over from scratch would you make any changes? (Because I am thinking of a ground-up re-write.
> I want to rebuild or at least relook at how the keys and keymap are done.. If I knew I wanted every key to be movable (yet could still be associated with a column) would I have build it the same way? Can we PLEASE implement click&drag columns and/or keys?
- "Record Gesture" custom gestures in the future would be awesome!
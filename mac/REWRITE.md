===
## TELL CODEX:
> `?` Can you use gesturepad or AppleMagicTouchstream for your reverse engineering efforts? What would allow you to do that? The trackpads are a little smaller but I set up a scaled down keymap that matches ('TouchStream' layout)
> I want to see if you can confirm any of the assumptions we made about the gestures we have implemented so far, the gesture engine, latching, or any timings!

> I really want to get the spellchecker logic out of the touchstream. 

> Can we go through all of the .md files and remove the parts where you infer that I'm an idiot. xD 

===
`GesturePad`:
0. Lets make the dots the same as our hardcoded finger colors in the example
1. Instead of using checkboxes we need to make each Gesture able to select an Action (from a dropdown) 
> The code should reflect this. Gestures should not have hardcoded actions and should be configurable via the menu.


2. ?Lets make the "hand" examples use the FingerWorks TouchStream hand examples (with my colorse) ?

3. I think maybe instead, when the gesture menu is open it should expand to take the full view?
> Lets ask Kara if we can borrow her menu idea!
===



===
0. Copy GlassToKey to `GlassToKey_old` to preserve current release
1. Remove all gestures/gesture logic
2. Start by adding Touchstream Gestures / config and building up from there what I miss. 
3. "Record Gesture" custom gestures in the future would be awesome!
===

`GlassToKey`:
0. Fit layout to image
1. Update GTK Windows Driver instructions they should be dead simple now.
2. DecalGirl left and right pads


`AppleMagicTouchstream`: 
0. Copy touchstream Layout from AMT to GTK!

===

`GlassToKey`: 
0. Can we use the Velocity data to tell when we are typing vs mousing? It seems like a stronger signal than 3mm intent classifier. I would like maybe 3 options to switch between to test feel: 1. Current setup. 2. 3mm intent classifier 3. Velocity/Pressure/Timing based. (Let me know if we need to do a typing test to get data on this)
* We should still work on this independently of Trackpad Takeover (which should be an *Preferred* Option, but an option)
1. remove extra Typing Tuning flags from logic
2. Do you see any inefficiencies of how the dynamic keys work right now? If we could start over from scratch would you make any changes? (Because I am thinking of a ground-up re-write.
> I want to rebuild or at least relook at how the keys and keymap are done.. If I knew I wanted every key to be movable (yet could still be associated with a column) would I have build it the same way? Can we PLEASE implement click&drag columns and/or keys?
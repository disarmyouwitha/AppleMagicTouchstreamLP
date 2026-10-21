===
## TELL CODEX:
> `?` Can you use gesturepad or AppleMagicTouchstream for your reverse engineering efforts? What would allow you to do that? The trackpads are a little smaller but I set up a scaled down keymap that matches? ('TouchStream' layout)
> I want to see if you can confirm any of the assumptions we made about the gestures we have implemented so far, the gesture engine, latching, or any timings!

> I really want to get the spellchecker logic out of the touchstream. 

===



===

`GesturePad`:
0. right click (thumb,middle,ring)
1. double click (3 finger tap)
2. drag/select (3 finger drag)
3. In Gesturepad I think I want to start by removing the left/right trackpad contacts where it shows a list of each with the raw measurements.
> Check out sidebar.jpg can we implement a menu like this?

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
1. a. TOGGLE for gestures? b. remove extra Typing Tuning flags from logic
2. Do you see any inefficiencies of how the dynamic keys work right now? If we could start over from scratch would you make any changes? (Because I am thinking of a ground-up re-write.
> I want to rebuild or at least relook at how the keys and keymap are done.. If I knew I wanted every key to be movable (yet could still be associated with a column) would I have build it the same way? Can we PLEASE implement click&drag columns and/or keys?
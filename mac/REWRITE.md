===
## TELL CODEX:
> `?` Can you use gesturepad or AppleMagicTouchstream for your reverse engineering efforts? What would allow you to do that? The trackpads are a little smaller but I set up a scaled down keymap that matches? ('TouchStream' layout)

> what i want more than anything is to get the spellchecker logic out of the touchstream. 

===

What is the next step? Can you implement a "2-finger mouse" checkbox in Gesturepad for testing or is there something you wanted to explore before that?

With the FingerWorks TouchStream it like.. "latched" so you could start with 2 fingers mousing, lift 1 (but still mousing) and it would let you do that until you release all fingers. A lot of the gestures were like that.

===

`GlassToKey`:
0. Fit layout to image
1. Update GTK Windows Driver instructions they should be dead simple now.
2. DecalGirl left and right pads


`AppleMagicTouchstream`: 
0. Copy touchstream Layout from AMT to GTK!


`GesturePad`:
0. implement 2finger synthetic mouse, and force click = click

===

`GlassToKey`: 
0. Can we use the Velocity data to tell when we are typing vs mousing? It seems like a stronger signal than 3mm intent classifier. I would like maybe 3 options to switch between to test feel: 1. Current setup. 2. 3mm intent classifier 3. Velocity/Pressure/Timing based. (Let me know if we need to do a typing test to get data on this)
* We should still work on this independently of Trackpad Takeover (which should be an *Preferred* Option, but an option)
1. a. TOGGLE for gestures? b. remove extra Typing Tuning flags from logic
2. Do you see any inefficiencies of how the dynamic keys work right now? If we could start over from scratch would you make any changes? (Because I am thinking of a ground-up re-write.
> I want to rebuild or at least relook at how the keys and keymap are done.. If I knew I wanted every key to be movable (yet could still be associated with a column) would I have build it the same way? Can we PLEASE implement click&drag columns and/or keys?
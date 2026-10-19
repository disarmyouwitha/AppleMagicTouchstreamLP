===
## TELL CODEX:
> 

===

`AppleMagicTouchstream`: 
1. Can we place the Touchstream keypad image in the background along with the squared background. I want to create a touchstream keymap


`GlassToKey`:
0. Can we copy GesturePad Trackpad takeover, sync, release, refresh, menu items, into AppleMagicTouchstream?
1. Copy touchstream keymap from AMT to GTK 

? Can you use gesturepad or AppleMagicTouchstream for your reverse engineering efforts? What would allow you to do that? The trackpads are a little smaller but I could set up a scaled down keymap that matches 


`GesturePad`:  
1. can we "translate" 2finger movement to 1 finger.. like take the movement/velocity and make it just as smooth as OSX?
> Should we allow the user to change the mouse speed in our app, or try to pull speed settings from OSX?

===

0. Update GTK Windows Driver instructions they should be dead simple now. 

===

`GlassToKey`: 
0. Can we use the Velocity data to tell when we are typing vs mousing? It seems like a stronger signal than 3mm intent classifier. I would like maybe 3 options to switch between to test feel: 1. Current setup. 2. 3mm intent classifier 3. Velocity/Pressure/Timing based. (Let me know if we need to do a typing test to get data on this)
* We should still work on this independently of Trackpad Takeover (which should be an *Preferred* Option, but an option)
1. a. TOGGLE for gestures? b. remove extra Typing Tuning flags from logic
2. Move Blackhole logic into GTK
3. Do you see any inefficiencies of how the dynamic keys work right now? If we could start over from scratch would you make any changes? (Because I am thinking of a ground-up re-write.
> I want to rebuild or at least relook at how the keys and keymap are done.. If I knew I wanted every key to be movable (yet could still be associated with a column) would I have build it the same way? Can we PLEASE implement click&drag columns and/or keys
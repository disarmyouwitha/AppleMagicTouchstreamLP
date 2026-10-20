===
## TELL CODEX:
> `?` Can you use gesturepad or AppleMagicTouchstream for your reverse engineering efforts? What would allow you to do that? The trackpads are a little smaller but I could set up a scaled down keymap that matches?


3. Lets make the Touchstream layout ;3

===

`AppleMagicTouchstream`: 
0. Can we place the Touchstream keypad image in the background under the squared background? I want to create a touchstream keymap
1. I want to creaet a Layout based on @left_layout.jpeg @full_layout.gif
> I want to lock this project to the AppleMagicTouchstream layout


`GlassToKey`:
0. Copy touchstream Layout from AMT to GTK!
1. Update GTK Windows Driver instructions they should be dead simple now.


`GesturePad`:  
1. can we "translate" 2finger movement to 1 finger.. like take the movement/velocity and make it just as smooth as OSX?
> Should we allow the user to change the mouse speed in our app, or try to pull speed settings from OSX? 

===

`GlassToKey`: 
0. Can we use the Velocity data to tell when we are typing vs mousing? It seems like a stronger signal than 3mm intent classifier. I would like maybe 3 options to switch between to test feel: 1. Current setup. 2. 3mm intent classifier 3. Velocity/Pressure/Timing based. (Let me know if we need to do a typing test to get data on this)
* We should still work on this independently of Trackpad Takeover (which should be an *Preferred* Option, but an option)
1. a. TOGGLE for gestures? b. remove extra Typing Tuning flags from logic
2. Do you see any inefficiencies of how the dynamic keys work right now? If we could start over from scratch would you make any changes? (Because I am thinking of a ground-up re-write.
> I want to rebuild or at least relook at how the keys and keymap are done.. If I knew I wanted every key to be movable (yet could still be associated with a column) would I have build it the same way? Can we PLEASE implement click&drag columns and/or keys?
666. What did we use to capture all of the gestures except for 1finger mouse? That didn't require any permissions? (fallback)
777. Can we copy AppleMagicTrackpad's "Trackpad takeover" driver, buttons, sync, "trackpad release", refresh lock logic, and menu item with shortcut into GlassToKey? [PORTING.md](mac/gesturepad/DriverKitProbe/PORTING.md)
> The takeover code is saved in commit fc117e2 for late
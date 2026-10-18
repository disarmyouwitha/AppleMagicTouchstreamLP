## Rewrite

`GesturePad`:  
0. Move "Live Values" into a column to the left of the visualizer and right in a column to the right. (like the column to the right in AppleMagicTouchstream, but for each side!)
3. Lets remove the blackhole target, refresh device. Lets have Blackhole trackpad HID input affect both selected trackpads from the trackpad section. 
4. Lets move Blackhole info under trackpad left/right

`AppleMagicTouchstream`: 
0. Lets go through each feature and you make a case for why it's still there, or remove it: (keyboard/mouse, auto-resync, run at startup, hold repeat); (Typing Grace) 

`GlassToKey`:

===

`GesturePad`: 
0. NEXT TEST: Can I allow certain actions to pass through blackhole? Lets test Ignoring all mouse movement sent from device, but allow click and gestures. 

`AppleMagicTouchstream`: 
0. Lets move blackhole test into `AppleMagicTouchstream`. In the Touchstream you have to use 2-finger drag to move the mouse. We should blackhole all AMT movement data. If we detect 2-finger drag we should synthesize mouse data to move the mouse.
> We can experiment with mouse/synthetic mouse to get it right here, then transfer to GTK
> FUTURE: I will need to make a Touchstream keymap / then we can remove Column tuning as well. We will need to scale the touchstream logic for the smaller AMT

`GlassToKey`: 
0. Can we use the Velocity data to tell when we are typing vs mousing? It seems like a stronger signal than 3mm intent classifier. I would like maybe 3 options to switch between to test feel: 1. Current setup. 2. 3mm intent classifier 3. Velocity/Pressure/Timing based. (Let me know if we need to do a typing test to get data on this)
> a. TOGGLE for gestures? b. remove extra Typing Tuning flags from logic
1. Move Blackhole logic into GTK

===

0. Update GTK Windows Driver instructions they should be dead simple now. 

1. Do you see any inefficiencies of how the dynamic keys work right now? If we could start over from scratch would you make any changes? (Because I am thinking of a ground-up re-write.
> I want to rebuild or at least relook at how the keys and keymap are done.. If I knew I wanted every key to be movable (yet could still be associated with a column) would I have build it the same way? Can we PLEASE implement click&drag columns and/or keys
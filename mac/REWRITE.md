`GesturePad`:  
2. Can we figure out how to give mouse access back without disabling the driver extension?
> most important
0. Can I allow certain actions to pass through blackhole? 
> Can we allow forceClicks through?
1. can we "translate" 2finger movement to 1 finger.. like take the movement/velocity and make it just as smooth as OSX?
> Should we allow the user to change the mouse speed in our app, or try to pull speed settings from OSX?
===

 
0. 1. lets make "synthetic 2finger pointer" off by default. 2. lets add another checkbox "allow click" that also defaults off?

1. quick break: Velocity are we calculating this or getting it over the line now? there is velocity reconstructed and reconstructed native

2. sync button / release trackpads first. (*or make sync trigger it)

3. how many frames per second do we get from HID? Is it better/worse than OMS?

---

? Do we have to remove it on exit/install every start?

===

`AppleMagicTouchstream`: 


`GlassToKey`:

===

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
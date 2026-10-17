## Rewrite

0. Inspect Touch Data should label the fingers.. 1 is thumb, 2 is index, 3 is middle, 4 is ring 5 is pinky 6 is palm. Implement in each of the Mac projects.

1. mac_gesturepad: remove all GTK gestures, remove layout. I want to use this as a playground for implementing fingerworks gesture and chord logic.

2. mac_keyboard: we need haptic feedback back stat. Was the detection logic re-written for this strip-down? It ALREADY feels better, lmao. 
> I want to add back in tap-hold behavior so all of my old shortcuts still work.

> Please continue our `Remaining Work` from FINDINGS.md


a. I just dropped in a bunch of FingerWorks Touchstream SDK documentation.. do you think you can use any of it to improve how we differentiate between typing/mousing/gestures?

b. can we sink all 1 finger mouse movements of the Apple trackpad and only mouse when 2 fingers are dragged? This might be the magic bullet.. if we can have a "2 finger mouse mode" like the original.
> Emergency hatch: Can we SINK all mouse traffic and reimplement?

c. Do you see any inefficiencies of how the dynamic keys work right now? If we could start over from scratch would you make any changes? (Because I am thinking of a ground-up re-write.
> I want to rebuild or at least relook at how the keys and keymap are done.. If I knew I wanted every key to be movable (yet coule still be associated with a column) would I have build it the same way? Can we PLEASE implement click&drag columns and/or keys?
# Notes:
* 4-Finger latching is so bad I am always triggering drag instead. Please use mac/AppleMagicTouchstream as a reference. 
###
0. Test GUI.
1. I want you to review the mac vs windows implementation using Mac as the gold standard — tell me where we are passing, where we are failing and were we still need work (be specific) in our implementation.
2. I want you to take a hard look at how Mouse actions (Primary, Secondard, Middle click, Mouse Movement, Drag, Pan/Zoom) and particularly the Gesture implementation of 2-finger taps, movement, etc. are done on mac/AppleMagicTouchstream with a specific focus of getting the FEEL right of mousing and clicking.
###
* Occasionally get huge delays before 2-finger mouse movement? Is this some sort of OS queueing? Any way to make this more efficient?
0. Manually test all new gestures. I aleady noticed pinch happening on move.. need to see how it is mapped on touchstream
1. ?Can I disable all windows gesture options in `Touchpad` during "Mouse Takeover" and re-enable them after? 
2. Make sure when a gesture is set to None (Like a 2-finger tap) that the logic doesnt affect a 2finger Move (please verify)
===
* * * Test on mac: In the Mac version when I separate my fingers or lift fingers (after latching 2-finger move) it does some kind of math to balance the remaining fingers, are we doing that here?
> Finger rotate test on mac after move latch! *** I think this makes fine selection crap on windows
* * * Need to see if we are sent finger recognition on Windows/Linux, otherwise we need to pull it out of the firmware and implement it.

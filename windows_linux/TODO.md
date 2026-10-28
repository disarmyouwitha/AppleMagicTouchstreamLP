# Notes:
=======
0. Export doesn't seem to save all of my gestures and settings when I import. Gesture settings don't appear saved between restarting the app.
?. (Verify. seems good now? may have been misconfigure) My 3-finger tap is set to Secondary Click but lately it just does Double click? 
===
* * * Pinch and Spread animations are crazy wrong (OHH BECAUSE NO THUMB RECOGNITION!)
* * * Need to see if we are sent finger recognition on Windows/Linux, otherwise we need to pull it out of the firmware and implement it.
* * More Reverse is required to get a better Trackpad Takeover.. Mouse takeover is lame. =x
===

* * 4-Finger latching is so bad I am always triggering 3-finger drag instead. Please use mac/AppleMagicTouchstream as a reference.
###
1. I want you to review the mac vs windows implementation using Mac as the gold standard — tell me where we are passing, where we are failing and were we still need work (be specific) in our implementation.
2. I want you to take a hard look at how Mouse actions (Primary, Secondard, Middle click, Mouse Movement, Drag, Pan/Zoom) and particularly the Gesture implementation of 2-finger taps, movement, etc. are done on mac/AppleMagicTouchstream with a specific focus of getting the FEEL right of mousing and clicking.
###
* Occasionally get huge delays before 2-finger mouse movement? Is this some sort of OS queueing? Any way to make this more efficient?
0. Manually test all new gestures. I aleady noticed pinch happening on move.. need to see how it is mapped on touchstream
1. ?Can I disable all windows gesture options in `Touchpad` during "Mouse Takeover" and re-enable them after? 
2. Make sure when a gesture is set to None (Like a 2-finger tap) that the logic doesnt affect a 2finger Move (please verify)
===
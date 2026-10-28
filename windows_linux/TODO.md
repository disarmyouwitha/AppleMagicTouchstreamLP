# Notes:
=======
0. Tap recognition is pretty bad can we clean it up? Here is an atpcap @2F_taps_moving_mouse.atpcap
1. 4-corners gesture doesn't work?
2. 4-Finger latching is so bad I am always triggering 3-finger drag instead. Please use mac/AppleMagicTouchstream as a reference.
3. Can you take a look at the latest mac/applemagictouchstream changes? I think we want to add directional behaviour options (every x ms OR repeat with motion) were there other changes I didn't catch?
4. Pointer sensitivity sliders should  be more sensitive (allow more "clicks" in the middle between 0,1,2)
===
* * * Pinch and Spread animations are crazy wrong (OHH BECAUSE NO THUMB RECOGNITION!)
* * * Need to see if we are sent finger recognition on Windows/Linux, otherwise we need to pull it out of the firmware and implement it.
* * More Reverse is required to get a better Trackpad Takeover.. Mouse takeover is lame. =x
===
###
1. I want you to review the mac vs windows implementation using Mac as the gold standard — tell me where we are passing, where we are failing and were we still need work (be specific) in our implementation.
2. I want you to take a hard look at how Mouse actions (Primary, Secondard, Middle click, Mouse Movement, Drag, Pan/Zoom) and particularly the Gesture implementation of 2-finger taps, movement, etc. are done on mac/AppleMagicTouchstream with a specific focus of getting the FEEL right of mousing and clicking.
###
* Occasionally get huge delays before 2-finger mouse movement? Is this some sort of OS queueing? Any way to make this more efficient?
0. Manually test all new gestures. I aleady noticed pinch happening on move.. need to see how it is mapped on touchstream
1. ?Can I disable all windows gesture options in `Touchpad` during "Mouse Takeover" and re-enable them after? 
2. Make sure when a gesture is set to None (Like a 2-finger tap) that the logic doesnt affect a 2finger Move (please verify)
===
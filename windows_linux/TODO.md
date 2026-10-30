# Notes:
=======
1. Can we look at the Touchstream Layout updates? I think we switched to using an updated background for LHS and RHS and because of that we moved the location of some of the keys to match.
> mac/AppleMagicTouchstream/AppleMagicTouchstream/AppleMagicTouchstream/Resources
2. Can we add Steno support? I just added it to mac/AppleMagicTouchstream last night so you can copy our notes.
===
0. What is the thing that keeps making me switch back / turn off the program:
> * * * OMG IT'S scrolling in the LIMS that kills me, lol. (pages it is perfect; this particular one I use every day is unusable because we implement our own scrolling logic? Maybe I would have better luck rewriting the LIMS logic. x.x but what to do about websites with bad mouse? Can we try a toggle where we turn off my scroll acceleration to see if that helps? Thoughts??)
> Mouse is "slow to start" / laggy under computer use
> Drag-Select issues
1. 2F mouse move too eager to start before 4F latch <atpcap?>
2. Pointer sensitivity sliders should  be more sensitive (allow more "clicks" in the middle between 0,1,2)
3. The examples are like laughably bad.. Can we make them have natural finger placement and look/feel more like the Mac
===
0. Can you take a look at the latest mac/applemagictouchstream changes? I think we want to add directional behaviour options (every x ms OR repeat with motion) were there other changes I didn't catch?
 examples?
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
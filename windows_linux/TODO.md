# Notes:
=======
0. The drop-down menus in gesture/keyboard need fancy menu's like mac/AppleMagicTrackpad where it is separated by category and searchable.
> New drop-down is cool! But it says "ActionOption { Action = None, Title = None } When I feel like it is supposed to display the Action or the Title (?)

ALSO! It doesn't show the recognized gesture in the visualizer like we do for mac!
===
0. Make sure when a gesture is set to None (Like a 2-finger tap) that the logic doesnt affect a 2finger Move (please verify)
---
1. I am getting jittery little starts with 2F movement (It is especially noticeable if I move slowly to start— a tiny jump in the cursor!).. I think it might be waiting to see if it isn't another gesture? However, I don't have any other 2F gestures set! check out my ATPCAP 2F_skips.atpcap 
===
1. Test Shortcut builder
> The GUI is about the worst it could be. (screenshot) `Text` doesn't match "Key" or "app" format of label. No Hyper button.. Mac doesn't have one, right? I am also getting the error "choose key modifier or target" (and when it "fired" it only typed the first letter and stopped)
> Let's add in: I want to use the "Mirror Edit" style icon from mac and place it next to the "Gestures" header (?screenshot?)
2. Test Layout editor
> Cleanup GUI (Make the column bigger? I think mac is like 333px? lol need room for all the new buttons.. lets see if we can take an eye to minimizing clutter)
3. Fully test STENO modes. 
> 
===
* * * Keep monitoring Mouse for notes
0. Lets go through and try every Gesture. (Lets test behaviour, shortcuts, etc)
1. Pointer sensitivity sliders should  be more sensitive (allow more "clicks" in the middle between 0,1,2)
2. The examples are like laughably bad.. Can we make them have natural finger placement and look/feel more like the Mac
===
* * * Pinch and Spread animations are crazy wrong (Gesture Recognition: OHH BECAUSE NO THUMB RECOGNITION!)
* * * Need to see if we are sent finger recognition on Windows/Linux, otherwise we need to pull it out of the firmware and implement it.
* * * More Reverse is required to get a better Trackpad Takeover.. Mouse takeover is lame. =x
===
###
1. I want you to review the mac vs windows implementation using Mac as the gold standard — tell me where we are passing, where we are failing and were we still need work in our implementation. (be specific) 
###
0. Occasionally get huge delays before 2-finger mouse movement? Is this some sort of OS queueing? Any way to make this more efficient?
1. ?Can I disable all windows gesture options in `Touchpad` during "Mouse Takeover" and re-enable them after? 
===
# Notes:
* Occasionally get huge delays before 2-finger mouse movement? Is this some sort of OS queueing? Any way to make this more efficient?
0. GUI cleanup: Lets remove `Pointer response` and just lock in with the apple profile we have now! It feels really good~  Can scroll sensitivity be a slider? Can we make the text for natural scrolling a lighter color like the rest? Pointer sensitivity should also be a slider.
1. Actually, can you look at the latest mac build? I made a lot of really good improvements to the GUI and I added a bunch of gestures you should integrate!
- ?Can I disable all windows gesture options in `Touchpad` during "Mouse Takeover" and re-enable them after? 
===
* Make sure when a gesture is set to None (Like a 2-finger tap) that the logic doesnt affect a 2finger Move (please verify)
* * * Test on mac: In the Mac version when I separate my fingers or lift fingers (after latching 2-finger move) it does some kind of math to balance the remaining fingers, are we doing that here?
* * Finger rotate test on mac after move latch! *** I think this makes fine selection crap on windows
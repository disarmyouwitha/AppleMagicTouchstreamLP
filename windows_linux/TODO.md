# Notes:
1. I think I want to add a similar latch delay or whatever you did for 2 figners for 4 finger scroll as well.. we can delay 3-finger drag for a moment if we need to wait for 4th finger. (breifly) It is WAY too scary trying to scroll my network folders and accidentally dragging a folder somewhere it should not be. 3-finger tap should be unaffected. Need a drag vs scroll capture?
2. GUI cleanup: I think you should start with, in Windows, making a left column for the trackpads / trackpad selectors and a right column for the gestures and settings. (Like in Mac/AppleMagicTouchstream)
3. GUI cleanup: Lets remove `Pointer response` and just lock in with the apple profile we have now! It feels really good~  Can scroll sensitivity be a slider? Can we make the text for natural scrolling a lighter color like the rest? Pointer sensitivity should also be a slider. 
4. Actually, can you look at the latest mac build? I made a lot of really good improvements to the GUI and I added a bunch of gestures you should integrate!
===
* Make sure when a gesture is set to None (Like a 2-finger tap) that the logic doesnt affect a 2finger Move
* Test on mac: In the Mac version when I separate my fingers or lift fingers (after latching 2-finger move) it does some kind of math to balance the remaining fingers, are we doing that here?
===
- ?Can I disable all windows gesture options in `Touchpad` during "Mouse Takeover" and re-enable them after? 
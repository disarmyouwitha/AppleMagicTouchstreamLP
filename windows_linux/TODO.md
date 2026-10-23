# Notes:
0. When I tap (occasionally) it's a little jerky because it thinks that I am moving the mouse. In mac/AppleMagicTouchstream do we have any rules to prevent this? If not, would a Capture help you fix the problem? 
1. Can we remove the mouse/keyboard option under mode toggle and the underlying feature from the code? We can remove the status circles to and use the icon we used for mac/AppleMagicTouchstream (though lets invert the white hand for a black hand?)
2. GUI cleanup: I think you should start with, in Windows, making a left column for the trackpads / trackpad selectors and a right column for the gestures and settings. (Like in Mac/AppleMagicTouchstream)
3. GUI cleanup: Lets remove `Pointer response` and just lock in with the apple profile we have now! It feels really good~  Can scroll sensitivity be a slider? Can we make the text for natural scrolling a lighter color like the rest? Pointer sensitivity should also be a slider. 
4. Actually, can you look at the latest mac build? I made a lot of really good improvements to the GUI and I added a bunch of gestures you should integrate!
===
* Make sure when a gesture is set to None (Like a 2-finger tap) that the logic doesnt affect a 2finger Move
===
- ?Can I disable all windows gesture options in `Touchpad` during "Mouse Takeover" and re-enable them after? 
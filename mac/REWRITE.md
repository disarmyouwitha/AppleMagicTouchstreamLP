# NEXT:
=======
I'M LEARNING STENO BABY!!
0. I want to implement a "STENO" layout with something similar to an astrisk v2 
1. I want you to implement `GeminiPR protocol` when switched to this layout.
2. Take a look at my layout on my @voyager.jpg
> It looks like we could use the 6x3 layout for it if we add STENO keycodes?
===
* Shortcut editor button make a little bigger? (screenshot)
1. `Shortcut builder`: "Text" option (that pastes text) / can we encrypt saved texts so only the app can read it?
===
* * Start working on TouchStream gesture defaults template!!


`AppleMagicTouchstream`:
===
1. Implement actions: Missing Apple actions:
> Smart-zoom 
2. Implement actions: Missing TouchStream actions:
> Missing capability	    Command/output
> Middle click and drag	    Mouse3 click or held drag
> Secondary drag	        Mouse2 down → movement → release
> Caps Word	                Capitalize the next word, then automatically stop
> Sequential macros:        Ctrl+X, (then) V, then =
**LATER:** I can go through and make a touchstream default keymap!! (I will need to hand-set a bunch of default keyboard shortcuts!)
3. Implement actions: Swipe between pages, swipe between applications(Like fancy alt-tab /w gestures)
4. Please god can we finally fix Column tuning? (Drag to move??)
===
* `Landings Zones`:
- 4F hold above homerow, on homerow, below homerow
- 3F tap above homerow, on homerow, below homerow
* 1Finger `Drawings`:
- Sides up/down left/right sides; left/right top/bottom sides
- Triangles?
===
* Print `Cheat Sheet` (Generate .html page or whatever so user can print their gestures out like the Quickstart Guide, lol)
* Maybe add under "1 Finger" called `Drawing` > `Triangles`, `Sides` and we have some presets (Expand to offer `Custom` tomorrow)
- "Record Gesture" custom gestures in the future would be awesome!
* Gestures Finger changes during movement
===
- Do you see any inefficiencies of how the dynamic keys work right now? If we could start over from scratch would you make any changes? (Because I am thinking of a ground-up re-write.
===
777. We need to have "Click & Drag" to move Columns. (individual keys?)
===
0. Need to fix ai artwork sub legends lmao
1. Implement special "HAND" key for Touchstream layout.
2. We will need to synthesize the keys from the legends when the hand is held. Can you create the keys and logic and map these on the RHS? 
> Here is the list of unshifted and "hand" shifted pairs: (y,0),(u,4),(i,5),(h,left),(j,1),(k,2),(l,3),(n,_),(m,0)
> You can see the sublegends here: @RHS_TOUCHSTREAM.png
===
* Both hand gestures like 3f hold lhs right directional 3f on rhs
> "linked gestures" ?



===
# WINDOWS: 
0. Can you look at both mac/AppleMagicTouchstream and windows/GlassToKey.windows (and core) and plan an extensive re-write for ONLY `windows_linux` you will use `mac/AppleMagicTouchstream` as the GOLDEN REFERENCE. We are recreating the look, feel, and functionality of each one of it's features. 
=======
## TELL CODEX:
> `?` Can you use gesturepad or AppleMagicTouchstream for your reverse engineering efforts? What would allow you to do that? The trackpads are a little smaller but I set up a scaled down keymap that matches ('TouchStream' layout)
> I want to see if you can confirm any of the assumptions we made about the gestures we have implemented so far.
> I also have all of the templates for all of the gestures in the SDK.. do you think you could start implementing them in Gesturepad? Or should we start using AppleMagicTouchstream for implementation? I have the entire keyboard implemented there already. 

> I really want to get the spellchecker logic out of the touchstream. 
===
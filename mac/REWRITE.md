# NEXT:
=======
0. 
1. Can we adjust the STENO Single layer to align the LHS thumb keys with A more under R (like in their diagram) and U aligned more under R (the spacing between them seems fine!) @screenshot
> Maybe they can be a little fatter too?
===
* Shortcut editor button make a little bigger? (screenshot)
1. `Shortcut builder`: "Text" option (that pastes text) / can we encrypt saved texts so only the app can read it?
> test?? I thought we build this but I cant find it, lol. You asked me if we should use the Apple Keychain? Am I hallucinating?
===
* * Start working on TouchStream gesture defaults template!!
* * make 6x3 decal girl template in gimp with layers for ppl to edit
* Built-in small typing games for typing practice and steno practice (like lapdrill.py)
===
VERY often during 3F pinch, 4F pinc and 5F pinch the gesture will be recognized as 3F,4F,5F movement or directional actions.. For an example 5F pinch it’s like it sees the 4 fingers touch down, the thumb joins the gesture, but it only takes into account the 4 fingers going down, not the thumb going in an oposite direction. 

Basically, Pinch gestures are not being recognized properly 
===
* Should the keys be truely dynamic? Right now they are in a grid and we can set padding and x,y / rotation on a column (and rotation on a key) but each key's x,y can't be set individually.. This is.. mostly fine, that's how keyboards are laid out.. but does it have to be this way for efficiency? This is how keyboards are wired.. but I don't think it would be very hard to dynamically place and track hits on dynamic keys.. we are already doing it basically? We just don't give the user freedom?
> Maybe this can be part of a bigger re-write where we change the Column Tuning editor to allow for click/drag colunms and keys?
> > This way.. we could allow STENO or Touchstream layouts to adjust their keys too?... (especially Steno$$)


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
> add/remove columns so we dont need so many different layout options?
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
0. **Need to fix AI artwork sub legends lmao**
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
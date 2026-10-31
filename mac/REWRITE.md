# NEXT:
=======
0. Please god can we finally fix Column tuning? (Drag to move??)
* Should the keys be truely dynamic? Right now they are in a grid and we can set padding and x,y / rotation on a column (and rotation on a key) but each key's x,y can't be set individually.. This is.. mostly fine, that's how keyboards are laid out.. but does it have to be this way for efficiency? This is how keyboards are wired.. but I don't think it would be very hard to dynamically place and track hits on dynamic keys.. we are already doing it basically? We just don't give the user freedom?
* Do you see any inefficiencies of how the dynamic keys work right now? If we could start over from scratch would you make any changes?
* Maybe this can be part of a bigger re-write where we change the Column Tuning editor to allow for click/drag colunms and keys? Lets talk about it!
> Comments:
> add/remove columns so we dont need so many different layout options?
> > This way.. we could allow STENO or Touchstream layouts to adjust their keys too?... (especially Steno)
===
0. In STENO mode, when we are in Key Tuning we should ONLY show Steno keys 
1. We should allow Shortcuts to fire in Steno mode (outside of the Steno protocol)
2. Built-in small typing games for typing practice and steno practice (like lapdrill.py) Ability to plug into lapdrill or like.. does monkeytype have an API? lmao. random word type monkey type generator? probably easier to roll you own. 
===
# Human Tasks...?
0. Start working on TouchStream gesture defaults template!!
1. make 6x3 decal girl template in gimp with layers for ppl to edit
===


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
3. Implement actions: Swipe between pages, swipe between applications(Like fancy alt-tab /w gestures)
===
# `Landings Zones`:
- 4F hold above homerow, on homerow, below homerow
- 3F tap above homerow, on homerow, below homerow
# 1Finger `Custom/Drawings`:
- `Record Gesture` custom gestures in the future would be awesome!
- `Sides` up/down left/right sides; left/right top/bottom sides
- `Triangles`? (we can finally demonstrate how to do them, lol.)
===
777. We need to have "Click & Drag" to move Columns. (individual keys?)
===
0. **Need to fix AI artwork sub legends lmao**
1. Implement special "HAND" key for Touchstream layout.
2. We will need to synthesize the keys from the legends when the hand is held. Can you create the keys and logic and map these on the RHS? 
> Here is the list of unshifted and "hand" shifted pairs: (y,0),(u,4),(i,5),(h,left),(j,1),(k,2),(l,3),(n,_),(m,0)
> You can see the sublegends here: @RHS_TOUCHSTREAM.png
===
# Linked Gestures:
* Both hand gestures like 3f hold lhs right directional 3f on rhs


=======
## TELL CODEX:
> `?` Can you use AppleMagicTouchstream for your reverse engineering efforts? What would allow you to do that? The trackpads are a little smaller but I set up a scaled down keymap that matches ('TouchStream' layout)
> I want to see if you can confirm any of the assumptions we made about what we have implemented so far.
===
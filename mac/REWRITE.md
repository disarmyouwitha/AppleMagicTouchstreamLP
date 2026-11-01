# NEXT:
=======
* * Test on Macbook!
===
1. I like how the buttons look when squished as far as possible (screenshot) can you make them default this size?
2. What does Group/Ungroup do? I can't really tell from the GUI / user experience as I usually just drag/select or shift-select the keys I want? They don't stay permanently grouped and that seems fine?
3. ALSO there are no buttons for transforming group selection size at the same time?
> Alternatively: Can we Drag/select resize for the whole selected group when we resize 1 of the members?
===
- Visual toolbar seems dope! (above/below trackpads, like photoshopy?)
- When we select a group of keys, can we resize them all at once? (by dragging?)
- We should remove "Select Key" Dropdown from Layout Editor
- Once we get Layout Editor done really well we can take "Custom Buttons" out of Keymap Editor! 
===
0. In STENO mode, when we are in Key Tuning we should ONLY show Steno keys 
1. We should allow Shortcuts to fire in Steno mode (outside of the Steno protocol)
2. Built-in small typing games for typing practice and steno practice (like lapdrill.py) Ability to plug into lapdrill or like.. does monkeytype have an API? lmao. random word type monkey type generator? probably easier to roll you own. 
===
# Human Tasks...?
0. Start working on TouchStream gesture defaults template!!
> Can Codex look at the Fingerworks gesture XML and translate that into one of my keymap files so I can import it? (as best as possible, given the gestures and actions I have implemented - keeping in mind that shortcuts can be formed for many things.)
1. make 6x3 decal girl template in gimp with layers for ppl to edit
> Layers for: Center legends vs top-right legends / sublegend layer
> Outline of where to line up for Decal Girl template
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
# NEXT:
=======
* * Can I get a full release DMG built and signed?
* Test on Macbook!
- Can you reset my column widths to the app's default?
===
Okay, yes, I reviewed the templates and I want you to set the template spacing and label presets based on DEFAULT_KEYMAP.json 

ADDITIONALLY!!
0. When you click one of the layout buttons can it flash or highlight or *look* like I clicked it?
1. When you select a group it shows a "Selection size" but it should also show "Selection Spacing" I think with x,y to allow you to adjust spacing for the whole column numerically
2. When you are trying to edit the "Section size" it wont let you backspace to 0 because of the minimum validation.
3. When you enter "Layout Editor" in STENO mode, we should "turn off" Steno mode temporarily and allow normal gestures until you exit Layout mode
===
1. Lets actually remove the snap-grid selector and just default it to 1mm I like that. 
2. when we go into Layout Editor the keys are assigned totally wrong letters.. like.. duplicated from the wrong half? or RHS? (If the Templates are wrong they should use what is saved now in DEFAULT_KEYMAP.json 
3. 6x3 Template reset doesn't reset to the actual 6x3 default.. it's like the underlying Corne template?
> None of the templates seem to default exactly as they load from my keymap files.. they all have like a little vertical padding between the rows?
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
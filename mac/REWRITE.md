# NEXT:
=======
0. Hey in the Layout Editor sometimes it would be nice to be able to see where your fingers land on the keys. We should have a "show contacts" that will show touch contacts without dispatching any keys. (Please make sure the layout editor does not get laggy)
1. I need to fix my 6x3 layout to match my actual keys, lmao.
2. THEN fix Steno 6x3 to match my actual keys. 
3. Then re-export MY_KEYMAP.json and DEFAULT_KEYMAP.JSON
===
0. Sometimes I feel like Command gets stuck (or I have to press it on my physical keyboard to get AMT mouse events unstuck..) Or maybe it is Shift that is stuck? Not sure if this is AMT issue or me issue..
> Is shift not being released from 4F hold gesture (?) grasping at straws here.. I can't control when it happens.
^ Needs more testing
# I GOT A PCAP!! It was stuck when trying to 2F click apps in my docked menu (it would open the app in finder instead) I tried clicking shift on physical keyboard but it didnt fix I had to do command on physical keyboard and then 2F click started working correctly. (It is not currently stuck)
===
2. Implement actions: Missing TouchStream actions:
> Missing capability	    Command/output
> Middle click and drag	    Mouse3 click or held drag
> Secondary drag	        Mouse2 down → movement → release
> Caps Word	                Capitalize the next word, then automatically stop
> Sequential macros:        Ctrl+X, (then) V, then =
3. Implement actions: Swipe between pages, swipe between applications(Like fancy alt-tab /w gestures)
===
# Human Tasks...?
0. make 6x3 decal girl template in gimp with layers for ppl to edit
> Layers for: Center legends vs top-right legends / sublegend layer
> Outline of where to line up for Decal Girl template
===


`AppleMagicTouchstream`:
===
# 1Finger `Custom/Drawings`:
- `Record Gesture` custom gestures in the future would be awesome!
- `Sides` up/down left/right sides; left/right top/bottom sides
- `Triangles`? (we can finally demonstrate how to do them, lol.)
===
# `Landings Zones`:
- 4F hold above homerow, on homerow, below homerow
- 3F tap above homerow, on homerow, below homerow
===
777. SwiftKey like "learning" hitmap
===
1. **Need to fix AI artwork sub legends lmao**
2. Implement special "HAND" key for Touchstream layout.
3. We will need to synthesize the keys from the legends when the hand is held. Can you create the keys and logic and map these on the RHS? 
> Here is the list of unshifted and "hand" shifted pairs: (y,0),(u,4),(i,5),(h,left),(j,1),(k,2),(l,3),(n,_),(m,0)
> You can see the sublegends here: @RHS_TOUCHSTREAM.png
===
# Linked Gestures:
* Both hand gestures like 3f hold lhs right directional 3f on rhs
> Could make for a cool CMD+TAB?


=======
## TELL CODEX:
> `?` Can you use AppleMagicTouchstream for your reverse engineering efforts? What would allow you to do that? The trackpads are a little smaller but I set up a scaled down keymap that matches ('TouchStream' layout)
> I want to see if you can confirm any of the assumptions we made about what we have implemented so far.
===
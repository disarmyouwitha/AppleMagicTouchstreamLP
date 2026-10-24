# NOTES:
*** Can you please look at the TouchStream QuickReference guide and make a map of all of the different gestures, how many fingers they take, if they are taps, moves, (What triggers them) and any restrictions. I want to find a way to group them to make it easier to map the gestures.. 
** I'm thinking in the end we will need to do something like Kara and expand the Gesture menu to "take over" / replace the left frame where the visualizer is to give more room for assignments. In her gui there seems to be 3 types of assignment pages but I am not sure if that is nessisary or if we can come up with a better way to display the information? It's a big ask. References: kara_drag_tap_hold_lift, kara_up_down_left_right_tap_hold_left

In this PDF you can see the original touchstream GUI on the left to compare:
TouchStream_for_Mac_vs_Utility_1.60.pdf

* Merge/Cleanup Action menus (They are all different) and allow volu,briu on movements (up,down,left,right) after we get the GUI set up for that!
===
0. ^
1. Can we add a "mirror left/right" toggle or checkbox somewhere to handle "both" and we can handle the extra 2-pad recognition later
2. I gave you this task earlier "Okay I don't want to implement all of the gestures yet but I do want you to implement the GUI for our current gestures! I really like everything you have in our mockups~ 
“Both” means coordinated two-hand input, not the same gesture enabled
independently on both pads." and you said:
> "I’ll build the expanded gesture workspace around the gestures we already support, keeping recognition and defaults unchanged. The guide’s “Both” means coordinated two-hand input; I’ll distinguish that from editing the same settings on both pads.

For the hand selector, I recommend Left / Right / Both pads, where Both pads edits the existing independent per-pad settings. Coordinated two-hand gestures would stay out of this pass because they need new recognition. Is that what you want?"

I would like to implement this now!
===

`AppleMagicTouchstream`:
===
0. ! Drag frame between left/right column to adjust width!!
1. Let's revisit if Auto-resync has a place in our program? Lets fix it or remove it. (BT off/on & BT/USB?) Let's start here: How does auto resync work?
1. Feel out 4 finger latching? Might need a delay like in windows?
2. Implement actions: Smart-zoom, Rotate; "Natural Scrolling" option?
3. Implement actions: Swipe between pages, swipe between applications(Like fancy alt-tab /w gestures)
4. TouchStream 2-finger LHS gestures: Up, Down, Left, Right are like arrows? (please confirm) I want to add these as selectable actions for "movement" gestures.
- Need to consolidate / Unify Gesture Actions drop-downs after build-out!
===
* Maybe we can clean up gestures by "adding" ones that you use? idk..
===
0. We are going to need a much more extensive menu like Kara's to handle mapping all of these gestures. =x 
1. Transfer Treasure to GTK~
2. Copy touchstream Layout from AMT to GTK! (Maybe get rid of GTK?)
===

===
666. NEED TO FIGURE OUT HOW TO TYPE DURING LOCK SCREEN (like BetterTouchTool) I noticed I can type (something) letters? into the input box but I can't access my layer to type numbers, or enter. Backspace also adds a character instead of delete. 
777. We need to have "Click & Drag" to move Columns. (individual keys?)

===


`Gesturepad`:
===
- Build more Gestures!
===



`GlassToKey`: ditch GTK?
===
1. Remove all gestures/gesture logic
2. Start by adding Touchstream Gestures / Updates
3. Remove `3-finger drag`, `keyboard/mouse` options and logic from the program.
3. Start building up from there what I miss from GTK (Edges, Triangles, *circle keys)
4. DecalGirl left and right pads
7. After Gestures are in we can start ripping out `Typing Tuning` features 1 at a time.
===

===
## TELL CODEX:
> `?` Can you use gesturepad or AppleMagicTouchstream for your reverse engineering efforts? What would allow you to do that? The trackpads are a little smaller but I set up a scaled down keymap that matches ('TouchStream' layout)
> I want to see if you can confirm any of the assumptions we made about the gestures we have implemented so far.
> I also have all of the templates for all of the gestures in the SDK.. do you think you could start implementing them in Gesturepad? Or should we start using AppleMagicTouchstream for implementation? I have the entire keyboard implemented there already. 

> I really want to get the spellchecker logic out of the touchstream. 

> Can we go through all of the .md files and remove the parts where you infer that I'm an idiot. xD like in the trackpad dimensions where I gave the wrong measurements on the trackpad (or where we provide incorrect information, and then correct it with updated information - lets just keep the updated information in .MD files.)
=== 

=======
- Update GTK `Windows` Driver instructions they should be dead simple now.
- Do you see any inefficiencies of how the dynamic keys work right now? If we could start over from scratch would you make any changes? (Because I am thinking of a ground-up re-write.
> I want to rebuild or at least relook at how the keys and keymap are done.. If I knew I wanted every key to be movable (yet could still be associated with a column) would I have build it the same way? Can we PLEASE implement click&drag columns and/or keys?
- "Record Gesture" custom gestures in the future would be awesome!
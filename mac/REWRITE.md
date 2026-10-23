===
## TELL CODEX:
> `?` Can you use gesturepad or AppleMagicTouchstream for your reverse engineering efforts? What would allow you to do that? The trackpads are a little smaller but I set up a scaled down keymap that matches ('TouchStream' layout)
> I want to see if you can confirm any of the assumptions we made about the gestures we have implemented so far.
> I also have all of the templates for all of the gestures in the SDK.. do you think you could start implementing them in Gesturepad? Or should we start using AppleMagicTouchstream for implementation? I have the entire keyboard implemented there already. 

> I really want to get the spellchecker logic out of the touchstream. 

> Can we go through all of the .md files and remove the parts where you infer that I'm an idiot. xD like in the trackpad dimensions where I gave the wrong measurements on the trackpad (or where we provide incorrect information, and then correct it with updated information - lets just keep the updated information in .MD files.)
=== 


`AppleMagicTouchstream`:
0. If you can, can we make the gesture more general? I want it to be applicable to any number of fingers + thumb, so... Thumb + Index all the way to all 5 fingers.. as long as the fingers are pinching or spreading. (That way i could be an action and be mapped to any "pinch/spread" gestures.)
1. For the Gesture headers, on "Both" can we have the left hand to the left and the right hand to the right of "# fingers"?
2. Can we start with all of the gesture subheaders "minimized"
3. Can we move the "Pointer sensitivy" slider below "2-finger movement" and zoom sensitivity under Pinch / zoom? Please move 2-finger tap above 2-finger movement.
===
0. 2-Finger Pinch/zoom gesture?
0. Can you check the template files in the SKD, and the research we have left in FINDINGS.md and GESTURE_ENGINE.md from reverse engineering the fingerworks drivers and see if this is how it was implemented there? 
1. TouchStream 2-finger LHS gestures: Up, Down, Left, Right are like arrows? (please confirm) I want to add these as selectable actions for "movement" gestures.
2. Apple-like movement actions 2-finger left / right do "back" and "forward" in browser. (please verify)
2. Transfer Treasure to GTK~
4. Copy touchstream Layout from AMT to GTK!
===
666. NEED TO FIGURE OUT HOW TO TYPE DURING LOCK SCREEN (like BetterTouchTool) I noticed I can type (something) letters? into the input box but I can't access my layer to type numbers, or enter. Backspace also adds a character instead of delete. 
777. We need to have "Click & Drag" to move Columns. (individual keys?)

===

`GlassToKey`:
===
1. Remove all gestures/gesture logic
2. Start by adding Touchstream Gestures / Updates
3. Remove `3-finger drag`, `keyboard/mouse` options and logic from the program.
3. Start building up from there what I miss from GTK (Edges, Triangles, *circle keys)
4. DecalGirl left and right pads
7. After Gestures are in we can start ripping out `Typing Tuning` features 1 at a time.
===


`Gesturepad`:
===
- Build more Gestures!
===



=======
- Update GTK `Windows` Driver instructions they should be dead simple now.
- Do you see any inefficiencies of how the dynamic keys work right now? If we could start over from scratch would you make any changes? (Because I am thinking of a ground-up re-write.
> I want to rebuild or at least relook at how the keys and keymap are done.. If I knew I wanted every key to be movable (yet could still be associated with a column) would I have build it the same way? Can we PLEASE implement click&drag columns and/or keys?
- "Record Gesture" custom gestures in the future would be awesome!
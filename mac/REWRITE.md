===
## TELL CODEX:
> `?` Can you use gesturepad or AppleMagicTouchstream for your reverse engineering efforts? What would allow you to do that? The trackpads are a little smaller but I set up a scaled down keymap that matches ('TouchStream' layout)
> I want to see if you can confirm any of the assumptions we made about the gestures we have implemented so far.
> I also have all of the templates for all of the gestures in the SDK.. do you think you could start implementing them in Gesturepad? Or should we start using AppleMagicTouchstream for implementation? I have the entire keyboard implemented there already. 

> I really want to get the spellchecker logic out of the touchstream. 

> Can we go through all of the .md files and remove the parts where you infer that I'm an idiot. xD like in the trackpad dimensions where I gave the wrong measurements on the trackpad (or where we provide incorrect information, and then correct it with updated information - lets just keep the updated information in .MD files.)
=== 


`AppleMagicTouchstream`:
0. Order DecalGirl TouchStream skins!
1. Implement actions: Notification Center, Mission Control, App Expose, Launch Pad, Show Desktop - add to pinch/spread
2. Implement actions: Smart-zoom, Rotate, "Natural Scrolling".
3. Implement actions: Swipe between pages, swipe between applications(Like fancy alt-tab /w gestures)
- Need to consolidate / Unify Gesture Actions drop-downs after build-out!
===
0. We are going to need a much more extensive menu like Kara's to handle mapping all of these gestures. =x 
1. TouchStream 2-finger LHS gestures: Up, Down, Left, Right are like arrows? (please confirm) I want to add these as selectable actions for "movement" gestures.
2. Transfer Treasure to GTK~
3. Copy touchstream Layout from AMT to GTK! (Maybe get rid of GTK?)
===

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
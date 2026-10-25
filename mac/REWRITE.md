# NOTES:
0. Pinch,Spread, and ROTATE baby: Rotation gestures next!
=======
1. Maybe instead of the 1 LONG "Move Pointer" we have up,down,left,right and middle boxes.. @middle_movement_button Middle is a <Movement> selector button and if selected it grays out the other options (up,down,left,right) Vice-versa.. if an up,down,left,or right option is set movement is grayed out. *or highlighted red? hm, help me out!
> One implementation detail: we currently recognize continuous movement, but don’t yet have independent directional assignments or their repeat behavior. So the cross is a good GUI direction, and making those outer cards functional would be our next gesture-engine addition.
===
2. Occasionally I can't 2-finger tap click.. Like earlier I was doing a 3-finger drag and it got "skippy" or laggy and then I couldn't 2-finger tap after that, I had to use a mouse to click the button before I could 2F tap again. Do you think the Gesture isn't releasing? Is there a queue that is getting full / dropped? What do you think is happening? @2finger_tap_cursor_error (In this case I repeatedly observed this after "holding s" which fires my CMD+S shortcut)
===
3. I gave you this task earlier "Okay I don't want to implement all of the gestures yet but I do want you to implement the GUI for our current gestures! I really like everything you have in our mockups~ 
“Both” means coordinated two-hand input, not the same gesture enabled
independently on both pads." and you said:
> "I’ll build the expanded gesture workspace around the gestures we already support, keeping recognition and defaults unchanged. The guide’s “Both” means coordinated two-hand input; I’ll distinguish that from editing the same settings on both pads.

For the hand selector, I recommend Left / Right / Both pads, where Both pads edits the existing independent per-pad settings. Coordinated two-hand gestures would stay out of this pass because they need new recognition. Is that what you want?"

I would like to implement this now!
===
1. After we get the GUI set up: Merge/Cleanup Action menus (They are all different) and allow volu,briu on movements (up,down,left,right)
===
0. ??? NOt sure if really nessisary or if it will be problematic to allow hold/lift?
> If there is no <Move>,<pinch>, or <spread> action set, we should allow <hold> actions!
> Can we have the <hold> slot in the Session Lifetime setable~ (The other Move options should "lock out" hold like it is now!)

`AppleMagicTouchstream`:
===
1. Let's revisit if Auto-resync has a place in our program? Lets fix it or remove it. (BT off/on & BT/USB?) Let's start here: How does auto resync work?
1. Feel out 4 finger latching? Might need a delay like in windows?
4. TouchStream 2-finger LHS gestures: Up, Down, Left, Right are like arrows? (please confirm) I want to add these as selectable actions for "movement" gestures.
- Need to consolidate / Unify Gesture Actions drop-downs after build-out!
2. Implement actions: Smart-zoom, Rotate; "Natural Scrolling" option?
3. Implement actions: Swipe between pages, swipe between applications(Like fancy alt-tab /w gestures)
===
* Maybe we can clean up gestures by adding actions that I am missing (volu,briu)?
===
0. Please god can we finally fix Column tuning? (Drag to move??)
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
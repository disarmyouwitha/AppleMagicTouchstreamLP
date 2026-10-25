# NOTES:
=======
0. 1 Finger Hold should be disabled, "No seperate gesture is available for this."
1. I want to remove "4 Corners" taps, for "Both" and per-pad pages leave only Holds for now.
2. Can we clean up the GUI page headers a bit? I left notes in this image @GUI_CLEANUP
===
7. Can you make sure all of these Gesture rules aren't a bunch of bandaid patches? I want to make sure it has a really strong logic that is consistent all the way through. Please check out our @FINDINGS.md and FINGERWORKS_IMPLEMENTATION_PLAN.md if useful. 
---
0. I am removing GesturePad and GlassToKey only leaving AppleMagicTrackpad under Mac can you find all .md referencing them and scrub them from the record?
00. Can we go through all of the .md files and remove the parts where you infer that I'm an idiot. xD like in the trackpad dimensions where I gave the wrong measurements on the trackpad (or where we provide incorrect information, and then correct it with updated information - lets just keep the updated information in .MD files.)
0. My 2F Tap to click doesn't work when I am using the Screenshot app on my Mac, I can't click "Capture" unless it is with my real mouse? Everything else works at the time. IN FACT! I can even click other items on the same menu! I just can't click "Capture"??

===
2. Pinch,Spread, and ROTATE baby: Rotation gestures next!
3. It looks like we have most gestures in to cover all of the touchstream stuff.. Can you add each of the Actions you find on the TouchStream QuickStart guide?
4. After we get the GUI set up: Merge/Cleanup Action menus (They are all different)
===
* Print `Cheat Sheet` (Generate .html page or whatever so user can print their gestures out like the Quickstart Guide, lol)


`AppleMagicTouchstream`:
===
0. Let's revisit if Auto-resync has a place in our program? Lets fix it or remove it. (BT off/on & BT/USB?) Let's start here: How does auto resync work?
1. TouchStream 2-finger LHS gestures: Up, Down, Left, Right are like arrows? (please confirm) I want to add these as selectable actions for "movement" gestures.
- Need to consolidate / Unify Gesture Actions drop-downs after build-out!
2. Implement actions: Smart-zoom, Rotate; "Natural Scrolling" option?
3. Implement actions: Swipe between pages, swipe between applications(Like fancy alt-tab /w gestures)
4. Please god can we finally fix Column tuning? (Drag to move??)
===
`Zones` Gestures? 
- Sides up/down left/right sides; left/right top/bottom sides
- Triangles?
===

===
666. NEED TO FIGURE OUT HOW TO TYPE DURING LOCK SCREEN (like BetterTouchTool) I noticed I can type (something) letters? into the input box but I can't access my layer to type numbers, or enter. Backspace also adds a character instead of delete. 
777. We need to have "Click & Drag" to move Columns. (individual keys?)
===


===
## TELL CODEX:
> `?` Can you use gesturepad or AppleMagicTouchstream for your reverse engineering efforts? What would allow you to do that? The trackpads are a little smaller but I set up a scaled down keymap that matches ('TouchStream' layout)
> I want to see if you can confirm any of the assumptions we made about the gestures we have implemented so far.
> I also have all of the templates for all of the gestures in the SDK.. do you think you could start implementing them in Gesturepad? Or should we start using AppleMagicTouchstream for implementation? I have the entire keyboard implemented there already. 

> I really want to get the spellchecker logic out of the touchstream. 
=== 

=======
- Update GTK `Windows` Driver instructions they should be dead simple now.
- Do you see any inefficiencies of how the dynamic keys work right now? If we could start over from scratch would you make any changes? (Because I am thinking of a ground-up re-write.
- "Record Gesture" custom gestures in the future would be awesome!
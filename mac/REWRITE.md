# NEXT:
=======
00. We need the ability to edit the shortcut list / remove items.
===
> need to test hold release optons
> Need to test holding shift with gesture RHS while holding shift button LHS, releasing gesture and pressing key on RHS. (shared modifer)
===
1. We need to revisit typing. It feels bad, maybe it's picking up fast typing as 2 finger gestures?
> TYPING GRACE? How does TouchStream do it? REVERSE???
2. My 2F Tap to click doesn't work when I am using the Screenshot app on my Mac, I can't click "Capture" unless it is with my real mouse? Everything else works at the time. IN FACT! I can even click other items on the same menu! I just can't click "Capture"??
===
* `Diagonals`:
- Thumb + two fingers	↖ ↗ ↙ ↘	
> I am thinking we can re-use the "up,down,left,right" grid from "tap and move" here.. I am thinking:
[↖, tap, ↗]
[rotate left, blank?, rotate right]
[↙, hold, ↘]

`AppleMagicTouchstream`:
===
0. Let's revisit if Auto-resync has a place in our program? Lets fix it or remove it. (BT off/on & BT/USB?) Let's start here: How does auto resync work?
1. TouchStream 2-finger LHS gestures: Up, Down, Left, Right are like arrows? (please confirm) I want to add these as selectable actions for "movement" gestures.
2. Implement actions: Smart-zoom, Rotate; "Natural Scrolling" option?
3. Implement actions: Swipe between pages, swipe between applications(Like fancy alt-tab /w gestures)
4. Please god can we finally fix Column tuning? (Drag to move??)
===
* `Diagonals`:
- Thumb + two fingers	↖ ↗ ↙ ↘	
> I am thinking we can re-use the "up,down,left,right" grid from "tap and move" here.. I am thinking:
[↖, tap, ↗]
[rotate left, blank, rotate right]
[↙, hold, ↘]
* `Landings Zones`:
- 4F hold above homerow, on homerow, below homerow
- 3F tap above homerow, on homerow, below homerow
* 1Finger `Drawings`:
- Sides up/down left/right sides; left/right top/bottom sides
- Triangles?
===
* Print `Cheat Sheet` (Generate .html page or whatever so user can print their gestures out like the Quickstart Guide, lol)
* Maybe add under "1 Finger" called `Drawing` > `Triangles`, `Sides` and we have some presets (Expand to offer `Custom` tomorrow)
* Gestures Finger changes during movement
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
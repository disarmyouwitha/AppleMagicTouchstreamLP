# NEXT:
=======
0. After initiating Emoji shortcut in Gesture my tapping is messed up like modifiers are still held?
1. I can't get Voice to trigger unless the Config window is open (unacceptable)
> export new keymaps (default & MY)
===
0. For our Directional gestures there should be a behavior dropdown (repeat every ms, repeat with motion)
1. `Shortcut builder`: "Text" option (that pastes text) / can we encrypt saved texts so only the app can read it?
2. My 2F Tap to click doesn't work when I am using the Screenshot app on my Mac, I can't click "Capture" unless it is with my real mouse? Everything else works at the time. IN FACT! I can even click other items on the same menu! I just can't click "Capture"??
3. Click typing (typing when I am trying to 2-finger tap) Tricky to distinguish.. lets do our best and brainstorm! <atcap>
> (Setting Default keymap back to default was a good example)
===


`AppleMagicTouchstream`:
===
0. Let's revisit if Auto-resync has a place in our program? Lets fix it or remove it. (BT off/on & BT/USB?) Let's start here: How does auto resync work?
1. TouchStream 2-finger LHS gestures: Up, Down, Left, Right are like arrows? (please confirm) I want to add these as selectable actions for "movement" gestures.
2. Implement actions: Missing Apple actions:
> Smart-zoom 
2. Implement actions: Missing TouchStream actions:
> Missing capability	    Command/output
> Middle click and drag	    Mouse3 click or held drag
> Secondary drag	        Mouse2 down → movement → release
> Caps Word	                Capitalize the next word, then automatically stop
> Sequential macros:        Ctrl+X, (then) V, then =
**LATER:** I can go through and make a touchstream default keymap!! (I will need to hand-set a bunch of default keyboard shortcuts!)
3. Implement actions: Swipe between pages, swipe between applications(Like fancy alt-tab /w gestures)
4. Please god can we finally fix Column tuning? (Drag to move??)
===
* `Landings Zones`:
- 4F hold above homerow, on homerow, below homerow
- 3F tap above homerow, on homerow, below homerow
* 1Finger `Drawings`:
- Sides up/down left/right sides; left/right top/bottom sides
- Triangles?
===
* Print `Cheat Sheet` (Generate .html page or whatever so user can print their gestures out like the Quickstart Guide, lol)
* Maybe add under "1 Finger" called `Drawing` > `Triangles`, `Sides` and we have some presets (Expand to offer `Custom` tomorrow)
- "Record Gesture" custom gestures in the future would be awesome!
* Gestures Finger changes during movement
===
- Do you see any inefficiencies of how the dynamic keys work right now? If we could start over from scratch would you make any changes? (Because I am thinking of a ground-up re-write.
===
666. NEED TO FIGURE OUT HOW TO TYPE DURING LOCK SCREEN (like BetterTouchTool) I noticed I can type (something) letters? into the input box but I can't access my layer to type numbers, or enter. Backspace also adds a character instead of delete. 
777. We need to have "Click & Drag" to move Columns. (individual keys?)
===
* `rubberbanding mouse`: Why does it happen? When?



===
# WINDOWS: 
0. Can you look at both mac/AppleMagicTouchstream and windows/GlassToKey.windows (and core) and plan an extensive re-write for ONLY `windows_linux` you will use `mac/AppleMagicTouchstream` as the GOLDEN REFERENCE. We are recreating the look, feel, and functionality of each one of it's features. 
=======
## TELL CODEX:
> `?` Can you use gesturepad or AppleMagicTouchstream for your reverse engineering efforts? What would allow you to do that? The trackpads are a little smaller but I set up a scaled down keymap that matches ('TouchStream' layout)
> I want to see if you can confirm any of the assumptions we made about the gestures we have implemented so far.
> I also have all of the templates for all of the gestures in the SDK.. do you think you could start implementing them in Gesturepad? Or should we start using AppleMagicTouchstream for implementation? I have the entire keyboard implemented there already. 

> I really want to get the spellchecker logic out of the touchstream. 
===
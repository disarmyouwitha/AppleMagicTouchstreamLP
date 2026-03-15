## TODO
- Look at how it's implemented in Windows and implement the shortcut builder like that: If you click on any of the base buttons it toggles it: Ctrl, Shift, etc. and if you HOLD it will let you select which side from the dropdown.. Left Shift, Right Shift.. For Mac.. do we need a seperate AltGr or does Option fully replace it? Would it be nice as a compatibility option when people HOLD "Option" toggle?
---
- Mx Spacing, Choc Spacing 50/50 buttons (that also set the padding to the correct spacing)
---
- right click bugs bc 3 finger drag, lets fix!
---
- Can we add colored highlights like "Shortcut Buiilder" for each of the Gesture sub-collapsables? Can you make them each different colors?
- ^ Then I want to decide on a better theme for Shorcut Builder I hate that blue, lol. Its so un-mac looking..
- Add gestures (and collapsable sub-menu) to Gesture Tuning: Corners, Clicks, Force Clicks, Triangles
- Can we make Gesture Tuning section scrollable??
-------
- Sometimes Mixed mode ignores taps for typing? Frustrating when starting to type having to hit the key multiple times to start typing mode.
- I think it was because early on i had you build a 2 key buffer before typing in the intent machine and I want to remove it.
^ tip switch like on windows?
^ capture
---
- auto-reconnect not working correctly after sleep
- .atpcap should capture keymap! that would be super helpful!
---

## ICONIC:
- Need a logo for glasstokey!
- Start transition from Circles to Triangles

## Issues: (verify) [Still an issue?]
- Short drag sometimes fires click
- sometimes 2-finger scrolling types letters (Lifting fingers after drag)
- sometimes tap-click types letters (Lifting fingers after tap)

# Release Build:
cd ~/Documents/AppleMagicTouchstreamLP/mac
./release.sh
/usr/bin/ditto ~/Documents/AppleMagicTouchstreamLP/mac/release-output/1.0.0-1/GlassToKey-1.0.0.dmg /Users/nap/Downloads/

# Clear permissions for testing:
tccutil reset All ink.ranna.glasstokey
defaults delete ink.ranna.glasstokey
## TODO
- What is Key Padding and when did it get here? I already have that.. it's called.. Column spacing.. I guess you added this because windows Column spacing is implemented at the layout level, not the column level, but I dont want you to add Key Padding. Remove it. I think you can accomplish the same thing by applying the same Column Spacing to each Column. I think, in the end, I will make Windows Column Spacing per-column as well - but that is not your job. Your job is to fix
- Hm, we don't seem to be adding the extra horizontal spacing via Column X % and Column Y % like we do in windows?
- add "mx spacing" and "choc spacing" 50/50 buttons (that also set the padding to the correct spacing based on mx dimensions!) please analyze how this is implemented in the ../windows_linux version of glasstokey and create a plan for porting this to mac!
---
- Can we add colored highlights like "Shortcut Buiilder" for each of the Gesture sub-collapsables? Can you make them each different colors?
- ^ Then I want to decide on a better theme for Shorcut Builder I hate that blue, lol. Its so un-mac looking..
- Add gestures (and collapsable sub-menu) to Gesture Tuning: Corners, Clicks, Force Clicks, Triangles
- Can we make Gesture Tuning section scrollable??
-------
- right click bugs bc 3 finger drag, lets fix!

## Great test for windows/linux:
Test on 6x3, 6x4, 5x3, and 5x4, then compare resulting column scales and offsets against Windows/Linux for
     the same preset and padding. Finish with xcodebuild and a manual UI check that both buttons set both scale
     and spacing, not just size.
    
## TODO:
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
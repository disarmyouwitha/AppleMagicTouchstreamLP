## TODO
- Can we have a toggle that opens up mac settings to 3-finger drag in mac settings?
---
- 3-Finger Hold assigned to Right-Click bugs out because of Mac's 3-finger drag.. Can I make them coexist? I am able to do it in ../windows_linux because we implemented our own 3-finger drag.. but I would like to avoid that if possible because mac already does it at the OS level!
- It has to do with the gesture canceling. It triggers properly but the menu gets immediately cancelled. I know this is due to 3-finger drag and nothing we are doing because disabling this at the OS level fixes the problem with gestures. I went ahead and reverted the changes you made back to main. Please take a look at the code and see if there is anything we can do, given what you know now.
-------
- Can we add colored highlights like "Shortcut Buiilder" for each of the Gesture sub-collapsables? Can you make them each different colors?
- ^ Then I want to decide on a better theme for Shorcut Builder I hate that blue, lol. Its so un-mac looking..
- Add gestures (and collapsable sub-menu) to Gesture Tuning: Corners, Clicks, Force Clicks, Triangles
- Can we make Gesture Tuning section scrollable??
- ms cadence for gestures
---


    
## TODO:
- FULLY adopt and ingest OMS framework with much tighter coupling into Mac glass the key
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
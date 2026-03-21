## TODO
- hold repeat
- right click bugs bc 3 finger drag, lets fix!
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
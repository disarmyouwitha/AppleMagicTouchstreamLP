## Current:
- Add "Screenshot" shortcut to the dropdown that calls the official shortcut on each os: windows:win+shift+s, mac:cmd+shift+4, Linux equivalent?

    
## TODO:
- `Typing feels` bad bro.. did we re-introduce that 2-key buffer before typing?
- FULLY adopt and `ingest OMS framework` with much `tighter coupling` into Mac glass the key; Change ./release to simplify notorizing and signing since we wont have nested frameworks!
-------
- Can we fix 'xcode' builds dispatching keys? this testing process suuuucks
---
- "Memory saver" doesn't keep Typing Toggle state from before restart???
- auto-reconnect not working correctly after sleep (REMOVE IT?)
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
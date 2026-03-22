## Current:
- GUI edits are fire but the  VOL_UP, VOL_DOWN, BRIGHT_UP, and BRIGHT_DOWN keys still do not repeat. They must be special keys that need to be treated differently. I am able to do this by repeatedly pressing the key so you
  can probably do something like that!
- Move the following `Taps` into `Clicks` below "Bottom Right": "2-Finger Tap", "3-Finger Tap" and get rid of the Taps collapsable in Gestures. 
- - Add a gestureSubsectionHeader into `Clicks` between `Bottom Right` and `3-Finger Tap`
- Shortcut Builder: Add to Dropdown (import/export compatible with windows/linux)
- Force Clicks needs a slider where you set what force is Force.
- Force Instead of Hold
------
- Can we add colored highlights like "Shortcut Buiilder" for each of the Gesture sub-collapsables? Can you make them each different colors?
- ^ Then I want to decide on a better theme for Shorcut Builder I hate that blue, lol. Its so un-mac looking..

    
## TODO:
- Typing feels bad bro.. did we re-introduce that 2-key buffer before typing?
- FULLY adopt and `ingest OMS framework` with much `tighter coupling` into Mac glass the key; Change ./release to simplify notorizing and signing since we wont have nested frameworks!
-------
- "Memory saver" doesn't keep Typing Toggle state from before restart???
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
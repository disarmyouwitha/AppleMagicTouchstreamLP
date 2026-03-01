## TODO
- need a logo for glasstokey! Wintermute logo?
- sometimes Mixed mode ignores taps for typing? frustrating when starting to type having to hit the key multiple times to start typing mode.
- I think it was because early on i had you build a 2 key buffer before typing in the intent machine and I want to remove it.
^ tip switch like on windows?
^ capture
---
- Add gestures (and collapsable sub-menu) to Gesture Tuning: Corners, Clicks, Force Clicks, Triangles
- Can we make Gesture Tuning section scrollable??
---
- Mac Replay does not update contact pills, status pills

### FUTURE
- auto-reconnect not working correctly after sleep
---

## Issues: (verify)
- Short drag sometimes fires click
- sometimes 2-finger scrolling types letters (Lifting fingers after drag)
- sometimes tap-click types letters (Lifting fingers after tap)

# Release Build:
cd ~/Documents/AppleMagicTouchstreamLP/mac
./release
/usr/bin/ditto ~/Documents/AppleMagicTouchstreamLP/mac/release-output/1.0.0-1/GlassToKey-1.0.0.dmg /Users/nap/Downloads/
# tccutil reset All ink.ranna.glasstokey
# defaults delete ink.ranna.glasstokey
## TODO
- Can we add colored highlights like "Shortcut Buiilder" for each of the Gesture sub-collapsables? Can you make them each different colors?
- ^ Then I want to decide on a better theme for Shorcut Builder I hate that blue, lol. Its so un-mac looking..
- Add gestures (and collapsable sub-menu) to Gesture Tuning: Corners, Clicks, Force Clicks, Triangles
- Can we make Gesture Tuning section scrollable??
- ms cadence for gestures
-------
- Shift on same hand is broken.. 2-finger hold/2-finger tap related??
- right click bugs bc 3 finger drag, lets fix!


_
• There’s a more fundamental mismatch surfacing now than the per-touch rules: the live mac path is callback → AsyncStream(bufferingNewest: 2) → another AsyncStream(bufferingNewest: 2) → actor ingest. That is materially
  different from the Windows core’s direct frame processing, and it can silently drop frames under load, which would feel exactly like “I tapped repeatedly and only some letters ever existed.”
_
    
## TODO:
- Sometimes Mixed mode ignores taps for typing? Frustrating when starting to type having to hit the key multiple times to start typing mode.
- I think it was because early on i had you build a 20ms key buffer before typing in the intent machine and I want to remove it.
- in keyboard mode it is also really bad, so maybe it doesn’t have to do with Mixed mode, or the 20ms key buffer? Maybe it's hit detection after the anchor/keymap change? it feels TERRIBLE


^ tip switch like on windows?
^ capture
---
- hold repeat
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
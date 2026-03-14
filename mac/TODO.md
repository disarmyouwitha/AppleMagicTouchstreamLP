## TODO
- Can we make Space a continuous key like Backspace?
- International keys like AltGR on mac?
- I thought we didn't ask for "Input Monitoring" permissions unless the user toggled: "Keyboard/Mouse mode" (because that is where event tap is)
---
- Sometimes Mixed mode ignores taps for typing? Frustrating when starting to type having to hit the key multiple times to start typing mode.
- I think it was because early on i had you build a 2 key buffer before typing in the intent machine and I want to remove it.
^ tip switch like on windows?
^ capture
---
- Add gestures (and collapsable sub-menu) to Gesture Tuning: Corners, Clicks, Force Clicks, Triangles
- Can we make Gesture Tuning section scrollable??
---
- .atpcap should capture keymap! that would be super helpful!
- auto-reconnect not working correctly after sleep
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
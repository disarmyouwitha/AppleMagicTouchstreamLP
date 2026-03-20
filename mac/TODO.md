## TODO
- Can we make app packaging / signing simpler now that we don't have the framework as external?

- I see we added a bunch of code to "Framework/OpenMultitouchSupportXCF/OpenMTManagerV2.m" I thought we were moving it into our app? Or does that not make sense? If we are leaving it out I want to remove all of the old stuff and just trim it to our tightly coupled code and anything left to be implemented~

- Can we make a cruft pass and get rid of this BS? I don't want to keep anything around just for compatibilities sake - only if it belongs to the new code { • I’m patching the bridge now: adding a direct raw-frame callback API in OpenMTManagerV2, keeping the old listener API intact for compatibility, and changing callback lifecycle decisions to use “any raw consumers” rather
  than only OpenMTListener. After that I’ll switch InputRuntimeService to this app-specific path. }

- Does Chordal SHift gesture (4-finger hold) only trigger chordal shift when the toggle is enabled? I would like to remove the toggle entirely and ONLY trigger chordal shift if the gesture is set.
- 4-finger hold is hella messed up

- Any way to make config transsparent background?

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
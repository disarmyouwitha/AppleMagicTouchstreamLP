## TODO:
-  Remaining work if you want the absolute tightest path:

  - Replace the callback-to-engine handoff with a real SPSC ring buffer so the OMS callback only writes into a preallocated slot and the engine queue drains synchronously.
  - Remove the remaining OMSRawTouch materialization inside mac/Sources/OpenMultitouchSupport/OMSManager.swift:241 so the bridge stores POD contacts in ring-buffer memory instead of building a Swift array in the callback.
  - Collapse the remaining OpenMultitouchSupport package layer into the app target and move rawTouchStream into a tool-only adapter if you want maximum coupling.
- `Typing feels` bad bro.. did we re-introduce that 2-key buffer before typing?
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
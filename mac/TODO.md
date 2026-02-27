## TODO
- sometimes Mixed mode ignores taps for typing? frustrating when starting to type having to hit the key multiple times to start typing mode.
- 3-finger click for right-click immediately closes!
---
- Add gestures (and collapsable sub-menu) to Gesture Tuning: Corners, Clicks, Force Clicks, Triangles
- Can we make Gesture Tuning section scrollable??
-------
- User idea#48: Super cool project, I would love to be able to rotate a key a few degrees when adjusting its position

### FUTURE
- auto-reconnect not working correctly after sleep
---

## Issues: (verify)
- Short drag sometimes fires click
- sometimes 2-finger scrolling types letters (Lifting fingers after drag)
- sometimes tap-click types letters (Lifting fingers after tap)

# Release Build:

# xcodebuild -project mac/GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/GlassToKeyReleaseBuild build

# /usr/bin/ditto /tmp/GlassToKeyReleaseBuild/Build/Products/Release/GlassToKey.app /Users/nap/Downloads/GlassToKey.app && ls -ld /Users/nap/Downloads/GlassToKey.app
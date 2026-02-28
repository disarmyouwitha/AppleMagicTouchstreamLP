## TODO
- sometimes Mixed mode ignores taps for typing? frustrating when starting to type having to hit the key multiple times to start typing mode.
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

# xcodebuild -project mac/GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/GlassToKeyReleaseBuild build

# /usr/bin/ditto /tmp/GlassToKeyReleaseBuild/Build/Products/Release/GlassToKey.app /Users/nap/Downloads/GlassToKey.app && ls -ld /Users/nap/Downloads/GlassToKey.app
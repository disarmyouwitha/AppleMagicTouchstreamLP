## TODO
- 
- Add Rotatable Keys to Column Tuning
- Add Rotatable keys to Keymap Tuning
- 3-finger click for right-click immediately closes!
- Can we make gestures section collapsable by default
- can we make the right side "* Tuning" sections scrollable
- sometimes Mixed mode ignores taps for typing? frustrating when starting to type having to hit the key multiple times to start typing mode.
---
???
› why couldn't you build the framework? {  I ran an Xcode build, but it is currently blocked by an existing
  project dependency issue
    unrelated to this patch: the app target cannot resolve OpenMultitouchSupport during build. No compile
  error
    from the new mouse-hold code surfaced before that failure.
   }
---
- Add gestures (and collapsable sub-menu) to Gesture Tuning: Corners, Clicks, Force Clicks, Triangles
- Can we make Gesture Tuning section scrollable??
-------
- User Issue#48: "Super cool project, I would love to be able to rotate a key a few degrees when adjusting its position"


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
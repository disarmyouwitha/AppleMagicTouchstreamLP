## TODO
- Add gestures (and collapsable sub-menu) to Gesture Tuning: Corners, Clicks, Force Clicks, Triangles
- Can we make Gesture Tuning section scrollable??
---
- I need you to check out how we did Autocorrect with Symspell in "../windows/glasstokey" and implement it in the same way here. If we can reuse the AX stuff for a cleaner replace than backspace replace we can use that, but I want to rip the word ressurection engine out and start using Symspell for the correction engine.
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

# xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/GlassToKeyReleaseBuild build

# /usr/bin/ditto /tmp/GlassToKeyReleaseBuild/Build/Products/Release/GlassToKey.app /Users/nap/Downloads/GlassToKey.app && ls -ld /Users/nap/Downloads/GlassToKey.app
## TODO
- Add gestures (and collapsable sub-menu) to Gesture Tuning: Corners, Clicks, Force Clicks, Triangles
- What other dropdown actions can we add to hit parity /w ../windows/glasstokey??
-------

### FUTURE
- Can we make Gesture Tuning section scrollable??
- * Can MAKE NOTE ONLY of any migration/legacy code we are not using or that was used to transition to our current architecture? We are about to have our first release, so there are no users with "legacy" settings and we don't need to support anything legacy except the Opensource drivers. 

- Fix Planck layout
- Fix 6x4 keymap.
---
- auto-reconnect not working?
- Short drag sometimes fires click
- Replay Addition: Add replay hotkeys (Space play/pause, arrow keys frame step).
---

## Issues: (verify)
- sometimes 2-finger scrolling types letters (Lifting fingers after drag)
- sometimes tap-click types letters (Lifting fingers after tap)

# Release Build:

# xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/GlassToKeyReleaseBuild build

# /usr/bin/ditto /tmp/GlassToKeyReleaseBuild/Build/Products/Release/GlassToKey.app /Users/nap/Downloads/GlassToKey.app && ls -ld /Users/nap/Downloads/GlassToKey.app
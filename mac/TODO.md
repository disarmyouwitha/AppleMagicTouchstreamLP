## TODO
- When setting Hold action sometimes it copies the entire key from the other side (LHS copies RHS for same column and key) I do not understand how this is happening, instead of just updating the key from the dropdown?
---
- Add gestures (and collapsable sub-menu) to Gesture Tuning: Corners, Clicks, Force Clicks, Triangles
- What other actions can we add to hit parity??
-------

### FUTURE
- Can we make Gesture Tuning section scrollable??
- * Can MAKE NOTE ONLY of any migration/legacy code we are not using or that was used to transition to our current architecture? We are about to have our first release, so there are no users with "legacy" settings and we don't need to support anything legacy
- export /import keymaps, **load GLASSTOKEY_DEFAULT_KEYMAP.json (package with app) if no keymap is saved.
- autocorrect bugging (lets go symspell)
- * far future - keymap import/export on windows/osx interop?
- Fix Planck layout
- auto-reconnect not working?
- Short drag sometimes fires click
- Replay Addition: Add replay hotkeys (Space play/pause, arrow keys frame step).
---

## Issues: (verify)
- sometimes 2-finger scrolling types letters (Lifting fingers after drag)
- sometimes tap-click types letters (Lifting fingers after tap)


# xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/GlassToKeyReleaseBuild build

# /usr/bin/ditto /tmp/GlassToKeyReleaseBuild/Build/Products/Release/GlassToKey.app /Users/nap/Downloads/GlassToKey.app && ls -ld /Users/nap/Downloads/GlassToKey.app
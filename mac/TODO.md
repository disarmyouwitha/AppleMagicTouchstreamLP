## TODO
A few things about the gestures:
[0]: sometimes using Typing Toggle on 5F Swipe it will change twice during 1 swipe! As long as you are going in the same direction it should be considered the same gesture so it doesn't fire twice!
[1]: 2F, 3F, and 4F Holds all dispatch keys on release, when they should not. If 2+ finger have been on the same trackpad for longer than Hold (m) we are doing a Hold Gesture and we should only dispatch the gesture's action, not any keys the gesture landed on. Please look at how Hold Getures are implemented in "../windows/glasstokey" if you need to!
[2]: Corners, dictate enough be an action and set to Outer corners.. right now it fires independently of the action set. 
[3]: 2 finger hold shouldn't fire on corner gestures. (again look at "../windows/glasstokey" if you need to!)
---
- left, middle right click actions!
- export /import keymaps, load global.json default
- capture / replay .atpcap
- autocorrect bugging.
- auto-reconnect not working
- more realtime haptics? it still feels bad.
- Short drag sometimes fires click (Lifting fingers dispatches keys)
###
- normalize % to px??
- Have Codex refactor the GUI for effiency
- Have Codex redesign the GUI for looks, keeping efficiency
###
- "Auto" set column x,y based on finger splay "4 finger touch" snapsMetro.


# Karabiner stuck, help!
sudo launchctl kickstart -k system/org.pqrs.vhid 
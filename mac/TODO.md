## TODO
[0] Can we move “Layout” dropdown out of the “Column Tuning” section and put it right above it? [1] Instead of having Scale, X, Y, Pad (Column Tuning fields) hidden/visible depending on if a column is clicked - Can we have them always visible, but make Column Tyning collapsable?
[2] Can we have "Primary Action" and "Hold Action" always visible in Keymap Tuning, but make Keymap Tuning collapsable?
---
- PRETTIFY ACTION DROP DOWN
- Grayed out action/hold action if nothing is selected.
- grayed out x,y custom button fields if one isnt selected.
---
- Please explain to me how haptics works in the framework. Is this portable to windows in any way? Do you think it would be possible to implement in windows by reverse engineering?
---
### Gesture config:
- Create dropdown for each of my gestures and implement them as actions that can be selected from a drop down. (You can reference ../windows/glasstokey if you need!)
- Left / Right / Double Click actions in Action Dropdown
-------
- export /import keymaps, **load global.json default
- autocorrect bugging (lets go symspell)
- auto-reconnect not working?
- Short drag sometimes fires click
- not sure it should be able to go into gesture mode during typing intent/typing grace
- sometimes click types letters (Lifting fingers after tap)
###
# HUGE:
- normalize %!??
- normalize keymap for 6x3 5x3 where it looks the same minus outer column.
###
- "Autosplay" set column x,y based on finger splay "4 finger touch" snapsMetro.
- e v e n s p a c e
###
Gestures Config
###
- Replay genius: If you want, I can also add replay hotkeys (Space play/pause, arrow keys frame step).
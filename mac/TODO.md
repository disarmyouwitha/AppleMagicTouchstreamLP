## TODO
- Hey I've been thinking about "mac/Tools/ReplayHarness/verify_replay_baselines.sh" and I think I want you to remove it / remove it from our swift package. We can delete any files from the folder that do not match the scheme.
- Please explain to me how haptics works in the framework. Is this portable to windows in any way?
- fix edit keymap lag
- fix start typing lag 
- REWRITE FRAMEWORK up: Framework handles all frame logic, not handled in app. Deterministic capture and replay
---
- export /import keymaps, load global.json default
- capture / replay .atpcap
- autocorrect bugging.
- auto-reconnect not working
- more realtime haptics? it still feels bad.
- Short drag sometimes fires click
- not sure it should be able to go into gesture mode during typing intent/typing grace
- sometimes click types letters (Lifting fingers after tap)
###
- normalize % to px??
- Have Codex refactor the GUI for effiency
- Have Codex redesign the GUI for looks, keeping efficiency
###
- "Auto" set column x,y based on finger splay "4 finger touch" snapsMetro.


# Karabiner stuck, help!
sudo launchctl kickstart -k system/org.pqrs.vhid 
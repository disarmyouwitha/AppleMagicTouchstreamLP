# TODO:
- Import button crashes program.
- Test Keymap Edit / set Hold.
- Typing Tuning columns.
-------
1. Can `glasstokey` call `glasstokey-gui` (i.e. open in the tray)
2. If `glasstokey` tray is already running, if you run `glasstokey show-config` it shouldn't open a new instance but instead should open the config window. (If the tray is not running, IT CAN start it's own instance.)
3. If `glasstokey` tray is already running, `glasstokey start` should say something like "Glasstokey is already running in the tray.
4. If `glasstokey` tray is running, `glasstokey stop` should also try to stop the tray, instead of just saying "The background runtime is not running.
5. If glasstokey is running headless via `glasstokey start` and someone uses `glasstokey show-config` can we have it open the config in a way that DOESN'T start the runtime? (like a secret flag or something or a different entry point?) I want to be able to let headless users open the config without starting the tray program or runtime (without affecting normal default tray behaviour)
--------
# CHANGE TO: 
GlassToKey Linux install complete.

Recommended next steps:
  1. Reconnect the trackpads or wait a few seconds for refreshed udev permissions.
  2. Add the desktop user to the 'glasstokey' group:
     sudo usermod -aG glasstokey $USER
  3. Log out and back in so the new group membership applies.
  4. Run `glasstokey doctor`

  # Usage:
  glasstokey            # start tray host in background
  glasstokey start      # start in headless mode
  glasstokey stop       # to stop the background runtime

  # Other commands:
  glasstokey list-devices
  glasstokey bind-left  <stable-id-left>
  glasstokey bind-right <stable-id-right>
  glasstokey show-config --print


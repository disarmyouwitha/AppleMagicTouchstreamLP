# TODO:
- Column Tuning
- More gestures.
- 5-finger Up "D" is triggering Choral shift on it's own side? 
-------

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


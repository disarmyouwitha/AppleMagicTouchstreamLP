# TODO:

[0] So I noticed that glasstokey-gui does not run in the background. When you launch the "GUI" with this command you are really launching the Tray process that should RUN ENTIRELY IN THE BACKGROUND. Not like "nohup glasstokey-gui &" Like legitimately at startup it should run in the background. if this is a service in linux, I dont know the terminology but this needs to be resolved.

[1] If I close the program from command-line it gets stuck in the tray until I kill the process.

[2] Import button crashes program.

- Test Keymap Edit / set Hold.
- Typing Tuning columns.


# Change

GlassToKey Linux install complete.

Recommended next steps:
# NESSISARY doesnt the install script take care of this?
  1. Reconnect the trackpads or wait a few seconds for refreshed udev permissions.
  2. Add the desktop user to the 'glasstokey' group:
     sudo usermod -aG glasstokey $USER
  3. Log out and back in so the new group membership applies.
# PURPOSE?
  4. Run 'glasstokey doctor'
  6. Run 'glasstokey show-config --print' and verify left/right device bindings

# can this just set up init-config on install? why make them do it after?
  5. Run 'glasstokey init-config' if this is the first install

  7. Run 'glasstokey start' to launch the background runtime
  8. Run 'glasstokey stop' to stop the background runtime
# remove
  9. Run 'glasstokey run-engine 10' for a direct foreground smoke test when needed

Optional user service:
  systemctl --user daemon-reload
  systemctl --user enable --now glasstokey.service

Optional GUI:
  glasstokey-gui            # start tray host in background
  glasstokey-gui --show     # open config window

# TO: 
GlassToKey Linux install complete.

Usage:
  glasstokey-gui            # start tray host in background
  glasstokey-gui --show     # open config window

Recommended next steps:
  1. Reconnect the trackpads or wait a few seconds for refreshed udev permissions.
  2. Add the desktop user to the 'glasstokey' group:
     sudo usermod -aG glasstokey $USER
  3. Log out and back in so the new group membership applies.
  4. Run 'glasstokey start' to launch the background runtime
  5. Run 'glasstokey stop' to stop the background runtime
# TODO:


- when doing `glasstokey stop` it tries to close the tray even when it isn't open? 
> "The tray host did not stop within 10s and could not be force-stopped."

- 3 finger drag doesn't release to mouse the right way (like purple switch)

- Device should not be "auto" except when started headless, the GUI should start default NONE and and you should have to pick from the dropdown list, unless you have saved devices.

Now complete {
  4. In core, add a pure-keyboard intent path so headless never transitions into MouseCandidate / MouseActive; keep key and non-pointer gesture semantics only.
  5. Change grab policy to be policy-driven: headless pure-keyboard grabs the evdev node whenever we are in a real desktop seat; only skip grab behind an explicit --no-grab or a proven no-pointer environment.
}



- If I Switch between keyboard (purple) and mouse (red) during keyboard/mouse mode.. It actually wont give mouse control back to the mouse until I click.

- Is there a less aggressive way to take over? 

# ARCH SUPPORT
- try installing Arch tonight, lol. 

# GUI
- Can we remove the <hr> dividers between the collapsables in the right column?
 
- BRIGHT_UP, BRIGHT_DOWN doesn't work on Linux. I think we need a Linux specific implementation. 

- Adjust FOrce min / force max slider to max out at 255 ON LINUX ONLY

- In Windows there are "contact pills" and "state pills" can you please implement those in Linux?

# Autocorrect
- Turning off Autocorrect should unload it from memory
- Closing the Config should unload it from memory / restart

# TEST / root cause:
- 5-finger Up "D" is triggering Choral shift on it's own side? 
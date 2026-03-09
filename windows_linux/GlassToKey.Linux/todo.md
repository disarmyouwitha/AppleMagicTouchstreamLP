# TODO:
- If the program starts in keyboard/mouse mode the circles are still green/red, and it's actually not in `keyboard/mouse` until you toggle it off/back on.. looks like it's not getting initialized correctly?

- If I Switch between keyboard (purple) and mouse (red) during keyboard/mouse mode.. It actually wont give control back to the mouse until I click.

# HEADLESS
- Try starting headless. `glasstokey start`
- Can it *just* start headless /w `glasstokey` if it recognized no GUI is available?

# GUI
- Can we remove the <hr> dividers between the collapsables in the right column?
 
- BRIGHT_UP, BRIGHT_DOWN doesn't work on Linux. I think we need a Linux specific implementation. 

- Adjust FOrce min / force max slider to max out at 255 ON LINUX ONLY (maybe prod more.. are we not getting force phases from Linux like we are for WIndows? Why is `f:255` the max in the visualizer?)

- In Windows there are "contact pills" and "state pills" can you please implement those in Linux?

# Autocorrect
- Turning off Autocorrect should unload it from memory
- Closing the Config should unload it from memory / restart

# TEST / root cause:
- 5-finger Up "D" is triggering Choral shift on it's own side? 

# Wayland?
- What happens when you actually run this on arch? do ppl use GUI on arch? lol. 
- What happens when you run this on non-wayland? How flexible is avalonia or whatever?
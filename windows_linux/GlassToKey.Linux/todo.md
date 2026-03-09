# TODO:
- If the program starts in keyboard/mouse mode the circles are still green/red!
- If I switch to keyboard mode while in mixed mode the circles doesn't immediately turn purple, only after toggling modes.

# HEADLESS
- Try starting headless. 
- Try `glasstokey` can it *just* start headless if it recognized no GUI is available?

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
# TODO:
- Before the trackpad visualizer was tracked to the Layer drop-down in the GUI, but didn't flip when MO(1) was pressed. You changed this to track the live state. Neither one of these is 100% correct. I want the visualizer to track based on the Layer selected in the dropdown UNLESS a layer key is pressed, which can override was is displayed.

- Haptics support in Linux?

- In Windows there are "contact pills" and "state pills" can you please implement those in Linux?

- BRIGHT_UP, BRIGHT_DOWN doesn't work on Linux. I think we need a Linux specific implementation. 

- Adjust FOrce min / force max slider to max out at 255 ON LINUX ONLY (maybe prod more.. are we not getting force phases from Linux like we are for WIndows? Why is `f:255` the max in the visualizer?)

- Turning off Autocorrect should unload it from memory
- Closing the Config should unload it from memory / restart

# TEST / root cause:
- 5-finger Up "D" is triggering Choral shift on it's own side? 
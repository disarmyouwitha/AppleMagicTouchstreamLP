# TODO:

[1] When clicking on a letter I am getting dispatch on tap and on release. (double dispatch)

[2] Sometimes touches get stuck in the visualizer / runtime and don't lift when I lift my fingers. This causes a problem when I hit "space" later it will dispatch the ghost key

- In Windows there are "contact pills" and "state pills" can you please implement those in Linux?

- BRIGHT_UP, BRIGHT_DOWN doesn't work on Linux. I think we need a Linux specific implementation. 

- Adjust FOrce min / force max slider to max out at 255 ON LINUX ONLY (maybe prod more.. are we not getting force phases from Linux like we are for WIndows? Why is `f:255` the max in the visualizer?)

- Turning off Autocorrect should unload it from memory
- Closing the Config should unload it from memory / restart

# TEST / root cause:
- 5-finger Up "D" is triggering Choral shift on it's own side? 
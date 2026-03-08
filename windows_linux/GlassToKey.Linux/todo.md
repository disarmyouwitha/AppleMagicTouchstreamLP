# TODO:
- Gestures section needs to be fully fleshed out, look at how it's implemented on the Windows side and CAREFULLY move everything needed into the shared/core.

- BRIGHT_UP, BRIGHT_DOWN doesn't work on Linux. I think we need a Linux specific implementation. 

- sometimes touches get stuck in the visualizer / runtime and don't lift when I lift my fingers. This causes a problem when I hit "space" later it will dispatch the ghost nam,

- Turning off Autocorrect should unload it from memory
- Closing the Config should unload it from memory / restart
n
# TEST / root cause:
- 5-finger Up "D" is triggering Choral shift on it's own side? 
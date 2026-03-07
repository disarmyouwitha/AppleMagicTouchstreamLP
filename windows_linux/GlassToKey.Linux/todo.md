# TODO:
- Autocorrect: You may need to update project files or build installers to add the ThirdParty Symspell dictionary, etc.
- Gestures section needs to be fully fleshed out, look at how it's implemented on the Windows side and CAREFULLY move everything needed into the shared/core.

- BRIGHT_UP, BRIGHT_DOWN doesn't work on Linux. I think we need a Linux specific implementation. 

# TEST / root cause:
- 5-finger Up "D" is triggering Choral shift on it's own side? 
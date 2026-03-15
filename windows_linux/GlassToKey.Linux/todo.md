# TODO:
-  In the Action/Hold/Gesture shared dropdown please rename the `Shift` under `Modes` to `Chordal Shift` while leaving the `Shift` under `Modifiers alone.
- Please make all "Custom" actions added at the bottom with their own fancy `Custom` header~ (like in Windows)
- What is the Difference between Super and AltGr in Linux?
- I'm having a really hard time stopping glasstokey when running `dotnet run` do you think that is indicitave of actual installs or just testing?
---
- Add Linux Equivalents for: `System & Media`: EMOJI, VOICE, BRIGHT_UP, BRIGHT_DOWN
- Ctrl, Shift, Alt, Super do not match the description in Shortcut Builder: when you click they DO toggle but nothing happens when I HOLD (should present sided options: Left Shift, Right Shift) please see windows. How does AltGr work in Linux? How do I do AltGr+n > Accented N in Linux?
---
- Test AltGr on Linux
1. You said Super+N then N should send the international letter? I can't get it to work now, (because it's set to Win?)
- Meta keys? or is that same as Super? distinct enough to add to shortcut builder and action dropdowns?
- The GUI colors are so bad when you hover over any button please make it more high contrast
-------
# Test Linux Restart:
- Linux does not respect `open in tray` and always opens in fullscreen
- Test `open after restart` in linux by restarting
- Test typing password after restart in Linux type shit.

# BUG:
- If I Switch between keyboard (purple) and mouse (red) during keyboard/mouse mode.. It actually wont give mouse control back to the mouse until I click - Is there another way to accomplish this? I really don't like EVIOCGRAB style suppression. =x 

- Test `Run on Linux Startup`


# ARCH SUPPORT
- try installing Arch tonight, lol. 

# GUI
- BRIGHT_UP, BRIGHT_DOWN doesn't work on Linux. I think we need a Linux specific implementation. 

- In Windows there are "contact pills" and "state pills" can you please implement those in Linux?

# Autocorrect
- Turning off Autocorrect should unload it from memory
- Closing the Config should unload it from memory / restart

# TEST / root cause:
- 5-finger Up "D" is triggering Choral shift on it's own side? 

# NUKE
pkill -f 'GlassToKey.Linux/Gui/GlassToKey.Linux.Gui.csproj'
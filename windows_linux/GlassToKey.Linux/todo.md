# TODO:
[x] Add Linux Equivalents for: `System & Media`: EMOJI
> Added to the Linux Action dropdown. Linux runtime now launches `/usr/libexec/ibus-ui-emojier`, waits for either the clipboard message or process completion, and then attempts a paste.
  
- Add Linux Equivalents for: `System & Media`: BRIGHT_UP and BRIGHT_DOWN

- Add Linux Equivalents for: `System & Media`: VOICE, 

-------
# Test Linux Restart:
- Linux does not respect `open in tray` and always opens in fullscreen
- Test `open after restart` in linux by restarting
- Test typing password after restart in Linux type shit.
- Test this again, but from headless startup (like Login from startup)

# BUG:
- If I Switch between keyboard (purple) and mouse (red) during keyboard/mouse mode.. It actually wont give mouse control back to the mouse until I click - Is there another way to accomplish this? I really don't like EVIOCGRAB style suppression. =x 

- Test `Run on Linux Startup`


# ARCH SUPPORT
- try installing Arch tonight, lol. 

# GUI
- In Windows there are "contact pills" and "state pills" can you please implement those in Linux?

# Autocorrect
- Turning off Autocorrect should unload it from memory
- Closing the Config should unload it from memory / restart

# TEST / root cause:
- 5-finger Up "D" is triggering Choral shift on it's own side? 

# NUKE
pkill -f 'GlassToKey.Linux/Gui/GlassToKey.Linux.Gui.csproj'

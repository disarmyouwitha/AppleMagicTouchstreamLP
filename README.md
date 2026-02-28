# Apple Magic TouchstreamLP
- Also known as GlassToKey!

## Mac: **(Packaged with .APP)**
- Built on top of the wonderful: https://github.com/Kyome22/OpenMultitouchSupport

*The app will ask for elevated Accessibility permissions on first run*

## Windows: **(*PREREQUISITE INSTALL)**
- Supports both the Official Apple Bootcamp drivers and Opensource drivers!
- **Please follow the <a href="windows_linux/GlassToKey/INSTALL.md" target="_NEW">DRIVER INSTALL GUIDE</a>!**

****If you can move your mouse and you can scroll with a 2-finger gesture — you already have drivers installed!***

## Usage
I have posted a <a href="https://github.com/disarmyouwitha/AppleMagicTouchstreamLP/releases/tag/beta">Beta Release</a> with a **.app** and **.exe** file and hopefully people will be able to run it!

It can't hurt to submit an Issue or PR but this is just a fun side project I am working on with Codex, so it's something you might have to fork and extend! 

**TaskBar Indicators:** (You may need to expand it and drag it out on Windows)<br>
**Green** 🟢: Mixed mode<br>
**Purple**🟣: Keyboard mode (clicking disabled)<br>
**Red** &nbsp;&nbsp;&nbsp;🔴: Mouse mode (typing disabled)<br>
Right-clicking the indicator opens tray actions: Config, Capture, Replay, Restart, and Exit.

**Useful Tips:**
- I would turn off "tap to click" at the OS level (Or turn on Keyboard/Mouse mode)
- In Keyboard mode Mouse clicks are disabled.
- 5-finger left/right swipes will toggle Typing Mode on/off!
- If Chordal Shift is enabled, placing 4 fingers on 1 side will shift characters on the other side 
- If Snap Radius is enabled, taps near keys (but not on them) will snap to the nearest key during typing

**You can use just 1 Trackpad!**
- I encourage you to try it out with your normal split keyboard setup + Apple Magic Trackpad first before you commit to two! Just set your AMT to one side and next time you want to type just don't move your hand from the mouse~
- There is also a "Blank" mode where you can just use it as a Trackpad + Gestures + Custom buttons
- There is also a "Planck" mode where all 12x4 are on 1 trackpad xD (It's terrible)
- **YES** It will work with your internal laptop^ trackpad + 1 Apple Magic Trackpad!

**Windows Haptics:**
- Working over USB!!!
- **~I do not see a path forward for Bluetooth Haptics on Windows!~**
- Maybe through extending the Opensource driver, now that Vito has BT working?
 https://github.com/vitoplantamura/MagicTrackpad2ForWindows

## GESTURES:
- I have been adding Gestures that you can set in the Gesture Tuning config!
- I am open to adding Gestures/Actions - just add a comment to issue https://github.com/disarmyouwitha/AppleMagicTouchstreamLP/issues/16 with your idea or a .atpcap capture!

## FUTURE:
Lots to do in the TODO! For now I am working on feature parity between MAC and WIN and to really hone the controls~

Once I get time I would like to explore the possibility of extending the Opensource driver to add missing per-finger Force (and possibly Haptics over BT for Windows) which would help support the community but also help this project! =]

## Intention
<img src="touchstreamLP.jpg" width="900px">
The Fingerworks TouchStreamLP was a flat, zero-force, gesture keyboard developed for people with RSI in 2002 — it was way before it’s time, and it was *totally rad* FingerWorks was acquired by Apple in 2005 and the TouchStreamLP was immediately discontinued, the technology becoming the basis for the iPhone’s touchscreen in 2007.

**——So here we are——:** it has come full circle. ⭕️

I have been working to revive this ancient keyboard using the DNA of it’s own lineage — the Apple Magic Trackpad!

Since it is built on the same technology, I thought it would be fun to try and create an open source version~

<img src="apple-magic-touchstreamlp.jpg" />

<img src="splatpad.jpg" />

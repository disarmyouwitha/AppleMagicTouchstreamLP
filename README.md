# AppleMagicTouchstreamLP
Consolidating GlassToKey and GlassToKeyForWindows into 1 repo with a more descriptive name! 

## OSX: **(Packaged with .APP)**
- Built on top of the wonderful:
- https://github.com/Kyome22/OpenMultitouchSupport

## WIN: **(PRE-REQUISITE INSTALL)**
- Built on top of the Official Apple Bootcamp drivers:
- **https://github.com/lc700x/MagicTrackPad2_Windows_Precision_Drivers/releases**


If you use an open source driver based on `imbushuo/mac-precision-touchpad`, you will need to change the device decoder in the GUI but it is still supported!

## DRIVER INSTALL WINDOWS

**For LIGHTNING:** I think you can just right-click the `.INF` files and click `Install`

<img src="windows/GlassToKey/screenshots/0_INF_INSTALL.png" width="500px">

**For USB-C, or if the above does not work:** 
Please follow the <a href="windows/GlassToKey/INSTALL.md" target="_NEW">INSTALL GUIDE</a>!

## Usage
I have posted a Beta Release with a .app and .exe file and hopefully people will be able to run it! I cannot confirm it will work for anyone else, however I have tested it on both my Mac laptop/desktop and Windows laptop/desktop~

It can't hurt to submit an Issue or PR but this is just a fun side project I am working on with Codex, so it's something you might have to fork and extend! 

**Cool Features:**
- I would turn off "tap to click" at the OS level, and turn it on within the app!
- You can turn on Keyboard-only mode to toggle between mouse / keyboard (Rather than mouse / mixed)
- ^ 5-finger left/right swipes will toggle Typing Mode on/off!
- If Chordal Shift is enabled, placing 4 fingers on 1 side will shift characters on the other side 
- If Snap Radius is enabled, taps near keys (but not on them) will snap to the nearest key during typing

## Intention
<img src="touchstreamLP.jpg" width="900px">
The Fingerworks TouchStreamLP was a flat, zero-force, gesture keyboard developed for people with RSI in 2002 — it was way before it’s time, and it was *totally rad* FingerWorks was acquired by Apple in 2005 and the TouchStreamLP was immediately discontinued, the technology becoming the basis for the iPhone’s touchscreen in 2007.


**So here we are:** it has come full circle. ⭕️

I have been working to revive this ancient keyboard using the DNA of it’s own lineage — the Apple Magic Trackpad. 👀

Since it is built on the same technology, I thought it would be fun to try and create an open source version!

<img src="apple-magic-touchstreamlp.jpg" />

<img src="splatpad.jpg" />

## FUTURE:
Lots to do in the TODO! For now I have plenty to do to get feature parity between OSX and WIN and to really hone the controls.

One of my biggest gripes is that for Windows all known drivers don't expose Pressure data or allow you to trigger Haptics, which are killer features for OSX.

I have hacked pressure data into the PTP_REPORT for the open source driver DLLs as an experiment.. I hope to enable Haptics by extending the driver but I have had **NO** luck.

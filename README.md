# AppleMagicTouchstreamLP
Consolidating GlassToKey and GlassToKeyForWindows into 1 repo with a much better name! 

## OSX: **(Packaged with .DMG)**
- Built on top of the wonderful 
- https://github.com/Kyome22/OpenMultitouchSupport

## WIN: **(PRE-REQUISITE INSTALL)**
- Built on top of the Official Apple Bootcamp drivers:
- **https://github.com/lc700x/MagicTrackPad2_Windows_Precision_Drivers/releases**


If you use an open source driver, you may need to change the device read type in the GUI.

## DRIVER INSTALL WINDOWS (Update with my own Guide)

**For LIGHTNING:** I think you can just right-click the .INF files and click Install

**For USB-C:** https://github.com/vitoplantamura/MagicTrackpad2ForWindows/issues/30


## Usage
I will post a release with a .dmg and .exe file and hopefully people will be able to run it! I cannot confirm it will work for anyone else~ This is just a fun side project I am working on with Codex so it's something you might have to fork and extend!

## Intention
An attempt to use the Apple Magic Trackpad as a keyboard (and mouse!) like the TouchStream LP~
Since it is built on the same technology, I thought it would be fun to try and create an open source version!

<img src="touchstreamLP.jpg" width="900px" />

<img src="apple-magic-touchstreamlp.jpg" width="900px" />

## FUTURE:
Lots to do in the TODO! For now I have plenty to do to get feature parity between OSX and WIN and to to really hone the controls.


One of my biggest gripes is that for WIN all known drivers don't expose Pressure data or allow you to trigger Haptics, which are killer features for OSX.

I have hacked pressure data into the PTP_REPORT for the open source driver DLLs under `artifacts/DLLs` as an experiment. I hope to enable Haptics by extending the driver but I have had **NO** luck.

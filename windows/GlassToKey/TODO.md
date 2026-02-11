## TODO:
- replay still doesnt work. I don't think we need to dispatch keys exatcly but it doesnt show green highlight of keys either. It does update the pills so maybe it is doing something not visible?
-------
I get this warning when I start the app:
C:\Program Files\dotnet\sdk\9.0.310\Sdks\Microsoft.NET.Sdk\targets\Microsoft.NET.EolTargetFrameworks.targets(32,5): warning NETSDK1138: The target framework 'net6.0-windows' is out of support and will not receive security updates in the future. Please refer to https://aka.ms/dotnet-core-support for more information about the support policy.

I also noticed I had to install `windowsdesktop-runtime-6.0.36-win-x64.exe` to get GlassToKey to run on this computer.. Why? 
Also, Why is this written in .net6? Is there a more modern version we can use? What is the best language to write this in for the most performant and efficient taskbar app that will run in the background and dispatch keys? The Config/visualizer also needs to work incredibly well like this one does! EXACT FUUNCTIONALITY AND FEATURE PARITY. 
-------
- Revisit tap-click.. it feels awful. Settings? Maybe 2-finger and 3-finger hold to trigger click??
- autoreconnect? (yellow circle) and add to taskbar dropdown
- Autocorrect: spelljam? symjam? Windows variant?
- Voice mode: "windows siri/dictation" or use whipserX?
- REFACTOR

## Worth it?
- Only worth persuing Pressure if we can get Haptics to work, I think
- Add force cut off into GUI and settings. Make pressure over cutoff disqualify key dispatch

## CURSED:
- HAPTICS: Not sure if I can get codex to figure it out, I certainly cant. 

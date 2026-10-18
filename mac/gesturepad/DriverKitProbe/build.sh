#!/bin/zsh
set -euo pipefail
probe_root=${0:A:h}
probe_sdk=$(xcrun --sdk driverkit --show-sdk-path)
probe_output="$probe_root/build"
mkdir -p "$probe_output/generated"
probe_flags=(-target x86_64-apple-driverkit20.0 -isysroot "$probe_sdk" -isystem "$probe_sdk/System/DriverKit/usr/include" -iframework "$probe_sdk/System/DriverKit/System/Library/Frameworks" -std=c++17 -fblocks -DDRIVERKIT=1 -I "$probe_output/generated")
xcrun iig --def "$probe_root/Driver/AMTRawHIDReceiver.iig" --header "$probe_output/generated/AMTRawHIDReceiver.h" --impl "$probe_output/generated/AMTRawHIDReceiver.cpp" --deployment-target 20.0 -- -isysroot "$probe_sdk/System/DriverKit" -x c++ -D__IIG=1 -std=c++17 -F "$probe_sdk/System/DriverKit/System/Library/Frameworks" -isystem "$probe_sdk/System/DriverKit/usr/include"
xcrun clang++ "${probe_flags[@]}" -Wall -Wextra -c "$probe_root/Driver/AMTRawHIDReceiver.cpp" -o "$probe_output/Receiver.o"
xcrun clang++ "${probe_flags[@]}" -c "$probe_output/generated/AMTRawHIDReceiver.cpp" -o "$probe_output/Generated.o"
xcrun clang++ "${probe_flags[@]}" -nostdlib  -Wl,-application_extension -framework DriverKit -framework HIDDriverKit -L "$probe_sdk/System/DriverKit/usr/lib"   -lc++ "$probe_output/Receiver.o" "$probe_output/Generated.o" -o "$probe_output/AMTRawHIDReceiver"
probe_app="$probe_output/GesturePadRawHIDProbe.app"
probe_dext="$probe_app/Contents/Library/SystemExtensions/ink.ranna.glasstokey.gesturepad.rawhidprobe.driver.dext"
mkdir -p "$probe_app/Contents/MacOS" "$probe_dext"
cp "$probe_output/AMTRawHIDReceiver" "$probe_dext/AMTRawHIDReceiver"
python3 "$probe_root/package.py" "$probe_app" "$probe_dext"
xcrun swiftc -parse-as-library -target x86_64-apple-macos13.0 "$probe_root/Host/main.swift" -framework AppKit -framework SystemExtensions -framework IOKit -o "$probe_app/Contents/MacOS/GesturePadRawHIDProbe"
print "Built unsigned prototype: $probe_app"

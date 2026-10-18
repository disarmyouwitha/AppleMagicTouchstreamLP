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

#!/bin/zsh
set -euo pipefail
probe_root=${0:A:h}
python3 "$probe_root/generate-config.py"
probe_sdk=$(xcrun --sdk driverkit --show-sdk-path)
probe_output="$probe_root/build"
mkdir -p "$probe_output/generated"
probe_flags=(-target x86_64-apple-driverkit20.0 -isysroot "$probe_sdk" -isystem "$probe_sdk/System/DriverKit/usr/include" -iframework "$probe_sdk/System/DriverKit/System/Library/Frameworks" -std=c++17 -fblocks -DDRIVERKIT=1 -I "$probe_output/generated")
for probe_class in AMTRawHIDReceiver; do
xcrun iig --def "$probe_root/Driver/$probe_class.iig" --header "$probe_output/generated/$probe_class.h" --impl "$probe_output/generated/$probe_class.cpp" --deployment-target 20.0 -- -isysroot "$probe_sdk/System/DriverKit" -x c++ -D__IIG=1 -std=c++17 -F "$probe_sdk/System/DriverKit/System/Library/Frameworks" -isystem "$probe_sdk/System/DriverKit/usr/include"
done
for probe_class in AMTRawHIDReceiver; do
xcrun clang++ "${probe_flags[@]}" -Wall -Wextra -c "$probe_root/Driver/$probe_class.cpp" -o "$probe_output/$probe_class.o"
xcrun clang++ "${probe_flags[@]}" -c "$probe_output/generated/$probe_class.cpp" -o "$probe_output/$probe_class-generated.o"
done
xcrun clang++ "${probe_flags[@]}" -nostdlib  -Wl,-application_extension -framework DriverKit -framework HIDDriverKit -L "$probe_sdk/System/DriverKit/usr/lib"   -lc++ "$probe_output/AMTRawHIDReceiver.o" "$probe_output/AMTRawHIDReceiver-generated.o" -o "$probe_output/AMTRawHIDReceiver"
probe_helper_name=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["helperAppName"])' "$probe_root/takeover-config.json")
probe_driver_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["driverBundleID"])' "$probe_root/takeover-config.json")
probe_helper_executable=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["helperExecutable"])' "$probe_root/takeover-config.json")
probe_driver_executable=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["driverExecutable"])' "$probe_root/takeover-config.json")
probe_app="$probe_output/$probe_helper_name"
probe_dext="$probe_app/Contents/Library/SystemExtensions/$probe_driver_id.dext"
mkdir -p "$probe_app/Contents/MacOS" "$probe_dext"
cp "$probe_output/AMTRawHIDReceiver" "$probe_dext/$probe_driver_executable"
python3 "$probe_root/package.py" "$probe_app" "$probe_dext"
xcrun swiftc -parse-as-library -target x86_64-apple-macos13.0 "$probe_root/Host/main.swift" "$probe_root/../GesturePad/GesturePad/Runtime/DriverSession.swift" "$probe_root/../GesturePad/GesturePad/Runtime/TakeoverConfiguration.swift" -framework Security -framework AppKit -framework SystemExtensions -framework IOKit -o "$probe_app/Contents/MacOS/$probe_helper_executable"
print "Built unsigned prototype: $probe_app"

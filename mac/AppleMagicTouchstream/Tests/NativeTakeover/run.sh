#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p "$ROOT/build/NativeTakeoverTests"
SOURCES=()
for source in "$ROOT"/Framework/OpenMultitouchSupportXCF/*.m; do
    [[ "$source" == */OpenMTManagerV2.m ]] || SOURCES+=("$source")
done
xcrun clang -fobjc-arc -fmodules -Wno-deprecated-declarations \
    -F/System/Library/PrivateFrameworks -framework MultitouchSupport \
    -framework Cocoa -framework IOKit \
    "$ROOT/Tests/NativeTakeover/main.m" "${SOURCES[@]}" \
    -o "$ROOT/build/NativeTakeoverTests/NativeTakeoverTests"
"$ROOT/build/NativeTakeoverTests/NativeTakeoverTests"

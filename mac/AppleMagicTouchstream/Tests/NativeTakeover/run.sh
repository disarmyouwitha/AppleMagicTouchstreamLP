#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p "$ROOT/build/NativeTakeoverTests"
SOURCES=()
for source in "$ROOT"/Framework/OpenMultitouchSupportXCF/*.m; do
    case "$source" in
        */OpenMTManagerV2.m|*/OpenMTManager.m) ;;
        *) SOURCES+=("$source") ;;
    esac
done
xcrun clang -fobjc-arc -fmodules -Wno-deprecated-declarations \
    -F/System/Library/PrivateFrameworks -framework MultitouchSupport \
    -framework Cocoa -framework IOKit \
    "$ROOT/Tests/NativeTakeover/main.m" "$ROOT/Tests/NativeTakeover/HapticCacheTests.m" "${SOURCES[@]}" \
    -o "$ROOT/build/NativeTakeoverTests/NativeTakeoverTests"
"$ROOT/build/NativeTakeoverTests/NativeTakeoverTests"

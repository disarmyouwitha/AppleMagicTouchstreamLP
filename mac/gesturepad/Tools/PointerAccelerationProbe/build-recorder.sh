#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="$ROOT/../../build/PointerAccelerationProbe"
mkdir -p "$OUTPUT"
xcrun clang -fobjc-arc -O2 -Wall -Wextra "$ROOT/record.m" \
    -F/System/Library/PrivateFrameworks -framework Foundation \
    -framework ApplicationServices -framework IOKit -framework MultitouchSupport \
    -o "$OUTPUT/Recorder"
printf '%s\n' "$OUTPUT/Recorder"

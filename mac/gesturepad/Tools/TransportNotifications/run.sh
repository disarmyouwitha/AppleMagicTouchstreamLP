#!/bin/zsh
set -euo pipefail
probe_root=${0:A:h}
mkdir -p "$probe_root/build"
xcrun swiftc "$probe_root/main.swift" -framework Foundation -framework IOKit -o "$probe_root/build/notification-observer"
exec "$probe_root/build/notification-observer" "${@}"

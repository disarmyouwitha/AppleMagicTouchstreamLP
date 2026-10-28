#!/bin/bash
set -euo pipefail
PROBE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_EXECUTABLE="$PROBE_ROOT/../../build/HIDSeizureProbe/NativeFilterProbe.app/Contents/MacOS/NativeFilterProbe"
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 BLUETOOTH_ADDRESS" >&2
    exit 2
fi
[[ -x "$PROBE_EXECUTABLE" ]] || { echo "Build Tools/HIDSeizureProbe/build.sh first" >&2; exit 1; }
umask 077
PROBE_CAPTURE_DIR="$(mktemp -d /tmp/amt-native-filter.XXXXXX)"
finish() {
    local result=$?
    trap - EXIT
    if [[ "${SUDO_UID:-}" =~ ^[0-9]+$ && "${SUDO_GID:-}" =~ ^[0-9]+$ ]]; then
        chown "$SUDO_UID:$SUDO_GID" "$PROBE_CAPTURE_DIR"
        [[ ! -f "$PROBE_CAPTURE_DIR/session.log" ]] || chown "$SUDO_UID:$SUDO_GID" "$PROBE_CAPTURE_DIR/session.log"
    fi
    printf '\nTest exit: %s\nSaved session: %s/session.log\n' "$result" "$PROBE_CAPTURE_DIR"
    exit "$result"
}
trap finish EXIT
printf '%s\n' 'Release DriverKit takeover and quit the trackpad apps/BTT; keep another mouse/keyboard available.' 'Keep the right Bluetooth pad ON and connected. Move fingers through BASELINE, FILTER, and RECOVERY.' 'Do not move another mouse during measurement, and do not press down to click during this first test.' 'The native FLTR window is 8 seconds, automatically closed; Ctrl-C ends early.'
"$PROBE_EXECUTABLE" --probe --address "$1" 2>&1 | tee "$PROBE_CAPTURE_DIR/session.log"

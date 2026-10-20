#!/bin/bash
set -euo pipefail
PROBE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_EXECUTABLE="$PROBE_ROOT/../../build/HIDSeizureProbe/BluetoothChannelProbe.app/Contents/MacOS/BluetoothChannelProbe"
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 BLUETOOTH_ADDRESS" >&2
    exit 2
fi
[[ -x "$PROBE_EXECUTABLE" ]] || { echo "Build Tools/HIDSeizureProbe/build.sh first" >&2; exit 1; }
umask 077
PROBE_CAPTURE_DIR="$(mktemp -d /tmp/amt-bluetooth-reconnect.XXXXXX)"
finish() {
    local result=$?
    trap - EXIT
    printf '\nTest exit: %s\nSaved session: %s/session.log\n' "$result" "$PROBE_CAPTURE_DIR"
    exit "$result"
}
trap finish EXIT
printf '%s\n' 'Start with the selected pad OFF. Turn it on after WATCHING appears.' 'Keep a separate mouse/keyboard available; quit the trackpad apps and release DriverKit takeover.'
"$PROBE_EXECUTABLE" --watch-reconnect --address "$1" --seconds 30 2>&1 | tee "$PROBE_CAPTURE_DIR/session.log"

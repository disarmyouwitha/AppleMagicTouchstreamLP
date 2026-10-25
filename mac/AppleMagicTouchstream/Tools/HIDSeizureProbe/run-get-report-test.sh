#!/bin/bash
set -euo pipefail
PROBE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_EXECUTABLE="$PROBE_ROOT/../../build/HIDSeizureProbe/HIDGetReportProbe.app/Contents/MacOS/HIDGetReportProbe"
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 BLUETOOTH_ADDRESS" >&2
    exit 2
fi
[[ -x "$PROBE_EXECUTABLE" ]] || { echo "Build Tools/HIDSeizureProbe/build.sh first" >&2; exit 1; }
umask 077
PROBE_CAPTURE_DIR="$(mktemp -d /tmp/amt-get-report.XXXXXX)"
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
printf '%s\n' 'Release DriverKit takeover and quit the trackpad apps; keep another mouse/keyboard available.' 'Keep the selected Bluetooth pad ON and connected. Move several fingers after BASELINE appears.' 'Seizure is attempted only if both baseline input-report requests return known framing.'
"$PROBE_EXECUTABLE" --probe --address "$1" 2>&1 | tee "$PROBE_CAPTURE_DIR/session.log"

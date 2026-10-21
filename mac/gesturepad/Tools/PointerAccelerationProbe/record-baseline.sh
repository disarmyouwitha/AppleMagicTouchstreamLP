#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 <pad serial/MAC or current native device ID> [seconds, default 20]" >&2
    exit 2
fi
IDENTITY="$1"
DURATION="${2:-20}"
"$ROOT/build-recorder.sh" > /dev/null
SESSION="$(mktemp -d "$ROOT/../../build/PointerAccelerationProbe/native.XXXXXX")"
python3 -B "$ROOT/acceleration.py" snapshot --output "$SESSION/settings.json" > "$SESSION/settings-summary.json"
DEVICE_ID="$(python3 -B - "$SESSION/settings.json" "$IDENTITY" <<'PY'
import json,sys
entries=json.load(open(sys.argv[1]))['devices']
selected=[d for d in entries if sys.argv[2].lower() in (d['device_id'].lower(),d.get('serial','').lower())]
if len(selected)!=1: sys.exit('Identity must match exactly one settings entry; inspect '+sys.argv[1])
print(selected[0]['device_id'])
PY
)"
printf 'Session: %s\nSelected native ID: %s\n' "$SESSION" "$DEVICE_ID"
echo 'Uncheck Trackpad Takeover first. Quit other pointer modifiers such as BTT for this baseline.'
echo 'Use ONE finger on this pad only, slow/medium/fast strokes, lifting between strokes.'
echo 'Stay away from screen edges; do not click or move another mouse. Recording lasts at most 60 seconds.'
set +e
"$ROOT/../../build/PointerAccelerationProbe/Recorder" --device-id "$DEVICE_ID" --seconds "$DURATION" --output "$SESSION/native.jsonl" 2>&1 | tee "$SESSION/session.log"
RESULT=${PIPESTATUS[0]}
set -e
printf '\nRecorder exit: %s\nSend this session folder for analysis: %s\n' "$RESULT" "$SESSION"
exit "$RESULT"

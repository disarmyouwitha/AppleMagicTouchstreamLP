#!/bin/zsh
set -euo pipefail
handoff_root=${0:A:h}
if (( $# != 2 )); then
    print -u2 "Usage: $0 left|right close|reopen|terminate|rematch|retake|status"
    exit 2
fi
case "$1" in
 left) handoff_serial='D0:C0:50:D4:75:6C' ;;
 right) handoff_serial='J84HMA00H0B0000501' ;;
 *) print -u2 'Choose left or right.'; exit 2 ;;
esac
case "$2" in
 close|reopen|terminate|rematch|retake|status) ;;
 *) print -u2 'Choose close, reopen, terminate, rematch, retake, or status.'; exit 2 ;;
esac
handoff_helper='/Applications/GesturePad.app/Contents/Helpers/GesturePadDriverService.app/Contents/MacOS/GesturePadRawHIDProbe'
handoff_output=$(mktemp -d /tmp/GesturePad-handoff-XXXXXXXX)
python3 "$handoff_root/registry-snapshot.py" > "$handoff_output/before.json"
# Close first so the app/watchdog observe the intentional handoff before removal.
if [[ "$2" == terminate ]]; then
 "$handoff_helper" --handoff "$handoff_serial" close > "$handoff_output/close.json"
fi
handoff_result=0
"$handoff_helper" --handoff "$handoff_serial" "$2" > "$handoff_output/command.json" || handoff_result=$?
python3 "$handoff_root/registry-snapshot.py" > "$handoff_output/after.json"
cat "$handoff_output/command.json"
print "Evidence: $handoff_output"
print 'A successful command is not proof native input returned. Verify cursor, click, scroll and gestures physically; check the other pad still streams.'
exit "$handoff_result"

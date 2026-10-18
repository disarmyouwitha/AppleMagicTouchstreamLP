#!/bin/zsh
set -euo pipefail
trace_root=${0:A:h}
trace_stamp=$(date +%s)
trace_dir="$trace_root/evidence/$trace_stamp"
mkdir -p "$trace_dir"
print 'Prepare System Settings → General → Login Items & Extensions → Driver Extensions.'
print 'Authenticate here. At TRACING, ENABLE/APPROVE the pending AMT Raw HID Receiver v0.3 in SETTINGS.'
print 'Do not press Activate again when macOS says waiting for user.'
print 'Keep GesturePad control/tests released. Move one/two fingers on RIGHT USB pad.'
print 'After 90s: disable the receiver in Driver Extensions. No USB mode command is sent by this script.'
sudo -v
systemextensionsctl list > "$trace_dir/extensions-before.txt"
ioreg -a -l -p IOService > "$trace_dir/registry-before.plist"
print 'TRACING — ENABLE/APPROVE AMT Raw HID Receiver in SYSTEM SETTINGS now, then move one/two fingers.'
sudo -n /usr/bin/ktrace trace -T 90s -f 'S0x052d,S0x0523' --ndjson > "$trace_dir/delivery.ndjson"
ioreg -a -l -p IOService > "$trace_dir/registry-after.plist"
systemextensionsctl list > "$trace_dir/extensions-after.txt"
/usr/bin/log show --last 3m --style compact --predicate 'eventMessage CONTAINS "AMTRawHIDReceiver" OR eventMessage CONTAINS "GesturePadRawHIDProbe:"' > "$trace_dir/driver.log"
print "Saved delivery evidence: $trace_dir"
python3 "$trace_root/summarize-delivery.py" "$trace_dir"

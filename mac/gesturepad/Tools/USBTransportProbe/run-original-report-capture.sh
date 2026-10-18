#!/bin/zsh
set -euo pipefail
probe_dir=${0:A:h}
probe_duration=15
if [[ ${1:-} == --seized ]]; then
    probe_duration=30
elif (( $# > 0 )); then
    print -u2 'Usage: run-original-report-capture.sh [--seized]'
    exit 2
fi
if [[ $(/usr/bin/uname -m) != x86_64 || $(/usr/bin/sw_vers -buildVersion) != 24G517 ]]; then
    print -u2 'Unsupported kernel build: registry layout must be revalidated before this probe.'
    exit 1
fi
probe_stamp=$(date +%s)
probe_script=/tmp/GesturePad-original-report-$probe_stamp.d
probe_log=/tmp/GesturePad-original-report-$probe_stamp.log
/usr/sbin/ioreg -a -l -r -c IOHIDDevice | /usr/bin/python3 -c '
import sys,plistlib,pathlib
nodes=plistlib.loads(sys.stdin.buffer.read()); found=[]
def walk(n):
 if not isinstance(n,dict):return
 if n.get("IOObjectClass")=="AppleUSBTopCaseHIDDriver" and n.get("VendorID")==1452 and n.get("ProductID")==804 and n.get("SerialNumber")=="J84HMA00H0B0000501" and n.get("PrimaryUsagePage")==1 and n.get("PrimaryUsage")==2 and n.get("Transport")=="USB": found.append(n["IORegistryEntryID"])
 for child in n.get("IORegistryEntryChildren",[]):walk(child)
for n in nodes if isinstance(nodes,list) else [nodes]:walk(n)
if len(found)!=1:raise SystemExit("Expected exactly one right USB mouse interface; no trace started.")
source=pathlib.Path(sys.argv[1]).read_text().replace("@RID@",str(found[0])).replace("@DURATION@",sys.argv[3]);pathlib.Path(sys.argv[2]).write_text(source)
print("Resolved right USB HID registry ID:",found[0])
' "$probe_dir/capture-original-report.d.in" "$probe_script" "$probe_duration"
if [[ $probe_duration == 30 ]]; then
    print 'Prepare GesturePad RIGHT USB 0001:0002 Capture one (15s), mode checkbox OFF.'
    print 'After READY: start that app capture, then move one/two fingers during seizure and after release.'
    print 'The original-buffer trace lasts30s to cover the entire15s seizure.'
else
    print 'Leave GesturePad trackpads released for this first capture.'
    print 'After READY appears, move one finger, then two fingers on the RIGHT USB pad for15s.'
fi
print 'This reads original report buffers only; no seizure, boot argument, mode write or kernel patch.'
trap 'print "Saved: $probe_log"' EXIT
print 'Checking DTrace program and probe matches before activation…'
sudo /usr/sbin/dtrace -e -s "$probe_script"
sudo /usr/sbin/dtrace -s "$probe_script" 2>&1 | tee "$probe_log"

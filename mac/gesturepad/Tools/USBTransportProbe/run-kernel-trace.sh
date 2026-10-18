#!/bin/zsh
set -euo pipefail
trace_log=/tmp/GesturePad-usb-hid-kernel-$(date +%s).ndjson
print 'This records USB/HID kernel trace events for 20 seconds.'
print 'Leave trackpads released in GesturePad. After sudo authenticates, move one and two fingers on the RIGHT USB pad.'
print 'No mode command, seizure, reset, driver change, or firmware write is performed.'
print "Output: $trace_log"
# SDK sys/kdebug.h: DBG_IOKIT=5, DBG_IOUSB=45 (0x2d), DBG_IOHID=35 (0x23).
# Elevate only Apple's bounded tracing executable; redirection stays user-owned.
sudo /usr/bin/ktrace trace -T 20s -f 'S0x052d,S0x0523' --ndjson > "$trace_log"
print "Saved: $trace_log"

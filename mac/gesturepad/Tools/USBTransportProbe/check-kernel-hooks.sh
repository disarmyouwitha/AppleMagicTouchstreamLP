#!/bin/zsh
set -uo pipefail
probe_log=/tmp/GesturePad-kernel-hooks-$(date +%s).log
print 'Lists available kernel function probes only. No capture, mode write, boot-argument or security-setting change.'
print 'No trackpad touches are needed for this check.'
{
    /usr/bin/csrutil status
    print 'Current boot arguments:'
    /usr/sbin/sysctl -n kern.bootargs
    print 'DTrace function-probe inventory:'
    sudo /usr/sbin/dtrace -Z -l \
        -n 'fbt::*hid_trace*:entry' \
        -n 'fbt::*IOHIDDevice*handleReportWithTime*:entry' \
        -n 'fbt::*IOUSBHostHIDDevice*interruptReadComplete*:entry'
    probe_status=$?
    print "DTrace inventory exit=$probe_status"
} 2>&1 | tee "$probe_log"
print "Saved: $probe_log"

#!/bin/zsh
set -euo pipefail
probe_dir=${0:A:h}
probe_binary=/tmp/GesturePad-USBInterfaceCapture
probe_log=/tmp/GesturePad-usb-interface-$(date +%s).log
clang -Wall -Wextra -Werror -Wno-deprecated-declarations "$probe_dir/capture-interface.c" -framework IOKit -framework CoreFoundation -o "$probe_binary"
print 'Release trackpads in GesturePad first. This test runs independently of the app.'
print 'It attempts exclusive access to ONLY the known right USB pad, interface1.'
print 'If accepted: move one/two fingers for15s. Ctrl-C releases early.'
print 'If Apple refuses: the probe stops immediately. No driver detach/reset/mode command is attempted.'
print "Output: $probe_log"
read -r 'probe_reply?Press Return to start: '
trap 'print "Result saved: $probe_log"' EXIT
"$probe_binary" --capture-right-usb | tee "$probe_log"

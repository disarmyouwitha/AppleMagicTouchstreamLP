#!/bin/zsh
set -euo pipefail
probe_root=${0:A:h}
# Never replace the on-disk helper while it may own a device or await approval.
probe_state=$(systemextensionsctl list)
if print -r -- "$probe_state" | /usr/bin/grep 'ink.ranna.glasstokey.gesturepad.rawhidprobe.driver' | /usr/bin/grep -v 'terminated waiting to uninstall on reboot' >/dev/null; then
    print -u2 'Release/deactivate the existing AMT receiver before installing. No files were replaced.'
    exit 1
fi
"$probe_root/build.sh"
python3 "$probe_root/sign.py" --driver-profile "$probe_root/profiles/driver.provisionprofile" --host-profile "$probe_root/profiles/host.provisionprofile"
if [[ -d /Applications/GesturePadRawHIDProbe.app ]]; then
    mkdir -p "$probe_root/build/previous"
    ditto /Applications/GesturePadRawHIDProbe.app "$probe_root/build/previous/GesturePadRawHIDProbe.app"
fi
killall GesturePadRawHIDProbe 2>/dev/null || true
ditto "$probe_root/build/GesturePadRawHIDProbe.app" /Applications/GesturePadRawHIDProbe.app
codesign --verify --strict /Applications/GesturePadRawHIDProbe.app
print 'Installed signed v0.6 helper. No driver activated. Start the test inside GesturePad.'

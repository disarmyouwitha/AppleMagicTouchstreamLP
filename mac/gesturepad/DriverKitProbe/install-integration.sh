#!/bin/zsh
set -euo pipefail
probe_root=${0:A:h}
if (( $# )); then
    print -u2 "Usage: $0"; exit 2
fi
probe_driver_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["driverBundleID"])' "$probe_root/takeover-config.json")
probe_state=$(systemextensionsctl list)
if print -r -- "$probe_state" | /usr/bin/grep -F -e "$probe_driver_id" -e "ink.ranna.glasstokey.gesturepad.rawhidprobe.driver" | /usr/bin/grep -v 'terminated waiting to uninstall on reboot' >/dev/null; then
    print -u2 'Release the AMT receiver before installing. No files were replaced.'
    exit 1
fi
"$probe_root/build.sh"
python3 "$probe_root/sign.py" --driver-profile "$probe_root/profiles/driver.provisionprofile" --host-profile "$probe_root/profiles/host.provisionprofile"
"$probe_root/../build.sh"
probe_main="$probe_root/../build/DerivedData/Build/Products/Debug/GesturePad.app"
codesign --verify --deep --strict "$probe_main"
mkdir -p "$probe_root/build/previous"
if [[ -d /Applications/GesturePad.app ]]; then
    ditto /Applications/GesturePad.app "$probe_root/build/previous/GesturePad.app"
fi
# Receiver is not registered; safe to stop the old UI before replacing the bundle.
killall GesturePad 2>/dev/null || true
killall GesturePadRawHIDProbe 2>/dev/null || true
# ditto merges directories: move the old bundle aside to avoid stale renamed dexts.
if [[ -d /Applications/GesturePad.app ]]; then
    mv /Applications/GesturePad.app "$probe_root/build/previous/GesturePad-before-install-$(date +%Y%m%d-%H%M%S).app"
fi
ditto "$probe_main" /Applications/GesturePad.app
codesign --verify --deep --strict /Applications/GesturePad.app
if [[ -d /Applications/GesturePadRawHIDProbe.app ]]; then
    ditto /Applications/GesturePadRawHIDProbe.app "$probe_root/build/previous/GesturePadRawHIDProbe.app"
    rm -rf /Applications/GesturePadRawHIDProbe.app
fi
print 'Installed GesturePad with its internal background driver service. No driver activated.'

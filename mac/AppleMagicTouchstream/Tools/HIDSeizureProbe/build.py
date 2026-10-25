#!/usr/bin/env python3
"""Build/sign isolated HID diagnostics, including opt-in native contact counts."""
import os
from pathlib import Path
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT.parents[1] / 'build/HIDSeizureProbe'
APP = OUTPUT / 'HIDSeizureProbe.app'
MACOS = APP / 'Contents/MacOS'
BLUETOOTH_APP = OUTPUT / 'BluetoothChannelProbe.app'
GET_REPORT_APP = OUTPUT / 'HIDGetReportProbe.app'
NATIVE_FILTER_APP = OUTPUT / 'NativeFilterProbe.app'


def run(*args):
    subprocess.run([str(a) for a in args], check=True)


def main():
    MACOS.mkdir(parents=True, exist_ok=True)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    for arch in ['arm64', 'x86_64']:
        native = OUTPUT/f'native-{arch}.o'
        run('xcrun', 'clang', '-fobjc-arc', '-std=gnu11',
            '-target', f'{arch}-apple-macos13.5', '-isysroot', sdk,
            '-c', ROOT/'NativeContacts.m', '-o', native)
        run('xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-O',
            '-target', f'{arch}-apple-macos13.5', '-sdk', sdk,
            ROOT/'ProbeModel.swift', ROOT/'main.swift', native,
            '-import-objc-header', ROOT/'NativeContacts.h',
            '-F/System/Library/PrivateFrameworks', '-framework', 'MultitouchSupport',
            '-framework', 'Foundation', '-framework', 'IOKit', '-framework', 'CoreGraphics',
            '-o', OUTPUT/f'probe-{arch}')
        run('xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-O',
            '-target', f'{arch}-apple-macos13.5', '-sdk', sdk,
            ROOT/'ProbeModel.swift', ROOT/'BluetoothModel.swift', ROOT/'GetReportModel.swift', ROOT/'NativeFilterMain.swift', native,
            '-import-objc-header', ROOT/'NativeContacts.h',
            '-F/System/Library/PrivateFrameworks', '-framework', 'MultitouchSupport',
            '-framework', 'Foundation', '-framework', 'IOKit', '-framework', 'CoreGraphics', '-o', OUTPUT/f'native-filter-{arch}')
        bluetooth = OUTPUT/f'bluetooth-{arch}.o'
        run('xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra',
            '-target', f'{arch}-apple-macos13.5', '-isysroot', sdk,
            '-c', ROOT/'BluetoothChannels.m', '-o', bluetooth)
        run('xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-O',
            '-target', f'{arch}-apple-macos13.5', '-sdk', sdk,
            ROOT/'ProbeModel.swift', ROOT/'BluetoothModel.swift', ROOT/'BluetoothMain.swift', bluetooth,
            '-import-objc-header', ROOT/'BluetoothChannels.h',
            '-framework', 'Foundation', '-framework', 'IOKit', '-framework', 'IOBluetooth',
            '-o', OUTPUT/f'bluetooth-probe-{arch}')
        run('xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-O',
            '-target', f'{arch}-apple-macos13.5', '-sdk', sdk,
            ROOT/'ProbeModel.swift', ROOT/'BluetoothModel.swift', ROOT/'GetReportModel.swift', ROOT/'GetReportMain.swift',
            '-framework', 'Foundation', '-framework', 'IOKit', '-o', OUTPUT/f'get-report-{arch}')
    executable = MACOS/'HIDSeizureProbe'
    run('xcrun', 'lipo', '-create', OUTPUT/'probe-arm64', OUTPUT/'probe-x86_64', '-output', executable)
    (APP/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(
        CFBundleIdentifier='ink.ranna.applemagictouchstream.hidseizureprobe',
        CFBundleName='HIDSeizureProbe', CFBundleExecutable='HIDSeizureProbe',
        CFBundlePackageType='APPL', CFBundleVersion='1', CFBundleShortVersionString='0.1',
        LSMinimumSystemVersion='13.5', LSUIElement=True)))
    bluetooth_macos = BLUETOOTH_APP/'Contents/MacOS'
    bluetooth_macos.mkdir(parents=True, exist_ok=True)
    run('xcrun', 'lipo', '-create', OUTPUT/'bluetooth-probe-arm64', OUTPUT/'bluetooth-probe-x86_64',
        '-output', bluetooth_macos/'BluetoothChannelProbe')
    (BLUETOOTH_APP/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(
        CFBundleIdentifier='ink.ranna.applemagictouchstream.bluetoothchannelprobe',
        CFBundleName='BluetoothChannelProbe', CFBundleExecutable='BluetoothChannelProbe',
        CFBundlePackageType='APPL', CFBundleVersion='1', CFBundleShortVersionString='0.1',
        LSMinimumSystemVersion='13.5', LSUIElement=True,
        NSBluetoothAlwaysUsageDescription='Test raw input from one explicitly selected Magic Trackpad.')))
    get_report_macos = GET_REPORT_APP/'Contents/MacOS'
    get_report_macos.mkdir(parents=True, exist_ok=True)
    run('xcrun', 'lipo', '-create', OUTPUT/'get-report-arm64', OUTPUT/'get-report-x86_64',
        '-output', get_report_macos/'HIDGetReportProbe')
    (GET_REPORT_APP/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(
        CFBundleIdentifier='ink.ranna.applemagictouchstream.hidgetreportprobe',
        CFBundleName='HIDGetReportProbe', CFBundleExecutable='HIDGetReportProbe',
        CFBundlePackageType='APPL', CFBundleVersion='1', CFBundleShortVersionString='0.1',
        LSMinimumSystemVersion='13.5', LSUIElement=True)))
    filter_macos = NATIVE_FILTER_APP/'Contents/MacOS'
    filter_macos.mkdir(parents=True, exist_ok=True)
    run('xcrun', 'lipo', '-create', OUTPUT/'native-filter-arm64', OUTPUT/'native-filter-x86_64',
        '-output', filter_macos/'NativeFilterProbe')
    (NATIVE_FILTER_APP/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(
        CFBundleIdentifier='ink.ranna.applemagictouchstream.nativefilterprobe',
        CFBundleName='NativeFilterProbe', CFBundleExecutable='NativeFilterProbe',
        CFBundlePackageType='APPL', CFBundleVersion='1', CFBundleShortVersionString='0.1',
        LSMinimumSystemVersion='13.5', LSUIElement=True)))
    identity = os.environ.get('PROBE_SIGN_IDENTITY')
    if not identity:
        identities = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
        matches = re.findall(r'\b([0-9A-F]{40})\s+"Developer ID Application:[^"\n]*\(N9XQZJR4EP\)"', identities)
        identity = matches[0] if matches else '-'
    for app in [APP, BLUETOOTH_APP, GET_REPORT_APP, NATIVE_FILTER_APP]:
        run('codesign', '--force', '--sign', identity, '--options', 'runtime',
            '--timestamp' if identity != '-' else '--timestamp=none', app)
        run('codesign', '--verify', '--deep', '--strict', '--verbose=2', app)
    run('lipo', '-archs', executable)
    print(f'Built {APP}\nSigning: {"ad-hoc" if identity == "-" else "certificate"}; no restricted entitlements or profiles. Not notarized.')
    print(f'Help (no device access): "{executable}" --help')
    print(f'Bluetooth experiment: {BLUETOOTH_APP} (not activated)')


if __name__ == '__main__':
    main()

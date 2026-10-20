#!/bin/bash
set -euo pipefail
PROBE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_OUTPUT="$PROBE_ROOT/../../build/HIDSeizureProbe"
mkdir -p "$PROBE_OUTPUT"
xcrun swiftc -parse-as-library "$PROBE_ROOT/ProbeModel.swift" "$PROBE_ROOT/BluetoothModel.swift" "$PROBE_ROOT/GetReportModel.swift" "$PROBE_ROOT/Tests.swift" -o "$PROBE_OUTPUT/probe-tests"
"$PROBE_OUTPUT/probe-tests"
xcrun clang -fobjc-arc -Wall -Wextra -Werror "$PROBE_ROOT/BluetoothChannels.m" \
    "$PROBE_ROOT/BluetoothBridgeTests.m" -framework Foundation -framework IOBluetooth \
    -o "$PROBE_OUTPUT/bluetooth-bridge-tests"
"$PROBE_OUTPUT/bluetooth-bridge-tests"
xcrun clang -fobjc-arc -std=gnu11 -Wall -Wextra -Werror \
    -DIORegistryEntrySearchCFProperty=FakeSearch -DIORegistryEntryGetChildIterator=FakeChildren \
    -DIOIteratorNext=FakeNext -DIOObjectConformsTo=FakeConforms -DIOObjectRelease=FakeRelease \
    -DIORegistryEntryCreateCFProperty=FakeProperty \
    "$PROBE_ROOT/NativeContacts.m" "$PROBE_ROOT/NativeFilterTests.m" -framework Foundation \
    -o "$PROBE_OUTPUT/native-filter-tests"
exec "$PROBE_OUTPUT/native-filter-tests"

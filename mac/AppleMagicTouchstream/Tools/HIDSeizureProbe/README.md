# User-space trackpad seizure experiment

**Latest result:** [reconnect observer saw the device, but no HID channels](RECONNECT_TEST.md#hardware-result-2026-10-19).
**Latest request result:** [input GET_REPORT failed in the F1 keyhole path; no seizure attempted](GET_REPORT_TEST.md#hardware-result-2026-10-19).
**Positive Bluetooth hardware result:** [native FLTR mode delivered continuous contacts, suppressed visible cursor movement, and recovered](NATIVE_FILTER_TEST.md#third-run-continuous-one-finger-test).
Do not repeat the earlier Bluetooth channel tests.
The former second-channel test is disabled: [hardware result and correction](BLUETOOTH_TEST.md).
The earlier raw-HID/native-contact seizure results and their limits remain below.

Standalone diagnostic for one explicitly selected model 0324 Magic Trackpad HID
interface. Seizure uses public IOKit APIs; optional native contact counting uses
the app's existing private MultitouchSupport API. It declares no restricted entitlements and
does not load, alter, or replace our custom DriverKit extension. It does not
generate keyboard/mouse events or integrate with the main app.

## Build and offline checks

From the AppleMagicTouchstream folder:

```sh
./Tools/HIDSeizureProbe/test.sh
./Tools/HIDSeizureProbe/build.sh
```

Output: `build/HIDSeizureProbe/HIDSeizureProbe.app`. Its command-line executable
contains arm64 and x86_64 slices, targeting macOS 13.5+. The builder uses the
available team Developer ID Application identity, otherwise ad-hoc signing;
`PROBE_SIGN_IDENTITY` overrides that choice. This experiment is not notarized.
Build/tests do not enumerate, open, or activate hardware. Default execution and
`--help` only print help. Invoke the executable in Terminal; this is not a GUI app.

## Manual hardware procedure

These commands are for an intentional live hardware test, not build validation.
Keep an independent keyboard/mouse available. Quit AppleMagicTouchstream/GesturePad
and release their Trackpad Takeover first. The probe refuses to capture when an
`AMTRawHIDReceiver` service is present. It does not deactivate another owner's driver.

```sh
PROBE="$PWD/build/HIDSeizureProbe/HIDSeizureProbe.app/Contents/MacOS/HIDSeizureProbe"
"$PROBE" --list
```

Inventory is read-only: it does not call `IOHIDDeviceOpen`. Choose the decimal
`registryID ` for exactly one eligible USB/Bluetooth mouse collection. IDs are
temporary; list again after reconnecting. No automatic selection or all-pad mode
exists, and keyboard/keypad collections are refused.

Run a shared baseline, then a separate exclusive test, replacing 123 with that ID:

```sh
"$PROBE" --observe --registry-id 123 --seconds 15 --output /tmp/amt-shared.jsonl
"$PROBE" --seize --registry-id 123 --seconds 15 --output /tmp/amt-seized.jsonl
```

During each session, touch/move/click only the selected pad. Compare raw report
counts and `framed`/`withContacts` counts. During seizure, observe whether the
native pointer, physical click, tap-to-click, scrolling and system gestures stop.
Also verify that a separate mouse/pad still works. After timeout or Ctrl-C,
verify native input returns. Repeat separately over USB and Bluetooth.

If seizure succeeds but no contact packets arrive, explicitly test the existing
driver's initialization command in a fresh session:

```sh
"$PROBE" --seize --registry-id 123 --seconds 15 --initialize --output /tmp/amt-seized-init.jsonl
```

`--initialize` is opt-in and allowed only for exclusive capture. It sends feature
payload `02 01`, report ID `02` on USB or`F1` on Bluetooth, preserving the existing
driver's macOS keyhole convention. It is not a promise that the user-space API
exposes the same reports. The feature operation and close result are printed.
The probe sends no guessed mode-reset command when closing; restoration is an
explicit observation, and reconnecting may be needed if native operation fails.

For permission failures, record the exact return code, UID, transport and macOS
version. `--request-input-access` explicitly requests Input Monitoring; running
from Terminal may attribute privacy permission to the terminal application.
Permissions are never requested automatically. An explicitly administered
comparison under `sudo` can distinguish privilege-related failures, but root
does not waive TCC permission checks. No SIP, AMFI, Gatekeeper, or entitlement
enforcement changes are part of this experiment.

## Bounds and interpretation

- Duration defaults to 15 seconds, maximum 60. Timeout, Ctrl-C/SIGTERM and disconnect
  close the selected device; a POSIX alarm terminates a stalled capture process
  three seconds after the requested duration. OS process teardown releases its
  handles. Ctrl-Z is ignored during capture to prevent accidental suspension.
- Captures retain at most 4096 reports / 1 MiB of payload; additional reports are
  counted and marked dropped. JSONL is written after closing. New files are
  created exclusively with 0600 permissions; existing files/symlinks are refused.
- Framing recognizes USB `02` and Bluetooth `31`, with 9-byte contact records. It
  handles callback payloads with and without a leading report ID. Coordinates are
  raw signed sensor integers. This is a diagnostic parser, not the production
  calibrated decoder or proof that native input is suppressed.
- `OPEN=success` alone proves neither usable contacts nor takeover. A viable
  replacement needs all three: selected-pad suppression, continuing multi-contact
  reports, and reliable restoration. Then test reconnect, crash, sleep/wake,
  selected-device isolation, and Intel/Apple silicon before product integration.
- This first probe has no production sleep/session/watchdog service. Its existing
  timed lifetime limits ordinary tests; it is not a production ownership manager.

A working capture replacement remains **unverified**; recorded hardware observations
are below. Consult
[KARABINER.md](KARABINER.md) for the independent output-driver investigation.

## Native-contact coexistence diagnostic

The user's Bluetooth tests on both pads successfully stopped native movement,
with successful Open/Close return codes, but received zero raw-report callbacks.
The right-pad feature initialization also returned success while report counts
stayed zero. Neither result establishes native restoration after close; that must
still be observed. This rules out a packet-decoding explanation for those runs:
no raw callback was delivered in the first place.

To test a separate contact source while preserving user-space suppression:

```sh
sudo "$PROBE" --seize --registry-id 123 --seconds 15 --native-contacts
```

This is a **25-second manual test**: native contacts for 5 seconds before opening,
15 seconds seized, then 5 seconds after closing. Move several fingers on the
selected pad throughout all phases. The native monitor matches the selected
pad's serial and transport exactly; zero or multiple matches abort before HID
Open. No other native device is started, and no feature command is sent. The
custom driver must remain inactive and apps using the same contact stream closed.

`NATIVE frames` and `withContacts` are deltas within each named phase. The last
observed count and session maximum can be stale when callbacks stop; they are not
evidence of continuing delivery. A useful result requires positive before-open
contact counts, increasing contact counts while seized with native interference
suppressed, and successful restoration after close. Zero baseline counts makes
the coexistence result inconclusive. `--observe --native-contacts` is also
available to compare shared access. Initialization and native counting cannot be
combined, to keep this diagnostic separate from feature-mode changes.

Only the optional native-monitor flag invokes private contact APIs; inventory,
help and offline checks do not. The added bridge has static-lifetime atomic
counters so native callback threads never access a freed Swift context. This
coexistence path is **not yet hardware-tested**. Its use of private APIs carries
the same compatibility limits as the app's existing native capture backend.

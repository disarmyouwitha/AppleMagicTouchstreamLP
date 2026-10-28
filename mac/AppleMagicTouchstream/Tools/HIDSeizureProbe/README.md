# Standalone trackpad diagnostics

Production uses [selected-pad native FLTR](../../TRACKPAD_TAKEOVER.md). These
probes are independent historical diagnostics and are not part of release input.

## Offline checks

From `mac/AppleMagicTouchstream/`:

```sh
./Tools/HIDSeizureProbe/test.sh
./Tools/HIDSeizureProbe/build.sh
```

Output: `build/HIDSeizureProbe/HIDSeizureProbe.app`. Build/tests do not open or
activate hardware; default invocation and `--help` print help. These are command-line
probes. Build/signing details, flags and hardware observations remain in the
[archived full guide](../../../../../new_code/touchstream-archive/AppleMagicTouchstream-research-2026-10-26/notes/Tools/HIDSeizureProbe/README.md).

## Hardware boundaries

- Do not rerun the Bluetooth channel/enumeration experiment. The private channel
  accessor had connection side effects; listening/enumeration remains disabled.
  `run-bluetooth-test.sh` exits without opening a probe. See the
  [archived result](../../../../../new_code/touchstream-archive/AppleMagicTouchstream-research-2026-10-26/notes/Tools/HIDSeizureProbe/BLUETOOTH_TEST.md).
- Other live tests require an explicit intentional hardware session: release
  production takeover, quit trackpad apps and keep an independent keyboard/mouse.
  Use exactly one selected eligible device, with bounded timeout and observed
  restoration. Successful Open/Close alone proves neither contact delivery nor
  usable recovery. Re-list temporary registry IDs after reconnecting.
- Root does not bypass TCC. No SIP, AMFI, Gatekeeper or entitlement changes are
  part of these probes. Build validation must never request input permissions,
  perform seizure, send mode writes or start a native filter.
- The successful native FLTR path is documented in the current takeover contract.
  Earlier raw-HID seizure, GET_REPORT and reconnect observations are historical
  evidence, not a replacement production transport.

[Research index](../../../../../new_code/touchstream-archive/AppleMagicTouchstream-research-2026-10-26/README.md)
contains the original reports, procedure details and source evidence.

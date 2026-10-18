# Read-only notification transport probe

Build/run while GesturePad takeover is already active:

```sh
./run.sh 45 /tmp/GesturePad-notification-observer.json
```

Move fingers on the pads during the observation. No driver activation, seizure,
IOServiceOpen, property write, feature command, entitlement or app change occurs.
The tool registers public kIOGeneralInterest notifications on current raw receivers.
A250ms sequence-only poll independently confirms reports advanced; that poll is
not the proposed transport. No callback plus no report advancement is inconclusive.
A source disappearing/restarting invalidates this run's per-source count; repeat
without releasing, Syncing or power-cycling during the test.

This is not a CPU/latency benchmark. It measures whether the existing registry
publication generates notifications at all. The probe uses no UserClient entitlement.
The compiled observer lives in ignored build/. Maximum duration120seconds.

The2026-10-18 live run observed7,336 report advances across both currently attached
Bluetooth receivers and zero callbacks. See RewriteValidation/NOTIFICATION_TRANSPORT_RESULT.json.

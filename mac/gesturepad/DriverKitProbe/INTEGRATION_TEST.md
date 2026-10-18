# GesturePad DriverKit integration test — v0.7

Status: built and signed; **the integrated hardware path has not yet been tested**.
The earlier standalone USB/build3 and Bluetooth/build4 captures both succeeded.

## First live session

1. Run `/Applications/GesturePad.app`. Select left Bluetooth
   `D0:C0:50:D4:75:6C` and right USB `J84HMA00H0B0000501`. Both must be selected:
   the development extension contains exactly these two matching personalities.
   Other selections are refused before activation, rather than claiming control
   of an unselected pad. Keep a normal mouse connected.
2. Under the left trackpad selector, use
   **DriverKit Takeover**. Synthetic 2-finger pointer defaults on. Grant
   GesturePad Accessibility if requested, then retry the button.
3. The internal background service submits activation without opening another app window. If macOS asks, enable
   **AMT Raw HID Receiver** in General → Login Items & Extensions → Driver Extensions.
   Takeover remains active until Release Trackpads. A pending approval is not
   an active receiver. Do not click Activate again.
4. On each pad, try one finger, then two fingers, lift and repeat. Watch dots,
   contact pressure and the packet/synthetic-move counters. One finger should
   visualize without moving the cursor. Two fingers should visualize and move it.
   Native scrolling/pinch/swipes should be suppressed. This version synthesizes
   movement only: trackpad clicks/scroll/keyboard output are not implemented.
   Confirm the separate physical mouse still moves and clicks normally.
5. Try **Release Trackpads**, or existing global **Control–Option–R**, before timeout.
   There is no session timeout. macOS may require
   authentication to remove the driver. The internal service remains alive if GesturePad
   quits, and watches for owner-process exit. It does not quit while removal is pending.
6. Wait for **Driver removed** in GesturePad, then confirm normal native input has
   returned on both pads. That message verifies deregistration, not native-handler
   restoration. If still blocked, disable the receiver in Settings; reconnect USB
   or power-cycle Bluetooth if necessary. Report that as a restoration failure.

Config close, selection change, refresh, replay start, app quit and sleep request
release too. Do not deliberately stress all lifecycle paths in the first session:
first establish live contacts + suppression + movement + manual restoration.

## Evidence

GesturePad records aggregate JSON to
`/tmp/GesturePad-driverkit-session-<UUID>.json` at release and confirmed removal.
It includes per-pad packet/max-contact counts, stream gaps and synthetic moves.
Unified logs include the UUID, periodic counters and helper/driver events.
Regular Capture is fed by the same runtime ingestion/capture boundary; raw fields
have DriverKit semantics: pressure is the raw byte, size/axes are uncalibrated,
and anatomical finger telemetry is absent. Tracking IDs must not become finger labels.
An optional .atpcap recording can establish stream/replay behavior after the first
basic test; capture/replay on the hardware is not yet verified for this backend.

## Implementation boundary and limits

- Current development build is Intel/x86_64 and two exact tested serials only.
- Driver receives into a preallocated64-record ring (176bytes/record, payload up
  to148bytes). Report callback maps/copies/returns pool buffers; no logging or
  registry publication occurs inside it. A16ms serial timer publishes snapshots.
- App polls snapshots at16ms, deduplicates by per-driver session+sequence and
  resets movement on gaps/restarts/stale frames. Frames older than150ms are dropped.
  This registry bridge is a bounded development transport, not the final low-latency
  shared-memory IOUserClient implementation. No new IPC entitlement is required.
- Duplicate OMS contacts from these pads are gated until driver removal. Existing
  runtime rendering/capture is reused; replay remains output-free. Auto-resync is
  paused during takeover and restored from the existing setting afterward.
- USB sends the previously tested feature0201 once after2s. Bluetooth sends none.
- The driver runs continuously until removal/Stop, with no session deadline.
  Closing alone does not guarantee native handling returns. The helper explicitly
  requests extension removal and checks SystemExtensions properties afterward.
  Removal can need authorization or a reboot; the UI must not claim restoration early.
- Verification of continuous ownership, arbitrary selected-device matching, optimized IPC,
  app/driver crash and reconnect stress, deployment to other machines and public
  distribution remain follow-up work after this first integrated hardware result.
  The user explicitly requested removal of the earlier30s development cap.

## Rebuild / install

`./mac/gesturepad/build.sh` builds the normal GesturePad app. Then:

```sh
./mac/gesturepad/DriverKitProbe/install-integration.sh
```

The installer builds, signs with existing ignored development profiles, validates,
backs up previous installs, embeds the service and installs `GesturePad.app/Contents/Helpers/GesturePadDriverService.app`.
It refuses if a receiver is registered/awaiting approval (except a historical
terminated build pending reboot cleanup). It **does not activate** a driver.
The test is explicitly launched inside GesturePad. Existing app bundle ID,
menu shape, selector IDs and original nonseizing filter controls are preserved.

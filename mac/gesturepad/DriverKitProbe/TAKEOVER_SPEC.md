# Trackpad takeover lifecycle

Current direction, 2026-10-18 (v22): capture supported connected pads together.
Per-pad native handoff/retake has been removed at the user's request. This supersedes
v8–v21's selected-ownership experiments, including their UserClient requirement.

## Current behavior

- Takeover Trackpads activates the extension once. All matching connected Magic
  Trackpad2 model0324 interfaces are captured, regardless of Left/Right selections.
  Arbitrary serials are supported for the tested USB/Bluetooth model; other AMT
  generations need separate report/calibration validation.
- Zero, one or two Left/Right selections control visualization and synthetic output,
  not driver ownership. An unselected supported pad stays captured. Sync Trackpads
  updates those app routes without commands to the driver or extension cycling.
- Each receiver processes and drains independently. Losing Bluetooth must not
  interrupt USB. Replaced/reconnected streams wait for explicit Sync. Transport
  identity aliases and automatic native-driver reclaim are absent.
- A status-only coordinator indicates activation even with no connected pads.
  No NewUserClient implementation, handoff client, provider rematch cache or
  user-client command endpoint is compiled into the driver.
- Telemetry continues through bounded registry publication. Signing requests only
  DriverKit and HID transport for the driver, and system-extension.install for the
  embedded helper. Neither scoped userclient-access nor development
  allow-any-userclient-access is signed, even if the Apple profile authorizes it.
- Restart transfers the live helper session through the existing signed owner check,
  single-use nonce and bounded20s lease. Routing and unselected device inventory
  survive Restart. No activation/removal request is made for that transfer.
- Release Trackpads, actual Exit, owner death, sleep and replay retain full-release
  safeguards. Removal can require macOS authorization; restoration is not claimed
  before removal is confirmed. Release applies to every captured pad together.

## Validation

The user confirmed one-pad and zero-pad selections worked before this simplification.
The v21 Bluetooth power-cycle/Sync and unaffected USB behavior, telemetry parity and
warm Restart evidence remain in RewriteValidation. v22 changes ownership policy and
must be physically rechecked after installation; offline tests cannot establish it.

1. Enable Takeover Trackpads with both pads attached; both selected streams appear.
2. Select one or neither and Sync: supported pads remain captured; only selected
   streams visualize. Select both again and Sync: both visualizations resume.
3. Power Bluetooth off: USB stays captured and visualizes. Power it on and Sync:
   Bluetooth visualization returns without cycling the driver.
4. Restart from the app menu with zero/one/two selected: extension/helper remain,
   selections and the other captured pads' selector entries survive.
5. Release/Exit: all pads return to native input.

Build/install: `./DriverKitProbe/install-integration.sh` (no development-userclients
flag). Install does not activate the driver. DriverKit/HID development permissions
remain required for local signing; distribution approval/profiles are separate.
The pending UserClient Access request is no longer a runtime dependency.

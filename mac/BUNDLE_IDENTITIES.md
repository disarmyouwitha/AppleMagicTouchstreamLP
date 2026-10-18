# Permanent bundle identities

| Product | Bundle ID |
| --- | --- |
| GlassToKey | `ink.ranna.glasstokey` |
| AppleMagicTouchstream | `ink.ranna.applemagictouchstream` |
| GesturePad | `ink.ranna.gesturepad` |
| Shared takeover background service | `ink.ranna.trackpadtakeover` |
| Shared takeover DriverKit extension | `ink.ranna.trackpadtakeover.driver` |

Team: `N9XQZJR4EP`. App build/release identities live in each `project.env`
and Xcode project. Takeover deployment/signing identities live in
`gesturepad/DriverKitProbe/takeover-config.json`; regenerate its bindings with
`generate-config.py`. Exact owner verification currently authorizes GesturePad
only. Porting to another app requires explicitly configuring its owner identity;
settling shared names does not authorize multiple concurrent owners.

On their first launch under the permanent ID, AppleMagicTouchstream and GesturePad
copy their former preference domains (`ink.ranna.glasstokey.keyboard` and
`ink.ranna.glasstokey.gesturepad`) without replacing values in the new domains.
The old domains remain intact. Existing serialized keys, capture schemas, queue
labels, notification names and restart-transfer keys remain compatible.
The embedded OpenMultitouchSupportXCF framework retains its own existing identity.

## Signing and deployment transition

The old prototype driver ID was
`ink.ranna.glasstokey.gesturepad.rawhidprobe.driver`; its helper was the same
without `.driver`. Existing profiles for those IDs cannot sign the permanent IDs.
New explicit helper/driver profiles are required. The current code signs only
DriverKit + HID transport on the driver and system-extension.install on the
helper. No UserClient access or Allow Any UserClient entitlement is added.

Release the old extension before replacing the installed app. The installer
refuses installation while either old or new driver identity is registered and
not terminated. Changing IDs may require fresh macOS extension approval and
Accessibility/Input Monitoring approval; existing grants are identity-specific.
Do not delete the old IDs/profiles until the new signed installation passes a
physical takeover, Sync, restart and release test.

## Apple request correction

Pending UserClient request `TZ5M9X67Q9` was submitted with the old prototype
identities. It needs the permanent IDs above supplied to Apple before approval.
The Virtual HID request draft has been corrected and remains unsubmitted.
Historical capture/research documents retain the IDs actually used in those tests.

## Migration completed 2026-10-18

All five permanent App IDs are registered in Apple Developer. The driver has
DriverKit (development) and DriverKit Transport HID (development); the helper has
System Extension. Replacement profiles are downloaded, verified and installed
in the ignored DriverKitProbe/profiles folder, with the former profiles backed up.
Driver profile portal ID: `626XJXDMS8`; helper profile ID: `NKWTA82SMW`.
The signed app is installed at `/Applications/GesturePad.app`. Its only embedded
driver is `ink.ranna.trackpadtakeover.driver`; deep strict signature validation
passes. Hardware takeover under the new identity still needs user verification.

The installer now moves the old installed bundle aside instead of overlaying it,
and the driver build reconstructs the generated helper bundle before packaging.
This prevents stale old-ID extensions from surviving a bundle rename.

Apple still lists UserClient request `TZ5M9X67Q9` as **Submitted**, type **Team**.
Its Request History dialog exposes no amendment control. No request was cancelled
or resubmitted. Supply `USERCLIENT_REQUEST_ID_CORRECTION.txt` through the existing
Apple correspondence; ask whether they can amend it before cancelling/replacing
the pending request. The corrected Virtual HID draft remains unsubmitted.

# Permanent bundle identities

Current source/deployment map · 2026-10-18

| Product | Bundle ID |
| --- | --- |
| GlassToKey | `ink.ranna.glasstokey` |
| AppleMagicTouchstream | `ink.ranna.applemagictouchstream` |
| GesturePad | `ink.ranna.gesturepad` |
| Shared takeover background service | `ink.ranna.trackpadtakeover` |
| Shared takeover DriverKit extension | `ink.ranna.trackpadtakeover.driver` |

Team: `N9XQZJR4EP`. These five explicit App IDs are registered with Apple.
Keep this file as the cross-project signing map; configuration files, signed
entitlements and Apple-issued profiles are the authority for a particular build.

## Configuration and ownership

- Each app's `project.env` and Xcode project define its app bundle ID.
- GesturePad's [takeover manifest](gesturepad/DriverKitProbe/takeover-config.json)
  authorizes the exact signed owner `ink.ranna.gesturepad`.
- AppleMagicTouchstream's [takeover manifest](AppleMagicTouchstream/DriverKitProbe/takeover-config.json)
  authorizes the exact signed owner `ink.ranna.applemagictouchstream`.
- All three use the same permanent helper/driver IDs. Run that project's
  `DriverKitProbe/generate-config.py` after manifest edits; generated Swift bindings
  feed the app/helper and generated C++ bindings feed the driver build.
- **One owning app at a time.** Each packaged helper accepts its configured exact
  app identity and team, not both apps or a wildcard. Release and quit the owning
  app before switching to another app's takeover build. Shared names alone do not
  provide concurrent ownership or inter-app handoff.
- GlassToKey's [takeover manifest](GlassToKey/DriverKitProbe/takeover-config.json)
  authorizes the exact signed owner `ink.ranna.glasstokey`.

The helper filenames differ by project (`GesturePadDriverService.app`,
`AppleMagicTouchstreamDriverService.app`, and `GlassToKeyDriverService.app`); filenames are not bundle IDs. Existing
wire notification names and executable names are compatibility details.

## Signing and installation

Current takeover builds sign DriverKit + HID transport on the driver and
`system-extension.install` on the helper. **No UserClient Access, Allow Any
UserClient Access or Virtual HID entitlement is signed into these builds.**
Development capabilities/profiles do not establish distribution authorization.

Apple-issued replacement development profiles authorize the shared identities:
driver portal profile `626XJXDMS8`, helper profile `NKWTA82SMW`. Profiles live in
project-local ignored `DriverKitProbe/profiles/` directories. Existing certificates,
profile validity, device coverage and authorized entitlements must still be checked
when signing. Do not commit profiles or signing/notarization credentials.

Release the active extension before replacing its owning app. The installers check
the configured driver ID and refuse replacement while ownership/removal is pending.
Driver builds recreate the helper bundle; installers back up and replace the app
instead of merging stale embedded files. macOS may request fresh extension/Accessibility/Input
Monitoring approval after identity changes. Follow each project's takeover README
for installation and physical acceptance; a signed build is not a hardware pass.

## Settings compatibility

AppleMagicTouchstream migrates the former `ink.ranna.glasstokey.keyboard` preference
domain, and GesturePad migrates `ink.ranna.glasstokey.gesturepad`. Migration copies
missing values without replacing the new domain's settings and leaves old domains
intact. Serialized `GlassToKey.*` keys, capture formats and restart compatibility
keys are deliberately preserved. OpenMultitouchSupportXCF retains its own identity.
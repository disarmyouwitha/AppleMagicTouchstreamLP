# Permanent bundle identities

Current source/deployment map · 2026-10-19

| Product | Bundle ID |
| --- | --- |
| GlassToKey | `ink.ranna.glasstokey` |
| AppleMagicTouchstream | `ink.ranna.applemagictouchstream` |
| GesturePad | `ink.ranna.gesturepad` |
| Retired takeover background service | `ink.ranna.trackpadtakeover` |
| Retired takeover DriverKit extension | `ink.ranna.trackpadtakeover.driver` |

Team: `N9XQZJR4EP`. These five explicit App IDs are registered with Apple.
Keep this file as the cross-project signing map; configuration files, signed
entitlements and Apple-issued profiles are the authority for a particular build.

## Current configuration and signing

Each app's `project.env` and Xcode project define its app bundle ID.

On 2026-10-19 the user requested complete removal of the custom DriverKit takeover
implementation from GesturePad and AppleMagicTouchstream. Their helper/driver
source, manifests, configuration generator, embedding phases and driver-only app
code have been removed. Neither app now packages a helper or `.dext`. App build
scripts no longer generate DriverKit configuration. App entitlements remain free
of DriverKit/system-extension installation permissions.

The shared takeover App IDs above are retained here as historical identifiers;
this source cleanup did not delete Apple Developer account registrations or
change keychain certificates. Earlier portal profile IDs were `626XJXDMS8` (driver)
and `NKWTA82SMW` (helper). These are not current build dependencies. Do not commit
profiles or signing/notarization credentials.

GesturePad now provides continuous selected-pad native FLTR takeover, following
user-confirmed Bluetooth/USB tests, using Apple's existing multitouch driver
without installing our own extension. See
[TRACKPAD_TAKEOVER.md](gesturepad/TRACKPAD_TAKEOVER.md). As of 2026-10-20, AppleMagicTouchstream and GlassToKey also include independently
ported native FLTR takeover, using their existing native keyboard pipelines. Existing optional
raw-report capture provenance remains readable in both projects.

GlassToKey's earlier DriverKit takeover port is also absent from its app and release
pipeline; the original port is preserved in commit `fc117e2`. The apps' normal
Developer ID signing/notarization pipelines remain in place. A source removal or
successful build does not itself uninstall an already registered system extension;
macOS may finish an already-requested removal on reboot.

## Settings compatibility

AppleMagicTouchstream migrates the former `ink.ranna.glasstokey.keyboard` preference
domain, and GesturePad migrates `ink.ranna.glasstokey.gesturepad`. Migration copies
missing values without replacing the new domain's settings and leaves old domains
intact. Serialized `GlassToKey.*` keys, capture formats and restart compatibility
keys are deliberately preserved. OpenMultitouchSupportXCF retains its own identity.
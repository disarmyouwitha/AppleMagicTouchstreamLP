# Karabiner as an output backend

Research date: 2026-10-18. No Karabiner driver was installed or activated, and no
input events were generated during this investigation.

## Can its signed driver pass through to ours?

It can carry **our application's synthesized output** into macOS. It cannot lend
its entitlements to our custom driver, activate an unauthorized extension, or
serve as an arbitrary raw-trackpad-report tunnel to our driver. The available
client API initializes virtual keyboard/pointing devices and submits HID output
reports; it does not expose a general DriverKit authorization proxy.

A possible architecture that does not depend on approval of our own DriverKit
extension is:

```mermaid
flowchart LR
  P[Physical Magic Trackpad] --> S[Our user-space seizure and raw capture]
  S --> D[Our existing contact decoder and TouchStream engine]
  D --> B[Our signed privileged output bridge]
  B --> K[Upstream Karabiner daemon and signed virtual HID driver]
  K --> M[macOS keyboard and mouse input]
```

The unresolved prerequisite is the first arrow: suppression plus usable contacts
from our selected trackpad. Karabiner's virtual output cannot repair missing raw
contact input. Keeping Core Graphics output is also possible if user-space capture
works; adopting virtual output is a separate decision.

Upstream distinguishes its user-space physical-device grabber from its virtual
DriverKit output. Its development notes specifically warn that Apple Trackpads
do not supply ordinary IOKit HID-value events as other pointing devices do.
Our experiment deliberately measures raw-report callbacks and CompactV7 framing
instead of assuming HID element/value callbacks will provide contacts.
[Karabiner-Elements development notes](https://github.com/pqrs-org/Karabiner-Elements/blob/main/DEVELOPMENT.md)

## The supported external integration boundary

Use the standalone **Karabiner-DriverKit-VirtualHIDDevice** package, retaining its
original signatures and identities. Its daemon owns the entitled connection to
the driver. Our privileged bridge would use upstream's C++ client library and its
root-only Unix socket. The ordinary GUI should remain unprivileged; authenticate
GUI-to-bridge communication by exact signing requirement/team and console user,
accept only bounded keyboard/pointing operations, and reset held keys/buttons on
disconnect. Do not expose the privileged socket or a generic shell/report proxy
to untrusted clients.

Using that documented daemon client avoids our own direct DriverKit user-client
connection; it does not require adding our own UserClient Access entitlement just
to connect to the socket. This remains an integration to build and validate, not
an already-tested backend in AppleMagicTouchstream.

Upstream requires administrator installation, normal extension approval and a
root client. Client headers must match the daemon protocol. We would pin/test an
upstream release, detect missing/incompatible components, install/start the service
through a deliberate administrator flow, and provide clean uninstall/recovery.
Prefer this standalone boundary over depending on the full Karabiner-Elements
Core-Service XPC APIs, which restrict peer signing identities.
[Standalone integration documentation](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/blob/main/README.md)

The pinned 8.6.0 example calls keyboard/pointing initialize, waits for readiness,
and uses typed `async_post_report` operations. It supports multiple clients.
Keyboard down/up/reset, modifiers, repeat, button transitions, relative motion,
scrolling and all-up on process loss would need explicit acceptance tests. Virtual
HID output is not a promise of login/FileVault, protected-screen, game, or every
special-key behavior without testing.
[Upstream client example](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/blob/v8.6.0/examples/virtual-hid-device-service-client/src/main.cpp)
[Client library](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/blob/v8.6.0/include/pqrs/karabiner/driverkit/virtual_hid_device_service/client.hpp)

## Binary verification and licensing

The official 8.6.0 release installer was downloaded to`/tmp` and inspected without
installation. `pkgutil --check-signature` reported Developer ID Installer signing
by Fumihiko Takayama, team`G43BCU2T37`, trusted notarization and a secure timestamp.
`spctl --assess --type install` accepted it as Notarized Developer ID. Expanded
manager/daemon/driver binaries contain arm64 and x86_64 slices. The daemon has
UserClient Access to its own upstream driver; that authorization stays with the
upstream daemon. This verifies the package, not runtime behavior on our hardware.
[Inspected release](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/tag/v8.6.0)

The repository's top-level license is the Unlicense/public-domain dedication.
However, the inspected C++ client header explicitly declares the **Boost Software
License 1.0**, and vendored dependencies carry their own licenses. Preserve those
notices when shipping the bridge; do not treat the top-level license as the only
license. Keep upstream installer binaries unmodified; modifying/re-signing the
driver would return us to needing our own approved DriverKit signing setup.
[Top-level license](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/blob/main/LICENSE.md)
[Boost Software License](https://www.boost.org/LICENSE_1_0.txt)

## Recommendation

First establish the user-space capture feasibility result with this probe. If it
works over both transports, route its canonical raw reports through the existing
decoder/engine in a later, reviewed integration. Keep the custom DriverKit backend
intact as a separate option. Add Karabiner output only if we want true virtual
devices and accept the external installer/privileged-service dependency. No public
release claim should depend on an untested capture path.

Apple documents user-space exclusive HID access through
[`IOHIDDeviceOpen`](https://developer.apple.com/documentation/iokit/1588670-iohiddeviceopen).
That API contract alone does not establish compatibility with Apple's proprietary
trackpad report path; the probe must provide that evidence.

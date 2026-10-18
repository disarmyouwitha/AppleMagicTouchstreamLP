# Event-driven transport investigation —2026-10-18

Goal: improve report delivery efficiency/latency without custom DriverKit UserClient
Access, before porting. Production code, signing and permissions remain unchanged.

## Verified current-public-API result

Tools/TransportNotifications is a standalone read-only public general-interest
observer. During45s, the existing two receivers advanced3,690 and3,646 reports,
with zero general-interest or property-change messages. Both pads were Bluetooth
in this run. This disproves relying on current SetProperties publication alone to
wake the app. It does not measure CPU use or report-to-app latency, and does not
prove every possible IOKit notification mechanism impossible. Saved JSON is
NOTIFICATION_TRANSPORT_RESULT.json. The initial idle run had no advancing reports
and is not used as active-frame evidence.

The installed public DriverKit SDK gates SendIOMessageServicePropertyChange behind
PRIVATE_WIFI_ONLY. Apple's kernel implementation has the same restriction. Do not
expose private declarations or call private RPC IDs as a shipping transport.
IOServiceAddInterestNotification is public on the app side, but observing messages
does not cause SetProperties to emit them.

Sources:
- https://developer.apple.com/documentation/iokit/1514866-ioserviceaddinterestnotification
- https://github.com/apple-oss-distributions/xnu/blob/main/iokit/DriverKit/IOService.iig
- https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/IOUserServer.cpp

## Routes

###1. Improve the existing transport without new permissions

Use IOServiceAddMatchingNotification for receiver appearance/removal and cache
service handles, avoiding full IORegistry discovery every16ms. Arrival of a new
source must not implicitly accept replacement frames: existing explicit Sync
semantics remain unchanged.

Publish changing data only when reports/state change, keep static metadata out of
repeated payloads, and check sequence before reading unchanged rings. Keep the
bounded ring, generation/sequence validation and explicit gap handling. A suitably
measured active/idle polling strategy can then reduce redundant work. These changes
still poll for contact data; they are not an OMS-like callback transport. Shorter
poll intervals alone reduce delay at the cost of more work.

This is the strongest immediate route using exactly the current permissions.
Before implementation, record receive-to-consumer latency percentiles, batches,
idle/active wakeups, CPU and gaps for both transports. Capture timestamps currently
preserve report timing; they do not directly measure processing latency.

###2. Public vendor-defined HID report relay — promising, not yet validated

A driver-side IOUserHIDDevice provider could publish a data-only, vendor-defined
HID collection. Send one compact contact record per report using handleReport;
consume via IOHIDDeviceRegisterInputReportCallback in the app. This uses the system
HID client path, not a custom DriverKit UserClient. Use no keyboard, pointer or
consumer-control usages; the relay must produce no native UI actions.

Potential advantages: callback-driven delivery, no idle contact polling and no
full64-record registry copy on each poll. This still crosses OS/HID queues and
copies data; efficiency/latency must be measured, not assumed equal to OMS.

It requires additional HID device-family authorization/provisioning. The existing
Apple-issued driver profile has no com.apple.developer.driverkit.family.hid.device.
Apple also documents com.apple.developer.driverkit.family.hid.virtual.device as a
requested entitlement; applicability to this topology/OS must be checked rather
than assuming the device-family checkbox alone grants permission. No capability
was enabled, request submitted, profile regenerated or relay installed here.
This avoids the pending UserClient entitlement but may introduce another approval
requirement. App Input Monitoring requirements also need live validation.

Sources:
- https://developer.apple.com/documentation/hiddriverkit/iohiddevice
- https://developer.apple.com/documentation/hiddriverkit/iouserhiddevice
- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.driverkit.family.hid.device
- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.driverkit.family.hid.virtual.device
- https://developer.apple.com/documentation/iokit/1588666-iohiddeviceregisterinputreportca

###3. Other notification/shared-memory approaches

IODataQueueDispatchSource has producer/consumer notification support, but no public
app bootstrap for mapping this driver's memory and registering its callback was
established without a custom client. DriverKit's service/system-state notification
sources are not a general app message bus. App-style Foundation notifications/XPC
must not be presumed available from the restricted DriverKit runtime. These are
not established alternatives for the current permissions.

Do not repeatedly call RegisterService/rematch hardware per packet merely to force
matching notifications: that invokes driver matching machinery, not lightweight
report delivery, and works against the efficiency/ownership goals.

## Recommendation

First implement/measure current-permission discovery caching and change-only
publication. In parallel, evaluate whether the HID relay's additional approved
permissions are obtainable without a new review. Keep the working transport as
fallback until a replacement proves loss-free report delivery, bounded latency,
independent pads, Sync, warm Restart and explicit Release/Exit. No UserClient
permission is part of the proposed immediate optimization.

## Portal eligibility checked2026-10-18

On the existing driver App ID's Capability Requests tab, HID Virtual Device
(development) is **Assigned** to the team; the ordinary HID Virtual Device row is
**No Requests** and links to the entitlement request form. The capability tooltip
identifies the development key as `com.apple.developer.hid.virtual.device`.
Its checkbox is currently OFF on the driver App ID. DriverKit Family HID Device
(development), key `com.apple.developer.driverkit.family.hid.device`, is also
available as an unchecked development capability. The existing profile grants
neither key. Availability is not an enabled/signed permission or a successful relay.

The System Extension request form has a Virtual HID option. A1738-character draft
was prepared describing both shipping apps, the data-only DriverKit HID relay,
and asking which of the HID-family/virtual-HID permissions applies. It references
pending UserClient request TZ5M9X67Q9 only to distinguish this separate route.
**Not submitted; no new request ID; no capabilities/profiles changed.**

Development-only prototyping may therefore be possible without waiting for a new
review, after explicitly enabling the development capabilities and regenerating
the driver development profile. Whether DriverKit's separate family.hid.virtual.device
permission is additionally required by this topology remains unproven. Distribution
approval remains separate; do not equate assigned development access with shipping
authorization. Prepared form stays open for user review.

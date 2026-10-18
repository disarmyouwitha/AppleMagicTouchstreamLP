# Seamless native handback on Exit — investigation2026-10-18

Goal: return every captured pad to Apple's native handler on Exit without an
administrator password. Keep v22's all-pads ownership policy and avoid reintroducing
per-pad selectors/retake logic.

## Established evidence

- v22 Release/Exit submits a system-extension deactivation request. The user reports
  an administrator password is required. That is extension removal authorization,
  not a touch-parser or ordinary HID Close permission.
- DEVICE_HANDOFF_V12_RESULT.json physically established Bluetooth native movement
  returning while USB remained controlled. That experiment used an authorized
  UserClient to close/terminate the receiver and request provider matching. It is
  not evidence of seamless handback without a UserClient or successful USB handback.
- v22 intentionally compiles no UserClient. Registry telemetry is readable, but this
  does not provide an app-to-driver release command channel.

## Public API findings

Apple documents RemovableSystemExtensions as allowing application deactivation
without administrator authorization. Its System Extensions policy payload requires
user-approved MDM. This is useful for managed fleets, not a general consumer fix.
https://developer.apple.com/documentation/devicemanagement/systemextensions
https://support.apple.com/guide/deployment/depa5fb8376f/web

The SDK's IOService::SetProperties is a driver-to-service RPC and must not be
mistaken for an app-to-driver command endpoint. The SDK places UserSetProperties
behind PRIVATE_WIFI_ONLY. Apple's public IOUserServer implementation supplies no
public forwarding endpoint for an arbitrary app property command. Do not invent
an unsupported public override or claim reading IORegistry implies write/control.
https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/IOUserServer.cpp

A standalone, inert property probe was prepared in /tmp/amt-property-probe.swift.
It found no active v22 coordinator and sent no property write. Therefore no live
write-path result exists; do not describe it as a tested permission denial.

## Practical direction and unresolved checks

The most direct supported architecture is keep the extension installed and use an
entitled, authenticated control channel to hand every receiver back together on
Exit. This does not require restoring per-pad selection or retake features. It
would bring back the pending scoped UserClient Access entitlement dependency.
Both USB and Bluetooth native restoration and subsequent acquisition would need
physical validation. Do not claim this is implemented or seamless yet.

No supported password-free handback using only v22's current permissions was
established in this investigation. Preserve working v22; no driver build, identity,
signing entitlement or release behavior was changed for this research.

## Replacement entitlement request

User confirmed original GesturePad request P6HGP368G8 was cancelled. A replacement
request was submitted and Apple displayed confirmation on2026-10-18:
**TZ5M9X67Q9**. Submission is not approval.

The replacement explicitly names both intended shipping apps:
- GlassToKey: `ink.ranna.glasstokey`
- AppleMagicTouchstream: `ink.ranna.glasstokey.keyboard`

Requested only scoped UserClient Access, describing native handback as optional,
with current takeover + authorized extension removal retained as fallback. The
form's UserClient Bundle IDs field asks for the target DRIVER extension, so it
contains the existing `ink.ranna.glasstokey.gesturepad.rawhidprobe.driver`. The app
description explains that GesturePad is a research app, production driver/helper
identity is not finalized, and asks Apple how to authorize both shipping products.
No App ID capability or provisioning profile was changed; no runtime code changed.

Product URL: https://github.com/disarmyouwitha/AppleMagicTouchstreamLP
Confirmation screenshot: USERCLIENT_REQUEST_TZ5M9X67Q9.png

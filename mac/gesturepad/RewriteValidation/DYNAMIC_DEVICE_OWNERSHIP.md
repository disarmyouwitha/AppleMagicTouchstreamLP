# Dynamic device ownership: required product behavior

## Why v7 has a two-pad constraint

DriverKitProbe/package.py publishes two static IOKit personalities containing the
research pads' exact serial numbers. AMTRawHIDReceiver::Start also checks those
serials, then immediately opens every matching interface. App selection only
chooses streams to consume; it does not change kernel driver matching. Ignoring
an unselected stream cannot restore native behavior.

This is a research restriction, not the desired product behavior. Do not broaden
matching to all Magic Trackpads until unselected devices have a proven native
ownership path. Never label dropped reports as native passthrough.

## Required behavior

- Zero selected devices is valid: native input, no takeover request.
- One or two selected devices is valid even with other pads connected.
- Selection changes apply to individual devices, without routine extension
  installation/removal or repeated approval dialogs.
- Identify supported model/report formats and transports, not personal serials.
  Runtime registry identity distinguishes individual connected instances.
- Unsupported models remain native until their protocol/calibration is validated.
- Preserve normal native gestures on unselected pads. Reimplementing a pointer
  does not count as restoring Apple's native touch/gesture path.
- Release, process loss, sleep and disconnect retain explicit recovery semantics.

## Next experiment: independent native handoff

Keep the current known-device matching for the experiment. Add an authenticated
app/driver control channel and independent per-instance lifecycle state. Investigate
whether releasing/terminating one receiver and requesting device rematching can
restore Apple's native handler without removing the whole system extension or
immediately matching our own receiver again. A control channel alone is not proof
that matching can be made selective. IOHIDInterface::Close only documents stopping
callbacks; our earlier work did not establish native restoration from Close alone.

Pass criteria with two connected pads:
1. Take over A while B retains native pointer, click, scroll and gestures.
2. Change selection to B: A becomes native and B supplies full raw telemetry.
3. Clear selection: both become native; extension remains enabled.
4. Repeat, disconnect/reconnect and terminate the app; no stuck pad or mixed sources.

Do not broaden personalities before these ownership transitions are proven.
If public per-instance handoff cannot preserve the native service, report that
limitation before choosing a different architecture. Continuous ownership with
synthetic event output can switch interpretations dynamically, but is not native
passthrough and must not be substituted without an explicit product decision.

## Distribution is a separate validation gate

Remove serial checks only after selective ownership works. Expand model/transport
coverage with report descriptors and surface calibration, including hardware
revisions not tested here. Distribution signing, notarization and any required
DriverKit entitlement approval also need validation. Current development profiles
and successful testing on two pads do not prove universal device compatibility.

References:
- https://developer.apple.com/documentation/systemextensions/installing-system-extensions-and-drivers
- https://developer.apple.com/documentation/hiddriverkit/iohidinterface
- https://developer.apple.com/documentation/hiddriverkit/iohideventservice

## Implemented v8 handoff test — 2026-10-18

This is executable instrumentation, not a completed dynamic-selection feature.
The embedded signed service now has `--handoff SERIAL close|reopen|terminate|status`.
It opens an IOUserClient on exactly one matching build8 receiver, validates command
shape, and logs IOReturn values and both receivers' states. The driver checks the
client's exact signed helper application identity. No allow-any-client entitlement
or security-setting bypass was added. The existing profile does not include
userclient-access; if macOS denies the same-team unsandboxed connection, that denial
will be captured and profile provisioning must be addressed before hardware claims.

The receiver command executes on its dispatch queue. Close stops reports from only
that interface without canceling the callback action, allowing explicit reopen.
Terminate first closes, then calls IOService::Terminate(0); it records the result
rather than assuming matched services support termination. The app recognizes the
explicit handoff flag, clears that pad's visible contacts and OMS gate, resets
synthesis/velocity baselines, and retains monitoring/ownership of the other pad.
The helper watchdog still removes the extension on owner-process loss, but does
not remove everything merely because this experiment deliberately closed a pad.
Global Release still requests full extension removal as the recovery path.

Tools/DeviceHandoff/run-handoff.sh left close
Tools/DeviceHandoff/run-handoff.sh left reopen
Tools/DeviceHandoff/run-handoff.sh left terminate

The terminate wrapper always performs Close first and waits for observation so
app/watchdog can recognize deliberate closure before the receiver disappears.
Before/after read-only registry evidence includes Apple native multitouch service
instances and both receiver counters. Logs go to a unique /tmp/GesturePad-handoff-*
folder. No driver activation occurs from the wrapper; takeover must already be
explicitly enabled by the user in GesturePad. Unknown serials/actions are refused.

Build/sign/install succeeded; app tests69/69 pass. Read-only native baseline and
inactive command/error handling were exercised. Pending physical test: enable
v8 takeover, then close left only and verify its native pointer/click/scroll/gesture
behavior while right continues raw delivery. If Close alone is insufficient,
compare Terminate and native service creation. Never infer native restoration
from a successful return value or the disappearance of our receiver alone.

### First live command result: provisioning blocker

At 2026-10-18 14:48:08 UTC both build8 receivers were open. A close command targeted
serial D0:C0:50:D4:75:6C by identity (physical positions were swapped). IOServiceOpen
returned 0xe00002e2 / kIOReturnNotPermitted before ExternalMethod. Kernel log:
`UC failed userclient-access check, needed bundle ID ink.ranna.glasstokey.gesturepad.rawhidprobe.driver`.
Neither receiver changed; this was not a Close failure or native-handoff result.
Evidence: /tmp/GesturePad-handoff-1jek07gg, plus kernel unified log at that time.

Host.entitlements/package.py now request exactly that userclient-access entry.
sign.py validates the profile permits it and refuses signing before modifying
bundles if missing; previously signing only requested the install entitlement.
A refreshed host provisioning profile is required. Driver profile needs no new
capability for same-team clients. Browser inventory reported local browser use
disabled in Work settings, preventing account setup from this session.

Developer portal target App ID:
ink.ranna.glasstokey.gesturepad.rawhidprobe (host, not .driver)
Capability/entitlement: com.apple.developer.driverkit.userclient-access
Array entry: ink.ranna.glasstokey.gesturepad.rawhidprobe.driver
Save regenerated macOS development profile to DriverKitProbe/profiles/host.provisionprofile.
Then release the current extension, rerun install-integration.sh, enable takeover,
and repeat the same identity-targeted close test. No security bypass is required.

## Authorized development path and later integration

User authorized development permissions to complete ownership work, then integration
into AppleMagicTouchstream and GlassToKey after validation, with permanent helper/
driver identity and any additional provisioning requests settled at that stage.
The driver App ID exposes unchecked "DriverKit Allow Any UserClient (development)".
Browser policy requires action-time confirmation for changing that security-sensitive
capability; the exact confirmation is pending. No portal changes have been saved.

Explicit --development-userclients signing/install mode now requires the matching
Apple-issued driver profile capability and debugging-enabled development profile;
the default continues to require scoped host userclient-access. Do not silently
fall back to broader access or distribution use. Fixed a signing identity-key
collision in the scoped profile path; six signing validation tests pass. Both
receiving apps have compatible RuntimeRawFrame/runtime boundaries, but no sibling
source has been changed before per-device native restoration is proven.

### Development permission enabled and installed (v9)

User explicitly confirmed the development capability change. Enabled "DriverKit
Allow Any UserClient (development)" on the existing driver App ID, saved and
regenerated GesturePad Raw HID Receiver Development. Downloaded profile was
verified for team, HID transport and allow-any-userclient-access, then copied to
ignored profiles/driver.provisionprofile with a local backup of its predecessor.
No new host capability or security-setting bypass was used. Scoped production
UserClient Access request P6HGP368G8 remains separately pending Apple review.

Released v8 through its managed helper before replacing files. Built/signed and
installed v9 with install-integration.sh --development-userclients. Deep strict
signature verification passed; installed driver signature includes the development
allow-any-userclient-access entitlement. Exact signed helper identity validation
in AMTHandoffClient::Start remains mandatory. Six signing tests and 69 app tests
pass. App reopened from /Applications, takeover off. Next dependency: explicit
live activation, then repeat close for serial D0:C0:50:D4:75:6C, watching both
receiver/native service states before asking for physical behavior confirmation.

Driver functionality must pass independent native handoff before porting it to
AppleMagicTouchstream/GlassToKey and settling permanent bundle identifiers. This
scope is authorized; it is not completed by this development provisioning step.

### v9 first successful per-device Close — 2026-10-18 15:23:19 UTC

Development provisioning resolved the command-channel denial: IOServiceOpen=0,
Close command=0. Bluetooth D0:C0:50:D4:75:6C changed StreamOpened1→0 and
StreamHandoffRequested0→1, sequence3801. USB J84HMA00H0B0000501 stayed open,
sequence910. Extension0.9/9 remained enabled/active. No native Bluetooth
multitouch handler appeared in the immediate registry snapshot. Physical behavior
confirmation requested before testing Terminate. Evidence:
/tmp/GesturePad-handoff-CRr5g8gV/{before,command,after}.json.
This proves independent interface closure, not native handoff or completed selection.

### v9 termination result and v10 watchdog correction

Close alone did not restore Bluetooth native input (user confirmed). Bluetooth-only
Terminate returned0 and its receiver disappeared while USB initially remained open.
However the helper still had a second hard-coded `count < 2` watchdog branch;
it requested full extension removal at 2026-10-18 15:24:13 UTC. Both native
handlers reappeared after full removal at15:24:18, consistent with the user's
report that both pads released. This is NOT independent native restoration.
Evidence /tmp/GesturePad-handoff-EkU5RlZ7 and unified logs at those times.

v10 replaces the count assumption with ReceiverWatchdog per-serial observed and
intentional-handoff sets. Reopening reinstates unexpected-loss protection. Regression
checks cover one pad, zero pads, deliberate close/disappearance, unexpected
closure/loss and reopening. Owner-process watchdog/global Release remain. Driver
and app rebuilt/signed/installed, strict deep signatures pass. App reopened with
takeover off; repeat termination after explicit live activation is pending.

### v10 independent termination and v11 rematch experiment

At 2026-10-18 15:27:48 UTC Bluetooth Terminate returned0 and only its receiver
vanished. Extension0.10 remained active and USB remained open; USB reports later
increased0→296. No native Bluetooth handler appeared. Public userspace
IOServiceRequestProbe on the exact released interface returned0xe00002c7
(kIOReturnUnsupported). No completed physical native-behavior result: the user
had not finished the check before we initiated full release to update the build.
Do not interpret their later "both released" as failure of the fixed v10 watchdog;
that was our explicit managed release preceding v11 installation.
Evidence /tmp/GesturePad-handoff-HBjeyR5v and
/tmp/GesturePad-v10-terminated-stable.json.

v11 adds a driver-side rematch command through the surviving receiver. Terminate
records a native-handoff gate and retains the exact released provider in a bounded
per-process two-slot table. Rematch calls RegisterService on that provider; new
receiver Starts decline gated pads, so the experiment can test fallback to Apple's
native handler rather than immediately opening the same pad again. A lock protects
provider lifetime; acquire/release atomics protect cross-instance gating. No report
callback allocations/locks or broad matching changes were introduced.
The state is process-local; shared-server lifetime and Apple native fallback remain
to be tested. This is not a completed zero/one/two dynamic-selection implementation.

Tools/DeviceHandoff/run-handoff.sh left terminate
Tools/DeviceHandoff/run-handoff.sh left rematch

The rematch operation targets Bluetooth identity via the surviving USB receiver;
for right rematch, it targets USB via Bluetooth. It refuses when no surviving
receiver exists, retaining the full Release recovery path. v11 signed/installed,
69 app tests pass, deep strict signature verification passes; app reopened with
takeover off. Hold the next live state for physical feedback before full release.

### v11 result and v12 process/lifetime corrections

v11 Bluetooth-only termination succeeded; USB stayed open and delivered137 reports.
The following rematch returned0xe00002f0/NotFound. Native Bluetooth input did not
return (user confirmed; USB visualized). Evidence /tmp/GesturePad-handoff-ZjIUGEG5
and /tmp/GesturePad-handoff-l2j4E3f3. Two AMTRawHIDReceiver processes were running:
IOUserServerName alone does not select shared-process mode. Apple's documented
IOUserServerOneProcess key must be true in both personalities. v12 now sets it.
https://developer.apple.com/documentation/bundleresources/information-property-list/iokitpersonalities

Full release of v11 then stalled after system-extension request completed: only
Bluetooth's process28284 remained under _driverkit, holding the intentionally
retained provider proxy. User was asked to run sudo kill -TERM28284 for this exact
already-uninstalling process; current shell's direct SIGTERM was denied. No SIP or
security policy change is requested. v12 counts successfully started receivers and
releases cached provider proxies on the last Stop before acknowledging it, so a
single-process handoff can retain the released provider while another receiver is
active, but full release does not retain those RPC references indefinitely.
New diagnostics expose the native gate mask and rematch provider registryID to
distinguish missing process-local state from kernel RegisterService rejection.
Build/sign succeeds; installation waits for the old v11 process to finish removal.

User terminated the exact stalled v11 process; verified it exited and extension11
was removed. v12 installed via --development-userclients; strict deep signatures
and both installed IOUserServerOneProcess flags verified. GesturePad reopened with
takeover off. Waiting for live activation before inspecting process count and
repeating Bluetooth-only terminate + rematch. Old process cleanup is complete.

### v12 native reattachment observed — 2026-10-18 15:39:36 UTC

Verified one AMTRawHIDReceiver process before both-pad test. Bluetooth termination
returned0; surviving USB receiver's gate mask became2, proving the native gate
survived within the shared process. Bluetooth rematch via USB returned0 with exact
provider registryID4294969929. Kernel logged the gated receiver declining usb=0.
AppleMultitouchTrackpadHIDEventDriver4294983332 and AppleMultitouchDevice4294983336
then appeared under Bluetooth. USB receiver4294983278 stayed open with reports
increasing140→170. Extension0.12 stayed enabled/active. Physical check requested;
hold this live state until the user replies. Saved DEVICE_HANDOFF_V12_RESULT.json.
This is successful per-pad native driver reattachment; do not claim full physical
input/gesture success, reverse retake, zero-pad persistence, or general-device
support until separately validated.

### v13 continuation after credit interruption

User physically confirmed v12 Bluetooth native input works while USB remains
controlled; Bluetooth contact display was absent. v13 adds throttled native-service
registry discovery and OMS callback refresh after handoff (without restarting
DriverKit ingestion), plus a retake command that clears the selected native gate
and calls RegisterService to test replacement of the reattached Apple handler.
The app clears old per-serial service/cursor state on deliberate retake so a new
receiver instance is treated as an expected generation change. Reverse takeover
is experimental, not yet physically validated.

v13 app build and69 tests pass; driver built and signed. Full managed v12 removal
was accepted but stalled with process29264 under _driverkit. User was asked to
terminate that exact already-uninstalling process. v13 additionally cancels the
report callback action even when a deliberately closed receiver's Finish path is
skipped, and drops stopped receiver timer/action/interface proxies before Stop
completion. Validate full cleanup in the next live test; do not claim it fixed
solely from compilation. Installation remains pending old-process exit.

User killed stalled v12 process29264; verified process exited and v12 extension
removed. v13 installed successfully with development-userclients mode. Strict deep
code signature and installed helper build13 verified; app reopened, takeover off.
Next physical test requires explicit activation, then Bluetooth terminate/rematch,
check native contacts refresh, and retake while USB remains controlled. Full-release
process cleanup also remains a live verification item.

### v13 teardown crash; v14 candidate correction

Live terminate at15:49:01 UTC caused an EXC_BAD_ACCESS address0x8 in DriverKit
on a libdispatch teardown path. The driver process crashed, macOS restarted USB,
and app source-generation protection requested full removal; both pads restored.
No valid rematch/native-contact/reverse-takeover test occurred in v13. Evidence
/tmp/GesturePad-handoff-5Tl0vyPB and /tmp/GesturePad-handoff-0eec06fJ;
crash /Library/Logs/DiagnosticReports/AMTRawHIDReceiver-2026-10-18-104901.ips.

Suspected regression: v13 released timer/action/provider objects immediately after
asynchronous Cancel calls while DriverKit was still dispatching teardown. v14
removes those premature releases, preserving ownership until free(), while still
canceling the report action for a deliberately closed receiver (the leak-prone
path formerly bypassed Finish). This is a candidate correction, not proven by
unit tests. v14 rebuilt, signed, installed; app tests69 pass, deep strict signatures
pass, app reopened takeover off. No stuck-process admin intervention was needed
after v13 recovery. Retest forward handoff before reverse takeover; validate final
uninstall cleanup afterward. Preserve v12's physically confirmed forward success.

### v14 forward handoff observed

At15:53:36 UTC Bluetooth termination returned0; USB stayed open and shared native
gate mask2 persisted. Rematch15:53:46 returned0 and native Bluetooth services
AppleMultitouchTrackpadHIDEventDriver4294983928/AppleMultitouchDevice4294983932
reattached. App attached two native user clients, consistent with its new listener
refresh. Extension0.14 remains active, no teardown crash observed. User asked to
confirm native behavior and contact visibility before reverse takeover. Evidence
/tmp/GesturePad-handoff-4R64c0uG and /tmp/GesturePad-handoff-vz7lxh9i.

### v14 physical confirmation and reverse-retake limitation

User confirmed Bluetooth native input AND contacts both work while USB remains
controlled. This validates the OMS listener refresh and forward native handoff.
Reverse `left retake` at15:54:45 UTC returned0/RegisterService accepted, gate2→0,
but no Bluetooth receiver appeared: the same native handler4294983928 remained
attached. USB stayed open and reports494. Thus RegisterService success does not
prove displacement of an already attached native handler. Evidence:
/tmp/GesturePad-handoff-7W5m2sEu. Do not label reverse retake complete.

Next bounded physical experiment: power-cycle only Bluetooth now that its gate is
cleared, leaving USB and extension active. Fresh provider matching should let our
receiver compete again, but this requires validation and is a reconnect fallback,
not seamless arbitrary selection. Avoid internal IOCatalogue-wide termination
or terminating unrelated native handlers as a shortcut. Native→takeover without
reconnect or extension replacement remains unresolved.

### v14 reconnect and full-release results; v15 Bluetooth initialization

User power-cycled Bluetooth after reverse-retake gate cleared. A new Bluetooth
receiver4294984066 opened under the still-active extension, while USB4294983850
stayed open with616 reports. Bluetooth delivered1089 callbacks, all rejected by
contact-format validation, sequence0, mappingErrors0. Thus ownership on reconnect
worked, but telemetry did not; do not count it as completed reconnect support.
The device likely returned to a non-multitouch report mode before Apple's native
handler could initialize it. v15 records first input report ID/bytes and mode
result, and sends the exact Linux Magic Trackpad2 Bluetooth featureF1 02 01 once
after2s only if no valid contact report has arrived. Existing USB0201 behavior and
exact tested-model guards remain; no invented reverse command or repeated writes.
Primary protocol reference: linux/drivers/hid/hid-magicmouse.c,
magicmouse_enable_multitouch, feature_mt_trackpad2_bt.
https://github.com/torvalds/linux/blob/master/drivers/hid/hid-magicmouse.c

v14 full managed release removed extension successfully without a stuck process or
administrator kill. This is the first live confirmation of the revised callback
cancellation/cleanup path after forward handoff and reconnect. v15 next tests:
initial delivery, Bluetooth power-cycle during takeover, valid contact bytes and
native telemetry, then explicit release restoration. Seamless reverse retake and
zero-pad persistent control remain unresolved; sibling integration not started.

### v15 reconnect safeguard regression; v16 per-pad disconnect waiting

User restarted Bluetooth directly while it was actively controlled, unlike the
previous test where it had first been deliberately handed to native. App's
receiver-disappearance check released the session at10:59:26 local; removal prompt
then disabled both pads. This does NOT test the Bluetooth mode command after
reconnect. The earlier request to restart immediately missed this safeguard path.

v16 distinguishes physical disconnection from receiver failure using current
IOHIDDevice serial inventory in the app and helper. Missing/closing receivers for
physically absent pads clear their contacts and wait for fresh matching; the
other pad and extension stay active. Reconnected receivers get new stream/service
baselines. Receiver loss while the device remains physically connected still
triggers full recovery. Inventory errors conservatively assume known devices are
connected rather than mistaking lookup failure for disconnect. Watchdog regression
checks cover physical absence, delayed receiver return, returning opened receiver,
subsequent crash, zero connected pads and closing-before-disappearance.
App69 tests and standalone watchdog tests pass. Live reconnect behavior is pending;
no claim of completed zero-pad persistent ownership or arbitrary-device support.

## User scope change: manual selector sync, v17

User explicitly rejected further automatic reconnect development. Desired workflow:
verify Left/Right selectors and click DriverKit Takeover again. A disconnect must
not emergency-disable the whole extension. This supersedes v16 inventory-based
reconnect/recovery rules above; do not keep expanding automatic reconnect handling.

v17 removes helper receiver-count/loss/presence checks and their initial no-match
removal timeout. Owner-process loss and explicit managed removal remain. The app
clears a disappeared/closed/replaced stream, resets synthesis/cursors, and requires
an explicit Takeover click before accepting its replacement. No physical inventory
lookup, retry loop or automatic whole-extension release occurs on stream loss.
Takeover is enabled while active (disabled only while restoring/replaying), rebuilds
routing from the current selected device IDs/indices, and resets stream baselines
without activation/removal. Trackpad Refresh no longer releases active DriverKit.
Choosing new selectors updates the pending targets; explicit click applies them.
Zero selected pads then clicking Takeover uses existing full Release restoration.
No keyboard output, cursor correction, generic event passthrough or sibling changes.

Static known-device driver personalities still limit supported hardware and cannot
turn arbitrary already-native pads into owned ones on demand. This manual workflow
change does not claim seamless reverse retake or completed general-device matching.
The earlier ReceiverWatchdog experiment source/tests remain research references,
but are no longer compiled into the helper. Historical success/failure evidence is
retained. Native-handoff research and permanent identity/sibling integration remain
separate unfinished work under the overall project objective.

### v17 user report; v18 fixes

User reported both visualizers stopped after Bluetooth power-off, manual Takeover
restored only USB, and app restart after full removal showed no devices. Logs reveal
actual shared driver process crashes at11:16:13 and11:19:00 local, not merely an
app reconnect state issue. Crash reports AMTRawHIDReceiver-2026-10-18-111613.ips
and -111900.ips show EXC_BAD_ACCESS0x8 at the same DriverKit/libdispatch teardown
path as earlier. v18 marks report/timer cancellation once per action; previously
Finish and Stop could cancel the same report action twice. This is a candidate
crash correction requiring live validation, not a proven fix from compilation.

Native recovery check after full removal: MTDeviceIsAvailable=1 and
MTDeviceCreateList count2 in a fresh read-only process. Found Swift OMSManager
permanently retained nil when initialized while MTDeviceIsAvailable was false;
all device discovery/listener access now retry acquiring the manager when nil.
No native event registration, mode writes or security changes in that diagnostic.

Driver contact ingestion no longer depends on InputRuntimeService.isRunning,
because native listening may stop/fail while DriverKit owns the sources. Explicit
DriverKit/replay/lifecycle session gates remain. New production runtime regression
feeds both pads with native listener stopped, clears one, verifies the other still
renders. All70 tests pass; v18 builds/signs/installs, deep strict signatures pass.
App reopened takeover off. No automatic reconnect behavior restored; manual selector
sync remains. Bluetooth raw mode/delivery and driver teardown remain live checks.

### v18 failure; v19 cancellation lifetime and Restart ordering

User confirmed v18 did not fix Bluetooth-off affecting USB or Restart's empty
inventory. New crash reports at11:26:01 and11:27:24 show the same0x8 fault.
Offline extraction of the installed DriverKit shared cache (macOS15.7.4 24G517,
x86_64h) resolved DriverKit image offset0xbe80 to
`IOTimerDispatchSource::Cancel_Impl`'s block invoke, offset24. Instructions:

```
movq 0x28(%rdi), %r15  // timer captured by the framework cancel block
movq 0x30(%r15), %rax  // timer ivars
movq 0x8(%rax), %rbx   // fault: rax=0, timer free cleared its ivars
```

This identifies premature timer destruction during asynchronous cancellation;
merely preventing duplicate Cancel calls in v18 did not fix lifetime ordering.
Both services share one driver process, so the Bluetooth teardown crash kills
USB too. The earlier independently successful native handoff remains valid.

v19 closes/disables the departing receiver, retains receiver/provider, cancels its
timer, then timer action, then input report action; only their completions call
super Stop. Startup failure uses that same drain instead of immediately releasing
cancelled objects. Other receivers' sources/actions are untouched. Apple's Stop
contract explicitly requires cancellation completion before super Stop:
https://developer.apple.com/documentation/driverkit/ioservice/stop

`Tests/test_shutdown.py` compiles and executes the actual production Stop body
against delayed source/action doubles. It checks all8 complete/partial startup
combinations, repeated Stop, destruction ordering and an independent untouched USB
receiver. This verifies the ordering contract offline, not actual hardware behavior.
Seven driver/signing tests and70 app tests pass. Hardware Bluetooth-off, manual
retake and full-removal behavior still require live validation of v19.

The app's Restart command now requests release while the old app/helper are alive,
waits for confirmed driver removal, and only then launches the replacement process
and terminates. Previously it launched first, so the new process discovered no
native trackpads before the old helper finished restoration. No removal timeout is
treated as success: authorization/restoration pending keeps the current app alive.
No automatic reconnect polling or global removal on pad disconnect was added.

### v20: session specification implementation candidate

User explicitly adopted the persistent-selected-pad spec, accepting activation once
per app launch and full teardown on Exit, while retaining takeover across Restart.
Implementation/limits and physical acceptance steps now live in
DriverKitProbe/TAKEOVER_SPEC.md. Supersedes v19's release-before-Restart behavior.

Added control-only coordinator, generic0324 model personalities/runtime serial
slots, selected-serial helper policy, explicit Sync, per-device estimator/pointer
resets, preserved supplemental device inventory, signed-process Restart ownership
transfer with single-use20s lease, and release-before-Exit completion. Retained
v19 asynchronous source/action drain. Offline76 app +7 driver/signing tests pass;
physical proof is still required. The original native-to-driver reverse retake gap
is explicitly not claimed solved. No sibling sources, cursor correction, mode
command expansion, new portal entitlement or automatic whole-driver recovery.

### v20 live isolation pass; Bluetooth mode framing failure; v21 correction

User physically confirmed Bluetooth off while captured USB kept visualizing.
Driver PID36112, helper36103 and USB receiver4294987221 stayed unchanged; USB
sequence582→1145. No new crash report. See V20_BLUETOOTH_DISCONNECT_RESULT.json.
The control-only coordinator was present. This establishes disconnect isolation for
that test, not all subsequent matching/restart/handoff behavior.

After Bluetooth reconnect and Sync, USB still worked but Bluetooth had no contacts
or cursor. Replacement receiver4294987317 was opened with1208 reports, all mouse-only
8-byte reports02, sequence0, no mapping errors. Mode request result0xe00002c7.

Read-only bluetoothd logs identify the exact framing error:

```
setReportWithKeyhole type=2 reportID=0xf1 reportLength=3 keyholeID=0xf1
Set report {type:3 ID:241 size:4 {'F1 F1 02 01'}}
setReportWithKeyhole ... failed:0xe00002c7
```

The native Bluetooth IOHIDUserDevice advertises KeyholeReportID241. macOS prepends
F1; our copied Linux wire buffer incorrectly included it again. v21 keeps reportIDF1
but supplies payload02 01, yielding the intended wireF1 02 01. USB's successful
02 01 payload is unchanged. No additional commands, haptic writes or mode guesses.
Production command framing now lives in Driver/MultitouchMode.h with a regression
checking exactly one keyhole prefix.

An explicit signed-helper diagnostic attempted the corrected payload through the
same pad's IOHIDDevice parent, without seizure/driver close/removal. SetReport was
not open0xe00002cd; ordinary nonseizing Open was not permitted0xe00002e2. Thus that
live correction did NOT reach hardware and did not prove the fix. Driver-side v21
is prepared for loading after development replacement of the currently active v20.
Driver tests8 pass, including the new packet-framing test. Physical mode recovery,
Restart transfer and full native handoff/reclaim still require validation.

### v21 first activation: stale app protocol filter, UI-only correction

User reported coordinator-not-found and no visualizations despite capture. Registry
proved coordinator present plus opened USB95/BT145 full packets, zero malformed or
mapping errors, mode result0 for both. The app's poll still compared StreamBuild20;
a scripted version bump missed its newly refactored `else` guard. This was an app
compatibility bug, not missing coordinator or failed Bluetooth initialization.

The app now uses one streamBuild constant for helper-version validation, stream
acceptance and evidence. Regression accepts current-build coordinator/receiver and
rejects old/missing build.77 app tests pass; Xcode build and deep signatures pass.
UI-only update staged/signed and atomically swapped in /Applications while preserving
the running app bundle at /Applications/.GesturePad-before-ui-fix-12fce6f75b.app.
Verified embedded helper executable unchanged. App37166/helper37318/driver37325
remained alive; no activation/deactivation requested. User must use Restart to load
the fixed UI, exercising the bounded live-session transfer. Do not remove the saved
running bundle until its old processes have exited.

### v21 warm Restart physically confirmed

User confirmed visualization and takeover returned through Restart. App PID37166→37738; helper37318 and driver37325 unchanged. Both receiver IDs unchanged (USB4294987808, BT4294987804), still opened; sequences95→1295 /145→991. Extension remains activated/enabled. See V21_WARM_RESTART_RESULT.json. This proves live Restart transfer for this session; it does not yet prove Bluetooth power-cycle recovery with corrected framing or arbitrary native reverse reclaim. Keep the preserved previous bundle while its helper process is still running.

### v21 physical transport identity transition

User confirmed full Bluetooth off/on + manual Sync succeeds with USB uninterrupted;
see V21_BLUETOOTH_RESYNC_RESULT.json. Unplugging right USB then selecting its new BT
MAC failed: helper log12:41:59 handed D0:C0:50:D5:69:55 back because it wasn't selected
yet; Sync12:42:23 requested retake0 but native AppleMultitouchDevice4294989076 remained.
The left BT stream remained controlled. This is the known native reverse-claim gap.

Found authoritative cross-transport association in the earlier native USB registry
snapshot: AppleDeviceManagementHIDEventService exposes DeviceAddress alongside the
USB SerialNumber (J84HMA00H0B0000501→d0-c0-50-d5-69-55). New helper policy learns/caches
these associations from supported USB management services, normalizes MACs, rejects
ambiguous links and treats positively paired transport identities as one selected
physical pad. It does not infer from names/timing, keep unrelated arrivals captured,
automatically update visualizer routing, or cycle the extension. Sync remains manual.

Helper update was signed/built with79 app tests passing, including alias symmetry,
no unrelated-device inclusion, empty selection and invalid/ambiguous rejection.
Atomically deployed app bundle; a replacement manager38607 adopted the existing
session/coordinator before old manager37318 was retired (without AppKit deactivation).
Driver37325 remained enabled/running throughout. The new manager uses current owner
app37738 and selected two BT identities. Seeded one cache association by parsing the
saved native USB registry snapshot; no personal IDs were hardcoded into product code.

Already-native right pad still needs one physical reconnect to match after the old
policy's handback. Future USB→BT transitions should avoid that premature handback;
physical validation is pending. Matching truly unrelated already-native newly selected
pads still has the reverse-reclaim limitation. IOHIDDeviceForceInterfaceRematch exists
in Apple source but its IOHIDLibUserClient route is gated by the separate
com.apple.hid.manager.user-access-interface-rematch entitlement; no entitlement was
added, no privileged rematch bypass attempted, and no security settings changed.
Preserve old bundles while their running processes remain alive.

### Transport identity change reverted at user request

Removed physical-identity alias policy, USB management scanning/cache, its two tests
and --adopt-existing-driver helper mode. Retained corrected Bluetooth framing,
current-build stream filter, Sync and warm Restart. Historical experiment notes
above are evidence only, not current behavior. Rebuilt without changing live ownership.

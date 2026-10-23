import AppKit
import ApplicationServices
import Combine
import OpenMultitouchSupport

/// App-owned settings and eligibility; no input is opened by initialization.
@MainActor
final class TrackpadGestureController: ObservableObject {
    @Published private(set) var settings = HandGestureSettings.load(from: .standard)
    @Published private(set) var statusRevision: UInt64 = 0
    @Published private(set) var hapticTestStatus = ""
    private var lastHapticTest = -Double.infinity
    private var pads = GestureSelectedPads()
    private var devices: [OMSDeviceInfo] = []
    private var owned: Set<UInt64> = []
    private var takeoverEnabled = false
    private var armed = false
    private var pointerProfiles: [UInt64: ApplePointerAccelerationProfile] = [:]
    private var scrollProfiles: [UInt64: AppleScrollProfile] = [:]

    func select(left: OMSDeviceInfo?, right: OMSDeviceInfo?) {
        let next = GestureSelectedPads(left: left?.deviceIDNumeric, right: right?.deviceIDNumeric)
        let infos = [left, right].compactMap { $0 }
        guard next != pads || infos != devices else { return }
        InterpretedTrackpadPointer.shared.resetBaseline()
        pads = next; devices = infos
        reloadProfiles()
        configure()
    }

    func updateOwnership(enabled: Bool, armed: Bool, owned: Set<UInt64>) {
        takeoverEnabled = enabled; self.armed = armed; self.owned = owned
        configure()
    }

    func suspend() {
        armed = false
        InterpretedTrackpadPointer.shared.stop()
        statusRevision &+= 1
    }

    func setAction(_ action: GestureAction, for trigger: GestureTrigger, scope: GestureHandScope) {
        guard trigger.allowedActions.contains(action) else { return }
        InterpretedTrackpadPointer.shared.resetBaseline()
        settings.setAction(action, for: trigger, in: scope)
        settings.save(to: .standard)
        if action != .disabled {
            reloadProfiles()
            if !AXIsProcessTrusted() {
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
        }
        configure()
    }

    func setSensitivity(_ value: Double, kind: GestureSensitivity, scope: GestureHandScope) {
        InterpretedTrackpadPointer.shared.resetBaseline()
        settings.set(kind, value: value, in: scope)
        settings.save(to: .standard)
        configure()
    }

    func setForceHapticLevel(_ value: Double, scope: GestureHandScope) {
        updateForceHaptic(scope:scope) { $0.level = value }
    }
    func setForceHapticWaveform(_ value: Int, scope: GestureHandScope) {
        updateForceHaptic(scope:scope) { $0.waveform = value }
    }
    private func updateForceHaptic(scope: GestureHandScope, edit:(inout ForceClickHapticSettings) -> Void) {
        InterpretedTrackpadPointer.shared.resetBaseline()
        if scope != .right {
            var next = settings.left.resolvedForceHaptic; edit(&next)
            settings.left.forceHaptic = next.normalized
        }
        if scope != .left {
            var next = settings.right.resolvedForceHaptic; edit(&next)
            settings.right.forceHaptic = next.normalized
        }
        settings.save(to:.standard)
        hapticTestStatus = ""
        configure()
    }

    func testForceHaptic(scope: GestureHandScope) {
        guard takeoverEnabled, armed else { hapticTestStatus = "Enable Trackpad Takeover to test."; return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastHapticTest >= 0.25 else { return }
        lastHapticTest = now
        let targets = Set([scope != .right ? pads.left : nil, scope != .left ? pads.right : nil].compactMap {$0}).intersection(owned)
        guard !targets.isEmpty else { hapticTestStatus = "Select an owned trackpad."; return }
        let routed = settings.routed(to:pads)
        if targets.allSatisfy({routed[$0]?.resolvedForceHaptic.level == 0}) {
            hapticTestStatus = "Feedback is off (level 0)."; return
        }
        var successes = 0
        for id in targets where routed[id]?.resolvedForceHaptic.play(device:id) == true { successes += 1 }
        hapticTestStatus = successes == targets.count ? "Pulse requested. Compare by feel." : "No pulse, or the actuator rejected this setting."
    }

    func refreshPermission() { configure() }

    func status(_ trigger: GestureTrigger, scope: GestureHandScope) -> String {
        func hand(_ side: GestureHandScope) -> String {
            let action = settings.action(trigger, in: side) ?? .disabled
            guard action != .disabled else { return "None" }
            guard let id = side == .left ? pads.left : pads.right else { return "Select a trackpad." }
            guard AXIsProcessTrusted() else { return "Paused: Accessibility permission required." }
            guard takeoverEnabled, armed, owned.contains(id) else { return "Waiting for Trackpad Takeover." }
            if action.requiresPointerProfile && pointerProfiles[id] == nil { return "Paused: tracking profile unavailable." }
            if action == .scroll && scrollProfiles[id] == nil { return "Paused: scroll profile unavailable." }
            if action == .primaryDrag && !InterpretedTrackpadPointer.shared.dragObserverAvailable { return "Paused: mouse-button observer unavailable. Toggle Trackpad Takeover to retry." }
            return "Active"
        }
        if scope != .both { return hand(scope) }
        let left = hand(.left), right = hand(.right)
        return left == right ? left : "Left: \(left) · Right: \(right)"
    }

    private func reloadProfiles() {
        pointerProfiles = [:]; scrollProfiles = [:]
        for device in devices {
            pointerProfiles[device.deviceIDNumeric] = try? InstalledPointerCurveReader.read(device: device)
            scrollProfiles[device.deviceIDNumeric] = try? InstalledScrollCurveReader.read(device: device)
        }
    }

    private func configure() {
        let routed = settings.routed(to: pads)
        let eligible = NativeTwoFingerMouseGate.outputDevices(enabled: true, armed: armed,
            takeoverEnabled: takeoverEnabled, trusted: AXIsProcessTrusted(), selected: Set(routed.keys), owned: owned)
        func devicesFor(_ trigger: GestureTrigger) -> Set<UInt64> {
            Set(routed.filter { id, config in
                let action = config.bindings.action(for: trigger)
                return eligible.contains(id) && action != .disabled
                    && (!action.requiresPointerProfile || pointerProfiles[id] != nil)
                    && (action != .scroll || scrollProfiles[id] != nil)
            }.map(\.key))
        }
        let two = devicesFor(.twoFingerMove), three = devicesFor(.threeFingerMove), four = devicesFor(.fourFingerMove)
        let tap = devicesFor(.twoFingerTap), triple = devicesFor(.threeFingerTap), thumb = devicesFor(.thumbTwoTap)
        let output = InterpretedTrackpadPointer.shared
        output.configureGestures(twoFingerMoveDevices: two, fourFingerMoveDevices: four,
            threeFingerMoveDevices: three, thumbTwoTapDevices: thumb, threeFingerTapDevices: triple,
            twoFingerTapDevices: tap, doubleClickInterval: NSEvent.doubleClickInterval,
            profiles: scrollProfiles, sensitivity: 1, sensitivities: routed.mapValues(\.scrollSensitivity),
            bindings: routed.mapValues(\.bindings), forceHaptics:routed.mapValues(\.resolvedForceHaptic))
        output.configure(response: .apple, sensitivity: 1, profiles: pointerProfiles,
            sensitivities: routed.mapValues(\.pointerSensitivity))
        let all = two.union(three).union(four).union(tap).union(triple).union(thumb)
        output.enable(devices: all.union(eligible)) // Force click needs no acceleration profile.
        let keyboardPads = NativeTwoFingerMouseGate.outputDevices(enabled: true, armed: armed,
            takeoverEnabled: takeoverEnabled, trusted: true, selected: Set(routed.keys), owned: owned)
        output.configureKeyboardReservations(devices: keyboardPads)
        statusRevision &+= 1
    }
}

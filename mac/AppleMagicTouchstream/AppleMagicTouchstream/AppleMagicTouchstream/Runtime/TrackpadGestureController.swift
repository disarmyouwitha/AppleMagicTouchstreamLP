import AppKit
import ApplicationServices
import Combine
import OpenMultitouchSupport

/// App-owned settings and eligibility; no input is opened by initialization.
@MainActor
final class TrackpadGestureController: ObservableObject {
    @Published private(set) var settings = HandGestureSettings.load(from: .standard)
    @Published private(set) var statusRevision: UInt64 = 0
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
        if GestureDirectionalAssignments.triggers.contains(trigger) {
            settings.editMovement(trigger,mode:.continuous,in:scope)
        }
        settings.save(to: .standard)
        if action != .disabled {
            reloadProfiles()
            if !AXIsProcessTrusted() {
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
        }
        configure()
    }

    func setMovementMode(_ mode:GestureMovementMode,for trigger:GestureTrigger,scope:GestureHandScope) {
        guard GestureDirectionalAssignments.triggers.contains(trigger) else { return }
        InterpretedTrackpadPointer.shared.resetBaseline()
        settings.editMovement(trigger,mode:mode,in:scope)
        settings.save(to:.standard)
        requestDirectionalPermissionIfNeeded(trigger)
        configure()
    }

    func setDirectionalAction(_ action:GestureAction,direction:GestureMovementDirection,for trigger:GestureTrigger,scope:GestureHandScope) {
        guard GestureDirectionalAssignments.allowedActions.contains(action),
              GestureDirectionalAssignments.triggers.contains(trigger) else { return }
        InterpretedTrackpadPointer.shared.resetBaseline()
        settings.editMovement(trigger,mode:.directional,direction:direction,action:action,in:scope)
        settings.save(to:.standard)
        requestDirectionalPermissionIfNeeded(trigger)
        configure()
    }

    private func requestDirectionalPermissionIfNeeded(_ trigger:GestureTrigger) {
        guard trigger == .threeFingerMove, !AXIsProcessTrusted(),
              [settings.left,settings.right].contains(where:{ config in
                  let editor = config.movement(trigger)
                  return editor.mode == .directional && GestureMovementDirection.allCases.contains { editor.action($0) != .disabled }
              }) else { return }
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt":true] as CFDictionary)
    }

    func setDirectionalRepeatInterval(_ milliseconds:Double,direction:GestureMovementDirection,for trigger:GestureTrigger,scope:GestureHandScope) {
        InterpretedTrackpadPointer.shared.resetBaseline()
        settings.setDirectionalRepeatInterval(milliseconds,direction:direction,for:trigger,in:scope)
        settings.save(to:.standard)
        configure()
    }

    func setSensitivity(_ value: Double, kind: GestureSensitivity, scope: GestureHandScope) {
        InterpretedTrackpadPointer.shared.resetBaseline()
        settings.set(kind, value: value, in: scope)
        settings.save(to: .standard)
        configure()
    }

    func applyImportedSettings(_ imported: HandGestureSettings) {
        InterpretedTrackpadPointer.shared.resetBaseline()
        var normalized = imported
        normalized.left.normalize(); normalized.right.normalize()
        settings = normalized
        settings.save(to:.standard)
        configure()
    }

    func refreshPermission() { configure() }

    func status(_ trigger: GestureTrigger, scope: GestureHandScope) -> String {
        func hand(_ side: GestureHandScope) -> String {
            let directional = GestureDirectionalAssignments.triggers.contains(trigger)
                && settings.movementMode(trigger,in:side) == .directional
            if directional && trigger != .threeFingerMove { return "Directional mode: output not implemented yet." }
            let action = settings.action(trigger, in: side) ?? .disabled
            guard directional || action != .disabled else { return "None" }
            guard let id = side == .left ? pads.left : pads.right else { return "Select a trackpad." }
            guard AXIsProcessTrusted() else { return "Paused: Accessibility permission required." }
            guard takeoverEnabled, armed, owned.contains(id) else { return "Waiting for Trackpad Takeover." }
            if directional {
                let config = side == .left ? settings.left.movement(trigger) : settings.right.movement(trigger)
                guard GestureMovementDirection.allCases.contains(where:{ config.action($0) != .disabled }) else { return "Choose a directional action." }
                let plans = AppleShortcutPlan.load()
                for direction in GestureMovementDirection.allCases {
                    let assigned = config.action(direction)
                    if assigned.isAppleShortcut && plans[assigned] == nil { return "\(direction.title): \(assigned.title) is unavailable." }
                }
                return "Active"
            }
            if action.isAppleShortcut && AppleShortcutPlan.load()[action] == nil { return "Paused: \(action.title) is unavailable on this macOS version." }
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
        let shortcuts = AppleShortcutPlan.load()
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
        let pinch = GestureTrigger.pinchTriggers.reduce(into:Set<UInt64>()) { $0.formUnion(devicesFor($1)) }
        let tap = devicesFor(.twoFingerTap), triple = devicesFor(.threeFingerTap), thumb = devicesFor(.thumbTwoTap)
        let directionalBindings = routed.compactMapValues { config -> GestureDirectionalAssignments? in
            let assignments = config.movement(.threeFingerMove)
            return assignments.mode == .directional ? assignments : nil
        }
        let output = InterpretedTrackpadPointer.shared
        output.configureGestures(twoFingerMoveDevices: two, fourFingerMoveDevices: four,
            threeFingerMoveDevices: three, thumbTwoTapDevices: thumb, threeFingerTapDevices: triple,
            twoFingerTapDevices: tap, pinchDevices:pinch,
            zoomSensitivities:routed.mapValues { $0[GestureSensitivity.zoom] }, doubleClickInterval: NSEvent.doubleClickInterval,
            profiles: scrollProfiles, sensitivity: 1, sensitivities: routed.mapValues(\.scrollSensitivity),
            bindings: routed.mapValues(\.bindings), directionalBindings:directionalBindings, appleShortcuts:shortcuts)
        output.configure(response: .apple, sensitivity: 1, profiles: pointerProfiles,
            sensitivities: routed.mapValues(\.pointerSensitivity))
        let all = pinch.union(two).union(three).union(four).union(tap).union(triple).union(thumb)
        output.enable(devices: all.union(eligible)) // Force click needs no acceleration profile.
        let keyboardPads = NativeTwoFingerMouseGate.outputDevices(enabled: true, armed: armed,
            takeoverEnabled: takeoverEnabled, trusted: true, selected: Set(routed.keys), owned: owned)
        output.configureKeyboardReservations(devices: keyboardPads)
        statusRevision &+= 1
    }
}

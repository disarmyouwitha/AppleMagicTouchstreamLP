// Ported from GesturePad: live output only, no HID seizure/probe paths.
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import OpenMultitouchSupport
import QuartzCore
import os

struct SelectedTrackpadEventPolicy {
    static let interpreterTag: Int64 = 0x414D544745535455
}

struct TwoFingerPointerTracker {
    private var contacts: GestureContactMotionTracker
    var frameContinued: Bool { contacts.frameContinued }
    init(activationCount: Int = 2) { contacts = GestureContactMotionTracker(activationCount:activationCount) }
    mutating func reset() { contacts.reset() }
    mutating func reset(device: UInt64) { contacts.reset(device:device) }
    mutating func millimetres<C: Collection>(device: UInt64, time: Double, contacts touches: C) -> CGPoint? where C.Element == OMSRawTouch {
        contacts.millimetres(device:device,time:time,contacts:touches)
    }
    mutating func process(device: UInt64, time: Double, touches: OMSRawTouchBufferView) -> CGPoint? {
        process(device:device,time:time,contacts:touches)
    }
    mutating func process<C: Collection>(device: UInt64, time: Double, contacts: C) -> CGPoint? where C.Element == OMSRawTouch {
        guard let mm = millimetres(device:device,time:time,contacts:contacts) else { return nil }
        return CGPoint(x:mm.x*6,y:mm.y*6)
    }
}

final class InterpretedTrackpadPointer: @unchecked Sendable {
    static let shared = InterpretedTrackpadPointer()
    /// Installed only by live enable; no observer is created by init or tests.
    private struct ButtonObserver: @unchecked Sendable {
        let tap: CFMachPort
        let source: CFRunLoopSource
        func stop() {
            CGEvent.tapEnable(tap:tap,enable:false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes)
            CFMachPortInvalidate(tap)
        }
    }
    private struct State {
        var devices: Set<UInt64> = []
        var cornerEngines:[UInt64:SinglePadCornersEngine] = [:]
        var cornerSettings:[UInt64:TwoHandGestureSettings] = [:]
        var cornerEligible:Set<UInt64> = []
        var needsCornerTimer:Bool { !cornerEligible.isEmpty && cornerSettings.values.contains { $0.enabled(.fourCorners) } }
        mutating func postCorner(_ trigger:TwoHandTrigger,device:UInt64,time:Double) {
            let action = cornerSettings[device]?.action(trigger) ?? .disabled
            if action == .openConfig { openConfiguration?() }
            else if devices.contains(device) { postDirectional(action,device:device,time:time,owner:.corners(device)) }
        }
        var twoHandEngine = TwoHandGestureEngine()
        var twoHandPads = GestureSelectedPads()
        var twoHandSettings = TwoHandGestureSettings()
        var twoHandEligible = false, twoHandTrusted = false
        var openConfiguration: (@Sendable () -> Void)?
        var needsTwoHandTimer:Bool { twoHandEligible && TwoHandChord.allCases.contains(where:twoHandSettings.enabled) }
        mutating func postCoordinated(_ trigger:TwoHandTrigger,time:Double) {
            let action = twoHandSettings.action(trigger)
            if action == .openConfig { openConfiguration?() }
            else if twoHandTrusted, let device = twoHandPads.left { postDirectional(action,device:device,time:time,owner:.coordinated) }
        }
        var keyboardArbitration = GestureKeyboardArbitration()
        var keyboardClaimed = Set<UInt64>(minimumCapacity:2)
        var keyboardEpoch:UInt64 = 0
        var keyboardDevices: Set<UInt64> = []
        var recoverableKeyboardDevices:Set<UInt64> = []
        var keyboardRecoveryNeedsDragObserver:Set<UInt64> = []
        var keyboardChordDevices: Set<UInt64> = []
        var tracker = TwoFingerPointerMotionEngine()
        var router = TrackpadGestureRouter()
        var directionals: [UInt64:[GestureTrigger:GestureDirectionalAssignments]] = [:]
        var holds = GestureHoldRecognizer()
        var holdBindings:[UInt64:[Int:GestureAction]] = [:]
        var holdThresholds:[UInt64:[Int:Double]] = [:]
        var needsHoldTimer:Bool { !holdBindings.isEmpty }
        mutating func postHold(count:Int,device:UInt64,time:Double) {
            keyboardClaimed.insert(device)
            taps.cancel(device:device); threeFingerTaps.cancel(device:device); fourFingerTaps.cancel(device:device); fiveFingerTaps.cancel(device:device)
            forceClicks.cancel(device:device)
            router.reset(device:device); directionalStepper.reset(device:device)
            directionalRepeater.reset(device:device); tracker.reset(device:device)
            finishScroll(device:device,cancelled:true)
            if let action = holdBindings[device]?[count] { postDirectional(action,device:device,time:time) }
        }
        var directionalStepper = GestureDirectionalStepper()
        var directionalRepeater = GestureDirectionalRepeater()
        var needsDirectionalTimer:Bool { !directionals.isEmpty }
        var bindings: [UInt64:GestureActionBindings] = [:]
        var appleShortcuts: [GestureAction:AppleShortcutPlan] = [:]
        func action(_ trigger: GestureTrigger, device: UInt64) -> GestureAction {
            (bindings[device] ?? GestureActionBindings()).action(for:trigger)
        }
        func primaryClickConflicts(_ action:GestureAction) -> Bool {
            drag.owner != nil && (action == .primaryClick || action == .primaryDoubleClick)
        }
        var needsDragObserver: Bool { bindings.values.contains { $0.uses(.primaryDrag) } }
        var needsZoomTimer: Bool { bindings.values.contains { $0.uses(.zoom) } }
        var needsScrollTimer: Bool {
            bindings.values.contains { $0.uses(.scroll) } || directionals.values.contains { inputs in
                inputs.values.contains { config in GestureMovementDirection.allCases.contains { config.action($0).isDirectionalScroll } }
            }
        }
        func recognizes(_ trigger: GestureTrigger, device: UInt64) -> Bool {
            if let directional = directionals[device]?[trigger] { return directional.hasAssignments }
            let enabled: Bool
            switch trigger {
            case .twoFingerPinch,.threeFingerPinch,.fourFingerPinch,.fiveFingerPinch,
                 .twoFingerSpread,.threeFingerSpread,.fourFingerSpread,.fiveFingerSpread: enabled = pinchDevices.contains(device)
            case .twoFingerMove: enabled = twoFingerMoveDevices.contains(device)
            case .threeFingerMove: enabled = threeFingerMoveDevices.contains(device)
            case .fourFingerMove: enabled = fourFingerMoveDevices.contains(device)
            case .fiveFingerMove: enabled = fiveFingerMoveDevices.contains(device)
            case .twoFingerTap: enabled = twoFingerTapDevices.contains(device)
            case .threeFingerTap: enabled = threeFingerTapDevices.contains(device)
            case .fourFingerTap: enabled = fourFingerTapDevices.contains(device)
            case .fiveFingerTap: enabled = fiveFingerTapDevices.contains(device)
            case .thumbTwoTap: enabled = thumbTwoTapDevices.contains(device)
            default: enabled = trigger.forceCount != nil && devices.contains(device)
            }
            return enabled && action(trigger,device:device) != .disabled && (action(trigger,device:device) != .primaryDrag || buttonObserverHealthy)
        }
        mutating func postTap(_ trigger: GestureTrigger, device: UInt64, time: Double) {
            keyboardClaimed.insert(device)
            // Same discrete dispatcher as Force/Hold/directions, including native
            // Dock actions (Mission Control / App Exposé have no CGEvent sequence).
            postDirectional(action(trigger,device:device),device:device,time:time)
        }
        var shortcutOwners:Set<GestureShortcutOwner> = []
        mutating func releaseShortcut(_ owner:GestureShortcutOwner) {
            guard shortcutOwners.remove(owner) != nil else { return }
            DispatchService.shared.releaseGestureShortcut(owner)
        }
        mutating func postDirectional(_ action:GestureAction,device:UInt64,time:Double,owner:GestureShortcutOwner? = nil) {
            guard action != .disabled, !primaryClickConflicts(action) else { return }
            if let shortcut = action.shortcutAssignment {
                let owner = owner ?? .pad(device)
                if shortcut.holdUntilRelease { shortcutOwners.insert(owner) }
                DispatchService.shared.postGestureShortcut(shortcut,owner:owner)
                return
            }
            if appleShortcuts[action]?.dockMessage != nil {
                _ = appleShortcuts[action]?.postDock(); clicks.reset(); return
            }
            guard let location = CGEvent(source:nil)?.location,
                  let events = GestureTapActionOutput.events(action:action,location:location,time:time,
                    doubleClickInterval:doubleClickInterval,flags:CGEventSource.flagsState(.combinedSessionState).union(DispatchService.shared.heldGestureFlags),
                    clicks:&clicks,shortcut:appleShortcuts[action]) else { return }
            for event in events {
                event.post(tap:appleShortcuts[action]?.eventTap ?? .cghidEventTap); postedEvents &+= 1
            }
        }
        var drag = PrimaryDragOutput()
        var buttonObserver: ButtonObserver?
        var buttonObserverHealthy = false
        var threeFingerMoveDevices: Set<UInt64> = []
        var twoFingerMoveDevices: Set<UInt64> = []
        var pinchDevices: Set<UInt64> = []
        var zoomOutputs: [UInt64:MagnifyGestureOutput] = [:]
        var zoomSensitivities: [UInt64:Double] = [:]
        var fourFingerMoveDevices: Set<UInt64> = []
        var fiveFingerMoveDevices:Set<UInt64> = []
        var twoFingerTapDevices: Set<UInt64> = []
        var threeFingerTapDevices: Set<UInt64> = []
        var fourFingerTapDevices:Set<UInt64> = []
        var fiveFingerTapDevices:Set<UInt64> = []
        var thumbTwoTapDevices: Set<UInt64> = []
        var forceClicks = ForceClickRecognizer()
        var taps = TwoFingerTapRecognizer()
        var threeFingerTaps = ThreeFingerTapRecognizer()
        var fourFingerTaps = TwoFingerTapRecognizer(requiredCount:4)
        var fiveFingerTaps = TwoFingerTapRecognizer(requiredCount:5)
        var clicks = PrimaryTapClickOutput()
        /// Every exclusive owner consumes the same terminal frame. Clear all
        /// discrete candidates together so none can fire a second action on lift.
        mutating func consumeAllUp<C:Collection>(device:UInt64,time:Double,now:Double,contacts:C) where C.Element == OMSRawTouch {
            releaseShortcut(.pad(device))
            _ = holds.observe(device:device,time:time,now:now,contacts:contacts,motionClaimed:false,actions:[:])
            _ = forceClicks.recognize(device:device,time:time,contacts:contacts,enabled:{_ in false})
            _ = taps.process(device:device,time:time,contacts:contacts,gestureActive:true)
            _ = fourFingerTaps.process(device:device,time:time,contacts:contacts,gestureActive:true)
            _ = fiveFingerTaps.process(device:device,time:time,contacts:contacts,gestureActive:true)
            _ = threeFingerTaps.recognize(device:device,time:time,contacts:contacts,
                gestureActive:true,ordinaryEnabled:false,thumbEnabled:false)
        }
        var doubleClickInterval = 0.5
        var scrollProfiles: [UInt64:AppleScrollProfile] = [:]
        var scrollEngines: [UInt64:FourFingerScrollEngine] = [:]
        var directionalScrollEngines:[UInt64:DirectionalScrollEngine] = [:]
        var scrollOutputs: [UInt64:PreciseScrollOutput] = [:]
        var scrollSensitivity = 1.0
        var scrollSensitivities: [UInt64:Double] = [:]
        var momentum: [UInt64:ScrollMomentum] = [:]
        var momentumTimer: (any DispatchSourceTimer)?
        var lastForceHaptic: [UInt64:Double] = [:]
        var lastReceipt: [UInt64:Double] = Dictionary(minimumCapacity:2)
        var lastContactTime:[UInt64:Double] = Dictionary(minimumCapacity:2)
        mutating func cancelMomentum(device: UInt64) {
            scrollOutputs[device]?.finishMomentum()?.post(tap:.cghidEventTap)
            momentum[device]?.cancel()
        }
        mutating func finishScroll(device: UInt64, cancelled: Bool) {
            scrollOutputs[device]?.finish(cancelled:cancelled)?.post(tap:.cghidEventTap)
            cancelMomentum(device:device)
            scrollEngines[device]?.reset()
            directionalScrollEngines[device]?.reset()
        }
        mutating func releaseScroll(device:UInt64,time:Double,hostTime:Double) {
            if scrollOutputs[device]?.active == true {
                let coasting = momentum[device]?.start(contactTime:time,hostTime:hostTime) == true
                scrollOutputs[device]?.finish(cancelled:false,preserveForMomentum:coasting)?.post(tap:.cghidEventTap)
            }
            scrollEngines[device]?.reset(); directionalScrollEngines[device]?.reset()
        }
        mutating func reset(device: UInt64,preservingCorner:Bool = false) {
            releaseShortcut(.pad(device))
            if !preservingCorner { releaseShortcut(.corners(device)); cornerEngines[device]?.reset() }
            holds.cancel(device:device)
            keyboardChordDevices.remove(device)
            zoomOutputs[device]?.finish(cancelled:true)?.post(tap:.cghidEventTap)
            if drag.owners.contains(device) { drag.end(device:device,location:CGEvent(source:nil)?.location)?.post(tap:.cghidEventTap) }
            finishScroll(device:device,cancelled:true)
            forceClicks.cancel(device:device)
            taps.invalidate(device:device); threeFingerTaps.invalidate(device:device); fourFingerTaps.invalidate(device:device); fiveFingerTaps.invalidate(device:device)
            router.reset(device:device); directionalStepper.reset(device:device); directionalRepeater.reset(device:device); tracker.reset(device:device); lastReceipt[device] = nil; lastContactTime[device] = nil
        }
        mutating func reset() {
            keyboardEpoch &+= 1; keyboardClaimed.removeAll(keepingCapacity:true)
            for owner in Array(shortcutOwners) { releaseShortcut(owner) }
            for device in cornerEngines.keys { cornerEngines[device]?.reset() }
            holds.reset()
            twoHandEngine.reset()
            keyboardChordDevices.removeAll(keepingCapacity:true)
            for device in zoomOutputs.keys { zoomOutputs[device]?.finish(cancelled:true)?.post(tap:.cghidEventTap) }
            if drag.owner != nil { drag.end(location:CGEvent(source:nil)?.location)?.post(tap:.cghidEventTap) }
            for device in scrollOutputs.keys { finishScroll(device:device,cancelled:true) }
            forceClicks.reset(); taps.reset(); threeFingerTaps.reset(); fourFingerTaps.reset(); fiveFingerTaps.reset(); clicks.reset()
            router.reset(); directionalStepper.reset(); directionalRepeater.reset(); tracker.reset(); lastReceipt.removeAll(keepingCapacity:true); lastContactTime.removeAll(keepingCapacity:true)
        }
        var displayBounds: [CGRect] = []
        var postedEvents: UInt64 = 0
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let momentumQueue = DispatchQueue(label:"AppleMagicTouchstream.scrollMomentum",qos:.userInteractive)
    func configure(response: TwoFingerPointerResponse, sensitivity: Double,
                   profiles: [UInt64:ApplePointerAccelerationProfile], sensitivities: [UInt64:Double] = [:]) {
        lock.withLock { state in state.tracker.configure(response:response,sensitivity:sensitivity,profiles:profiles,sensitivities:sensitivities) }
    }
    func configureGestures(twoFingerMoveDevices: Set<UInt64>, fourFingerMoveDevices: Set<UInt64>,
                           threeFingerMoveDevices: Set<UInt64>, thumbTwoTapDevices: Set<UInt64>, threeFingerTapDevices: Set<UInt64>,
                           twoFingerTapDevices: Set<UInt64>, fourFingerTapDevices:Set<UInt64> = [], fiveFingerTapDevices:Set<UInt64> = [], fiveFingerMoveDevices:Set<UInt64> = [], pinchDevices: Set<UInt64> = [], zoomSensitivities: [UInt64:Double] = [:], doubleClickInterval: Double, profiles: [UInt64:AppleScrollProfile], sensitivity: Double, sensitivities: [UInt64:Double] = [:], bindings: [UInt64:GestureActionBindings] = [:], recoverableKeyboardDevices:Set<UInt64> = [], directionalBindings: [UInt64:[GestureTrigger:GestureDirectionalAssignments]] = [:], holdBindings: [UInt64:[Int:GestureAction]] = [:], holdThresholds: [UInt64:[Int:Double]] = [:], appleShortcuts: [GestureAction:AppleShortcutPlan] = [:]) {
        lock.withLock { state in
            guard state.fiveFingerTapDevices != fiveFingerTapDevices || state.fiveFingerMoveDevices != fiveFingerMoveDevices || state.fourFingerTapDevices != fourFingerTapDevices || state.recoverableKeyboardDevices != recoverableKeyboardDevices || state.holdBindings != holdBindings || state.holdThresholds != holdThresholds || state.directionals != directionalBindings || state.appleShortcuts != appleShortcuts || state.pinchDevices != pinchDevices || state.zoomSensitivities != zoomSensitivities || state.bindings != bindings || state.twoFingerMoveDevices != twoFingerMoveDevices || state.fourFingerMoveDevices != fourFingerMoveDevices || state.threeFingerMoveDevices != threeFingerMoveDevices
                || state.thumbTwoTapDevices != thumbTwoTapDevices || state.twoFingerTapDevices != twoFingerTapDevices || state.threeFingerTapDevices != threeFingerTapDevices || state.doubleClickInterval != doubleClickInterval
                || state.scrollProfiles != profiles || state.scrollSensitivity != sensitivity || state.scrollSensitivities != sensitivities else { return }
            state.reset()
            state.keyboardArbitration.reset()
            state.bindings = bindings
            state.recoverableKeyboardDevices = recoverableKeyboardDevices
            state.keyboardRecoveryNeedsDragObserver = Set(bindings.filter { $0.value.uses(.primaryDrag) }.keys)
            state.holdBindings = holdBindings
            state.holdThresholds = holdThresholds
            state.directionals = directionalBindings
            state.appleShortcuts = appleShortcuts
            state.pinchDevices = pinchDevices
            state.zoomSensitivities = zoomSensitivities
            state.zoomOutputs = bindings.mapValues { _ in MagnifyGestureOutput() }
            state.threeFingerMoveDevices = threeFingerMoveDevices
            state.twoFingerMoveDevices = twoFingerMoveDevices; state.fourFingerMoveDevices = fourFingerMoveDevices
            state.thumbTwoTapDevices = thumbTwoTapDevices
            state.threeFingerTapDevices = threeFingerTapDevices
            state.fourFingerTapDevices = fourFingerTapDevices
            state.fiveFingerTapDevices = fiveFingerTapDevices
            state.fiveFingerMoveDevices = fiveFingerMoveDevices
            state.twoFingerTapDevices = twoFingerTapDevices; state.doubleClickInterval = doubleClickInterval
            state.scrollProfiles = profiles; state.scrollSensitivity = sensitivity; state.scrollSensitivities = sensitivities
            state.scrollEngines = profiles.mapValues { FourFingerScrollEngine(profile:$0) }
            state.directionalScrollEngines = profiles.mapValues { DirectionalScrollEngine(profile:$0) }
            state.scrollOutputs = profiles.mapValues { _ in PreciseScrollOutput() }
            state.momentum = profiles.mapValues { _ in ScrollMomentum() }
            if !state.needsDragObserver {
                state.buttonObserver?.stop(); state.buttonObserver = nil; state.buttonObserverHealthy = false
            }
            if !state.needsScrollTimer && !state.needsDragObserver && !state.needsZoomTimer && !state.needsDirectionalTimer && !state.needsTwoHandTimer && !state.needsHoldTimer && !state.needsCornerTimer { state.momentumTimer?.cancel(); state.momentumTimer = nil }
        }
    }
    func enable(devices: Set<UInt64>) {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        let bounds: [CGRect]
        if CGGetActiveDisplayList(16, &displays, &count) == .success {
            bounds = displays.prefix(Int(count)).map { CGDisplayBounds($0) }
        } else { bounds = [] }
        lock.withLock { state in
            for device in state.devices.symmetricDifference(devices) { state.reset(device:device) }
            let now = CACurrentMediaTime()
            for (device,receipt) in state.lastReceipt where now-receipt > 0.2 && state.momentum[device]?.isCoasting != true {
                state.reset(device:device)
            }
            state.devices = devices; state.displayBounds = bounds
            if state.needsDragObserver && state.buttonObserver == nil {
                let mask = [CGEventType.leftMouseDown,.rightMouseDown,.otherMouseDown]
                    .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
                let tap = CGEvent.tapCreate(tap:.cghidEventTap,place:.headInsertEventTap,options:.listenOnly,
                    eventsOfInterest:mask,callback: { _,type,event,context in
                        if let context {
                            Unmanaged<InterpretedTrackpadPointer>.fromOpaque(context).takeUnretainedValue()
                                .observeButton(type:type,event:event)
                        }
                        return Unmanaged.passUnretained(event)
                    },userInfo:Unmanaged.passUnretained(self).toOpaque())
                if let tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0) {
                    state.buttonObserver = ButtonObserver(tap:tap,source:source)
                    state.buttonObserverHealthy = true
                    CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)
                    CGEvent.tapEnable(tap:tap,enable:true)
                } else if let tap { CFMachPortInvalidate(tap) }
            }
            if (state.needsScrollTimer || state.needsDragObserver || state.needsZoomTimer || state.needsDirectionalTimer || state.needsTwoHandTimer || state.needsHoldTimer || state.needsCornerTimer) && state.momentumTimer == nil {
                let timer = DispatchSource.makeTimerSource(queue:momentumQueue)
                timer.schedule(deadline:.now()+0.008333,repeating:.nanoseconds(8_333_333),leeway:.milliseconds(1))
                timer.setEventHandler { [weak self] in self?.tickMomentum() }
                state.momentumTimer = timer
                timer.resume()
            }
        }
    }
    private func tickMomentum() {
        lock.withLock { state in
            guard !state.devices.isEmpty || state.twoHandEligible || !state.cornerEligible.isEmpty else { return }
            let now = CACurrentMediaTime()
            if Self.polledButtonInterference(ownsPrimary:state.drag.owner != nil) {
                state.reset(); return
            }
            if state.twoHandEligible, let trigger = state.twoHandEngine.advance(now:now,settings:state.twoHandSettings) {
                state.postCoordinated(trigger,time:now)
            }
            if !state.twoHandEngine.maintainsHeldOutput { state.releaseShortcut(.coordinated) }
            for device in state.cornerEligible {
                if let config = state.cornerSettings[device], let trigger = state.cornerEngines[device]?.advance(now:now,settings:config) {
                    state.postCorner(trigger,device:device,time:now)
                }
                if state.cornerEngines[device]?.maintainsHeldOutput != true { state.releaseShortcut(.corners(device)) }
            }
            for owner in Array(state.shortcutOwners) {
                if case let .pad(device) = owner, GestureOutputLifecycle.isStale(receipt:state.lastReceipt[device],now:now) { state.reset(device:device) }
            }
            for device in state.devices {
                if let actions = state.holdBindings[device], let count = state.holds.advance(device:device,now:now,actions:actions,thresholds:state.holdThresholds[device] ?? [:]) {
                    state.postHold(count:count,device:device,time:now)
                }
            }
            for owner in state.drag.owners where GestureOutputLifecycle.isStale(receipt:state.lastReceipt[owner],now:now) {
                state.reset(device:owner)
            }
            for device in state.devices where state.zoomOutputs[device]?.active == true || state.scrollOutputs[device]?.active == true {
                if GestureOutputLifecycle.isStale(receipt:state.lastReceipt[device],now:now) { state.reset(device:device) }
            }
            for device in state.devices where state.directionalStepper.direction(device:device) != nil {
                if GestureOutputLifecycle.isStale(receipt:state.lastReceipt[device],now:now) { state.reset(device:device); continue }
                if let direction = state.directionalRepeater.tick(device:device,now:now),
                   let trigger = state.directionalStepper.trigger(device:device),
                   let assignments = state.directionals[device]?[trigger] {
                    state.postDirectional(assignments.action(direction),device:device,time:now)
                }
            }
            for device in state.devices where state.momentum[device]?.isCoasting == true {
                guard let step = state.momentum[device]?.advance(hostTime:now) else { continue }
                state.scrollOutputs[device]?.event(points:step.points,momentum:true)?.post(tap:.cghidEventTap)
                if step.finished { state.scrollOutputs[device]?.finishMomentum()?.post(tap:.cghidEventTap) }
            }
        }
    }
    private static func polledButtonInterference(ownsPrimary: Bool) -> Bool {
        // Do not even query the global tables while holding our own down.
        // The listen-only tagged observer covers outside presses in that state.
        guard !ownsPrimary else { return false }
        return DragButtonInterference.suppress(polledButtonsDown:
            CGEventSource.buttonState(.combinedSessionState,button:.left)
            || CGEventSource.buttonState(.combinedSessionState,button:.right)
            || CGEventSource.buttonState(.combinedSessionState,button:.center),ownsPrimary:false)
    }
    private func observeButton(type: CGEventType, event: CGEvent) {
        let tag = event.getIntegerValueField(.eventSourceUserData)
        lock.withLock { state in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                state.buttonObserverHealthy = false
                state.reset() // fail closed, including the reserved up
            } else if state.drag.owner != nil && DragButtonInterference.interrupts(type:type,
                tag:tag) {
                state.reset()
            }
        }
    }
    var dragObserverAvailable: Bool { lock.withLock { $0.buttonObserverHealthy } }
    var postedEventCount: UInt64 { lock.withLock { $0.postedEvents } }
    func stop() { lock.withLock {
        $0.cornerEligible.removeAll(keepingCapacity:true)
        $0.twoHandEligible = false
        $0.devices.removeAll(keepingCapacity:true); $0.reset(); $0.keyboardArbitration.reset(); $0.keyboardDevices.removeAll(keepingCapacity:true)
        $0.momentumTimer?.cancel(); $0.momentumTimer = nil
        $0.buttonObserver?.stop(); $0.buttonObserver = nil; $0.buttonObserverHealthy = false
    } }
    func resetBaseline() { lock.withLock { $0.reset() } }
    func resetBaseline(device: UInt64) { lock.withLock { $0.reset(device: device) } }
    func configureOpenConfiguration(_ handler:@escaping @Sendable () -> Void) {
        lock.withLock { $0.openConfiguration = handler }
    }
    func configureTwoHand(pads:GestureSelectedPads,settings:TwoHandGestureSettings,eligible:Bool,trusted:Bool) {
        lock.withLock { state in
            if pads != state.twoHandPads || settings != state.twoHandSettings || eligible != state.twoHandEligible || trusted != state.twoHandTrusted {
                state.reset()
            }
            state.twoHandPads = pads; state.twoHandSettings = settings
            state.twoHandEligible = eligible; state.twoHandTrusted = trusted
        }
    }
    /// Runs before keyboard/local gesture dispatch, on the same serialized frame.
    func reserveCoordinated(_ frame:OMSRawTouchFrame,keyboardChord:Bool) -> Bool {
        lock.withLock { state in
            let device = frame.deviceIDNumeric
            guard state.twoHandEligible,
                  device == state.twoHandPads.left || device == state.twoHandPads.right else { return false }
            let now = CACurrentMediaTime()
            let decision = state.twoHandEngine.process(leftHand:device == state.twoHandPads.left,now:now,
                contacts:frame.touches,settings:state.twoHandSettings,
                blocked:keyboardChord || !state.keyboardChordDevices.isEmpty || Self.polledButtonInterference(ownsPrimary:state.drag.owner != nil))
            if !state.twoHandEngine.maintainsHeldOutput { state.releaseShortcut(.coordinated) }
            guard decision.reserved else { return false }
            // Cancel both independent outputs when the shared chord owns them.
            if decision.began {
                if let left = state.twoHandPads.left { state.reset(device:left) }
                if let right = state.twoHandPads.right { state.reset(device:right) }
            } else { state.reset(device:device) }
            state.keyboardArbitration.reset(device:device)
            if !frame.touches.contains(where:{$0.state == .making || $0.state == .touching}) {
                state.consumeAllUp(device:device,time:frame.timestamp,now:CACurrentMediaTime(),contacts:frame.touches)
            }
            if let trigger = decision.trigger { state.postCoordinated(trigger,time:now) }
            return true
        }
    }

    func configureCorners(settings:[UInt64:TwoHandGestureSettings],eligible:Set<UInt64>) {
        lock.withLock { state in
            guard state.cornerSettings != settings || state.cornerEligible != eligible else { return }
            state.reset()
            state.cornerSettings = settings; state.cornerEligible = eligible
            state.cornerEngines = settings.mapValues { _ in SinglePadCornersEngine() }
        }
    }
    func reserveCorners(_ frame:OMSRawTouchFrame,keyboardChord:Bool) -> Bool {
        lock.withLock { state in
            let device = frame.deviceIDNumeric
            guard state.cornerEligible.contains(device), let settings = state.cornerSettings[device] else { return false }
            guard !keyboardChord, !state.keyboardChordDevices.contains(device),
                  !Self.polledButtonInterference(ownsPrimary:state.drag.owner != nil) else {
                state.releaseShortcut(.corners(device)); state.cornerEngines[device]?.reset(); return false
            }
            var engine = state.cornerEngines[device] ?? SinglePadCornersEngine()
            let now = CACurrentMediaTime()
            let decision = engine.process(now:now,contacts:frame.touches,settings:settings)
            if !engine.maintainsHeldOutput { state.releaseShortcut(.corners(device)) }
            if decision.reserved {
                state.reset(device:device,preservingCorner:true)
                state.keyboardArbitration.reset(device:device)
                if !frame.touches.contains(where:{$0.state == .making || $0.state == .touching}) {
                    state.consumeAllUp(device:device,time:frame.timestamp,now:CACurrentMediaTime(),contacts:frame.touches)
                }
                if let trigger = decision.trigger { state.postCorner(trigger,device:device,time:now) }
            }
            state.cornerEngines[device] = engine
            return decision.reserved
        }
    }

    func configureKeyboardReservations(devices: Set<UInt64>) {
        lock.withLock { $0.keyboardDevices = devices }
    }

    /// An established layer or modifier hold owns keyboard input on this pad. Cancel only its gesture
    /// state and consume its all-up frame so no recognizer remains blocked.
    func suspendForKeyboardChord(_ frame: OMSRawTouchFrame) {
        lock.withLock { state in
            let device = frame.deviceIDNumeric
            if !state.keyboardChordDevices.contains(device) {
                state.reset(device:device)
                state.keyboardChordDevices.insert(device)
            }
            state.keyboardArbitration.reset(device:device)
            if !frame.touches.contains(where:{$0.state == .starting || $0.state == .making || $0.state == .touching}) {
                state.consumeAllUp(device:device,time:frame.timestamp,now:CACurrentMediaTime(),contacts:frame.touches)
                state.keyboardChordDevices.remove(device)
            }
        }
    }

    /// Keyboard reservation uses configured inputs even if output permission or
    /// profiles are unavailable; a paused gesture must not turn into typed keys.
    func reserveKeyboard(_ frame: OMSRawTouchFrame) -> Bool {
        lock.withLock { state in
            let device = frame.deviceIDNumeric
            guard state.keyboardDevices.contains(device) else { return false }
            let count = frame.touches.reduce(0) { count, touch in
                count + ((touch.state == .making || touch.state == .touching) ? 1 : 0)
            }
            let bindings = state.bindings[device] ?? GestureActionBindings()
            let forceEnabled = GestureTrigger.force(count:count).map { bindings.action(for:$0) != .disabled } ?? false
            let forceClick = forceEnabled && frame.touches.contains {
                ($0.state == .making || $0.state == .touching) && $0.pressure.isFinite
                    && $0.pressure >= ForceClickRecognizer.threshold
            }
            let directional = state.directionals[device] ?? [:]
            return state.keyboardArbitration.process(device: device, activeCount: count, forceClick: forceClick,
                holdCandidate:state.holdBindings[device]?[count] != nil || (count == 3 && state.holdBindings[device]?[PerHandGestureSettings.thumbHoldKey] != nil)) {
                directional[$0] != nil || bindings.action(for: $0) != .disabled
            }
        }
    }
    struct KeyboardEvidence {
        let claimed:Bool
        let tapPending:Bool
        let enabled:Bool
        let epoch:UInt64
    }
    func keyboardEvidence(device:UInt64,allUp:Bool = false) -> KeyboardEvidence {
        lock.withLock { state in
            let pending = (state.twoFingerTapDevices.contains(device) && state.taps.canStillComplete(device:device))
                || ((state.threeFingerTapDevices.contains(device) || state.thumbTwoTapDevices.contains(device)) && state.threeFingerTaps.canStillComplete(device:device))
                || (state.fourFingerTapDevices.contains(device) && state.fourFingerTaps.canStillComplete(device:device))
                || (state.fiveFingerTapDevices.contains(device) && state.fiveFingerTaps.canStillComplete(device:device))
            let result = KeyboardEvidence(claimed:state.keyboardClaimed.contains(device),tapPending:pending,
                enabled:state.recoverableKeyboardDevices.contains(device) && (!state.keyboardRecoveryNeedsDragObserver.contains(device) || state.buttonObserverHealthy),epoch:state.keyboardEpoch)
            if allUp { state.keyboardClaimed.remove(device) }
            return result
        }
    }
    func process(_ frame: OMSRawTouchFrame) {
        process(device: frame.deviceIDNumeric, time: frame.timestamp, contacts: frame.touches)
    }
    func process<C: Collection & Sendable>(device: UInt64, time: Double, contacts: C, suppress: Bool = false) where C.Element == OMSRawTouch {
        let forceHaptic = lock.withLock { state -> ForceClickHapticSettings? in
            var feedback: ForceClickHapticSettings?
            guard state.devices.contains(device) else { return nil }
            if suppress || Self.polledButtonInterference(ownsPrimary:state.drag.owner != nil) {
                state.reset()
                state.taps.cancel(device:device)
                state.threeFingerTaps.cancel(device:device); state.fourFingerTaps.cancel(device:device); state.fiveFingerTaps.cancel(device:device)
                return nil
            }
            let hostTime = CACurrentMediaTime()
            if state.shortcutOwners.contains(.pad(device)),
               !HeldGestureShortcutInput.continues(time:time,previous:state.lastContactTime[device],contacts:contacts) {
                state.reset(device:device); return nil
            }
            state.lastContactTime[device] = time
            state.lastReceipt[device] = hostTime
            let allUp = !contacts.contains { $0.state == .making || $0.state == .touching }
            if !allUp && state.momentum[device]?.isCoasting == true {
                state.keyboardClaimed.insert(device)
                state.cancelMomentum(device:device)
                state.taps.cancel(device:device)
                state.threeFingerTaps.cancel(device:device); state.fourFingerTaps.cancel(device:device); state.fiveFingerTaps.cancel(device:device) // braking a coast must not also click
            }
            if state.holds.claimed(device:device) {
                _ = state.holds.observe(device:device,time:time,now:hostTime,contacts:contacts,motionClaimed:false,actions:[:])
                if allUp {
                    state.consumeAllUp(device:device,time:time,now:hostTime,contacts:contacts)
                }
                return nil
            }
            let forceBindings = state.bindings[device] ?? GestureActionBindings()
            let dragOnAnotherPad = state.drag.hasOtherOwner(than:device)
            if let trigger = state.forceClicks.recognize(device:device,time:time,contacts:contacts,
                    enabled:{ trigger in
                        let action = forceBindings.action(for:trigger)
                        return action != .disabled && !(dragOnAnotherPad && (action == .primaryClick || action == .primaryDoubleClick))
                    }),
               let location = CGEvent(source:nil)?.location,
               let events = forceBindings.action(for:trigger).shortcutAssignment != nil || state.appleShortcuts[forceBindings.action(for:trigger)]?.dockMessage != nil
                    ? [] : GestureTapActionOutput.events(action:forceBindings.action(for:trigger),location:location,
                        time:hostTime,doubleClickInterval:state.doubleClickInterval,
                        flags:CGEventSource.flagsState(.combinedSessionState).union(DispatchService.shared.heldGestureFlags),clicks:&state.clicks,
                        shortcut:state.appleShortcuts[forceBindings.action(for:trigger)]) {
                state.zoomOutputs[device]?.finish(cancelled:true)?.post(tap:.cghidEventTap)
                state.drag.end(device:device)?.post(tap:.cghidEventTap)
                state.finishScroll(device:device,cancelled:true)
                if forceBindings.action(for:trigger).shortcutAssignment != nil { state.postDirectional(forceBindings.action(for:trigger),device:device,time:hostTime) }
                for event in events { event.post(tap:state.appleShortcuts[forceBindings.action(for:trigger)]?.eventTap ?? .cghidEventTap) }
                if state.appleShortcuts[forceBindings.action(for:trigger)]?.postDock() == true { state.clicks.reset() }
                if hostTime - (state.lastForceHaptic[device] ?? -.infinity) >= 0.05 {
                    state.lastForceHaptic[device] = hostTime
                    feedback = .fixed
                }
            }
            if state.forceClicks.claimed(device:device) {
                state.keyboardClaimed.insert(device)
                state.holds.cancel(device:device)
                state.taps.cancel(device:device); state.threeFingerTaps.cancel(device:device); state.fourFingerTaps.cancel(device:device); state.fiveFingerTaps.cancel(device:device)
                state.router.reset(device:device); state.directionalStepper.reset(device:device); state.directionalRepeater.reset(device:device); state.tracker.reset(device:device)
                return feedback
            }
            // Copy recognition eligibility before mutating the router in State.
            let pinchEligible = state.pinchDevices.contains(device)
            let pinchBindings = state.bindings[device] ?? GestureActionBindings()
            let two = state.recognizes(.twoFingerMove,device:device)
            let three = state.recognizes(.threeFingerMove,device:device)
            let four = state.recognizes(.fourFingerMove,device:device)
            let five = state.recognizes(.fiveFingerMove,device:device)
            let update = state.router.recognize(device:device,time:time,contacts:contacts,enabled:{ trigger in
                if trigger.isRotation { return GestureTrigger.liveRotationTriggers.contains(trigger) && pinchBindings.action(for:trigger) != .disabled }
                if trigger.isPinch { return pinchEligible && pinchBindings.action(for:trigger) != .disabled }
                switch trigger {
                case .twoFingerMove: return two; case .threeFingerMove: return three; case .fourFingerMove: return four; case .fiveFingerMove: return five
                default: return false
                }
            })
            if update.phase == .began || update.phase == .changed { state.keyboardClaimed.insert(device) }
            let directionalOwner = update.gesture.flatMap { state.directionals[device]?[$0] } != nil
            if !directionalOwner, let actions = state.holdBindings[device], let count = state.holds.observe(device:device,time:time,now:hostTime,
                    contacts:contacts,motionClaimed:GestureHoldRecognizer.motionClaimsHold(update,directional:false,direction:nil),actions:actions,thresholds:state.holdThresholds[device] ?? [:]) {
                state.postHold(count:count,device:device,time:hostTime)
                return nil
            }
            if update.phase == .ended || update.phase == .cancelled {
                state.zoomOutputs[device]?.finish(cancelled:update.phase == .cancelled)?.post(tap:.cghidEventTap)
                // Complete the queued drag sequence at its own last destination.
                state.drag.end(device:device)?.post(tap:.cghidEventTap)
            }
            if let gesture = update.gesture, let assignments = state.directionals[device]?[gesture] {
                if allUp {
                    state.consumeAllUp(device:device,time:time,now:hostTime,contacts:contacts)
                } else {
                    state.taps.cancel(device:device); state.threeFingerTaps.cancel(device:device); state.fourFingerTaps.cancel(device:device); state.fiveFingerTaps.cancel(device:device)
                }
                state.tracker.reset(device:device)
                if update.phase == .began { state.directionalRepeater.reset(device:device) }
                let direction = state.directionalStepper.process(device:device,time:time,update:update,assignments:assignments)
                let heldDirection = state.directionalStepper.direction(device:device)
                if let actions = state.holdBindings[device], let count = state.holds.observe(device:device,time:time,now:hostTime,
                    contacts:contacts,motionClaimed:GestureHoldRecognizer.motionClaimsHold(update,directional:true,direction:heldDirection),actions:actions,thresholds:state.holdThresholds[device] ?? [:]) {
                    state.postHold(count:count,device:device,time:hostTime)
                    return nil
                }
                let heldAction = heldDirection.map { assignments.action($0) } ?? .disabled
                if GestureOutputLifecycle.normalLift(phase:update.phase,allUp:allUp) {
                    state.releaseScroll(device:device,time:time,hostTime:hostTime)
                } else if let heldDirection, heldAction.isDirectionalScroll,
                          update.phase == .began || update.phase == .changed {
                    if state.directionalScrollEngines[device]?.matches(direction:heldDirection,action:heldAction) != true {
                        state.finishScroll(device:device,cancelled:true)
                    }
                    if let travel = update.millimetres,
                       let delta = state.directionalScrollEngines[device]?.process(time:time,millimetres:travel,
                            direction:heldDirection,action:heldAction,
                            sensitivity:state.scrollSensitivities[device] ?? state.scrollSensitivity) {
                        // Record zero velocity too: a pause before lift must not fling old motion.
                        state.momentum[device]?.observe(points:delta,contactTime:time)
                        state.scrollOutputs[device]?.event(points:delta)?.post(tap:.cghidEventTap)
                    } else { state.finishScroll(device:device,cancelled:true) }
                } else { state.finishScroll(device:device,cancelled:true) }
                if let direction, !assignments.action(direction).isDirectionalScroll {
                    state.postDirectional(assignments.action(direction),device:device,time:hostTime)
                }
                state.directionalRepeater.refresh(device:device,direction:heldDirection,
                    intervalMS:heldDirection.map { assignments.repeatIntervalMS($0) } ?? 0,now:hostTime)
                return nil
            }
            // A different owner/discontinuity cannot retain directional progress.
            state.directionalRepeater.reset(device:device)
            state.directionalStepper.reset(device:device)
            if let gesture = update.gesture, gesture.isRotation || state.action(gesture,device:device).isDiscreteOutput {
                if allUp {
                    state.consumeAllUp(device:device,time:time,now:hostTime,contacts:contacts)
                } else {
                    state.taps.cancel(device:device); state.threeFingerTaps.cancel(device:device); state.fourFingerTaps.cancel(device:device); state.fiveFingerTaps.cancel(device:device)
                }
                state.finishScroll(device:device,cancelled:true)
                if update.phase == .began {
                    state.postDirectional(state.action(gesture,device:device),device:device,time:hostTime)
                }
                return nil
            }
            if let gesture = update.gesture, state.action(gesture,device:device) == .zoom {
                if allUp {
                    state.consumeAllUp(device:device,time:time,now:hostTime,contacts:contacts)
                } else {
                    state.taps.cancel(device:device); state.threeFingerTaps.cancel(device:device); state.fourFingerTaps.cancel(device:device); state.fiveFingerTaps.cancel(device:device)
                }
                state.finishScroll(device:device,cancelled:true)
                if update.phase == .began || update.phase == .changed {
                    if let rawDelta = update.scaleDelta, let location = CGEvent(source:nil)?.location {
                        let gain = state.zoomSensitivities[device] ?? 1
                        let delta = min(0.25,max(-0.25,rawDelta * gain))
                        if let event = state.zoomOutputs[device]?.update(delta:delta,began:update.phase == .began,
                            location:location,flags:CGEventSource.flagsState(.combinedSessionState).union(DispatchService.shared.heldGestureFlags)) {
                            event.post(tap:.cghidEventTap); state.postedEvents &+= 1
                        }
                    } else {
                        state.zoomOutputs[device]?.finish(cancelled:true)?.post(tap:.cghidEventTap)
                    }
                }
                return nil
            }
            let motion = update.gesture.flatMap { gesture in update.millimetres.map { (gesture:gesture,millimetres:$0) } }
            let motionAction = update.gesture.map { state.action($0,device:device) } ?? .disabled
            if motionAction == .primaryDrag && update.phase == .began {
                state.finishScroll(device:device,cancelled:true)
                if state.drag.owner != nil {
                    guard state.drag.join(device:device) else { state.reset(device:device); return nil }
                } else {
                    guard let location = CGEvent(source:nil)?.location,
                          let down = state.drag.begin(device:device,location:location,flags:CGEventSource.flagsState(.combinedSessionState).union(DispatchService.shared.heldGestureFlags)) else {
                        state.reset(device:device)
                        state.taps.cancel(device:device); state.threeFingerTaps.cancel(device:device); state.fourFingerTaps.cancel(device:device); state.fiveFingerTaps.cancel(device:device)
                        return nil
                    }
                    state.clicks.reset()
                    down.post(tap:.cghidEventTap)
                }
            }
            if state.recognizes(.twoFingerTap,device:device), state.taps.process(device:device,time:time,
                contacts:contacts,gestureActive:motion != nil) {
                state.postTap(.twoFingerTap,device:device,time:hostTime)
            }
            if state.fourFingerTapDevices.contains(device), state.fourFingerTaps.process(device:device,time:time,contacts:contacts,gestureActive:motion != nil) {
                state.postTap(.fourFingerTap,device:device,time:hostTime)
            }
            if state.fiveFingerTapDevices.contains(device), state.fiveFingerTaps.process(device:device,time:time,contacts:contacts,gestureActive:motion != nil) {
                state.postTap(.fiveFingerTap,device:device,time:hostTime)
            }
            if state.threeFingerTapDevices.contains(device) || state.thumbTwoTapDevices.contains(device),
                let trigger = state.threeFingerTaps.recognize(device:device,time:time,contacts:contacts,
                    gestureActive:motion != nil,ordinaryEnabled:state.recognizes(.threeFingerTap,device:device),
                    thumbEnabled:state.recognizes(.thumbTwoTap,device:device)) {
                state.postTap(trigger,device:device,time:hostTime)
            }
            guard let motion else {
                if GestureOutputLifecycle.normalLift(phase:update.phase,allUp:allUp) {
                    state.releaseScroll(device:device,time:time,hostTime:hostTime)
                } else if GestureOutputLifecycle.cancelsScroll(phase:update.phase,allUp:allUp) {
                    state.finishScroll(device:device,cancelled:true)
                }
                // Idle empty frames must not brake an already released coast.
                state.tracker.reset(device:device)
                return nil
            }
            if motionAction == .scroll {
                if let delta = state.scrollEngines[device]?.process(time:time,millimetres:motion.millimetres,
                    sensitivity:state.scrollSensitivities[device] ?? state.scrollSensitivity) {
                    state.momentum[device]?.observe(points:delta,contactTime:time)
                    state.scrollOutputs[device]?.event(points:delta)?.post(tap:.cghidEventTap)
                } else { state.reset(device:device) }
                return nil
            }
            guard motionAction.requiresPointerProfile else { state.reset(device:device); return nil }
            // Drag destinations accumulate from our last queued destination. Reading
            // WindowServer here can return an older cursor while posts are in flight.
            let anchor = state.drag.location ?? CGEvent(source:nil)?.location
            guard let delta = state.tracker.processMotion(device:device,time:time,millimetres:motion.millimetres),
                  let current = anchor else { state.reset(device:device); return nil }
            guard delta.x != 0 || delta.y != 0 else { return nil }
            var location = CGPoint(x: current.x + delta.x, y: current.y + delta.y)
            // Clamp to the nearest actual display, including negative-origin displays.
            var closest: CGPoint?; var distance = Double.infinity
            for bounds in state.displayBounds {
                let candidate = CGPoint(x: min(max(location.x, bounds.minX), bounds.maxX - 1),
                                        y: min(max(location.y, bounds.minY), bounds.maxY - 1))
                let dx = candidate.x - location.x, dy = candidate.y - location.y
                let d = dx * dx + dy * dy
                if d < distance { distance = d; closest = candidate }
            }
            if let closest { location = closest }
            if state.drag.owner != nil {
                guard let event = state.drag.movePointer(location:location,delta:delta,
                    flags:CGEventSource.flagsState(.combinedSessionState).union(DispatchService.shared.heldGestureFlags)) else { state.reset(device:device); return nil }
                event.post(tap:.cghidEventTap); state.postedEvents &+= 1
                return nil
            }
            guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                       mouseCursorPosition: location, mouseButton: .left) else { return nil }
            event.setIntegerValueField(.eventSourceUserData, value: SelectedTrackpadEventPolicy.interpreterTag)
            event.setDoubleValueField(.mouseEventDeltaX, value: delta.x)
            event.setDoubleValueField(.mouseEventDeltaY, value: delta.y)
            event.post(tap: .cghidEventTap)
            state.postedEvents &+= 1
            return nil
        }
        if let forceHaptic { _ = forceHaptic.play(device:device) }
    }
}


enum NativeTwoFingerMouseGate {
    static func outputDevices(enabled: Bool, armed: Bool, takeoverEnabled: Bool,
                              trusted: Bool, selected: Set<UInt64>, owned: Set<UInt64>) -> Set<UInt64> {
        guard enabled, armed, takeoverEnabled, trusted else { return [] }
        return selected.intersection(owned)
    }
}

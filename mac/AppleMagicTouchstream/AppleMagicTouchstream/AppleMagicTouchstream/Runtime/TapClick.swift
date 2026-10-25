import AppKit
import CoreGraphics
import Darwin
import Foundation
import OpenMultitouchSupport

/// Current finger count chooses the configured force action when any contact
/// crosses the pressure threshold. The action owns the cycle until all-up.
struct ForceClickRecognizer {
    static let threshold: Float = 130
    private struct Session {
        var ids = SIMD8<Int32>(repeating:0)
        var count = 0
        var lastTime: Double?
        var blocked = false
        var fired = false
    }
    private var sessions: [UInt64: Session] = [:]
    func claimed(device: UInt64) -> Bool { sessions[device]?.fired == true }
    mutating func cancel(device: UInt64) { sessions[device] = Session(blocked:true) }
    mutating func reset() { for device in sessions.keys { cancel(device:device) } }
    mutating func recognize<C: Collection>(device: UInt64, time: Double, contacts: C,
        enabled: (GestureTrigger) -> Bool) -> GestureTrigger? where C.Element == OMSRawTouch {
        var ids = SIMD8<Int32>(repeating:0), count = 0
        var maximumPressure: Float = 0
        var invalid = !time.isFinite
        for touch in contacts where touch.state == .making || touch.state == .touching {
            if count < 8 {
                for index in 0..<count where ids[index] == touch.id { invalid = true }
                ids[count] = touch.id
            }
            count += 1
            invalid = invalid || !touch.pressure.isFinite || touch.pressure < 0
                || !touch.posX.isFinite || !touch.posY.isFinite || touch.telemetry?.fingerID == 6
            maximumPressure = max(maximumPressure,touch.pressure)
        }
        if count == 0 { sessions[device] = nil; return nil }
        var session = sessions[device] ?? Session()
        defer { sessions[device] = session }
        guard !invalid, let trigger = GestureTrigger.force(count:count),
              session.lastTime.map({time > $0 && time - $0 <= 0.2}) ?? true,
              count >= session.count else { session.blocked = true; return nil }
        // Added fingers are allowed before pressing; substitutions or lifting
        // cannot turn an existing chord into another force-click gesture.
        for index in 0..<session.count {
            guard (0..<count).contains(where:{ ids[$0] == session.ids[index] }) else {
                session.blocked = true; return nil
            }
        }
        session.ids = ids; session.count = count; session.lastTime = time
        guard !session.blocked, !session.fired, enabled(trigger), maximumPressure >= Self.threshold else { return nil }
        session.fired = true
        return trigger
    }
}

/// A discrete tap completes on all-up, independently of continuous gesture latches.
struct TwoFingerTapRecognizer {
    static let maximumDuration = 0.5
    private let requiredCount: Int
    init(requiredCount: Int = 2) { precondition(requiredCount == 2 || requiredCount == 3); self.requiredCount = requiredCount }
    private struct Finger { let id: Int32; let x: Double; let y: Double }
    private struct Session {
        var first: Finger?, second: Finger?, third: Finger?
        var started = 0.0, lastTime = 0.0
        var paired: Double?, lifting: Double?
        var blocked = false
    }
    private var sessions: [UInt64:Session] = Dictionary(minimumCapacity:2)
    mutating func cancel(device: UInt64) { sessions[device] = Session(blocked:true) }
    mutating func invalidate(device: UInt64) { if sessions[device] != nil { cancel(device:device) } }
    mutating func reset() { for device in sessions.keys { cancel(device:device) } }
    mutating func process<C: Collection>(device: UInt64, time: Double, contacts: C,
        gestureActive: Bool = false) -> Bool where C.Element == OMSRawTouch {
        var ids = SIMD4<Int32>(repeating:0), count = 0
        var invalid = !time.isFinite
        for touch in contacts where touch.state == .making || touch.state == .touching {
            if count < 4 {
                for index in 0..<count where ids[index] == touch.id { invalid = true }
                ids[count] = touch.id
            }
            count += 1
            invalid = invalid || !touch.posX.isFinite || !touch.posY.isFinite || touch.telemetry?.fingerID == 6
        }
        if count == 0 {
            defer { sessions[device] = nil }
            guard !invalid, !gestureActive, let session = sessions[device], !session.blocked,
                  let paired = session.paired, time > session.lastTime,
                  time-session.lastTime <= 0.15, time-session.started <= Self.maximumDuration,
                  (session.lifting ?? time)-paired >= 0.02,
                  time-(session.lifting ?? time) <= 0.08 else { return false }
            return true
        }
        if sessions[device]?.blocked == true { return false }
        guard !invalid, count <= requiredCount, !gestureActive else { cancel(device:device); return false }
        var session = sessions[device] ?? Session(started:time,lastTime:time)
        if sessions[device] != nil {
            guard time > session.lastTime, time-session.lastTime <= 0.15,
                  time-session.started <= Self.maximumDuration else { cancel(device:device); return false }
        }
        for touch in contacts where touch.state == .making || touch.state == .touching {
            let original: Finger
            if let first = session.first, first.id == touch.id { original = first }
            else if let second = session.second, second.id == touch.id { original = second }
            else if let third = session.third, third.id == touch.id { original = third }
            else {
                guard session.paired == nil, time-session.started <= 0.08 else {
                    cancel(device:device); return false
                }
                let finger = Finger(id:touch.id,x:Double(touch.posX),y:Double(touch.posY))
                if session.first == nil { session.first = finger }
                else if session.second == nil { session.second = finger }
                else if requiredCount == 3 && session.third == nil { session.third = finger }
                else { cancel(device:device); return false }
                original = finger
            }
            guard hypot((Double(touch.posX)-original.x)*160,(Double(touch.posY)-original.y)*114.9) <= 1 else {
                cancel(device:device); return false
            }
        }
        if count == requiredCount {
            guard session.lifting == nil else { cancel(device:device); return false }
            if session.paired == nil { session.paired = time }
        } else if session.paired != nil {
            if session.lifting == nil { session.lifting = time }
            if time-session.lifting! > 0.08 { cancel(device:device); return false }
        }
        session.lastTime = time
        sessions[device] = session
        return false
    }
}

/// Creates both edges before either is posted. There is no held-button or drag state.
struct PrimaryTapClickOutput {
    struct Events { let down: CGEvent; let up: CGEvent }
    struct DoubleClickEvents {
        let first: Events
        let second: Events
    }
    static func doubleClickEvents(location: CGPoint, flags: CGEventFlags = []) -> DoubleClickEvents? {
        // A dedicated gesture always starts at 1 and completes at 2, independent
        // of previous single taps. Build every edge before posting any of them.
        var sequence = PrimaryTapClickOutput()
        guard let first = sequence.events(location:location,time:1,doubleClickInterval:0.5,flags:flags),
              let second = sequence.events(location:location,time:1.01,doubleClickInterval:0.5,flags:flags) else { return nil }
        return DoubleClickEvents(first:first,second:second)
    }
    private var lastTime: Double?
    private var lastLocation = CGPoint.zero
    private var clickCount: Int64 = 0
    private var lastFlags: CGEventFlags = []
    mutating func reset() { lastTime = nil; clickCount = 0 }
    mutating func events(location: CGPoint, time: Double, doubleClickInterval: Double,
                         flags: CGEventFlags = []) -> Events? {
        guard location.x.isFinite, location.y.isFinite, time.isFinite,
              let down = CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:location,mouseButton:.left),
              let up = CGEvent(mouseEventSource:nil,mouseType:.leftMouseUp,mouseCursorPosition:location,mouseButton:.left) else { return nil }
        let continuing = lastTime.map { time > $0 && time-$0 <= doubleClickInterval
            && flags == lastFlags && hypot(location.x-lastLocation.x,location.y-lastLocation.y) <= 4 } ?? false
        let count: Int64 = continuing ? min(3,clickCount+1) : 1
        func configure(_ event: CGEvent) {
            event.flags = flags
            event.setIntegerValueField(.mouseEventClickState,value:count)
            event.setIntegerValueField(.mouseEventButtonNumber,value:0)
            event.setIntegerValueField(.eventSourceUserData,value:SelectedTrackpadEventPolicy.interpreterTag)
        }
        configure(down); configure(up)
        down.setDoubleValueField(.mouseEventPressure,value:1)
        up.setDoubleValueField(.mouseEventPressure,value:0)
        lastTime = time; lastLocation = location; clickCount = count; lastFlags = flags
        return Events(down:down,up:up)
    }
}


/// Activation evidence only: retain the shared latch once this chord has won.
/// Millimetre limits are provisional ergonomics, not Apple's internal thresholds.
enum ThreeFingerRowChord {
    static func accepts<C: Collection>(_ contacts: C) -> Bool where C.Element == OMSRawTouch {
        var points = SIMD8<Double>(repeating:0)
        var count = 0
        for touch in contacts where touch.state == .making || touch.state == .touching {
            guard count < 3, touch.posX.isFinite, touch.posY.isFinite,
                  touch.telemetry?.fingerID != 1, touch.telemetry?.fingerID != 6 else { return false }
            points[count*2] = Double(touch.posX)*160
            points[count*2+1] = Double(touch.posY)*114.9
            count += 1
        }
        guard count == 3 else { return false }
        var longest = 0.0, endpointA = 0, endpointB = 1
        for a in 0..<3 {
            for b in (a+1)..<3 {
                let distance = hypot(points[a*2]-points[b*2],points[a*2+1]-points[b*2+1])
                guard distance >= 2, distance <= 60 else { return false }
                if distance > longest { longest = distance; endpointA = a; endpointB = b }
            }
        }
        let middle = 3-endpointA-endpointB
        let dx = points[endpointB*2]-points[endpointA*2]
        let dy = points[endpointB*2+1]-points[endpointA*2+1]
        let mx = points[middle*2]-points[endpointA*2]
        let my = points[middle*2+1]-points[endpointA*2+1]
        // Natural fingertip rows form an arch, not a straight line. Hardware
        // capture showed valid rows 9–13 mm deep; the old 8 mm gate delayed or
        // rejected them. Keep both absolute and relative arch bounds.
        guard abs(dx*my-dy*mx)/longest <= min(14,longest*0.35) else { return false }
        return hypot(mx,my) <= 35 && hypot(mx-dx,my-dy) <= 35
    }
}

/// One global primary-button owner. All methods are confined to the live output
/// lock (or an offline test). The reserved up event exists before down is returned.
struct PrimaryDragOutput: @unchecked Sendable {
    private(set) var owner: UInt64?
    private(set) var owners:Set<UInt64> = Set(minimumCapacity:2)
    private(set) var location: CGPoint?
    private var releaseEvent: CGEvent?
    private var source: CGEventSource?
    mutating func begin(device: UInt64, location: CGPoint, flags: CGEventFlags) -> CGEvent? {
        guard owner == nil, location.x.isFinite, location.y.isFinite,
              let source = CGEventSource(stateID:.privateState),
              let down = CGEvent(mouseEventSource:source,mouseType:.leftMouseDown,mouseCursorPosition:location,mouseButton:.left),
              let up = CGEvent(mouseEventSource:source,mouseType:.leftMouseUp,mouseCursorPosition:location,mouseButton:.left) else { return nil }
        self.source = source; owner = device; owners.insert(device); self.location = location; releaseEvent = up
        Self.configure(down,flags:flags,pressure:1)
        Self.configure(up,flags:flags,pressure:0)
        return down
    }
    mutating func move(device: UInt64, location: CGPoint, delta: CGPoint, flags: CGEventFlags) -> CGEvent? {
        guard owners.contains(device), location.x.isFinite, location.y.isFinite,
              delta.x.isFinite, delta.y.isFinite,
              let event = CGEvent(mouseEventSource:source,mouseType:.leftMouseDragged,mouseCursorPosition:location,mouseButton:.left) else { return nil }
        Self.configure(event,flags:flags,pressure:1)
        event.setDoubleValueField(.mouseEventDeltaX,value:delta.x)
        event.setDoubleValueField(.mouseEventDeltaY,value:delta.y)
        self.location = location
        releaseEvent?.location = location; releaseEvent?.flags = flags
        return event
    }
    func hasOtherOwner(than device:UInt64) -> Bool { owners.contains { $0 != device } }
    /// Another drag can share the one system primary button without a second down.
    mutating func join(device:UInt64) -> Bool {
        guard owner != nil else { return false }
        owners.insert(device); return true
    }
    /// Either pad's pointer can move a drag without becoming a button owner.
    mutating func movePointer(location:CGPoint,delta:CGPoint,flags:CGEventFlags) -> CGEvent? {
        guard let owner else { return nil }
        return move(device:owner,location:location,delta:delta,flags:flags)
    }
    mutating func end(device: UInt64? = nil, location: CGPoint? = nil) -> CGEvent? {
        guard device == nil || owners.contains(device!) else { return nil }
        if let device {
            owners.remove(device)
            if !owners.isEmpty { if owner == device { owner = owners.min() }; return nil }
        }
        if let location, location.x.isFinite, location.y.isFinite { releaseEvent?.location = location }
        releaseEvent?.timestamp = DispatchTime.now().uptimeNanoseconds
        let up = releaseEvent
        owner = nil; owners.removeAll(keepingCapacity:true); self.location = nil; releaseEvent = nil; source = nil
        return up
    }
    private static func configure(_ event: CGEvent, flags: CGEventFlags, pressure: Double) {
        event.flags = flags
        event.setIntegerValueField(.mouseEventClickState,value:1)
        event.setIntegerValueField(.mouseEventButtonNumber,value:0)
        event.setIntegerValueField(.eventSourceUserData,value:SelectedTrackpadEventPolicy.interpreterTag)
        event.setDoubleValueField(.mouseEventPressure,value:pressure)
    }
}


/// Polling global left-button state cannot distinguish our held synthetic down.
/// During ownership only tagged event observation decides button interference.
enum DragButtonInterference {
    static func suppress(polledButtonsDown: Bool, ownsPrimary: Bool) -> Bool {
        !ownsPrimary && polledButtonsDown
    }
    static func interrupts(type: CGEventType, tag: Int64) -> Bool {
        tag != SelectedTrackpadEventPolicy.interpreterTag &&
            (type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown)
    }
}


/// Anatomical classification chooses a discrete action; the shared count tap
/// recognizer still owns timing, movement, contact identity and cancellation.
struct ThreeFingerTapRecognizer {
    typealias Action = GestureTrigger
    private struct Identity {
        var sawThumb = false
        var matched = false
        var rejected = false
        // Thumb plus two interchangeable fingertip tracking IDs.
        var trackingIDs = SIMD4<Int32>(repeating:0)
        var handID: Int32 = 0
    }
    private var timing = TwoFingerTapRecognizer(requiredCount:3)
    private var identities: [UInt64:Identity] = Dictionary(minimumCapacity:2)
    mutating func cancel(device: UInt64) { timing.cancel(device:device); identities[device] = nil }
    mutating func invalidate(device: UInt64) { timing.invalidate(device:device); identities[device] = nil }
    mutating func reset() { timing.reset(); identities.removeAll(keepingCapacity:true) }
    // Compatibility wrapper for count-based diagnostic callers.
    mutating func process<C: Collection>(device: UInt64, time: Double, contacts: C,
        gestureActive: Bool = false, doubleClick: Bool, rightClick: Bool) -> GestureTrigger? where C.Element == OMSRawTouch {
        recognize(device:device,time:time,contacts:contacts,gestureActive:gestureActive,
            ordinaryEnabled:doubleClick,thumbEnabled:rightClick)
    }
    mutating func recognize<C: Collection>(device: UInt64, time: Double, contacts: C,
        gestureActive: Bool = false, ordinaryEnabled: Bool, thumbEnabled: Bool) -> GestureTrigger? where C.Element == OMSRawTouch {
        let completed = timing.process(device:device,time:time,contacts:contacts,gestureActive:gestureActive)
        var identity = identities[device] ?? Identity()
        var count = 0, mask = 0
        var exact = true
        var trackingIDs = SIMD4<Int32>(repeating:0)
        var handID: Int32 = 0
        var points = SIMD8<Double>(repeating:0)
        for touch in contacts where touch.state == .making || touch.state == .touching {
            count += 1
            let finger = touch.telemetry?.fingerID ?? 0
            if finger == 1 { identity.sawThumb = true }
            let slot: Int
            switch finger { case 1: slot = 0; case 2...5: slot = mask & 2 == 0 ? 1 : 2; default: slot = -1 }
            if slot < 0 { exact = false }
            else {
                if mask & (1 << slot) != 0 { exact = false }
                mask |= 1 << slot; trackingIDs[slot] = touch.id
                points[slot*2] = Double(touch.posX)*160
                points[slot*2+1] = Double(touch.posY)*114.9
            }
            let hand = touch.telemetry?.handID ?? 0
            if hand != 0 {
                if handID != 0 && handID != hand { exact = false; identity.rejected = true }
                handID = hand
            }
            if identity.matched {
                // A temporary Unknown is tolerated after positive evidence;
                // changes within the fingertip pair are allowed; role/hand changes reject.
                var expected = -1
                for index in 0..<3 where identity.trackingIDs[index] == touch.id { expected = index }
                if expected < 0 || (finger != 0 && (expected == 0 ? finger != 1 : !(2...5).contains(finger)))
                    || (hand != 0 && identity.handID != 0 && hand != identity.handID) { identity.rejected = true }
            }
        }
        if count == 0 {
            identities[device] = nil
            guard completed else { return nil }
            if identity.sawThumb {
                return thumbEnabled && identity.matched && !identity.rejected ? .thumbTwoTap : nil
            }
            return ordinaryEnabled ? .threeFingerTap : nil
        }
        if identity.matched && identity.handID == 0 { identity.handID = handID }
        // Provisional app geometry, not recovered DSP coefficients: a separated
        // thumb and a closer fingertip pair, independent of hand orientation.
        let pair = hypot(points[2]-points[4],points[3]-points[5])
        let near = min(hypot(points[0]-points[2],points[1]-points[3]),hypot(points[0]-points[4],points[1]-points[5]))
        let spread = pair >= 2 && pair <= 40 && near >= 15 && near >= pair*1.5
        if count == 3 && exact && mask == 7 && spread && !identity.matched {
            identity.matched = true; identity.trackingIDs = trackingIDs; identity.handID = handID
        }
        identities[device] = identity
        return nil
    }
}

/// Balanced secondary edges are prepared together; right-click never holds.
enum SecondaryTapClickOutput {
    static func events(location: CGPoint, flags: CGEventFlags = []) -> PrimaryTapClickOutput.Events? {
        guard location.x.isFinite, location.y.isFinite,
              let down = CGEvent(mouseEventSource:nil,mouseType:.rightMouseDown,mouseCursorPosition:location,mouseButton:.right),
              let up = CGEvent(mouseEventSource:nil,mouseType:.rightMouseUp,mouseCursorPosition:location,mouseButton:.right) else { return nil }
        for event in [down,up] {
            event.flags = flags
            event.setIntegerValueField(.mouseEventClickState,value:1)
            event.setIntegerValueField(.mouseEventButtonNumber,value:1)
            event.setIntegerValueField(.eventSourceUserData,value:SelectedTrackpadEventPolicy.interpreterTag)
        }
        down.setDoubleValueField(.mouseEventPressure,value:1)
        up.setDoubleValueField(.mouseEventPressure,value:0)
        return PrimaryTapClickOutput.Events(down:down,up:up)
    }
}


/// Action dispatch is separate from tap recognition. Build the complete sequence
/// before live code posts any edge; tests can inspect it without posting.
enum GestureTapActionOutput {
    static func events(action: GestureAction, location: CGPoint, time: Double,
        doubleClickInterval: Double, flags: CGEventFlags = [], clicks: inout PrimaryTapClickOutput, shortcut: AppleShortcutPlan? = nil) -> [CGEvent]? {
        if action.isAppleShortcut {
            clicks.reset()
            return shortcut?.events()
        }
        switch action {
        case .primaryClick:
            guard let pair = clicks.events(location:location,time:time,doubleClickInterval:doubleClickInterval,flags:flags) else { return nil }
            return [pair.down,pair.up]
        case .primaryDoubleClick:
            guard let sequence = PrimaryTapClickOutput.doubleClickEvents(location:location,flags:flags) else { return nil }
            clicks.reset()
            return [sequence.first.down,sequence.first.up,sequence.second.down,sequence.second.up]
        case .secondaryClick:
            guard let pair = SecondaryTapClickOutput.events(location:location,flags:flags) else { return nil }
            clicks.reset()
            return [pair.down,pair.up]
        default: return nil
        }
    }
}

// Historical diagnostic name for the same compact-row input geometry.
typealias ThreeFingerDragChord = ThreeFingerRowChord

/// Read symbolic-shortcut preferences only during configuration, never in input callbacks.
/// No preferences are changed. Missing entries use Apple's documented keyboard shortcuts.
struct AppleShortcutPlan: Equatable, Sendable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
    var dockMessage: String? = nil
    var mediaKeyType: Int32? = nil
    var eventTap: CGEventTapLocation { mediaKeyType == nil ? .cghidEventTap : .cgSessionEventTap }
    private typealias DockSender = @convention(c) (CFString, Int32) -> Void
    // Loaded by configuration, never first loaded in a contact callback. Keep handle resident.
    private static let dockSender: DockSender? = {
        let path = "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/HIServices"
        guard let handle = dlopen(path,RTLD_LAZY | RTLD_LOCAL),
              let symbol = dlsym(handle,"CoreDockSendNotification") else { return nil }
        return unsafeBitCast(symbol,to:DockSender.self)
    }()
    static func symbolicID(_ action: GestureAction) -> String? {
        switch action {
        case .missionControl: return "32"; case .appExpose: return "33"
        case .showDesktop: return "36"; case .launchpad: return "160"
        case .notificationCenter: return "163"; default: return nil
        }
    }
    static func resolve(_ action: GestureAction, preferences: [String:Any]) -> Self? {
        // Same media codes and Option–Shift encoding as GlassToKey's fine controls.
        let mediaCode: Int32?
        switch action {
        case .volumeUpSmall: mediaCode = 0
        case .volumeDownSmall: mediaCode = 1
        case .brightnessUpSmall: mediaCode = 2
        case .brightnessDownSmall: mediaCode = 3
        default: mediaCode = nil
        }
        if let mediaCode { return Self(keyCode:0,flags:[.maskShift,.maskAlternate],mediaKeyType:mediaCode) }
        // Dock actions must not depend on configurable (or disabled) Control-arrow shortcuts.
        if action == .missionControl || action == .appExpose {
            return Self(keyCode:0,flags:[],dockMessage:action == .missionControl
                ? "com.apple.expose.awake" : "com.apple.expose.front.awake")
        }
        guard let id = symbolicID(action) else { return nil }
        if let entry = preferences[id] as? [String:Any], (entry["enabled"] as? NSNumber)?.boolValue == true {
            guard let value = entry["value"] as? [String:Any], value["type"] as? String == "standard",
                  let parameters = value["parameters"] as? [NSNumber], parameters.count == 3 else { return nil }
            let code = parameters[1].intValue, modifiers = parameters[2].int64Value
            let allowed: CGEventFlags = [.maskShift,.maskControl,.maskAlternate,.maskCommand,.maskSecondaryFn]
            guard (0...127).contains(code), modifiers >= 0, UInt64(modifiers) & ~allowed.rawValue == 0 else { return nil }
            return Self(keyCode:CGKeyCode(code),flags:CGEventFlags(rawValue:UInt64(modifiers)))
        }
        // Globe shortcuts remain available independently of configurable symbolic shortcuts.
        switch action {
        case .notificationCenter: return Self(keyCode:45,flags:.maskSecondaryFn) // Fn-N
        case .launchpad: return Self(keyCode:0,flags:[.maskSecondaryFn,.maskShift]) // Fn-Shift-A; Apps on Tahoe+
        case .showDesktop: return Self(keyCode:4,flags:.maskSecondaryFn) // Fn-H
        default: return nil
        }
    }
    static func load() -> [GestureAction:Self] {
        let preferences = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString) as? [String:Any] ?? [:]
        let dockAvailable = dockSender != nil
        return Dictionary(uniqueKeysWithValues:GestureAction.oneShotActions.compactMap { action in
            guard let plan = resolve(action,preferences:preferences), plan.dockMessage == nil || dockAvailable else { return nil }
            return (action,plan)
        })
    }
    /// Native Dock requests have no keyboard edges and never change shortcut preferences.
    @discardableResult func postDock(phase: GestureSessionPhase = .began) -> Bool {
        guard phase == .began, let dockMessage, let sender = Self.dockSender else { return false }
        sender(dockMessage as CFString,0)
        return true
    }
    func events(phase: GestureSessionPhase = .began) -> [CGEvent]? {
        guard phase == .began, dockMessage == nil else { return nil }
        if let mediaKeyType {
            var events: [CGEvent] = []
            for state: Int32 in [0xA,0xB] {
                var modifiers = NSEvent.ModifierFlags(rawValue:UInt(state << 8))
                modifiers.formUnion([.shift,.option])
                guard let event = NSEvent.otherEvent(with:.systemDefined,location:.zero,
                    modifierFlags:modifiers,timestamp:ProcessInfo.processInfo.systemUptime,
                    windowNumber:0,context:nil,subtype:8,
                    data1:Int((mediaKeyType << 16) | (state << 8)),data2:-1)?.cgEvent else { return nil }
                event.setIntegerValueField(.eventSourceUserData,value:SelectedTrackpadEventPolicy.interpreterTag)
                events.append(event)
            }
            return events
        }
        guard let down = CGEvent(keyboardEventSource:nil,virtualKey:keyCode,keyDown:true),
              let up = CGEvent(keyboardEventSource:nil,virtualKey:keyCode,keyDown:false) else { return nil }
        for event in [down,up] {
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData,value:SelectedTrackpadEventPolicy.interpreterTag)
        }
        return [down,up]
    }
}

import CoreGraphics
import Foundation
import OpenMultitouchSupport

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
enum ThreeFingerDragChord {
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
        // Rotation-independent line fit. Reject a splayed/triangular thumb chord.
        guard abs(dx*my-dy*mx)/longest <= 8 else { return false }
        return hypot(mx,my) <= 35 && hypot(mx-dx,my-dy) <= 35
    }
}

/// One global primary-button owner. All methods are confined to the live output
/// lock (or an offline test). The reserved up event exists before down is returned.
struct PrimaryDragOutput: @unchecked Sendable {
    private(set) var owner: UInt64?
    private(set) var location: CGPoint?
    private var releaseEvent: CGEvent?
    private var source: CGEventSource?
    mutating func begin(device: UInt64, location: CGPoint, flags: CGEventFlags) -> CGEvent? {
        guard owner == nil, location.x.isFinite, location.y.isFinite,
              let source = CGEventSource(stateID:.privateState),
              let down = CGEvent(mouseEventSource:source,mouseType:.leftMouseDown,mouseCursorPosition:location,mouseButton:.left),
              let up = CGEvent(mouseEventSource:source,mouseType:.leftMouseUp,mouseCursorPosition:location,mouseButton:.left) else { return nil }
        self.source = source; owner = device; self.location = location; releaseEvent = up
        Self.configure(down,flags:flags,pressure:1)
        Self.configure(up,flags:flags,pressure:0)
        return down
    }
    mutating func move(device: UInt64, location: CGPoint, delta: CGPoint, flags: CGEventFlags) -> CGEvent? {
        guard owner == device, location.x.isFinite, location.y.isFinite,
              delta.x.isFinite, delta.y.isFinite,
              let event = CGEvent(mouseEventSource:source,mouseType:.leftMouseDragged,mouseCursorPosition:location,mouseButton:.left) else { return nil }
        Self.configure(event,flags:flags,pressure:1)
        event.setDoubleValueField(.mouseEventDeltaX,value:delta.x)
        event.setDoubleValueField(.mouseEventDeltaY,value:delta.y)
        self.location = location
        releaseEvent?.location = location; releaseEvent?.flags = flags
        return event
    }
    mutating func end(device: UInt64? = nil, location: CGPoint? = nil) -> CGEvent? {
        guard device == nil || owner == device else { return nil }
        if let location, location.x.isFinite, location.y.isFinite { releaseEvent?.location = location }
        releaseEvent?.timestamp = DispatchTime.now().uptimeNanoseconds
        let up = releaseEvent
        owner = nil; self.location = nil; releaseEvent = nil; source = nil
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

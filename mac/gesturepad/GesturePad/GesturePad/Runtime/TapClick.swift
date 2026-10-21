import CoreGraphics
import Foundation
import OpenMultitouchSupport

/// A discrete tap completes on all-up, independently of continuous gesture latches.
struct TwoFingerTapRecognizer {
    static let maximumDuration = 0.5
    private struct Finger { let id: Int32; let x: Double; let y: Double }
    private struct Session {
        var first: Finger?, second: Finger?
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
        var a: OMSRawTouch?, b: OMSRawTouch?, count = 0
        var invalid = !time.isFinite
        for touch in contacts where touch.state == .making || touch.state == .touching {
            count += 1
            invalid = invalid || !touch.posX.isFinite || !touch.posY.isFinite || touch.telemetry?.fingerID == 6
            if a == nil { a = touch } else if b == nil { b = touch }
        }
        if let a, let b, a.id == b.id { invalid = true }
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
        guard !invalid, count <= 2, !gestureActive else { cancel(device:device); return false }
        var session = sessions[device] ?? Session(started:time,lastTime:time)
        if sessions[device] != nil {
            guard time > session.lastTime, time-session.lastTime <= 0.15,
                  time-session.started <= Self.maximumDuration else { cancel(device:device); return false }
        }
        for touch in contacts where touch.state == .making || touch.state == .touching {
            let original: Finger
            if let first = session.first, first.id == touch.id { original = first }
            else if let second = session.second, second.id == touch.id { original = second }
            else {
                guard session.paired == nil, time-session.started <= 0.08 else {
                    cancel(device:device); return false
                }
                let finger = Finger(id:touch.id,x:Double(touch.posX),y:Double(touch.posY))
                if session.first == nil { session.first = finger }
                else if session.second == nil { session.second = finger }
                else { cancel(device:device); return false }
                original = finger
            }
            guard hypot((Double(touch.posX)-original.x)*160,(Double(touch.posY)-original.y)*114.9) <= 1 else {
                cancel(device:device); return false
            }
        }
        if count == 2 {
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

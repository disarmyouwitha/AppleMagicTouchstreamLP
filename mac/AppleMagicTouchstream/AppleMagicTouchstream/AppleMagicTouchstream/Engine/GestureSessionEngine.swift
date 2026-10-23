import CoreGraphics
import OpenMultitouchSupport

/// Recognition owns a gesture, never its output events or acceleration history.
enum GestureSessionPhase: Equatable, Sendable { case pending, began, changed, ended, cancelled }
enum GestureCancellationReason: Equatable, Sendable { case contactDiscontinuity, disabled, continuationRejected, explicitReset }

struct GestureActivationContext: Sendable {
    let time: Double
    let activeCount: Int
    let frameMovementMM: CGPoint
    let pendingMovementMM: CGPoint
}

struct GestureSessionUpdate<Gesture: Hashable & Sendable>: Sendable {
    let gesture: Gesture?
    let phase: GestureSessionPhase
    let millimetres: CGPoint?
    let cancellation: GestureCancellationReason?
    var scaleDelta: Double? = nil
}

/// Rules are configured outside callbacks. Array order is activation priority;
/// an existing owner always takes precedence over every pending candidate.
struct GestureActivationRule<Gesture: Hashable & Sendable>: Sendable {
    enum Continuation: Sendable {
        case untilAllUp
        case contactCount(ClosedRange<Int>)
        func permits(_ count: Int) -> Bool {
            switch self {
            case .untilAllUp: return count > 0
            case .contactCount(let allowed): return allowed.contains(count)
            }
        }
    }
    let gesture: Gesture
    let activationCount: Int
    let minimumMovementMM: Double
    var continuation: Continuation = .untilAllUp
}

/// Generic continuous gesture ownership, per physical pad. Discrete recognizers
/// may observe pending input but must cancel when this engine commits an owner.
/// No event posting, timers, I/O or per-frame candidate arrays/sets.
struct GestureSessionEngine<Gesture: Hashable & Sendable>: Sendable {
    private struct Session: Sendable {
        var pendingCount = 0
        var travel = CGPoint.zero
        var ownerRule: Int?
    }
    private let rules: [GestureActivationRule<Gesture>]
    private var contacts = GestureContactMotionTracker()
    private var sessions: [UInt64:Session] = Dictionary(minimumCapacity:2)
    init(rules: [GestureActivationRule<Gesture>]) {
        precondition(rules.allSatisfy { $0.activationCount > 0 && $0.minimumMovementMM.isFinite && $0.minimumMovementMM >= 0 })
        self.rules = rules
    }
    func owner(device: UInt64) -> Gesture? { sessions[device]?.ownerRule.map { rules[$0].gesture } }
    mutating func reset() { contacts.reset(); sessions.removeAll(keepingCapacity:true) }
    @discardableResult
    mutating func cancel(device: UInt64, reason: GestureCancellationReason = .explicitReset) -> GestureSessionUpdate<Gesture> {
        let owner = sessions.removeValue(forKey:device)?.ownerRule.map { rules[$0].gesture }
        contacts.reset(device:device)
        return GestureSessionUpdate(gesture:owner,phase:.cancelled,millimetres:nil,cancellation:reason)
    }
    mutating func process<C: Collection>(device: UInt64, time: Double, touches: C,
        enabled: (Gesture) -> Bool,
        activationFilter: (Gesture, GestureActivationContext) -> Bool = { _,_ in true }
    ) -> GestureSessionUpdate<Gesture> where C.Element == OMSRawTouch {
        // Count active contacts separately from validity: malformed input must
        // cancel rather than masquerade as normal all-up completion.
        var activeCount = 0
        for touch in touches where touch.state == .making || touch.state == .touching { activeCount += 1 }
        let movement = contacts.millimetres(device:device,time:time,contacts:touches)
        if !contacts.frameContinued {
            let prior = sessions.removeValue(forKey:device)?.ownerRule.map { rules[$0].gesture }
            if let prior {
                let completed = contacts.frameEndedNormally
                return GestureSessionUpdate(gesture:prior,phase:completed ? .ended : .cancelled,
                    millimetres:nil,cancellation:completed ? nil : .contactDiscontinuity)
            }
        }
        guard let movement else { return GestureSessionUpdate(gesture:nil,phase:.pending,millimetres:nil,cancellation:nil) }
        var session = sessions[device] ?? Session()
        if let index = session.ownerRule {
            let rule = rules[index]
            guard enabled(rule.gesture) else { return cancel(device:device,reason:.disabled) }
            guard rule.continuation.permits(activeCount) else { return cancel(device:device,reason:.continuationRejected) }
            return GestureSessionUpdate(gesture:rule.gesture,phase:.changed,millimetres:movement,cancellation:nil)
        }
        if session.pendingCount != activeCount { session.pendingCount = activeCount; session.travel = .zero }
        session.travel.x += movement.x; session.travel.y += movement.y
        let distance = hypot(session.travel.x,session.travel.y)
        let context = GestureActivationContext(time:time,activeCount:activeCount,
            frameMovementMM:movement,pendingMovementMM:session.travel)
        for index in rules.indices {
            let rule = rules[index]
            if rule.activationCount == activeCount && enabled(rule.gesture) && distance >= rule.minimumMovementMM && activationFilter(rule.gesture,context) {
                session.ownerRule = index
                sessions[device] = session
                return GestureSessionUpdate(gesture:rule.gesture,phase:.began,millimetres:session.travel,cancellation:nil)
            }
        }
        sessions[device] = session
        return GestureSessionUpdate(gesture:nil,phase:.pending,millimetres:nil,cancellation:nil)
    }
}

/// Shared contact identity/continuity and matched-contact motion; no gesture owner.
struct GestureContactMotionTracker: Sendable {
    private(set) var activeCount = 0
    // Fixed storage avoids per-frame arrays/sets on the contact callback. This
    // exceeds the supported pads' finger capacity; overflow cancels safely.
    struct Baseline: Sendable {
        var ids = SIMD16<Int32>(repeating: 0)
        var x = SIMD16<Double>(repeating: 0)
        var y = SIMD16<Double>(repeating: 0)
        var count = 0
        var time: Double
    }
    private var sessions: [UInt64: Baseline] = Dictionary(minimumCapacity: 2)
    private let activationCount: Int
    private(set) var frameContinued = false
    private(set) var frameEndedNormally = false
    init(activationCount: Int = 0) { self.activationCount = activationCount }
    mutating func reset() { sessions.removeAll(keepingCapacity: true) }
    mutating func reset(device: UInt64) { sessions[device] = nil }
    mutating func millimetres<C: Collection>(device: UInt64, time: Double, contacts: C) -> CGPoint? where C.Element == OMSRawTouch {
        frameContinued = false
        frameEndedNormally = false
        activeCount = 0
        guard time.isFinite else { sessions[device] = nil; return nil }
        var next = Baseline(time: time)
        for touch in contacts where touch.state == .making || touch.state == .touching {
            guard next.count < 16, touch.telemetry?.fingerID != 6,
                  touch.posX.isFinite, touch.posY.isFinite else {
                sessions[device] = nil; return nil
            }
            for index in 0..<next.count where next.ids[index] == touch.id {
                sessions[device] = nil; return nil
            }
            let index = next.count
            next.ids[index] = touch.id
            next.x[index] = Double(touch.posX); next.y[index] = Double(touch.posY)
            next.count += 1
        }
        activeCount = next.count
        guard next.count > 0 else {
            if let old = sessions[device] { frameEndedNormally = time > old.time && time-old.time < 0.15 }
            sessions[device] = nil
            return nil
        }
        guard let old = sessions[device], time > old.time, time - old.time < 0.15 else {
            // A discontinuity establishes a fresh baseline, never synthetic motion.
            sessions[device] = activationCount == 0 || next.count == activationCount ? next : nil
            return nil
        }
        var dx = 0.0, dy = 0.0, shared = 0
        for index in 0..<next.count {
            for previous in 0..<old.count where next.ids[index] == old.ids[previous] {
                dx += next.x[index] - old.x[previous]
                dy += next.y[index] - old.y[previous]
                shared += 1
                break
            }
        }
        guard shared > 0 else {
            // All old IDs disappeared, even if an all-up frame was missed.
            sessions[device] = activationCount == 0 || next.count == activationCount ? next : nil
            return nil
        }
        frameContinued = true
        sessions[device] = next
        // Use only continuing contacts for this interval. New fingers establish
        // their own baseline and cannot cause a centroid jump when joining.
        // On stable membership this equals the centroid's displacement.
        let delta = CGPoint(x: dx / Double(shared) * 160,
                            y: -dy / Double(shared) * 114.9)
        guard abs(delta.x) < 25, abs(delta.y) < 25 else { return nil }
        return delta
    }
}

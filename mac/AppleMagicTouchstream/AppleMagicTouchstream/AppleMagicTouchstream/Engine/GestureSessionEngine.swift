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

/// Direction changes after shared three-finger ownership. Repetition uses a separate host clock.
struct GestureDirectionalStepper {
    static let activationMM = 0.75
    static let minimumOutputInterval = 0.08
    private struct Session {
        var initial = CGPoint.zero
        var direction: GestureMovementDirection?
        var candidate: GestureMovementDirection?
        var candidateMM = 0.0
        var lastTime: Double?
        var lastOutput = -Double.infinity
    }
    private var sessions: [UInt64:Session] = Dictionary(minimumCapacity:2)
    mutating func reset() { sessions.removeAll(keepingCapacity:true) }
    mutating func reset(device:UInt64) { sessions[device] = nil }
    private func dominant(_ delta:CGPoint) -> GestureMovementDirection? {
        let x = Double(delta.x), y = Double(delta.y)
        if abs(x) > 0 && abs(x) >= abs(y)*1.25 { return x > 0 ? .right : .left }
        if abs(y) > 0 && abs(y) >= abs(x)*1.25 { return y > 0 ? .down : .up }
        return nil
    }
    private func projection(_ delta:CGPoint,onto direction:GestureMovementDirection) -> Double {
        switch direction {
        case .up: return -Double(delta.y); case .down: return Double(delta.y)
        case .left: return -Double(delta.x); case .right: return Double(delta.x)
        }
    }
    mutating func process(device:UInt64,time:Double,update:GestureSessionUpdate<GestureTrigger>,
                          assignments:GestureDirectionalAssignments) -> GestureMovementDirection? {
        guard assignments.mode == .directional, update.gesture == .threeFingerMove,
              update.phase == .began || update.phase == .changed else { reset(device:device); return nil }
        if update.phase == .began { reset(device:device) }
        guard update.phase == .began || sessions[device] != nil,
              let delta = update.millimetres, time.isFinite,
              delta.x.isFinite, delta.y.isFinite, abs(delta.x)<25, abs(delta.y)<25 else {
            reset(device:device); return nil
        }
        var session = sessions[device] ?? Session()
        if let previous = session.lastTime, !(time > previous && time-previous < 0.15) {
            reset(device:device); return nil
        }
        session.lastTime = time
        defer { sessions[device] = session }
        // Stationary frames retain the direction; the host-clock repeater handles output.
        guard delta != .zero else { return nil }
        guard let current = session.direction else {
            session.initial.x += delta.x; session.initial.y += delta.y
            guard let direction = dominant(session.initial),
                  projection(session.initial,onto:direction) >= Self.activationMM else { return nil }
            session.direction = direction; session.initial = .zero; session.lastOutput = time
            return direction
        }
        if let candidate = dominant(delta), candidate != current {
            if candidate != session.candidate { session.candidate = candidate; session.candidateMM = 0 }
            session.candidateMM += projection(delta,onto:candidate)
            guard session.candidateMM >= Self.activationMM,
                  time-session.lastOutput >= Self.minimumOutputInterval else { return nil }
            session.direction = candidate; session.candidate = nil; session.candidateMM = 0
            session.lastOutput = time
            return candidate
        }
        session.candidate = nil; session.candidateMM = 0
        return nil
    }
    func direction(device:UInt64) -> GestureMovementDirection? { sessions[device]?.direction }
}

/// Timer policy is pure and uses host time only. At most one event per tick,
/// with no catch-up bursts; loss of contact delivery cancels the held state.
struct GestureDirectionalRepeater {
    private struct Held {
        var direction:GestureMovementDirection
        var interval:Double
        var deadline:Double
        var receipt:Double
    }
    private var held:[UInt64:Held] = Dictionary(minimumCapacity:2)
    mutating func reset() { held.removeAll(keepingCapacity:true) }
    mutating func reset(device:UInt64) { held[device] = nil }
    mutating func refresh(device:UInt64,direction:GestureMovementDirection?,intervalMS:Double,now:Double) {
        let interval = GestureDirectionalAssignments.boundedIntervalMS(intervalMS)/1000
        guard let direction, interval > 0, now.isFinite else { reset(device:device); return }
        if var current = held[device], current.direction == direction, current.interval == interval,
           now >= current.receipt, now-current.receipt <= 0.2 {
            current.receipt = now; held[device] = current
        } else {
            held[device] = Held(direction:direction,interval:interval,deadline:now+interval,receipt:now)
        }
    }
    mutating func tick(device:UInt64,now:Double) -> GestureMovementDirection? {
        guard var current = held[device] else { return nil }
        guard now.isFinite, now >= current.receipt, now-current.receipt <= 0.2 else {
            reset(device:device); return nil
        }
        guard now >= current.deadline else { return nil }
        current.deadline = now+current.interval
        held[device] = current
        return current.direction
    }
}


/// Both pads use host time: native clocks may have different offsets. No output,
/// timers or I/O here; the live runtime supplies freshness ticks under its lock.
struct TwoHandGestureEngine {
    static let joinWindow = 0.15, staleWindow = 0.2, tapWindow = 0.5, movementSlopMM = 2.0
    private struct Sample {
        var time:Double, downAt:Double
        var count = 0, invalid = false
        var ids = SIMD8<Int32>(repeating:0)
        var points = SIMD16<Double>(repeating:0)
        func corners(left:Bool) -> Bool {
            count == 2 && !invalid && (left ? max(points[0],points[2]) <= 0.2 : min(points[0],points[2]) >= 0.8)
                && min(points[1],points[3]) <= 0.2 && max(points[1],points[3]) >= 0.8
        }
        func continues(_ anchor:Self) -> Bool {
            guard !invalid, count <= anchor.count else { return false }
            for i in 0..<count {
                guard let j = (0..<anchor.count).first(where:{anchor.ids[$0] == ids[i]}),
                      hypot((points[i*2]-anchor.points[j*2])*160,(points[i*2+1]-anchor.points[j*2+1])*114.9) <= TwoHandGestureEngine.movementSlopMM else { return false }
            }
            return true
        }
    }
    private struct Session {
        var chord:TwoHandChord, left:Sample, right:Sample, start:Double
        var valid = true, held = false, tapEligible = true
        var firstLift:Double?
    }
    struct Decision { var reserved:Bool = false; var trigger:TwoHandTrigger?; var began:Bool = false; var pending:Bool = false }
    private var left:Sample?, right:Sample?, session:Session?
    mutating func reset() { left = nil; right = nil; session = nil }
    var ownsCycle:Bool { session != nil }
    private func fresh(_ value:Sample?,now:Double) -> Bool {
        guard let value else { return false }; return now >= value.time && now-value.time <= Self.staleWindow
    }
    mutating func process<C:Collection>(leftHand:Bool,now:Double,contacts:C,
        settings:TwoHandGestureSettings,blocked:Bool = false) -> Decision where C.Element == OMSRawTouch {
        guard now.isFinite else { reset(); return Decision() }
        if blocked { reset(); return Decision() }
        let previous = leftHand ? left : right
        var sample = Sample(time:now,downAt:(previous?.count ?? 0) > 0 ? previous!.downAt : now)
        for touch in contacts where touch.state == .making || touch.state == .touching {
            let i = sample.count
            if i >= 8 { sample.invalid = true; continue }
            sample.invalid = sample.invalid || !touch.posX.isFinite || !touch.posY.isFinite
                || touch.posX < 0 || touch.posX > 1 || touch.posY < 0 || touch.posY > 1 || touch.telemetry?.fingerID == 6
                || (0..<i).contains(where:{sample.ids[$0] == touch.id})
            sample.ids[i] = touch.id; sample.points[i*2] = Double(touch.posX); sample.points[i*2+1] = Double(touch.posY)
            sample.count += 1
        }
        if leftHand { left = sample } else { right = sample }
        if var current = session, let left, let right {
            if !fresh(left,now:now) || !fresh(right,now:now) || !left.continues(current.left) || !right.continues(current.right) { current.valid = false }
            if current.firstLift != nil && sample.count > (previous?.count ?? 0) { current.valid = false }
            if left.count < current.left.count || right.count < current.right.count {
                if current.firstLift == nil { current.firstLift = now }
            }
            session = current
            if left.count == 0 && right.count == 0 {
                session = nil
                let tap = TwoHandTrigger(chord:current.chord,phase:.tap)
                let accepted = current.valid && current.tapEligible && !current.held && now-current.start >= 0.02 && now-current.start <= Self.tapWindow
                    && now-(current.firstLift ?? now) <= Self.joinWindow && settings.action(tap) != .disabled
                return Decision(reserved:true,trigger:accepted ? tap : nil)
            }
            return Decision(reserved:true,trigger:advance(now:now,settings:settings))
        }
        if let left, let right, fresh(left,now:now), fresh(right,now:now), !left.invalid, !right.invalid {
            for chord in TwoHandChord.recognitionOrder where settings.enabled(chord) {
                guard left.count == chord.count, right.count == chord.count else { continue }
                if chord == .fourCorners {
                    guard left.corners(left:true), right.corners(left:false) else { continue }
                }
                let joined = chord == .fourCorners || abs(left.downAt-right.downAt) <= Self.joinWindow
                guard joined || settings.action(.init(chord:chord,phase:.hold)) != .disabled else { continue }
                session = Session(chord:chord,left:left,right:right,start:now,tapEligible:joined)
                return Decision(reserved:true,began:true)
            }
        }
        // Give the other hand a short join opportunity only for enabled chords.
        // The default corner hold delays only the actual outer-corner posture.
        let pending = TwoHandChord.recognitionOrder.contains { chord in
            settings.enabled(chord) && !sample.invalid && sample.count == chord.count && now-sample.downAt <= Self.joinWindow
                && (chord != .fourCorners || sample.corners(left:leftHand))
        }
        return Decision(pending:pending)
    }
    mutating func advance(now:Double,settings:TwoHandGestureSettings) -> TwoHandTrigger? {
        guard var current = session, let left, let right else { return nil }
        if !now.isFinite || !fresh(left,now:now) || !fresh(right,now:now) { current.valid = false }
        defer { session = current }
        guard current.valid, !current.held, current.firstLift == nil,
              now-current.start >= current.chord.holdDuration else { return nil }
        current.held = true
        let hold = TwoHandTrigger(chord:current.chord,phase:.hold)
        return settings.action(hold) != .disabled ? hold : nil
    }
}

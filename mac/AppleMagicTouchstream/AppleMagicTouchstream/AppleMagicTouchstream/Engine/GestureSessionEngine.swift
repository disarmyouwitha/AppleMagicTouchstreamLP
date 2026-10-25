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

/// Direction changes after shared two/three/four-finger ownership. Repetition uses a separate host clock.
struct GestureDirectionalStepper {
    static let activationMM = 0.75
    static let minimumOutputInterval = 0.08
    private struct Session {
        var trigger = GestureTrigger.threeFingerMove
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
        guard assignments.mode == .directional, let trigger = update.gesture,
              GestureDirectionalAssignments.liveTriggers.contains(trigger),
              update.phase == .began || update.phase == .changed else { reset(device:device); return nil }
        if update.phase == .began { reset(device:device) }
        guard update.phase == .began || sessions[device] != nil,
              let delta = update.millimetres, time.isFinite,
              delta.x.isFinite, delta.y.isFinite, abs(delta.x)<25, abs(delta.y)<25 else {
            reset(device:device); return nil
        }
        var session = sessions[device] ?? Session(trigger:trigger)
        guard session.trigger == trigger else { reset(device:device); return nil }
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
    func trigger(device:UInt64) -> GestureTrigger? { sessions[device]?.trigger }
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
        var valid = true, held = false
        var firstLift:Double?
    }
    struct Decision { var reserved:Bool = false; var trigger:TwoHandTrigger?; var began:Bool = false }
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
                let accepted = current.valid && !current.held && now-current.start >= 0.02 && now-current.start <= Self.tapWindow
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
                session = Session(chord:chord,left:left,right:right,start:now)
                return Decision(reserved:true,began:true)
            }
        }
        return Decision()
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

/// A stationary count-based chord, independent per pad. Motion wins before the
/// deadline; a fired Hold owns the remaining cycle, including membership changes.
struct GestureHoldRecognizer {
    static let duration = 0.5
    static let landingWindow = 0.08
    static let movementSlopMM = 2.0
    static func motionClaimsHold(_ update:GestureSessionUpdate<GestureTrigger>,directional:Bool,
                                 direction:GestureMovementDirection?) -> Bool {
        update.phase == .cancelled || (update.gesture != nil && (!directional || direction != nil))
    }
    private struct Session {
        var baseline = GestureContactMotionTracker.Baseline(time:0)
        var first = 0.0, started = 0.0, receipt = 0.0
        var blocked = false, fired = false, sawThumb = false
        var key:Int?
    }
    private var sessions:[UInt64:Session] = Dictionary(minimumCapacity:2)
    func claimed(device:UInt64) -> Bool { sessions[device]?.fired == true }
    mutating func cancel(device:UInt64) {
        var session = sessions[device] ?? Session()
        session.blocked = true; session.fired = false; sessions[device] = session
    }
    mutating func reset() { for device in sessions.keys { cancel(device:device) } }
    mutating func observe<C:Collection>(device:UInt64,time:Double,now:Double,contacts:C,
        motionClaimed:Bool,actions:[Int:GestureAction]) -> Int? where C.Element == OMSRawTouch {
        var next = GestureContactMotionTracker.Baseline(time:time)
        var invalid = !time.isFinite || !now.isFinite
        for touch in contacts where touch.state == .making || touch.state == .touching {
            guard next.count < 16 else { invalid = true; continue }
            invalid = invalid || touch.telemetry?.fingerID == 6 || !touch.posX.isFinite || !touch.posY.isFinite
            for i in 0..<next.count where next.ids[i] == touch.id { invalid = true }
            next.ids[next.count] = touch.id
            next.x[next.count] = Double(touch.posX); next.y[next.count] = Double(touch.posY)
            next.count += 1
        }
        if next.count == 0 { sessions[device] = nil; return nil }
        let existed = sessions[device] != nil
        var session = sessions[device] ?? Session(baseline:next,first:now,started:now,receipt:now)
        defer { sessions[device] = session }
        // A fired chord remains owned even if fingers are added, lifted or relabeled.
        if session.fired { return nil }
        if session.blocked { return nil }
        let old = session.baseline
        if invalid || motionClaimed || next.count > 5 || now < session.receipt || now-session.receipt > 0.2
            || (existed && time <= old.time) || time-old.time > 0.15 {
            session.blocked = true; return nil
        }
        for i in 0..<old.count {
            guard let j = (0..<next.count).first(where:{next.ids[$0] == old.ids[i]}) else {
                session.blocked = true; return nil
            }
            if hypot((next.x[j]-old.x[i])*160,(next.y[j]-old.y[i])*114.9) > Self.movementSlopMM {
                session.blocked = true; return nil
            }
        }
        if next.count != old.count {
            guard next.count > old.count, now-session.first <= Self.landingWindow else {
                session.blocked = true; return nil
            }
            session.baseline = next; session.started = now
        }
        if next.count == 3 {
            session.sawThumb = session.sawThumb || contacts.contains { ($0.state == .making || $0.state == .touching) && $0.telemetry?.fingerID == 1 }
            if session.key != PerHandGestureSettings.thumbHoldKey {
                session.key = ThumbTwoChord.matches(contacts) ? PerHandGestureSettings.thumbHoldKey : session.sawThumb ? nil : 3
            }
        } else { session.key = next.count; session.sawThumb = false }
        // Preserve original positions for displacement, update only the frame clock.
        session.baseline.time = time; session.receipt = now
        if let key = session.key, actions[key] != nil && now-session.started >= Self.duration {
            session.fired = true; return key
        }
        return nil
    }
    mutating func advance(device:UInt64,now:Double,actions:[Int:GestureAction]) -> Int? {
        guard var session = sessions[device], !session.blocked, !session.fired else { return nil }
        defer { sessions[device] = session }
        guard now.isFinite, now >= session.receipt, now-session.receipt <= 0.2 else {
            session.blocked = true; return nil
        }
        guard let key = session.key, actions[key] != nil, now-session.started >= Self.duration else { return nil }
        session.fired = true; return key
    }
}

/// Shared spread-thumb geometry for the dedicated Thumb+2 Hold input.
enum ThumbTwoChord {
    static func matches<C:Collection>(_ contacts:C) -> Bool where C.Element == OMSRawTouch {
        var count = 0, mask = 0, points = SIMD8<Double>(repeating:0)
        var hand:Int32 = 0
        for touch in contacts where touch.state == .making || touch.state == .touching {
            count += 1
            guard touch.posX.isFinite, touch.posY.isFinite else { return false }
            let finger = touch.telemetry?.fingerID ?? 0
            let slot:Int
            switch finger { case 1:slot = 0; case 2...5:slot = mask & 2 == 0 ? 1 : 2; default:return false }
            guard mask & (1 << slot) == 0 else { return false }
            mask |= 1 << slot
            points[slot*2] = Double(touch.posX)*160; points[slot*2+1] = Double(touch.posY)*114.9
            let next = touch.telemetry?.handID ?? 0
            if next != 0 { if hand != 0 && hand != next { return false }; hand = next }
        }
        guard count == 3, mask == 7 else { return false }
        return isSpread(points)
    }
    static func isSpread(_ points:SIMD8<Double>) -> Bool {
        let pair = hypot(points[2]-points[4],points[3]-points[5])
        let near = min(hypot(points[0]-points[2],points[1]-points[3]),hypot(points[0]-points[4],points[1]-points[5]))
        return pair >= 2 && pair <= 40 && near >= 15 && near >= pair*1.5
    }
}

/// Single-frame corner chord using Both's geometry, timing and freshness rules.
/// Every contact is validated atomically; partial lifts remain reserved until all-up.
struct SinglePadCornersEngine {
    private struct Session {
        var anchor:GestureContactMotionTracker.Baseline
        var start:Double, receipt:Double
        var count = 4
        var firstLift:Double?
        var valid = true, held = false
    }
    private var session:Session?
    var ownsCycle:Bool { session != nil }
    mutating func reset() { session = nil }
    static func matches<C:Collection>(_ contacts:C) -> Bool where C.Element == OMSRawTouch {
        var count = 0, mask = 0, ids = SIMD4<Int32>(repeating:0)
        for touch in contacts where touch.state == .making || touch.state == .touching {
            guard count < 4, touch.posX.isFinite, touch.posY.isFinite, touch.telemetry?.fingerID != 6,
                  touch.posX >= 0, touch.posX <= 1, touch.posY >= 0, touch.posY <= 1 else { return false }
            for i in 0..<count where ids[i] == touch.id { return false }
            ids[count] = touch.id; count += 1
            let column = touch.posX <= 0.2 ? 0 : touch.posX >= 0.8 ? 1 : -1
            let row = touch.posY <= 0.2 ? 0 : touch.posY >= 0.8 ? 1 : -1
            guard column >= 0, row >= 0 else { return false }
            let bit = 1 << (column*2+row)
            guard mask & bit == 0 else { return false }; mask |= bit
        }
        return count == 4 && mask == 15
    }
    mutating func process<C:Collection>(now:Double,contacts:C,settings:TwoHandGestureSettings) -> TwoHandGestureEngine.Decision where C.Element == OMSRawTouch {
        var frame = GestureContactMotionTracker.Baseline(time:now)
        var invalid = !now.isFinite
        for touch in contacts where touch.state == .making || touch.state == .touching {
            guard frame.count < 16 else { invalid = true; continue }
            invalid = invalid || !touch.posX.isFinite || !touch.posY.isFinite || touch.telemetry?.fingerID == 6
                || touch.posX < 0 || touch.posX > 1 || touch.posY < 0 || touch.posY > 1
            for i in 0..<frame.count where frame.ids[i] == touch.id { invalid = true }
            frame.ids[frame.count] = touch.id; frame.x[frame.count] = Double(touch.posX); frame.y[frame.count] = Double(touch.posY)
            frame.count += 1
        }
        guard var current = session else {
            guard !invalid, Self.matches(contacts), settings.enabled(.fourCorners) else { return .init() }
            session = Session(anchor:frame,start:now,receipt:now)
            return .init(reserved:true,began:true)
        }
        if invalid || now < current.receipt || now-current.receipt > TwoHandGestureEngine.staleWindow { current.valid = false }
        for i in 0..<frame.count {
            guard let j = (0..<4).first(where:{current.anchor.ids[$0] == frame.ids[i]}) else { current.valid = false; continue }
            if hypot((frame.x[i]-current.anchor.x[j])*160,(frame.y[i]-current.anchor.y[j])*114.9) > TwoHandGestureEngine.movementSlopMM { current.valid = false }
        }
        if current.firstLift != nil && frame.count > current.count { current.valid = false }
        if frame.count < 4 && current.firstLift == nil { current.firstLift = now }
        current.count = frame.count; current.receipt = now
        if frame.count == 0 {
            session = nil
            let tap = TwoHandTrigger(chord:.fourCorners,phase:.tap)
            let accepted = current.valid && !current.held && now-current.start >= 0.02 && now-current.start <= TwoHandGestureEngine.tapWindow
                && now-(current.firstLift ?? now) <= TwoHandGestureEngine.joinWindow && settings.action(tap) != .disabled
            return .init(reserved:true,trigger:accepted ? tap : nil)
        }
        session = current
        return .init(reserved:true,trigger:advance(now:now,settings:settings))
    }
    mutating func advance(now:Double,settings:TwoHandGestureSettings) -> TwoHandTrigger? {
        guard var current = session else { return nil }
        if !now.isFinite || now < current.receipt || now-current.receipt > TwoHandGestureEngine.staleWindow { current.valid = false }
        defer { session = current }
        guard current.valid, !current.held, current.firstLift == nil, now-current.start >= TwoHandChord.fourCorners.holdDuration else { return nil }
        current.held = true
        let hold = TwoHandTrigger(chord:.fourCorners,phase:.hold)
        return settings.action(hold) != .disabled ? hold : nil
    }
}

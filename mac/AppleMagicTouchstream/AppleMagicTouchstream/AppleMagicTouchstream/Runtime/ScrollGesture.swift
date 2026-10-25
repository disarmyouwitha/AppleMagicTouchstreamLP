import CoreGraphics
import Foundation
import IOKit
import OpenMultitouchSupport

struct AppleScrollProfile: Equatable, Sendable {
    let horizontal: ApplePointerAccelerationProfile
    let vertical: ApplePointerAccelerationProfile
    let natural: Bool
    func overridingNaturalScrolling(_ value:Bool?) -> Self {
        Self(horizontal:horizontal,vertical:vertical,natural:value ?? natural)
    }
}

/// Independent model of Apple's parametric IOHIDScrollAccelerator history branch.
/// Input is a provisional contact-mm -> device-count conversion, not native ground truth.
struct AppleScrollAxis {
    let profile: ApplePointerAccelerationProfile
    private var times = SIMD16<Double>(repeating: 0)
    private var amounts = SIMD16<Double>(repeating: 0)
    private var head = 0, tail = 0
    private var lastTime: Double?
    private var positive: Bool?
    init(profile: ApplePointerAccelerationProfile) { self.profile = profile }
    mutating func reset() { head = 0; tail = 0; lastTime = nil; positive = nil }
    mutating func points(time: Double, counts: Double) -> Double? {
        guard time.isFinite, counts.isFinite else { reset(); return nil }
        guard counts != 0 else { return 0 }
        let elapsed = lastTime.map { (time-$0)*1000 } ?? 150
        guard elapsed > 0 else { reset(); return nil }
        lastTime = time
        if profile.acceleration < 0 { return counts }
        let inserted = head
        times[head] = elapsed; amounts[head] = abs(counts)
        head = (head+1)%9
        if head == tail { tail = (tail+1)%9 }
        if positive != (counts > 0) || elapsed > 500 { tail = inserted; positive = counts > 0 }
        var sumTime = 0.0, sumAmount = 0.0, samples = 0, index = head
        repeat {
            index = (index+8)%9
            sumAmount += amounts[index]; samples += 1
            if times[index] > 150 { sumTime += 150; break }
            sumTime += times[index]
            if sumTime >= 500 { break }
        } while index != tail
        let rate = profile.algorithmRate / 67
        let meanTime = min(150,max(1,sumTime/Double(samples)*rate))
        let velocity = max(1/65536,
            (2/65536*meanTime*meanTime - 955/65536*meanTime + 98369/65536)
            * sumAmount/Double(samples)*rate)
        // Source produces wheel units with 0x199a/65536; pixel events use 10 points/wheel unit.
        let output = counts * profile.acceleratedVelocity(velocity)/velocity * (6554/65536) * 10
        guard output.isFinite, abs(output) < 150 else { reset(); return nil }
        return output
    }
}

struct FourFingerScrollEngine {
    private var x: AppleScrollAxis
    private var y: AppleScrollAxis
    let profile: AppleScrollProfile
    init(profile: AppleScrollProfile) {
        self.profile = profile
        x = AppleScrollAxis(profile:profile.horizontal); y = AppleScrollAxis(profile:profile.vertical)
    }
    mutating func reset() { x.reset(); y.reset() }
    mutating func process(time: Double, millimetres: CGPoint, sensitivity: Double) -> CGPoint? {
        let scale = min(2,max(0.25,sensitivity))
        guard let dx = x.points(time:time,counts:millimetres.x*profile.horizontal.resolution/25.4*scale),
              let dy = y.points(time:time,counts:millimetres.y*profile.vertical.resolution/25.4*scale) else {
            reset(); return nil
        }
        let direction = profile.natural ? 1.0 : -1.0
        return CGPoint(x:dx*direction,y:dy*direction)
    }
}

/// Project travel along the assigned input direction, then route it to the action's
/// scroll/pan axis and sign. Source and output directions are independent.
struct DirectionalScrollEngine {
    private var engine:FourFingerScrollEngine
    private(set) var direction:GestureMovementDirection?
    private(set) var action:GestureAction?
    init(profile:AppleScrollProfile) { engine = FourFingerScrollEngine(profile:profile) }
    mutating func reset() { engine.reset(); direction = nil; action = nil }
    func matches(direction:GestureMovementDirection,action:GestureAction) -> Bool {
        self.direction == direction && self.action == action
    }
    static func travel(_ delta:CGPoint,direction:GestureMovementDirection) -> Double {
        switch direction {
        case .up:return max(0,-Double(delta.y)); case .down:return max(0,Double(delta.y))
        case .left:return max(0,-Double(delta.x)); case .right:return max(0,Double(delta.x))
        }
    }
    mutating func process(time:Double,millimetres:CGPoint,direction:GestureMovementDirection,
                          action:GestureAction,sensitivity:Double) -> CGPoint? {
        guard action.isDirectionalScroll, time.isFinite,
              millimetres.x.isFinite, millimetres.y.isFinite else { reset(); return nil }
        if !matches(direction:direction,action:action) {
            reset(); self.direction = direction; self.action = action
        }
        let distance = Self.travel(millimetres,direction:direction)
        let mapped = action.isHorizontalPan ? CGPoint(x:distance,y:0) : CGPoint(x:0,y:distance)
        guard let points = engine.process(time:time,millimetres:mapped,sensitivity:sensitivity) else { return nil }
        // Explicit action controls output axis/sign, independently of source travel
        // and natural scrolling. Positive wheel axes mean Up / Left.
        if action.isHorizontalPan { return CGPoint(x:action == .panLeft ? abs(points.x) : -abs(points.x),y:0) }
        return CGPoint(x:0,y:action == .scrollUp ? abs(points.y) : -abs(points.y))
    }
}

/// Shape scale is independent of translation, rotation, anatomy and output.
/// RMS pairwise spacing makes every participating contact contribute equally.
struct PinchSpreadTracker {
    struct Sample { let changeMM:Double; let initialRatio:Double; let frameRatio:Double }
    private struct Frame {
        var ids = SIMD8<Int32>(repeating:0), x = SIMD8<Double>(repeating:0), y = SIMD8<Double>(repeating:0)
        var count = 0
        var time:Double
        var initial:Double = 0
        var anchor:CGPoint?
        func index(_ id:Int32) -> Int? { (0..<count).first { ids[$0] == id } }
        func point(_ index:Int) -> CGPoint { CGPoint(x:x[index],y:y[index]) }
        func center(excluding id:Int32) -> CGPoint? {
            var px=0.0, py=0.0, n=0
            for i in 0..<count where ids[i] != id { px += x[i]; py += y[i]; n += 1 }
            return n > 0 ? CGPoint(x:px/Double(n),y:py/Double(n)) : nil
        }
        func span() -> Double {
            if count == 1, let anchor { return hypot(x[0]-anchor.x,y[0]-anchor.y) }
            var sum=0.0, pairs=0
            for i in 0..<count { for j in 0..<i {
                let dx=x[i]-x[j], dy=y[i]-y[j]
                sum += dx*dx+dy*dy; pairs += 1
            } }
            return pairs > 0 ? sqrt(sum/Double(pairs)) : 0
        }
        func sameMembers(as other:Self) -> Bool {
            count == other.count && (0..<count).allSatisfy { other.index(ids[$0]) != nil }
        }
    }
    private var frames:[UInt64:Frame] = [:]
    mutating func reset() { frames.removeAll(keepingCapacity:true) }
    mutating func reset(device:UInt64) { frames[device] = nil }
    mutating func process<C:Collection>(device:UInt64,time:Double,contacts:C,latched:Bool = false) -> Sample? where C.Element == OMSRawTouch {
        var next=Frame(time:time)
        guard time.isFinite else { frames[device] = nil; return nil }
        for touch in contacts where touch.state == .making || touch.state == .touching {
            guard next.count < 5, touch.telemetry?.fingerID != 6, touch.posX.isFinite, touch.posY.isFinite,
                  next.index(touch.id) == nil else { frames[device] = nil; return nil }
            let i=next.count
            next.ids[i]=touch.id; next.x[i]=Double(touch.posX)*160; next.y[i]=Double(touch.posY)*114.9
            next.count += 1
        }
        guard next.count > 0, latched || next.count >= 2 else { frames[device] = nil; return nil }
        let old=frames[device]
        let continuous=old.map {time > $0.time && time-$0.time < 0.15} ?? false
        if latched, next.count == 1, continuous, let old {
            next.anchor = old.count == 1 ? old.anchor : old.center(excluding:next.ids[0])
        }
        let span=next.span()
        guard span >= 5, span < 200 else { frames[device] = nil; return nil }
        guard continuous, let old else {
            next.initial=span; frames[device]=next; return nil
        }
        let same=next.sameMembers(as:old)
        if !same {
            next.initial=span; frames[device]=next
            // A survivor moves against the prior non-survivor centroid. The
            // removal itself changes no geometry and introduces no jump.
            if latched, next.count == 1, let prior=old.index(next.ids[0]), let anchor=next.anchor {
                let oldSpan=hypot(old.x[prior]-anchor.x,old.y[prior]-anchor.y)
                if oldSpan >= 5, abs(span-oldSpan) < 15 {
                    return Sample(changeMM:0,initialRatio:0,frameRatio:span/oldSpan-1)
                }
            }
            // Added/replaced/returning contacts establish a fresh constellation;
            // their new geometry is a baseline, never a magnification delta.
            return latched ? Sample(changeMM:0,initialRatio:0,frameRatio:0) : nil
        }
        guard abs(span-old.span()) < 15 else { frames[device]=nil; return nil }
        next.initial=old.initial; frames[device]=next
        return Sample(changeMM:span-old.initial,initialRatio:span/old.initial-1,frameRatio:span/old.span()-1)
    }
}

/// Native magnification packet layout, validated offline through NSEvent.
/// Undocumented CGEvent fields are isolated here; no event is posted by this type.
struct MagnifyGestureOutput {
    private(set) var active = false
    private var anchor = CGPoint.zero
    private var flags = CGEventFlags()
    static let hidType = CGEventField(rawValue:110)!
    static let amount = CGEventField(rawValue:113)!
    static let phase = CGEventField(rawValue:132)!
    static func event(delta:Double,phase:Int64,location:CGPoint,flags:CGEventFlags = []) -> CGEvent? {
        guard delta.isFinite, abs(delta) <= 0.25, [1,2,4,8].contains(phase), let event=CGEvent(source:nil) else { return nil }
        event.type = CGEventType(rawValue:29)!
        event.location = location; event.flags = flags
        event.setIntegerValueField(hidType,value:8)
        event.setIntegerValueField(Self.phase,value:phase)
        event.setDoubleValueField(amount,value:delta)
        event.setIntegerValueField(.eventSourceUserData,value:SelectedTrackpadEventPolicy.interpreterTag)
        return event
    }
    mutating func update(delta:Double,began:Bool,location:CGPoint,flags:CGEventFlags = []) -> CGEvent? {
        if began { anchor = location; self.flags = flags }
        guard began || active, let event=Self.event(delta:delta,phase:began ? 1 : 2,location:anchor,flags:self.flags) else { return nil }
        active = true
        return event
    }
    mutating func finish(cancelled:Bool) -> CGEvent? {
        guard active else { return nil }; active = false
        return Self.event(delta:0,phase:cancelled ? 8 : 4,location:anchor,flags:flags)
    }
}

/// Angular evidence around a tracked thumb; output and ownership remain in the router.
struct ThumbRotationTracker {
    struct Evidence { var angle:Double; var arc:Double; var radial:Double }
    private struct Sample {
        var ids = SIMD8<Int32>(repeating:0)
        var count:Int, thumb:Int32, time:Double, angle:Double, radius:Double
    }
    private var samples:[UInt64:Sample] = Dictionary(minimumCapacity:2)
    mutating func reset() { samples.removeAll(keepingCapacity:true) }
    mutating func reset(device:UInt64) { samples[device] = nil }
    mutating func process<C:Collection>(device:UInt64,time:Double,contacts:C) -> Evidence? where C.Element == OMSRawTouch {
        var ids = SIMD8<Int32>(repeating:0), count = 0, thumb:Int32?, tx=0.0, ty=0.0, x=0.0, y=0.0
        guard time.isFinite else { reset(device:device); return nil }
        for touch in contacts where touch.state == .making || touch.state == .touching {
            guard count < 5, touch.posX.isFinite, touch.posY.isFinite,
                  touch.telemetry?.fingerID != 6 else { reset(device:device); return nil }
            for i in 0..<count where ids[i] == touch.id { reset(device:device); return nil }
            ids[count] = touch.id; count += 1
            let px = Double(touch.posX)*160, py = -Double(touch.posY)*114.9
            if touch.telemetry?.fingerID == 1 {
                guard thumb == nil else { reset(device:device); return nil }
                thumb = touch.id; tx=px; ty=py
            } else { x += px; y += py }
        }
        guard count == 3 || count == 5, let thumb else { reset(device:device); return nil }
        let dx = x/Double(count-1)-tx, dy = y/Double(count-1)-ty
        let radius = hypot(dx,dy), angle = atan2(dy,dx)
        guard radius >= 15 else { reset(device:device); return nil }
        let next = Sample(ids:ids,count:count,thumb:thumb,time:time,angle:angle,radius:radius)
        guard var old = samples[device], time > old.time, time-old.time < 0.15,
              count == old.count, thumb == old.thumb,
              (0..<count).allSatisfy({ i in (0..<count).contains { old.ids[$0] == ids[i] } }) else {
            samples[device] = next; return nil
        }
        let turn = atan2(sin(angle-old.angle),cos(angle-old.angle))
        // Keep the initial angular/radial anchor until membership changes.
        old.time = time; samples[device] = old
        return Evidence(angle:turn,arc:abs(turn)*min(radius,old.radius),radial:abs(radius-old.radius))
    }
}

typealias LatchedGesture = GestureTrigger

/// Current recognizer registration/output adapter; ownership lives in the engine.
struct TrackpadGestureRouter {
    private var engine: GestureSessionEngine<LatchedGesture>
    private var pinch = PinchSpreadTracker()
    private var rotation = ThumbRotationTracker()
    init(mouseActivationMM: Double = 0.35) {
        engine = GestureSessionEngine(rules:[
            GestureActivationRule(gesture:.threeFingerRotateLeft,activationCount:3,minimumMovementMM:0),
            GestureActivationRule(gesture:.threeFingerRotateRight,activationCount:3,minimumMovementMM:0),
            GestureActivationRule(gesture:.fiveFingerRotateLeft,activationCount:5,minimumMovementMM:0),
            GestureActivationRule(gesture:.fiveFingerRotateRight,activationCount:5,minimumMovementMM:0),
            GestureActivationRule(gesture:.twoFingerPinch,activationCount:2,minimumMovementMM:0),
            GestureActivationRule(gesture:.threeFingerPinch,activationCount:3,minimumMovementMM:0),
            GestureActivationRule(gesture:.fourFingerPinch,activationCount:4,minimumMovementMM:0),
            GestureActivationRule(gesture:.fiveFingerPinch,activationCount:5,minimumMovementMM:0),
            GestureActivationRule(gesture:.twoFingerSpread,activationCount:2,minimumMovementMM:0),
            GestureActivationRule(gesture:.threeFingerSpread,activationCount:3,minimumMovementMM:0),
            GestureActivationRule(gesture:.fourFingerSpread,activationCount:4,minimumMovementMM:0),
            GestureActivationRule(gesture:.fiveFingerSpread,activationCount:5,minimumMovementMM:0),
            GestureActivationRule(gesture:.threeFingerMove,activationCount:3,minimumMovementMM:0.35),
            GestureActivationRule(gesture:.fourFingerMove,activationCount:4,minimumMovementMM:0.2),
            GestureActivationRule(gesture:.twoFingerMove,activationCount:2,minimumMovementMM:mouseActivationMM)
        ])
    }
    func owner(device:UInt64) -> GestureTrigger? { engine.owner(device:device) }
    mutating func reset() { engine.reset(); pinch.reset(); rotation.reset() }
    mutating func reset(device: UInt64) { engine.cancel(device:device); pinch.reset(device:device); rotation.reset(device:device) }
    mutating func update<C: Collection>(device: UInt64, time: Double, contacts: C,
        mouse: Bool, scroll: Bool, drag: Bool = false) -> GestureSessionUpdate<LatchedGesture> where C.Element == OMSRawTouch {
        recognize(device:device,time:time,contacts:contacts,enabled: { trigger in
            switch trigger {
            case .twoFingerMove: return mouse; case .threeFingerMove: return drag; case .fourFingerMove: return scroll
            default: return false
            }
        })
    }
    mutating func recognize<C: Collection>(device: UInt64, time: Double, contacts: C,
        enabled: (GestureTrigger) -> Bool) -> GestureSessionUpdate<GestureTrigger> where C.Element == OMSRawTouch {
        let turn = rotation.process(device:device,time:time,contacts:contacts)
        let pair = pinch.process(device:device,time:time,contacts:contacts,latched:engine.owner(device:device)?.isPinch == true)
        let activeCount=contacts.reduce(0) { $0 + (($1.state == .making || $1.state == .touching) ? 1 : 0) }
        let direction = (pair?.changeMM ?? 0) > 0 ? GestureTrigger.spread(count:activeCount) : GestureTrigger.pinch(count:activeCount)
        let hasThumb = contacts.contains {
            ($0.state == .making || $0.state == .touching) && $0.telemetry?.fingerID == 1
        }
        let directionEligible = direction != nil && hasThumb
        let pinchEnabled = directionEligible && (direction.map(enabled) ?? false)
        let rotationDirection = GestureTrigger.rotation(count:activeCount,right:(turn?.angle ?? 0) > 0)
        let rotationEligible = rotationDirection.map(enabled) == true && hasThumb
            && (activeCount == 5 || ThumbTwoChord.matches(contacts))
        let rotationCandidate = rotationEligible && turn.map { abs($0.angle) >= Double.pi/240 && $0.arc >= 0.75 && $0.arc > $0.radial*1.1 } == true
        let rotationWins = rotationCandidate && abs(turn?.angle ?? 0) >= Double.pi/60
        var update = engine.process(device:device,time:time,touches:contacts,enabled:enabled,
            activationFilter:{ trigger,context in
                let separation = abs(pair?.changeMM ?? 0)
                let translation = hypot(context.pendingMovementMM.x,context.pendingMovementMM.y)
                // A stationary thumb and 2–4 moving fingertips translate their
                // centroid more than a two-finger chord; normalize dominance.
                let dominance = 3.0 / Double(max(2,context.activeCount))
                if trigger.isRotation { return rotationWins && trigger == rotationDirection }
                if rotationWins { return false }
                if trigger.isPinch { return !rotationCandidate && directionEligible && trigger == direction && pair != nil && separation >= 0.6 && separation > translation*dominance }
                if trigger.isContinuous && !trigger.isPinch && pinchEnabled && separation > translation*dominance { return false }
                return trigger != .threeFingerMove || ThreeFingerRowChord.accepts(contacts)
            })
        if update.gesture?.isPinch == true, let pair {
            update.scaleDelta = update.phase == .began ? pair.initialRatio : pair.frameRatio
        }
        return update
    }
    mutating func process<C: Collection>(device: UInt64, time: Double, contacts: C,
        mouse: Bool, scroll: Bool, drag: Bool = false) -> (gesture: LatchedGesture, millimetres: CGPoint)? where C.Element == OMSRawTouch {
        let result = update(device:device,time:time,contacts:contacts,mouse:mouse,scroll:scroll,drag:drag)
        guard let gesture = result.gesture, let motion = result.millimetres else { return nil }
        return (gesture,motion)
    }
}

/// Release-speed estimate and analytic coast. Constants are provisional feel tuning,
/// not Apple's unpublished momentum generator. Contact time and host tick time stay separate.
struct ScrollMomentum {
    struct Step { let points: CGPoint; let finished: Bool }
    private var sampleX = SIMD16<Double>(repeating:0)
    private var sampleY = SIMD16<Double>(repeating:0)
    private var sampleDT = SIMD16<Double>(repeating:0)
    private var sampleTime = SIMD16<Double>(repeating:0)
    private var head = 0, count = 0
    private var lastContact: Double?
    private var lastDelta = CGPoint.zero
    private var velocity = CGPoint.zero
    private var started = 0.0, lastTick = 0.0
    private(set) var isCoasting = false
    mutating func cancel() {
        head = 0; count = 0; lastContact = nil; lastDelta = .zero
        velocity = .zero; isCoasting = false
    }
    mutating func observe(points: CGPoint, contactTime: Double) {
        guard !isCoasting, contactTime.isFinite, points.x.isFinite, points.y.isFinite,
              abs(points.x)<150, abs(points.y)<150 else { cancel(); return }
        let dt = lastContact.map { contactTime-$0 } ?? 1/90
        guard dt > 0, dt < 0.15 else { cancel(); return }
        if points.x*lastDelta.x + points.y*lastDelta.y < 0 { count = 0; head = 0 }
        lastContact = contactTime
        if points != .zero { lastDelta = points }
        sampleX[head] = points.x; sampleY[head] = points.y
        sampleDT[head] = dt; sampleTime[head] = contactTime
        head = (head+1)%8; count = min(8,count+1)
    }
    mutating func start(contactTime: Double, hostTime: Double) -> Bool {
        guard !isCoasting, contactTime.isFinite, hostTime.isFinite,
              let lastContact, contactTime >= lastContact, contactTime-lastContact < 0.08 else {
            cancel(); return false
        }
        var dx = 0.0, dy = 0.0, duration = contactTime-lastContact
        for age in 0..<count {
            let i = (head+7-age)%8
            guard contactTime-sampleTime[i] < 0.08, duration < 0.08 else { break }
            let weight = min(sampleDT[i],0.08-duration)/sampleDT[i]
            dx += sampleX[i]*weight; dy += sampleY[i]*weight
            duration += sampleDT[i]*weight
        }
        guard duration > 0 else { cancel(); return false }
        velocity = CGPoint(x:dx/duration,y:dy/duration)
        let speed = hypot(velocity.x,velocity.y)
        guard speed.isFinite, speed >= 30 else { cancel(); return false }
        if speed > 6000 { velocity.x *= 6000/speed; velocity.y *= 6000/speed }
        started = hostTime; lastTick = hostTime; isCoasting = true
        return true
    }
    mutating func advance(hostTime: Double) -> Step? {
        guard isCoasting else { return nil }
        guard hostTime.isFinite, hostTime > lastTick, hostTime-lastTick <= 0.08 else {
            cancel(); return Step(points:.zero,finished:true)
        }
        let from = lastTick-started, to = min(2.5,hostTime-started)
        let tau = 0.325
        let scale = tau*(exp(-from/tau)-exp(-to/tau))
        let points = CGPoint(x:velocity.x*scale,y:velocity.y*scale)
        let finished = to >= 2.5 || hypot(velocity.x,velocity.y)*exp(-to/tau) < 5
        lastTick = hostTime
        if finished { cancel() }
        return Step(points:points,finished:finished)
    }
}

/// Creates continuous, phase-labelled scroll events; tests can inspect without posting.
struct PreciseScrollOutput {
    private(set) var active = false
    private(set) var momentumActive = false
    private var location: CGPoint?
    private var remainder = CGPoint.zero
    mutating func event(points: CGPoint, momentum: Bool = false) -> CGEvent? {
        guard momentum ? !active : !momentumActive else { return nil }
        guard points.x.isFinite, points.y.isFinite, abs(points.x)<150, abs(points.y)<150,
              points.x != 0 || points.y != 0 else { return nil }
        let accumulated = CGPoint(x:remainder.x+points.x,y:remainder.y+points.y)
        let ix = Int32(accumulated.x.rounded(.towardZero)), iy = Int32(accumulated.y.rounded(.towardZero))
        guard let event = CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:2,wheel1:iy,wheel2:ix,wheel3:0) else { return nil }
        if !momentum && !active { location = event.location }
        if let location { event.location = location }
        remainder = CGPoint(x:accumulated.x-Double(ix),y:accumulated.y-Double(iy))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1,value:points.y/10)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2,value:points.x/10)
        event.setIntegerValueField(.scrollWheelEventIsContinuous,value:1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase,value:momentum ? 0 : (active ? 2 : 1))
        event.setIntegerValueField(.scrollWheelEventMomentumPhase,value:momentum ? (momentumActive ? 2 : 1) : 0)
        event.setIntegerValueField(.scrollWheelEventScrollCount,value:1)
        event.setIntegerValueField(.eventSourceUserData,value:SelectedTrackpadEventPolicy.interpreterTag)
        if momentum { momentumActive = true } else { active = true }
        return event
    }
    mutating func finish(cancelled: Bool, preserveForMomentum: Bool = false) -> CGEvent? {
        guard active else { return nil }
        guard let event = CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:2,wheel1:0,wheel2:0,wheel3:0) else {
            active = false; remainder = .zero; return nil
        }
        event.setIntegerValueField(.scrollWheelEventIsContinuous,value:1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase,value:cancelled ? 8 : 4)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase,value:0)
        event.setIntegerValueField(.eventSourceUserData,value:SelectedTrackpadEventPolicy.interpreterTag)
        if let location { event.location = location }
        active = false
        if !preserveForMomentum { remainder = .zero; location = nil }
        return event
    }
    mutating func finishMomentum() -> CGEvent? {
        defer { momentumActive = false; remainder = .zero; location = nil }
        guard momentumActive,
              let event = CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:2,wheel1:0,wheel2:0,wheel3:0) else { return nil }
        event.setIntegerValueField(.scrollWheelEventIsContinuous,value:1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase,value:0)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase,value:3)
        event.setIntegerValueField(.eventSourceUserData,value:SelectedTrackpadEventPolicy.interpreterTag)
        if let location { event.location = location }
        return event
    }
}

enum InstalledScrollCurveReader {
    static func read(device: OMSDeviceInfo) throws -> AppleScrollProfile { try read(registryEntryID:device.registryEntryID) }
    static func read(registryEntryID: UInt64) throws -> AppleScrollProfile {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,IORegistryEntryIDMatching(registryEntryID))
        guard service != 0 else { throw PointerCurveError.invalid("Selected scroll service disappeared.") }
        defer { IOObjectRelease(service) }
        let system = IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("IOHIDSystem"))
        defer { if system != 0 { IOObjectRelease(system) } }
        let parameters = system == 0 ? nil : IORegistryEntryCreateCFProperty(system,"HIDParameters" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? [String:Any]
        func property(_ key: String) -> Any? {
            IORegistryEntrySearchCFProperty(service,kIOServicePlane,key as CFString,kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) ?? parameters?[key]
        }
        func fixed(_ value: Any?) -> Double? {
            guard let n = value as? NSNumber else { return nil }
            var raw = n.int64Value
            if raw >= 0x80000000 && raw <= 0xffffffff { raw -= 0x100000000 }
            return Double(raw)/65536
        }
        let type = property("HIDScrollAccelerationType") as? String ?? "HIDTrackpadScrollAcceleration"
        guard let index = fixed(property(type) ?? property("HIDMouseScrollAcceleration") ?? property("HIDScrollAcceleration")),
              let curves = (property("HIDUserScrollAccelCurves") ?? property("HIDScrollAccelCurves")) as? [[String:Any]] else {
            throw PointerCurveError.invalid("Paused: selected pad has no readable scroll profile.")
        }
        let decoded = try curves.map { entry -> ApplePointerCurve in
            guard let index = fixed(entry["HIDAccelIndex"]) else { throw PointerCurveError.invalid("Scroll curve index missing.") }
            return ApplePointerCurve(index:index,linear:fixed(entry["HIDAccelGainLinear"]) ?? 0,
                parabolic:fixed(entry["HIDAccelGainParabolic"]) ?? 0,cubic:fixed(entry["HIDAccelGainCubic"]) ?? 0,
                quartic:fixed(entry["HIDAccelGainQuartic"]) ?? 0,tangentLinear:fixed(entry["HIDAccelTangentSpeedLinear"]) ?? 0,
                tangentRoot:fixed(entry["HIDAccelTangentSpeedParabolicRoot"]) ?? 0)
        }
        let rawRate = fixed(property("HIDScrollReportRate")) ?? 67
        let rate = rawRate == 0 ? 67 : rawRate
        func axis(_ key: String) throws -> ApplePointerAccelerationProfile {
            guard let resolution = fixed(property(key) ?? property("HIDScrollResolution")) else {
                throw PointerCurveError.invalid("Scroll resolution missing.")
            }
            return try ApplePointerAccelerationProfile(resolution:resolution,acceleration:index,curves:decoded,algorithmRate:rate)
        }
        let natural = UserDefaults.standard.persistentDomain(forName:UserDefaults.globalDomain)?["com.apple.swipescrolldirection"] as? Bool ?? true
        return try AppleScrollProfile(horizontal:axis("HIDScrollResolutionX"),vertical:axis("HIDScrollResolutionY"),natural:natural)
    }
}

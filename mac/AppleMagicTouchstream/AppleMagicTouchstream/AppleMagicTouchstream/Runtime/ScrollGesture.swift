import CoreGraphics
import Foundation
import IOKit
import OpenMultitouchSupport

struct AppleScrollProfile: Equatable, Sendable {
    let horizontal: ApplePointerAccelerationProfile
    let vertical: ApplePointerAccelerationProfile
    let natural: Bool
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

typealias LatchedGesture = GestureTrigger

/// Current recognizer registration/output adapter; ownership lives in the engine.
struct TrackpadGestureRouter {
    private var engine: GestureSessionEngine<LatchedGesture>
    init(mouseActivationMM: Double = 0.35) {
        engine = GestureSessionEngine(rules:[
            GestureActivationRule(gesture:.threeFingerMove,activationCount:3,minimumMovementMM:0.35),
            GestureActivationRule(gesture:.fourFingerMove,activationCount:4,minimumMovementMM:0.2),
            GestureActivationRule(gesture:.twoFingerMove,activationCount:2,minimumMovementMM:mouseActivationMM)
        ])
    }
    mutating func reset() { engine.reset() }
    mutating func reset(device: UInt64) { engine.cancel(device:device) }
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
        engine.process(device:device,time:time,touches:contacts,enabled:enabled,
            activationFilter:{ trigger,_ in trigger != .threeFingerMove || ThreeFingerRowChord.accepts(contacts) })
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

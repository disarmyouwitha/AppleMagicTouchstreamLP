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

enum LatchedGesture: Sendable { case mouse, scroll }

/// Decide from the initial moving chord, then retain ownership across count changes.
struct TrackpadGestureRouter {
    struct Pending { var count = 0; var travel = CGPoint.zero; var gesture: LatchedGesture? }
    private var history = TwoFingerPointerTracker(activationCount:0)
    private var sessions: [UInt64:Pending] = Dictionary(minimumCapacity:2)
    mutating func reset() { history.reset(); sessions.removeAll(keepingCapacity:true) }
    mutating func reset(device: UInt64) { history.reset(device:device); sessions[device] = nil }
    mutating func process<C: Collection>(device: UInt64, time: Double, contacts: C,
        mouse: Bool, scroll: Bool) -> (gesture: LatchedGesture, millimetres: CGPoint)? where C.Element == OMSRawTouch {
        var count = 0
        for contact in contacts where contact.state == .making || contact.state == .touching { count += 1 }
        let movement = history.millimetres(device:device,time:time,contacts:contacts)
        if !history.frameContinued { sessions[device] = nil }
        guard let movement else { return nil }
        var session = sessions[device] ?? Pending()
        if let gesture = session.gesture {
            guard gesture == .mouse ? mouse : scroll else { reset(device:device); return nil }
            return (gesture,movement)
        }
        // Ignore landing jitter and let a four-finger chord finish arriving.
        if session.count != count { session.count = count; session.travel = .zero }
        session.travel.x += movement.x; session.travel.y += movement.y
        if hypot(session.travel.x,session.travel.y) >= 0.2 {
            if count == 4 && scroll { session.gesture = .scroll }
            else if count == 2 && mouse { session.gesture = .mouse }
        }
        sessions[device] = session
        guard let gesture = session.gesture else { return nil }
        return (gesture,session.travel)
    }
}

/// Creates continuous, phase-labelled scroll events; tests can inspect without posting.
struct PreciseScrollOutput {
    private(set) var active = false
    private var remainder = CGPoint.zero
    mutating func event(points: CGPoint) -> CGEvent? {
        guard points.x.isFinite, points.y.isFinite, abs(points.x)<150, abs(points.y)<150,
              points.x != 0 || points.y != 0 else { return nil }
        let accumulated = CGPoint(x:remainder.x+points.x,y:remainder.y+points.y)
        let ix = Int32(accumulated.x.rounded(.towardZero)), iy = Int32(accumulated.y.rounded(.towardZero))
        guard let event = CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:2,wheel1:iy,wheel2:ix,wheel3:0) else { return nil }
        remainder = CGPoint(x:accumulated.x-Double(ix),y:accumulated.y-Double(iy))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1,value:points.y/10)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2,value:points.x/10)
        event.setIntegerValueField(.scrollWheelEventIsContinuous,value:1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase,value:active ? 2 : 1)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase,value:0)
        event.setIntegerValueField(.scrollWheelEventScrollCount,value:1)
        event.setIntegerValueField(.eventSourceUserData,value:SelectedTrackpadEventPolicy.interpreterTag)
        active = true
        return event
    }
    mutating func finish(cancelled: Bool) -> CGEvent? {
        guard active else { remainder = .zero; return nil }
        guard let event = CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:2,wheel1:0,wheel2:0,wheel3:0) else {
            active = false; remainder = .zero; return nil
        }
        event.setIntegerValueField(.scrollWheelEventIsContinuous,value:1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase,value:cancelled ? 8 : 4)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase,value:0)
        event.setIntegerValueField(.eventSourceUserData,value:SelectedTrackpadEventPolicy.interpreterTag)
        active = false; remainder = .zero
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

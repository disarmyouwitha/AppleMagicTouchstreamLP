import CoreGraphics
import Foundation
import IOKit
import OpenMultitouchSupport

enum TwoFingerPointerResponse: String, CaseIterable, Identifiable, Sendable {
    case fixed = "Fixed 6 pt/mm"
    case apple = "Apple acceleration (test)"
    var id: String { rawValue }
}

enum PointerCurveError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

/// Independent numerical model of the pinned Apple equations in POINTER_ACCELERATION.md.
/// Coefficients describe a curve, not a validated conversion from OMS units to HID counts.
struct ApplePointerCurve: Sendable, Equatable {
    var index: Double
    var linear: Double
    var parabolic: Double = 0
    var cubic: Double = 0
    var quartic: Double = 0
    var tangentLinear: Double = 0
    var tangentRoot: Double = 0

    static func interpolate(_ curves: [Self], at index: Double) throws -> Self {
        guard index.isFinite, !curves.isEmpty else { throw PointerCurveError.invalid("No parametric curve.") }
        var previous = -Double.infinity
        for curve in curves {
            let numbers = [curve.index, curve.linear, curve.parabolic, curve.cubic, curve.quartic,
                           curve.tangentLinear, curve.tangentRoot]
            guard numbers.allSatisfy({ $0.isFinite && $0 >= 0 }), curve.index > previous,
                  curve.linear + curve.parabolic + curve.cubic + curve.quartic > 0,
                  curve.tangentLinear == 0 || curve.tangentRoot == 0 || curve.tangentRoot >= curve.tangentLinear else {
                throw PointerCurveError.invalid("Unsupported parametric curve values/order.")
            }
            previous = curve.index
        }
        let lo = curves.lastIndex(where: { $0.index <= index }) ?? 0
        guard lo + 1 < curves.count, index > curves[lo].index else { return curves[lo] }
        let a = curves[lo], b = curves[lo+1], ratio = (index-a.index)/(b.index-a.index)
        func lerp(_ x: Double, _ y: Double) -> Double { x + ratio*(y-x) }
        return Self(index: index, linear: lerp(a.linear,b.linear), parabolic: lerp(a.parabolic,b.parabolic),
            cubic: lerp(a.cubic,b.cubic), quartic: lerp(a.quartic,b.quartic),
            tangentLinear: lerp(a.tangentLinear,b.tangentLinear), tangentRoot: lerp(a.tangentRoot,b.tangentRoot))
    }

    func polynomial(_ x: Double) -> Double {
        linear*x + pow(parabolic*x,2) + pow(cubic*x,3) + pow(quartic*x,4)
    }
    func derivative(_ x: Double) -> Double {
        linear + 2*x*pow(parabolic,2) + 3*x*x*pow(cubic,3) + 4*pow(x,3)*pow(quartic,4)
    }
}

struct ApplePointerAccelerationProfile: Sendable, Equatable {
    let resolution: Double
    let algorithmRate: Double
    let reportRate: Double
    let fixedMultiplier: Double
    let acceleration: Double
    let curve: ApplePointerCurve
    let tangent0: Double
    let tangent1: Double
    let m0: Double
    let b0: Double
    let m1: Double
    let b1: Double

    init(resolution: Double, reportRate: Double = 0, fixedMultiplier: Double = 1,
         acceleration: Double, curves: [ApplePointerCurve], algorithmRate: Double = 67) throws {
        guard algorithmRate.isFinite && algorithmRate > 0, resolution.isFinite && resolution > 0, reportRate.isFinite && reportRate >= 0,
              fixedMultiplier.isFinite && fixedMultiplier > 0 else { throw PointerCurveError.invalid("Invalid pointer settings.") }
        self.algorithmRate = algorithmRate; self.resolution = resolution; self.reportRate = reportRate
        self.fixedMultiplier = fixedMultiplier; self.acceleration = acceleration
        curve = try ApplePointerCurve.interpolate(curves, at: acceleration)
        var t0 = Double.infinity, t1 = Double.infinity
        var slope0 = 0.0, intercept0 = 0.0, slope1 = 0.0, intercept1 = 0.0
        if curve.tangentLinear != 0 {
            t0 = curve.tangentLinear
            slope0 = curve.derivative(t0); intercept0 = curve.polynomial(t0)-slope0*t0
            if curve.tangentRoot != 0 {
                t1 = curve.tangentRoot
                let y1 = slope0*t1+intercept0
                slope1 = 2*y1*slope0; intercept1 = y1*y1-slope1*t1
            }
        } else if curve.tangentRoot != 0 {
            t0 = curve.tangentRoot
            let y0 = curve.polynomial(t0)
            slope1 = curve.derivative(t0); intercept1 = y0*y0-slope1*t0
        }
        tangent0 = t0; tangent1 = t1; m0 = slope0; b0 = intercept0; m1 = slope1; b1 = intercept1
    }

    func acceleratedVelocity(_ velocity: Double) -> Double {
        let x = velocity/(resolution/algorithmRate)
        let result: Double
        if x <= tangent0 { result = curve.polynomial(x) }
        else if x <= tangent1 && tangent0 == curve.tangentLinear { result = m0*x+b0 }
        else { result = sqrt(max(0,m1*x+b1)) }
        return result*96/67
    }
}

struct ApplePointerAccelerator: Sendable {
    let profile: ApplePointerAccelerationProfile
    private var lastTime: Double?
    init(profile: ApplePointerAccelerationProfile) { self.profile = profile }
    mutating func reset() { lastTime = nil }
    mutating func delta(time: Double, counts: CGPoint) -> CGPoint? {
        guard time.isFinite, counts.x.isFinite, counts.y.isFinite else { reset(); return nil }
        let dt = lastTime.map { time-$0 }
        lastTime = time
        guard dt == nil || dt! > 0 else { reset(); return nil }
        if profile.acceleration < 0 { return counts }
        var rateGain = 1.0
        if profile.reportRate > 0, let dt {
            let period = 1/profile.reportRate
            rateGain = period/max(period,dt)
        }
        var velocity = floor(hypot(Double(counts.x),Double(counts.y)))
        velocity *= profile.fixedMultiplier == 1 ? rateGain : profile.fixedMultiplier
        velocity = max(1/65536,velocity)
        let gain = profile.acceleratedVelocity(velocity)/velocity
        let result = CGPoint(x:Double(counts.x)*gain,y:Double(counts.y)*gain)
        guard result.x.isFinite && result.y.isFinite else { reset(); return nil }
        return result
    }
}

/// Registry reads are control-path only. No service writes or subprocesses.
enum InstalledPointerCurveReader {
    static func read(device: OMSDeviceInfo) throws -> ApplePointerAccelerationProfile {
        try read(registryEntryID:device.registryEntryID)
    }
    static func read(registryEntryID: UInt64) throws -> ApplePointerAccelerationProfile {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryEntryID))
        guard service != 0 else { throw PointerCurveError.invalid("Selected pad's service disappeared.") }
        defer { IOObjectRelease(service) }
        func property(_ key: String) -> Any? {
            IORegistryEntrySearchCFProperty(service,kIOServicePlane,key as CFString,kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
        }
        let system = IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("IOHIDSystem"))
        defer { if system != 0 { IOObjectRelease(system) } }
        let parameters = system == 0 ? nil : IORegistryEntryCreateCFProperty(system,"HIDParameters" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? [String:Any]
        func fixed(_ value: Any?) -> Double? {
            guard let number = value as? NSNumber else { return nil }
            var raw = number.int64Value
            if raw >= 0x80000000 && raw <= 0xffffffff { raw -= 0x100000000 }
            return Double(raw)/65536
        }
        guard let acceleration = fixed(property("HIDTrackpadAcceleration") ?? parameters?["HIDTrackpadAcceleration"]),
              let resolution = fixed(property("HIDPointerResolution")),
              let curves = (property("HIDUserPointerAccelCurves") ?? property("HIDAccelCurves")) as? [[String:Any]], !curves.isEmpty else {
            throw PointerCurveError.invalid("Paused: selected pad has no readable tracking profile.")
        }
        let decoded = try curves.map { entry -> ApplePointerCurve in
            guard let index = fixed(entry["HIDAccelIndex"]) else { throw PointerCurveError.invalid("Curve index missing.") }
            return ApplePointerCurve(index:index,linear:fixed(entry["HIDAccelGainLinear"]) ?? 0,
                parabolic:fixed(entry["HIDAccelGainParabolic"]) ?? 0,cubic:fixed(entry["HIDAccelGainCubic"]) ?? 0,
                quartic:fixed(entry["HIDAccelGainQuartic"]) ?? 0,tangentLinear:fixed(entry["HIDAccelTangentSpeedLinear"]) ?? 0,
                tangentRoot:fixed(entry["HIDAccelTangentSpeedParabolicRoot"]) ?? 0)
        }
        let multiplier = fixed(property("HIDPointerAccelerationMultiplier")) ?? 1
        return try ApplePointerAccelerationProfile(resolution:resolution,
            reportRate:(property("HIDPointerReportRate") as? NSNumber)?.doubleValue ?? 0,
            fixedMultiplier:multiplier == 0 ? 1 : multiplier,acceleration:acceleration,curves:decoded)
    }
}

/// Pure motion processing shared by live output and offline tests; never posts events.
struct TwoFingerPointerMotionEngine {
    private var tracker = TwoFingerPointerTracker()
    private var accelerators: [UInt64:ApplePointerAccelerator] = Dictionary(minimumCapacity:2)
    private var profiles: [UInt64:ApplePointerAccelerationProfile] = [:]
    private var response: TwoFingerPointerResponse = .fixed
    private var sensitivity = 1.0
    private var sensitivities: [UInt64:Double] = [:]

    mutating func configure(response: TwoFingerPointerResponse, sensitivity: Double,
                            profiles: [UInt64:ApplePointerAccelerationProfile], sensitivities: [UInt64:Double] = [:]) {
        let scale = sensitivity.isFinite ? min(2,max(0.25,sensitivity)) : 1
        let scales = sensitivities.mapValues { $0.isFinite ? min(2,max(0.25,$0)) : 1 }
        guard self.response != response || self.sensitivity != scale || self.profiles != profiles || self.sensitivities != scales else { return }
        let globalChange = self.response != response || self.sensitivity != scale
        for id in Set(self.profiles.keys).union(profiles.keys) {
            if globalChange || self.profiles[id] != profiles[id] || self.sensitivities[id] != scales[id] {
                tracker.reset(device:id)
                accelerators[id] = profiles[id].map { ApplePointerAccelerator(profile:$0) }
            }
        }
        self.response = response; self.sensitivity = scale; self.profiles = profiles; self.sensitivities = scales
    }
    mutating func reset() {
        tracker.reset()
        for key in accelerators.keys { accelerators[key]?.reset() }
    }
    mutating func reset(device: UInt64) { tracker.reset(device:device); accelerators[device]?.reset() }
    mutating func process<C: Collection>(device: UInt64, time: Double, contacts: C) -> CGPoint? where C.Element == OMSRawTouch {
        guard let mm = tracker.millimetres(device:device,time:time,contacts:contacts) else {
            accelerators[device]?.reset()
            return nil
        }
        return processMotion(device:device,time:time,millimetres:mm)
    }
    mutating func processMotion(device: UInt64, time: Double, millimetres mm: CGPoint) -> CGPoint? {
        let sensitivity = sensitivities[device] ?? self.sensitivity
        let delta: CGPoint
        switch response {
        case .fixed:
            delta = CGPoint(x:mm.x*6*sensitivity,y:mm.y*6*sensitivity)
        case .apple:
            guard let profile = profiles[device] else { return nil }
            // Explicit experimental OMS->count hypothesis, not a recovered calibration.
            let countsPerMM = profile.resolution/25.4*sensitivity
            guard let value = accelerators[device]?.delta(time:time,
                counts:CGPoint(x:mm.x*countsPerMM,y:mm.y*countsPerMM)) else { return nil }
            delta = value
        }
        guard delta.x.isFinite && delta.y.isFinite, abs(delta.x)<150, abs(delta.y)<150 else {
            accelerators[device]?.reset(); return nil
        }
        return delta
    }
}

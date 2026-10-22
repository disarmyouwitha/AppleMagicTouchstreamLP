import Foundation

enum GestureHandScope: String, CaseIterable, Identifiable, Sendable {
    case left = "Left", right = "Right", both = "Both"
    var id: String { rawValue }
}
enum GestureFeature: CaseIterable, Sendable {
    case mouse, tap, doubleTap, drag, scroll, rightClick
}
enum GestureSensitivity: Sendable { case pointer, scroll }

struct PerHandGestureSettings: Equatable, Sendable {
    var mouse = true, tap = true, doubleTap = true, drag = true, scroll = true, rightClick = true
    var pointerSensitivity = 1.0, scrollSensitivity = 1.0
    subscript(feature: GestureFeature) -> Bool {
        get {
            switch feature {
            case .mouse: return mouse; case .tap: return tap; case .doubleTap: return doubleTap
            case .drag: return drag; case .scroll: return scroll; case .rightClick: return rightClick
            }
        }
        set {
            switch feature {
            case .mouse: mouse = newValue; case .tap: tap = newValue; case .doubleTap: doubleTap = newValue
            case .drag: drag = newValue; case .scroll: scroll = newValue; case .rightClick: rightClick = newValue
            }
        }
    }
    subscript(kind: GestureSensitivity) -> Double {
        get { kind == .pointer ? pointerSensitivity : scrollSensitivity }
        set {
            let value = newValue.isFinite ? min(2,max(0.25,newValue)) : 1
            if kind == .pointer { pointerSensitivity = value } else { scrollSensitivity = value }
        }
    }
}

struct GestureSelectedPads: Equatable, Sendable {
    var left: UInt64?, right: UInt64?
}

/// Logical hand slots own settings; physical native IDs own live output sessions.
/// Existing process-local defaults are copied, not shared reference state.
struct HandGestureSettings: Equatable, Sendable {
    var left: PerHandGestureSettings
    var right: PerHandGestureSettings
    init(mirrored seed: PerHandGestureSettings = PerHandGestureSettings()) { left = seed; right = seed }
    func enabled(_ feature: GestureFeature, in scope: GestureHandScope) -> Bool? {
        switch scope {
        case .left: return left[feature]; case .right: return right[feature]
        case .both: return left[feature] == right[feature] ? left[feature] : nil
        }
    }
    func sensitivity(_ kind: GestureSensitivity, in scope: GestureHandScope) -> Double? {
        switch scope {
        case .left: return left[kind]; case .right: return right[kind]
        case .both: return left[kind] == right[kind] ? left[kind] : nil
        }
    }
    func anyEnabled(_ feature: GestureFeature) -> Bool { left[feature] || right[feature] }
    mutating func set(_ feature: GestureFeature, enabled: Bool, in scope: GestureHandScope) {
        if scope != .right { left[feature] = enabled }
        if scope != .left { right[feature] = enabled }
    }
    mutating func set(_ kind: GestureSensitivity, value: Double, in scope: GestureHandScope) {
        if scope != .right { left[kind] = value }
        if scope != .left { right[kind] = value }
    }
    func routed(to pads: GestureSelectedPads) -> [UInt64:PerHandGestureSettings] {
        var result: [UInt64:PerHandGestureSettings] = [:]
        if let id = pads.left { result[id] = left }
        if let id = pads.right {
            if id == pads.left {
                // One physical device cannot apply two independent gains. Merge
                // enabled gestures, retaining left sensitivity; UI explains this.
                var merged = left
                for feature in GestureFeature.allCases { merged[feature] = left[feature] || right[feature] }
                result[id] = merged
            } else { result[id] = right }
        }
        return result
    }
    func outputDevices(_ feature: GestureFeature, pads: GestureSelectedPads, eligible: Set<UInt64>) -> Set<UInt64> {
        Set(routed(to:pads).filter { eligible.contains($0.key) && $0.value[feature] }.map(\.key))
    }
}

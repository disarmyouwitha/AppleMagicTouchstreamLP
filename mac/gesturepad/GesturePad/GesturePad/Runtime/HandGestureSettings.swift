import Foundation

enum GestureHandScope: String, CaseIterable, Identifiable, Sendable {
    case left = "Left", right = "Right", both = "Both"
    var id: String { rawValue }
}

/// Inputs are recognized independently of the action assigned to them.
enum GestureTrigger: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case twoFingerMove, twoFingerTap, threeFingerMove, threeFingerTap, fourFingerMove, thumbTwoTap
    var id: String { rawValue }
    var isContinuous: Bool { self == .twoFingerMove || self == .threeFingerMove || self == .fourFingerMove }
    var title: String {
        switch self {
        case .twoFingerMove: return "2-finger movement"
        case .twoFingerTap: return "2-finger tap"
        case .threeFingerMove: return "3-finger movement"
        case .threeFingerTap: return "3-finger tap"
        case .fourFingerMove: return "4-finger movement"
        case .thumbTwoTap: return "Spread thumb + 2 fingertips tap"
        }
    }
    var allowedActions: [GestureAction] {
        isContinuous ? [.disabled,.pointer,.primaryDrag,.scroll] : [.disabled,.primaryClick,.primaryDoubleClick,.secondaryClick]
    }
    // Factory defaults only; recognition and dispatch do not derive actions here.
    var defaultAction: GestureAction {
        switch self {
        case .twoFingerMove: return .pointer; case .twoFingerTap: return .primaryClick
        case .threeFingerMove: return .primaryDrag; case .threeFingerTap: return .primaryDoubleClick
        case .fourFingerMove: return .scroll; case .thumbTwoTap: return .secondaryClick
        }
    }
    // Compatibility for existing diagnostic/test callers of the enable-only API.
    static let mouse = Self.twoFingerMove, tap = Self.twoFingerTap, drag = Self.threeFingerMove
    static let doubleTap = Self.threeFingerTap, scroll = Self.fourFingerMove, rightClick = Self.thumbTwoTap
    static let doubleClick = Self.threeFingerTap
}
typealias GestureFeature = GestureTrigger

enum GestureAction: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case disabled, pointer, primaryDrag, scroll, primaryClick, primaryDoubleClick, secondaryClick
    var id: String { rawValue }
    var title: String {
        switch self {
        case .disabled: return "None"; case .pointer: return "Move Pointer"
        case .primaryDrag: return "Drag / Select"; case .scroll: return "Scroll / Pan"
        case .primaryClick: return "Primary Click"; case .primaryDoubleClick: return "Double-Click"
        case .secondaryClick: return "Secondary Click"
        }
    }
    var requiresPointerProfile: Bool { self == .pointer || self == .primaryDrag }
}
enum GestureSensitivity: Sendable { case pointer, scroll }

struct GestureActionBindings: Equatable, Codable, Sendable {
    var twoFingerMove: GestureAction = .pointer, twoFingerTap: GestureAction = .primaryClick
    var threeFingerMove: GestureAction = .primaryDrag, threeFingerTap: GestureAction = .primaryDoubleClick
    var fourFingerMove: GestureAction = .scroll, thumbTwoTap: GestureAction = .secondaryClick
    subscript(trigger: GestureTrigger) -> GestureAction {
        get {
            switch trigger {
            case .twoFingerMove: return twoFingerMove; case .twoFingerTap: return twoFingerTap
            case .threeFingerMove: return threeFingerMove; case .threeFingerTap: return threeFingerTap
            case .fourFingerMove: return fourFingerMove; case .thumbTwoTap: return thumbTwoTap
            }
        }
        set {
            switch trigger {
            case .twoFingerMove: twoFingerMove = newValue; case .twoFingerTap: twoFingerTap = newValue
            case .threeFingerMove: threeFingerMove = newValue; case .threeFingerTap: threeFingerTap = newValue
            case .fourFingerMove: fourFingerMove = newValue; case .thumbTwoTap: thumbTwoTap = newValue
            }
        }
    }
    func uses(_ action: GestureAction) -> Bool { GestureTrigger.allCases.contains { self[$0] == action } }
    func action(for trigger: GestureTrigger) -> GestureAction {
        let action = self[trigger]
        return trigger.allowedActions.contains(action) ? action : .disabled
    }
}

struct PerHandGestureSettings: Equatable, Codable, Sendable {
    var bindings = GestureActionBindings()
    var pointerSensitivity = 1.0, scrollSensitivity = 1.0
    // Legacy enable-only clients use factory assignment when enabling a disabled input.
    subscript(trigger: GestureTrigger) -> Bool {
        get { bindings.action(for:trigger) != .disabled }
        set { bindings[trigger] = newValue ? (self[trigger] ? bindings[trigger] : trigger.defaultAction) : .disabled }
    }
    var mouse: Bool { get { self[.twoFingerMove] } set { self[.twoFingerMove] = newValue } }
    var tap: Bool { get { self[.twoFingerTap] } set { self[.twoFingerTap] = newValue } }
    var doubleTap: Bool { get { self[.threeFingerTap] } set { self[.threeFingerTap] = newValue } }
    var drag: Bool { get { self[.threeFingerMove] } set { self[.threeFingerMove] = newValue } }
    var scroll: Bool { get { self[.fourFingerMove] } set { self[.fourFingerMove] = newValue } }
    var rightClick: Bool { get { self[.thumbTwoTap] } set { self[.thumbTwoTap] = newValue } }
    subscript(kind: GestureSensitivity) -> Double {
        get { kind == .pointer ? pointerSensitivity : scrollSensitivity }
        set {
            let value = newValue.isFinite ? min(2,max(0.25,newValue)) : 1
            if kind == .pointer { pointerSensitivity = value } else { scrollSensitivity = value }
        }
    }
    mutating func normalize() {
        for trigger in GestureTrigger.allCases { bindings[trigger] = bindings.action(for:trigger) }
        self[GestureSensitivity.pointer] = pointerSensitivity; self[GestureSensitivity.scroll] = scrollSensitivity
    }
}

struct GestureSelectedPads: Equatable, Sendable { var left: UInt64?, right: UInt64? }

struct HandGestureSettings: Equatable, Codable, Sendable {
    static let defaultsKey = "GesturePad.handGestureBindings.v1"
    var left: PerHandGestureSettings
    var right: PerHandGestureSettings
    init(mirrored seed: PerHandGestureSettings = PerHandGestureSettings()) { left = seed; right = seed }
    func action(_ trigger: GestureTrigger, in scope: GestureHandScope) -> GestureAction? {
        switch scope {
        case .left: return left.bindings.action(for:trigger)
        case .right: return right.bindings.action(for:trigger)
        case .both:
            let a = left.bindings.action(for:trigger), b = right.bindings.action(for:trigger)
            return a == b ? a : nil
        }
    }
    @discardableResult mutating func setAction(_ action: GestureAction, for trigger: GestureTrigger, in scope: GestureHandScope) -> Bool {
        guard trigger.allowedActions.contains(action) else { return false }
        if scope != .right { left.bindings[trigger] = action }
        if scope != .left { right.bindings[trigger] = action }
        return true
    }
    func enabled(_ feature: GestureTrigger, in scope: GestureHandScope) -> Bool? {
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
    func anyEnabled(_ feature: GestureTrigger) -> Bool { left[feature] || right[feature] }
    mutating func set(_ feature: GestureTrigger, enabled: Bool, in scope: GestureHandScope) {
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
                var merged = left
                // Prefer an active left binding; otherwise take the active right
                // binding. A single device cannot execute two conflicting actions.
                for trigger in GestureTrigger.allCases where !left[trigger] { merged.bindings[trigger] = right.bindings[trigger] }
                result[id] = merged
            } else { result[id] = right }
        }
        return result
    }
    func outputDevices(_ feature: GestureTrigger, pads: GestureSelectedPads, eligible: Set<UInt64>) -> Set<UInt64> {
        Set(routed(to:pads).filter { eligible.contains($0.key) && $0.value[feature] }.map(\.key))
    }
    static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey:defaultsKey), var value = try? JSONDecoder().decode(Self.self,from:data) else { return Self() }
        value.left.normalize(); value.right.normalize()
        return value
    }
    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data,forKey:Self.defaultsKey)
    }
}

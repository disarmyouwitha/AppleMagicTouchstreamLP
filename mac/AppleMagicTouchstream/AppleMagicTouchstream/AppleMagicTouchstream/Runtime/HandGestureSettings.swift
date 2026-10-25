import Foundation
import OpenMultitouchSupport

enum GestureHandScope: String, CaseIterable, Identifiable, Sendable {
    case left = "Left", right = "Right", both = "Both"
    var id: String { rawValue }
}

/// Inputs are recognized independently of the action assigned to them.
enum GestureTrigger: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case twoFingerMove, twoFingerTap, threeFingerMove, threeFingerTap, fourFingerMove, fourFingerTap, fourCornersTap, thumbTwoTap
    case twoFingerPinch, threeFingerPinch, fourFingerPinch, fiveFingerPinch
    case twoFingerSpread, threeFingerSpread, fourFingerSpread, fiveFingerSpread
    case twoFingerRotateLeft, threeFingerRotateLeft, fourFingerRotateLeft, fiveFingerRotateLeft
    case twoFingerRotateRight, threeFingerRotateRight, fourFingerRotateRight, fiveFingerRotateRight
    case oneFingerForce, twoFingerForce, threeFingerForce, fourFingerForce, fiveFingerForce
    private static let inwardTriggers: [Self] = [.twoFingerPinch,.threeFingerPinch,.fourFingerPinch,.fiveFingerPinch]
    static let spreadTriggers: [Self] = [.twoFingerSpread,.threeFingerSpread,.fourFingerSpread,.fiveFingerSpread]
    static let pinchTriggers = inwardTriggers + spreadTriggers
    private static let leftRotations:[Self] = [.twoFingerRotateLeft,.threeFingerRotateLeft,.fourFingerRotateLeft,.fiveFingerRotateLeft]
    private static let rightRotations:[Self] = [.twoFingerRotateRight,.threeFingerRotateRight,.fourFingerRotateRight,.fiveFingerRotateRight]
    static let rotationTriggers = leftRotations + rightRotations
    static let liveRotationTriggers:[Self] = [.threeFingerRotateLeft,.threeFingerRotateRight,.fiveFingerRotateLeft,.fiveFingerRotateRight]
    var rotationCount:Int? { (Self.leftRotations.firstIndex(of:self) ?? Self.rightRotations.firstIndex(of:self)).map { $0+2 } }
    var isRotation:Bool { rotationCount != nil }
    var rotatesRight:Bool { Self.rightRotations.contains(self) }
    static func rotation(count:Int,right:Bool) -> Self? {
        (2...5).contains(count) ? (right ? rightRotations : leftRotations)[count-2] : nil
    }
    var isSpread: Bool { Self.spreadTriggers.contains(self) }
    var pinchCount: Int? { (Self.inwardTriggers.firstIndex(of:self) ?? Self.spreadTriggers.firstIndex(of:self)).map { $0 + 2 } }
    // Shared shape-recognition family, including both directions.
    var isPinch: Bool { pinchCount != nil }
    static func pinch(count:Int) -> Self? { (2...5).contains(count) ? inwardTriggers[count-2] : nil }
    static func spread(count:Int) -> Self? { (2...5).contains(count) ? spreadTriggers[count-2] : nil }
    static let forceTriggers: [Self] = [.oneFingerForce,.twoFingerForce,.threeFingerForce,.fourFingerForce,.fiveFingerForce]
    var forceCount: Int? { Self.forceTriggers.firstIndex(of:self).map { $0 + 1 } }
    static func force(count: Int) -> Self? { (1...5).contains(count) ? forceTriggers[count - 1] : nil }
    var id: String { rawValue }
    var isContinuous: Bool { isPinch || isRotation || self == .twoFingerMove || self == .threeFingerMove || self == .fourFingerMove }
    var title: String {
        if let count = pinchCount { return "\(count)-finger \(isSpread ? "spread" : "pinch") (thumb required)" }
        if let count = rotationCount {
            return count == 3 ? "Thumb + 2 fingertips rotate \(rotatesRight ? "right" : "left")"
                : "\(count)-finger rotate \(rotatesRight ? "right" : "left")"
        }
        if let count = forceCount { return "\(count)-finger force click" }
        switch self {
        case .twoFingerMove: return "2-finger movement"
        case .twoFingerTap: return "2-finger tap"
        case .threeFingerMove: return "3-finger movement"
        case .threeFingerTap: return "3-finger tap"
        case .fourFingerMove: return "4-finger movement"
        case .fourFingerTap: return "4-finger tap"
        case .fourCornersTap: return "4 corners tap"
        case .thumbTwoTap: return "Spread thumb + 2 fingertips tap"
        default: return "Force click"
        }
    }
    var allowedActions: [GestureAction] {
        if self == .fourCornersTap { return [.disabled] }
        if isPinch { return [.disabled,.zoom] + GestureAction.oneShotActions }
        if isRotation { return [.disabled,.primaryClick,.primaryDoubleClick,.secondaryClick] + GestureAction.oneShotActions }
        if forceCount != nil || self == .fourFingerTap { return [.disabled,.primaryClick,.primaryDoubleClick,.secondaryClick] + GestureAction.oneShotActions }
        return isContinuous ? [.disabled,.pointer,.primaryDrag,.scroll] : [.disabled,.primaryClick,.primaryDoubleClick,.secondaryClick] + GestureAction.smallStepActions
    }
    // Factory defaults only; recognition and dispatch do not derive actions here.
    var defaultAction: GestureAction {
        switch self {
        case .twoFingerMove: return .pointer; case .twoFingerTap: return .primaryClick
        case .threeFingerMove: return .primaryDrag; case .threeFingerTap: return .primaryDoubleClick
        case .fourFingerMove: return .scroll; case .thumbTwoTap: return .secondaryClick
        case .twoFingerPinch,.threeFingerPinch,.fourFingerPinch,.fiveFingerPinch,
             .twoFingerSpread,.threeFingerSpread,.fourFingerSpread,.fiveFingerSpread: return .zoom
        case .oneFingerForce: return .primaryClick
        default: return .disabled
        }
    }
    // Compatibility for existing diagnostic/test callers of the enable-only API.
    static let mouse = Self.twoFingerMove, tap = Self.twoFingerTap, drag = Self.threeFingerMove
    static let doubleTap = Self.threeFingerTap, scroll = Self.fourFingerMove, rightClick = Self.thumbTwoTap
    static let doubleClick = Self.threeFingerTap
}
typealias GestureFeature = GestureTrigger

enum GestureAction: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case disabled, pointer, primaryDrag, scroll, zoom, primaryClick, primaryDoubleClick, secondaryClick
    case notificationCenter, missionControl, appExpose, launchpad, showDesktop
    case openConfig
    case scrollUp, scrollDown, panLeft, panRight
    case volumeUpSmall, volumeDownSmall, brightnessUpSmall, brightnessDownSmall
    static let directionalScrollActions:[Self] = [.scrollUp,.scrollDown,.panLeft,.panRight]
    static let smallStepActions: [Self] = [.volumeUpSmall,.volumeDownSmall,.brightnessUpSmall,.brightnessDownSmall]
    static var oneShotActions: [Self] { appleShortcuts + smallStepActions }
    static let appleShortcuts: [Self] = [.notificationCenter,.missionControl,.appExpose,.launchpad,.showDesktop]
    var isAppleShortcut: Bool { Self.oneShotActions.contains(self) }
    var id: String { rawValue }
    var title: String {
        switch self {
        case .volumeUpSmall: return "Volume Up (Small Step)"
        case .volumeDownSmall: return "Volume Down (Small Step)"
        case .brightnessUpSmall: return "Brightness Up (Small Step)"
        case .brightnessDownSmall: return "Brightness Down (Small Step)"
        case .panLeft: return "Pan Left"
        case .panRight: return "Pan Right"
        case .scrollUp: return "Scroll Up"
        case .scrollDown: return "Scroll Down"
        case .openConfig: return "Open Config"
        case .notificationCenter: return "Notification Center"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .launchpad: return "Launch Pad"
        case .showDesktop: return "Show Desktop"
        case .disabled: return "None"; case .pointer: return "Move Pointer"
        case .primaryDrag: return "Drag / Select"; case .scroll: return "Scroll / Pan"
        case .primaryClick: return "Primary Click"; case .primaryDoubleClick: return "Double-Click"
        case .zoom: return "Zoom"
        case .secondaryClick: return "Secondary Click"
        }
    }
    var isDirectionalScroll:Bool { Self.directionalScrollActions.contains(self) }
    var isHorizontalPan:Bool { self == .panLeft || self == .panRight }
    var requiresPointerProfile: Bool { self == .pointer || self == .primaryDrag }
}
enum GestureSensitivity: Sendable { case pointer, scroll, zoom }

struct GestureActionBindings: Equatable, Codable, Sendable {
    var twoFingerMove: GestureAction = .pointer, twoFingerTap: GestureAction = .primaryClick
    var threeFingerMove: GestureAction = .primaryDrag, threeFingerTap: GestureAction = .primaryDoubleClick
    var fourFingerMove: GestureAction = .scroll, thumbTwoTap: GestureAction = .secondaryClick
    // Optional so old saved bindings decode without discarding customized actions.
    var fourFingerTap:GestureAction?
    var fourCornersTap:GestureAction?
    var forceActions: [String: GestureAction]?
    var twoFingerPinch: GestureAction?
    var pinchActions: [String:GestureAction]?
    var spreadActions: [String:GestureAction]?
    var rotationActions:[String:GestureAction]? // Saved assignments; recognition is not active yet.
    subscript(trigger: GestureTrigger) -> GestureAction {
        get {
            if trigger.isRotation { return rotationActions?[trigger.rawValue] ?? .disabled }
            switch trigger {
            case .fourFingerTap:return fourFingerTap ?? .disabled
            case .fourCornersTap:return .disabled // Decode-only legacy Tap assignment.
            case .twoFingerSpread,.threeFingerSpread,.fourFingerSpread,.fiveFingerSpread:
                return spreadActions?[trigger.rawValue] ?? self[GestureTrigger.pinch(count:trigger.pinchCount!)!]
            case .twoFingerPinch: return twoFingerPinch ?? .zoom
            case .threeFingerPinch,.fourFingerPinch,.fiveFingerPinch: return pinchActions?[trigger.rawValue] ?? trigger.defaultAction
            case .twoFingerMove: return twoFingerMove; case .twoFingerTap: return twoFingerTap
            case .threeFingerMove: return threeFingerMove; case .threeFingerTap: return threeFingerTap
            case .fourFingerMove: return fourFingerMove; case .thumbTwoTap: return thumbTwoTap
            default: return forceActions?[trigger.rawValue] ?? trigger.defaultAction
            }
        }
        set {
            if trigger.isRotation {
                if rotationActions == nil { rotationActions = [:] }
                rotationActions?[trigger.rawValue] = newValue
                return
            }
            if trigger.isPinch && spreadActions == nil {
                spreadActions = Dictionary(uniqueKeysWithValues:GestureTrigger.spreadTriggers.map { ($0.rawValue,self[$0]) })
            }
            switch trigger {
            case .fourFingerTap:fourFingerTap = newValue
            case .fourCornersTap:fourCornersTap = newValue
            case .twoFingerSpread,.threeFingerSpread,.fourFingerSpread,.fiveFingerSpread:
                spreadActions?[trigger.rawValue] = newValue
            case .twoFingerPinch: twoFingerPinch = newValue
            case .threeFingerPinch,.fourFingerPinch,.fiveFingerPinch:
                if pinchActions == nil { pinchActions = [:] }
                pinchActions?[trigger.rawValue] = newValue
            case .twoFingerMove: twoFingerMove = newValue; case .twoFingerTap: twoFingerTap = newValue
            case .threeFingerMove: threeFingerMove = newValue; case .threeFingerTap: threeFingerTap = newValue
            case .fourFingerMove: fourFingerMove = newValue; case .thumbTwoTap: thumbTwoTap = newValue
            default:
                if forceActions == nil { forceActions = [:] }
                forceActions?[trigger.rawValue] = newValue
            }
        }
    }
    func uses(_ action: GestureAction) -> Bool { GestureTrigger.allCases.contains { self[$0] == action } }
    func action(for trigger: GestureTrigger) -> GestureAction {
        let action = self[trigger]
        return trigger.allowedActions.contains(action) ? action : .disabled
    }
}

/// Experimental waveform scale: Apple's framework clamps this argument at 2.0.
/// It is not a calibrated acoustic-volume or physical-amplitude percentage.
struct ForceClickHapticSettings: Equatable, Codable, Sendable {
    var waveform: Int = 6
    var level: Double = 0.25
    static let fixed = Self(waveform:6,level:0.25)
    var normalized: Self {
        Self(waveform:min(6,max(1,waveform)),level:level.isFinite ? min(2,max(0,level)) : 0.25)
    }
    func play(device: UInt64) -> Bool {
        let value = normalized
        guard value.level > 0 else { return false }
        return OMSManager.shared.triggerRawHaptic(actuationID:Int32(value.waveform),unknown1:0,
            unknown2:Float(value.level),unknown3:0,deviceID:String(device))
    }
}

enum GestureMovementMode: String, Codable, Sendable { case continuous, directional }
enum GestureMovementDirection: String, CaseIterable, Codable, Identifiable, Sendable {
    case up, down, left, right
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String { "arrow." + rawValue }
}

/// Per-input directional assignments; live recognition currently supports three fingers.
struct GestureDirectionalAssignments: Equatable, Codable, Sendable {
    static let triggers: [GestureTrigger] = [.twoFingerMove,.threeFingerMove,.fourFingerMove]
    static let liveTriggers = triggers
    static let allowedActions: [GestureAction] = [.disabled,.primaryClick,.primaryDoubleClick,.secondaryClick] + GestureAction.oneShotActions + GestureAction.directionalScrollActions
    var mode: GestureMovementMode = .continuous
    var actions: [String:GestureAction] = [:]
    var repeatOverrides: [String:Bool]? // Decode compatibility with the original checkbox.
    var repeatIntervalsMS: [String:Double]?
    var repeatEnabledOverrides: [String:Bool]?
    static func boundedIntervalMS(_ value:Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        return min(5000,max(20,value.rounded()))
    }
    private func savedRepeatIntervalMS(_ direction:GestureMovementDirection) -> Double {
        if let value = repeatIntervalsMS?[direction.rawValue] { return Self.boundedIntervalMS(value) }
        return (repeatOverrides?[direction.rawValue] ?? GestureAction.smallStepActions.contains(action(direction))) ? 80 : 0
    }
    func configuredRepeatIntervalMS(_ direction:GestureMovementDirection) -> Double {
        max(20,savedRepeatIntervalMS(direction))
    }
    func repeatIntervalMS(_ direction:GestureMovementDirection) -> Double {
        guard !action(direction).isDirectionalScroll else { return 0 }
        if let enabled = repeatEnabledOverrides?[direction.rawValue] {
            return enabled ? configuredRepeatIntervalMS(direction) : 0
        }
        return savedRepeatIntervalMS(direction)
    }
    func repeats(_ direction:GestureMovementDirection) -> Bool {
        repeatIntervalMS(direction) > 0
    }
    var hasAssignments:Bool { GestureMovementDirection.allCases.contains { action($0) != .disabled } }
    func action(_ direction:GestureMovementDirection) -> GestureAction {
        let value = actions[direction.rawValue] ?? .disabled
        return Self.allowedActions.contains(value) ? value : .disabled
    }
}

struct PerHandGestureSettings: Equatable, Codable, Sendable {
    var bindings = GestureActionBindings()
    var pointerSensitivity = 1.0, scrollSensitivity = 1.0
    var zoomSensitivity: Double?
    var naturalScrolling:Bool? // Missing preserves the system preference.
    var directionalMovement: [String:GestureDirectionalAssignments]?
    // Optional for old profiles; count-keyed, independent of Tap/Force actions.
    var holdActions: [String:GestureAction]?
    static let holdAllowedActions = GestureDirectionalAssignments.allowedActions.filter { !GestureAction.directionalScrollActions.contains($0) }
    static func moveTrigger(count:Int) -> GestureTrigger? {
        switch count { case 2:return .twoFingerMove; case 3:return .threeFingerMove; case 4:return .fourFingerMove; default:return nil }
    }
    static let thumbHoldKey = 6, cornersHoldKey = 7
    static func holdActions(for key:Int) -> [GestureAction] { key == cornersHoldKey ? TwoHandGestureSettings.allowedActions : holdAllowedActions }
    func holdAvailable(count:Int) -> Bool { (2...7).contains(count) }
    func holdAction(count:Int) -> GestureAction {
        guard holdAvailable(count:count) else { return .disabled }
        let action = holdActions?[String(count)] ?? (count == Self.cornersHoldKey ? .openConfig : .disabled)
        return Self.holdActions(for:count).contains(action) ? action : .disabled
    }
    mutating func setHoldAction(_ action:GestureAction,count:Int) {
        guard holdAvailable(count:count), Self.holdActions(for:count).contains(action) else { return }
        if holdActions == nil { holdActions = [:] }
        holdActions?[String(count)] = action
    }
    var liveHoldActions:[Int:GestureAction] {
        Dictionary(uniqueKeysWithValues:(1...6).compactMap { count in
            let action = holdAction(count:count)
            return holdAvailable(count:count) && action != .disabled ? (count,action) : nil
        })
    }
    // Decode/round-trip prior experimental settings only. Live feedback uses .fixed.
    var forceHaptic: ForceClickHapticSettings?
    var singlePadCorners:TwoHandGestureSettings {
        var value = TwoHandGestureSettings()
        value.setAction(bindings.action(for:.fourCornersTap),for:.init(chord:.fourCorners,phase:.tap))
        value.setAction(holdAction(count:Self.cornersHoldKey),for:.init(chord:.fourCorners,phase:.hold))
        return value
    }
    // Legacy enable-only clients use factory assignment when enabling a disabled input.
    subscript(trigger: GestureTrigger) -> Bool {
        get { bindings.action(for:trigger) != .disabled }
        set { bindings[trigger] = newValue ? (self[trigger] ? bindings[trigger] : (trigger.defaultAction == .disabled ? .primaryClick : trigger.defaultAction)) : .disabled }
    }
    var mouse: Bool { get { self[.twoFingerMove] } set { self[.twoFingerMove] = newValue } }
    var tap: Bool { get { self[.twoFingerTap] } set { self[.twoFingerTap] = newValue } }
    var doubleTap: Bool { get { self[.threeFingerTap] } set { self[.threeFingerTap] = newValue } }
    var drag: Bool { get { self[.threeFingerMove] } set { self[.threeFingerMove] = newValue } }
    var scroll: Bool { get { self[.fourFingerMove] } set { self[.fourFingerMove] = newValue } }
    var rightClick: Bool { get { self[.thumbTwoTap] } set { self[.thumbTwoTap] = newValue } }
    subscript(kind: GestureSensitivity) -> Double {
        get {
            switch kind { case .pointer: return pointerSensitivity; case .scroll: return scrollSensitivity; case .zoom: return zoomSensitivity ?? 1 }
        }
        set {
            let value = newValue.isFinite ? min(2,max(0.25,newValue)) : 1
            switch kind { case .pointer: pointerSensitivity = value; case .scroll: scrollSensitivity = value; case .zoom: zoomSensitivity = value }
        }
    }
    func movement(_ trigger:GestureTrigger) -> GestureDirectionalAssignments {
        directionalMovement?[trigger.rawValue] ?? GestureDirectionalAssignments()
    }
    mutating func editMovement(_ trigger:GestureTrigger,mode:GestureMovementMode,
                               direction:GestureMovementDirection? = nil,action:GestureAction? = nil) {
        guard GestureDirectionalAssignments.triggers.contains(trigger) else { return }
        var editor = movement(trigger)
        if let direction, let action {
            guard GestureDirectionalAssignments.allowedActions.contains(action) else { return }
            editor.actions[direction.rawValue] = action
        }
        editor.mode = mode
        if directionalMovement == nil { directionalMovement = [:] }
        directionalMovement?[trigger.rawValue] = editor
    }
    mutating func setDirectionalRepeat(_ enabled:Bool,direction:GestureMovementDirection,for trigger:GestureTrigger) {
        guard GestureDirectionalAssignments.triggers.contains(trigger) else { return }
        var editor = movement(trigger)
        if enabled {
            let interval = editor.configuredRepeatIntervalMS(direction)
            if editor.repeatIntervalsMS == nil { editor.repeatIntervalsMS = [:] }
            editor.repeatIntervalsMS?[direction.rawValue] = interval
        }
        if editor.repeatEnabledOverrides == nil { editor.repeatEnabledOverrides = [:] }
        editor.repeatEnabledOverrides?[direction.rawValue] = enabled
        if directionalMovement == nil { directionalMovement = [:] }
        directionalMovement?[trigger.rawValue] = editor
    }
    mutating func setDirectionalRepeatInterval(_ milliseconds:Double,direction:GestureMovementDirection,for trigger:GestureTrigger) {
        guard GestureDirectionalAssignments.triggers.contains(trigger) else { return }
        var editor = movement(trigger)
        if editor.repeatIntervalsMS == nil { editor.repeatIntervalsMS = [:] }
        let interval = GestureDirectionalAssignments.boundedIntervalMS(milliseconds)
        editor.repeatIntervalsMS?[direction.rawValue] = interval
        if editor.repeatEnabledOverrides == nil { editor.repeatEnabledOverrides = [:] }
        editor.repeatEnabledOverrides?[direction.rawValue] = interval > 0
        if directionalMovement == nil { directionalMovement = [:] }
        directionalMovement?[trigger.rawValue] = editor
    }
    var liveDirectionalBindings:[GestureTrigger:GestureDirectionalAssignments] {
        Dictionary(uniqueKeysWithValues:GestureDirectionalAssignments.liveTriggers.compactMap { trigger in
            let config = movement(trigger)
            return config.mode == .directional ? (trigger,config) : nil
        })
    }
    var outputSettings: Self {
        var result = self
        for trigger in GestureDirectionalAssignments.triggers where movement(trigger).mode == .directional {
            result.bindings[trigger] = .disabled
        }
        return result
    }
    mutating func normalize() {
        for trigger in GestureTrigger.allCases where bindings[trigger] != bindings.action(for:trigger) {
            bindings[trigger] = bindings.action(for:trigger)
        }
        if zoomSensitivity != nil { self[GestureSensitivity.zoom] = self[GestureSensitivity.zoom] }
        if let forceHaptic { self.forceHaptic = forceHaptic.normalized }
        self[GestureSensitivity.pointer] = pointerSensitivity; self[GestureSensitivity.scroll] = scrollSensitivity
    }
}

struct GestureSelectedPads: Equatable, Sendable { var left: UInt64?, right: UInt64? }

struct HandGestureSettings: Equatable, Codable, Sendable {
    static let defaultsKey = "AppleMagicTouchstream.handGestureBindings.v1"
    var left: PerHandGestureSettings
    var right: PerHandGestureSettings
    var coordinated: TwoHandGestureSettings?
    var twoHand: TwoHandGestureSettings { coordinated ?? TwoHandGestureSettings() }
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
    func holdAvailable(count:Int,in scope:GestureHandScope) -> Bool {
        (scope == .right || left.holdAvailable(count:count)) && (scope == .left || right.holdAvailable(count:count))
    }
    func holdAction(count:Int,in scope:GestureHandScope) -> GestureAction? {
        let a = left.holdAction(count:count), b = right.holdAction(count:count)
        return scope == .left ? a : scope == .right ? b : a == b ? a : nil
    }
    mutating func setHoldAction(_ action:GestureAction,count:Int,in scope:GestureHandScope) {
        guard holdAvailable(count:count,in:scope) else { return }
        if scope != .right { left.setHoldAction(action,count:count) }
        if scope != .left { right.setHoldAction(action,count:count) }
    }
    func movementMode(_ trigger:GestureTrigger,in scope:GestureHandScope) -> GestureMovementMode? {
        let a = left.movement(trigger).mode, b = right.movement(trigger).mode
        return scope == .left ? a : scope == .right ? b : a == b ? a : nil
    }
    func directionalAction(_ direction:GestureMovementDirection,for trigger:GestureTrigger,in scope:GestureHandScope) -> GestureAction? {
        let a = left.movement(trigger).action(direction), b = right.movement(trigger).action(direction)
        return scope == .left ? a : scope == .right ? b : a == b ? a : nil
    }
    func directionalConfiguredRepeatInterval(_ direction:GestureMovementDirection,for trigger:GestureTrigger,in scope:GestureHandScope) -> Double? {
        let a = left.movement(trigger).configuredRepeatIntervalMS(direction), b = right.movement(trigger).configuredRepeatIntervalMS(direction)
        return scope == .left ? a : scope == .right ? b : a == b ? a : nil
    }
    func directionalRepeatInterval(_ direction:GestureMovementDirection,for trigger:GestureTrigger,in scope:GestureHandScope) -> Double? {
        let a = left.movement(trigger).repeatIntervalMS(direction), b = right.movement(trigger).repeatIntervalMS(direction)
        return scope == .left ? a : scope == .right ? b : a == b ? a : nil
    }
    mutating func setDirectionalRepeatInterval(_ milliseconds:Double,direction:GestureMovementDirection,for trigger:GestureTrigger,in scope:GestureHandScope) {
        if scope != .right { left.setDirectionalRepeatInterval(milliseconds,direction:direction,for:trigger) }
        if scope != .left { right.setDirectionalRepeatInterval(milliseconds,direction:direction,for:trigger) }
    }
    func directionalRepeats(_ direction:GestureMovementDirection,for trigger:GestureTrigger,in scope:GestureHandScope) -> Bool? {
        let a = left.movement(trigger).repeats(direction), b = right.movement(trigger).repeats(direction)
        return scope == .left ? a : scope == .right ? b : a == b ? a : nil
    }
    mutating func setDirectionalRepeat(_ enabled:Bool,direction:GestureMovementDirection,for trigger:GestureTrigger,in scope:GestureHandScope) {
        if scope != .right { left.setDirectionalRepeat(enabled,direction:direction,for:trigger) }
        if scope != .left { right.setDirectionalRepeat(enabled,direction:direction,for:trigger) }
    }
    mutating func editMovement(_ trigger:GestureTrigger,mode:GestureMovementMode,
                               direction:GestureMovementDirection? = nil,action:GestureAction? = nil,in scope:GestureHandScope) {
        if scope != .right { left.editMovement(trigger,mode:mode,direction:direction,action:action) }
        if scope != .left { right.editMovement(trigger,mode:mode,direction:direction,action:action) }
    }
    func enabled(_ feature: GestureTrigger, in scope: GestureHandScope) -> Bool? {
        switch scope {
        case .left: return left[feature]; case .right: return right[feature]
        case .both: return left[feature] == right[feature] ? left[feature] : nil
        }
    }
    func naturalScrolling(in scope:GestureHandScope,fallback:Bool) -> Bool? {
        let a = left.naturalScrolling ?? fallback, b = right.naturalScrolling ?? fallback
        return scope == .left ? a : scope == .right ? b : a == b ? a : nil
    }
    mutating func setNaturalScrolling(_ enabled:Bool,in scope:GestureHandScope) {
        if scope != .right { left.naturalScrolling = enabled }
        if scope != .left { right.naturalScrolling = enabled }
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
        let left = self.left.outputSettings, right = self.right.outputSettings
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


/// Coordinated inputs have their own namespace; Mirror Edit never writes these.
enum TwoHandChord:String,CaseIterable,Codable,Identifiable,Sendable {
    case fourCorners, threeFingers, fourFingers
    var id:String { rawValue }
    var title:String {
        switch self { case .fourCorners:return "4 corners"; case .threeFingers:return "3 fingers per hand"; case .fourFingers:return "4 fingers per hand" }
    }
    var count:Int { self == .fourCorners ? 2 : self == .threeFingers ? 3 : 4 }
    var phases:[TwoHandPhase] { self == .fourCorners ? [.hold] : TwoHandPhase.allCases }
    var holdDuration:Double { self == .fourCorners ? 1 : 0.5 }
    static let recognitionOrder:[Self] = [.fourCorners,.threeFingers,.fourFingers]
}
enum TwoHandPhase:String,CaseIterable,Codable,Identifiable,Sendable {
    case tap, hold
    var id:String { rawValue }
    var title:String { rawValue.capitalized }
}
struct TwoHandTrigger:Equatable,Sendable {
    var chord:TwoHandChord
    var phase:TwoHandPhase
    var key:String {
        switch (chord,phase) {
        case (.fourCorners,.tap):return "fourCorners.tap"
        case (.fourCorners,.hold):return "fourCorners.hold"
        case (.threeFingers,.tap):return "threeFingers.tap"
        case (.threeFingers,.hold):return "threeFingers.hold"
        case (.fourFingers,.tap):return "fourFingers.tap"
        case (.fourFingers,.hold):return "fourFingers.hold"
        }
    }
}
struct TwoHandGestureSettings:Equatable,Codable,Sendable {
    var assignments:[String:GestureAction] = [:]
    static let allowedActions:[GestureAction] = [.disabled,.openConfig,.primaryClick,.primaryDoubleClick,.secondaryClick]+GestureAction.oneShotActions
    func action(_ trigger:TwoHandTrigger) -> GestureAction {
        guard trigger.chord != .fourCorners || trigger.phase == .hold else { return .disabled }
        let value = assignments[trigger.key] ?? (trigger.chord == .fourCorners && trigger.phase == .hold ? .openConfig : .disabled)
        return Self.allowedActions.contains(value) ? value : .disabled
    }
    func enabled(_ chord:TwoHandChord) -> Bool {
        action(.init(chord:chord,phase:.tap)) != .disabled || action(.init(chord:chord,phase:.hold)) != .disabled
    }
    mutating func setAction(_ action:GestureAction,for trigger:TwoHandTrigger) {
        guard (trigger.chord != .fourCorners || trigger.phase == .hold), Self.allowedActions.contains(action) else { return }
        assignments[trigger.key] = action
    }
}


enum TwoHandGestureEligibility {
    static func enabled(pads:GestureSelectedPads,owned:Set<UInt64>,takeover:Bool,armed:Bool) -> Bool {
        guard takeover, armed, let left = pads.left, let right = pads.right, left != right else { return false }
        return owned.contains(left) && owned.contains(right)
    }
}

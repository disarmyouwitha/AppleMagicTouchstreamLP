import Foundation
import OpenMultitouchSupport

enum GestureHandScope: String, CaseIterable, Identifiable, Sendable {
    case left = "Left", right = "Right", both = "Both"
    var id: String { rawValue }
}

/// Inputs are recognized independently of the action assigned to them.
enum GestureTrigger: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case twoFingerMove, twoFingerTap, threeFingerMove, threeFingerTap, fourFingerMove, fourFingerTap, fiveFingerMove, fiveFingerTap, fourCornersTap, thumbTwoTap
    case thumbTwoMove
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
    static let liveRotationTriggers:[Self] = rotationTriggers
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
    var isContinuous: Bool { self == .thumbTwoMove || isPinch || isRotation || self == .twoFingerMove || self == .threeFingerMove || self == .fourFingerMove || self == .fiveFingerMove }
    var title: String {
        if let count = pinchCount { return "\(count)-finger \(isSpread ? "spread" : "pinch") (thumb required)" }
        if let count = rotationCount {
            return count == 3 ? "Thumb + 2 fingertips rotate \(rotatesRight ? "right" : "left")"
                : "\(count)-finger rotate \(rotatesRight ? "right" : "left")"
        }
        if let count = forceCount { return "\(count)-finger force click" }
        switch self {
        case .thumbTwoMove: return "Thumb + 2 fingertips diagonal swipe"
        case .twoFingerMove: return "2-finger movement"
        case .twoFingerTap: return "2-finger tap"
        case .threeFingerMove: return "3-finger movement"
        case .threeFingerTap: return "3-finger tap"
        case .fourFingerMove: return "4-finger movement"
        case .fourFingerTap: return "4-finger tap"
        case .fiveFingerMove: return "5-finger movement"
        case .fiveFingerTap: return "5-finger tap"
        case .fourCornersTap: return "Outer corners tap"
        case .thumbTwoTap: return "Spread thumb + 2 fingertips tap"
        default: return "Force click"
        }
    }
    var allowedActions: [GestureAction] {
        if self == .fourCornersTap || self == .thumbTwoMove { return [.disabled] }
        if isPinch { return [.disabled,.zoom] + GestureAction.oneShotActions }
        if isRotation { return [.disabled,.rotate,.primaryClick,.primaryDoubleClick,.secondaryClick] + GestureAction.oneShotActions }
        if forceCount != nil || self == .fourFingerTap || self == .fiveFingerTap { return [.disabled,.primaryClick,.primaryDoubleClick,.secondaryClick] + GestureAction.oneShotActions }
        return isContinuous ? [.disabled,.pointer,.primaryDrag,.scroll] : [.disabled,.primaryClick,.primaryDoubleClick,.secondaryClick,.smartZoom,.pageBack,.pageForward,.lookUp,.previousSpace,.nextSpace,.voice] + GestureAction.smallStepActions + GestureAction.mediaActions
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

enum GestureAction: CaseIterable, Identifiable, Hashable, Codable, RawRepresentable, Sendable {
    case disabled, pointer, primaryDrag, scroll, zoom, primaryClick, primaryDoubleClick, secondaryClick
    case notificationCenter, missionControl, appExpose, launchpad, showDesktop
    case openConfig, voice, smartZoom, lookUp, previousSpace, nextSpace, pageBack, pageForward, rotate
    case scrollUp, scrollDown, panLeft, panRight
    case playPause, previousTrack, nextTrack, mute
    case volumeUpSmall, volumeDownSmall, brightnessUpSmall, brightnessDownSmall
    case shortcut(GestureShortcutAssignment)
    static let allCases: [Self] = [.disabled,.pointer,.primaryDrag,.scroll,.zoom,.primaryClick,.primaryDoubleClick,.secondaryClick,.notificationCenter,.missionControl,.appExpose,.launchpad,.showDesktop,.smartZoom,.lookUp,.previousSpace,.nextSpace,.pageBack,.pageForward,.rotate,.playPause,.previousTrack,.nextTrack,.mute,.openConfig,.voice,.scrollUp,.scrollDown,.panLeft,.panRight,.volumeUpSmall,.volumeDownSmall,.brightnessUpSmall,.brightnessDownSmall]
    var rawValue: String {
        switch self {
        case .disabled: return "disabled"
        case .pointer: return "pointer"
        case .primaryDrag: return "primaryDrag"
        case .scroll: return "scroll"
        case .zoom: return "zoom"
        case .smartZoom: return "smartZoom"
        case .pageBack: return "pageBack"
        case .pageForward: return "pageForward"
        case .rotate: return "rotate"
        case .playPause: return "playPause"
        case .previousTrack: return "previousTrack"
        case .nextTrack: return "nextTrack"
        case .mute: return "mute"
        case .lookUp: return "lookUp"
        case .previousSpace: return "previousSpace"
        case .nextSpace: return "nextSpace"
        case .primaryClick: return "primaryClick"
        case .primaryDoubleClick: return "primaryDoubleClick"
        case .secondaryClick: return "secondaryClick"
        case .notificationCenter: return "notificationCenter"
        case .missionControl: return "missionControl"
        case .appExpose: return "appExpose"
        case .launchpad: return "launchpad"
        case .showDesktop: return "showDesktop"
        case .openConfig: return "openConfig"
        case .voice: return "voice"
        case .scrollUp: return "scrollUp"
        case .scrollDown: return "scrollDown"
        case .panLeft: return "panLeft"
        case .panRight: return "panRight"
        case .volumeUpSmall: return "volumeUpSmall"
        case .volumeDownSmall: return "volumeDownSmall"
        case .brightnessUpSmall: return "brightnessUpSmall"
        case .brightnessDownSmall: return "brightnessDownSmall"
        case let .shortcut(value):
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            return "shortcut:" + String(data:try! encoder.encode(value),encoding:.utf8)!
        }
    }
    init?(rawValue:String) {
        if let value = Self.allCases.first(where:{$0.rawValue == rawValue}) { self = value; return }
        guard rawValue.hasPrefix("shortcut:"),
              let data = String(rawValue.dropFirst(9)).data(using:.utf8),
              let spec = try? JSONDecoder().decode(GestureShortcutAssignment.self,from:data),
              spec.action != nil, !spec.holdUntilRelease || spec.action?.kind == .key else { return nil }
        self = .shortcut(spec)
    }
    init(from decoder:any Decoder) throws {
        let box = try decoder.singleValueContainer(); let text = try box.decode(String.self)
        guard let value = Self(rawValue:text) else { throw DecodingError.dataCorruptedError(in:box,debugDescription:"Unknown gesture action") }
        self = value
    }
    func encode(to encoder:any Encoder) throws { var box = encoder.singleValueContainer(); try box.encode(rawValue) }
    var shortcutAssignment:GestureShortcutAssignment? { if case let .shortcut(value) = self { return value }; return nil }
    var isHeldShortcut:Bool { shortcutAssignment?.holdUntilRelease == true }
    var isDiscreteOutput:Bool { isAppleShortcut || Self.nativeDiscreteActions.contains(self) || self == .voice || shortcutAssignment != nil }
    static let directionalScrollActions:[Self] = [.scrollUp,.scrollDown,.panLeft,.panRight]
    static let mediaActions:[Self] = [.playPause,.previousTrack,.nextTrack,.mute]
    static let smallStepActions: [Self] = [.volumeUpSmall,.volumeDownSmall,.brightnessUpSmall,.brightnessDownSmall]
    static var oneShotActions: [Self] { appleShortcuts + nativeDiscreteActions + mediaActions + smallStepActions + [.voice] }
    static let nativeDiscreteActions:[Self] = [.smartZoom,.pageBack,.pageForward]
    static let appleShortcuts: [Self] = [.notificationCenter,.missionControl,.appExpose,.launchpad,.showDesktop,.lookUp,.previousSpace,.nextSpace]
    var isAppleShortcut: Bool { Self.appleShortcuts.contains(self) || Self.smallStepActions.contains(self) || Self.mediaActions.contains(self) }
    var id: String { rawValue }
    var title: String {
        switch self {
        case let .shortcut(value): return value.action?.pickerText ?? "Unavailable shortcut"
        case .volumeUpSmall: return "Volume Up (Small Step)"
        case .volumeDownSmall: return "Volume Down (Small Step)"
        case .brightnessUpSmall: return "Brightness Up (Small Step)"
        case .brightnessDownSmall: return "Brightness Down (Small Step)"
        case .panLeft: return "Pan Left"
        case .panRight: return "Pan Right"
        case .scrollUp: return "Scroll Up"
        case .scrollDown: return "Scroll Down"
        case .openConfig: return "Open Config"
        case .voice: return "Voice"
        case .notificationCenter: return "Notification Center"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .launchpad: return "Launch Pad"
        case .showDesktop: return "Show Desktop"
        case .disabled: return "None"; case .pointer: return "Move Pointer"
        case .primaryDrag: return "Drag / Select"; case .scroll: return "Scroll / Pan"
        case .primaryClick: return "Primary Click"; case .primaryDoubleClick: return "Double-Click"
        case .zoom: return "Zoom"
        case .smartZoom: return "Smart Zoom"
        case .pageBack: return "Back (Page Navigation)"
        case .pageForward: return "Forward (Page Navigation)"
        case .rotate: return "Rotate Content"
        case .playPause: return "Play / Pause"
        case .previousTrack: return "Previous Track"
        case .nextTrack: return "Next Track"
        case .mute: return "Mute"
        case .lookUp: return "Look Up"
        case .previousSpace: return "Previous Space"
        case .nextSpace: return "Next Space"
        case .secondaryClick: return "Secondary Click"
        }
    }
    var isDirectionalScroll:Bool { Self.directionalScrollActions.contains(self) }
    var isHorizontalPan:Bool { self == .panLeft || self == .panRight }
    var requiresPointerProfile: Bool { self == .pointer || self == .primaryDrag }
}
enum GestureSensitivity: Sendable { case pointer, scroll, zoom }

enum GestureShapeRepeatMode:String,CaseIterable,Codable,Sendable {
    case once, timed, motion
    var title:String { switch self { case .once:return "Once"; case .timed:return "Repeat every ms"; case .motion:return "Repeat with motion" } }
}
struct GestureShapeRepeat:Equatable,Codable,Sendable {
    var mode:GestureShapeRepeatMode = .once
    var intervalMS:Double = 80
    var boundedIntervalMS:Double { intervalMS.isFinite ? min(5000,max(20,intervalMS.rounded())) : 80 }
}

struct GestureActionBindings: Equatable, Codable, Sendable {
    var twoFingerMove: GestureAction = .pointer, twoFingerTap: GestureAction = .primaryClick
    var threeFingerMove: GestureAction = .primaryDrag, threeFingerTap: GestureAction = .primaryDoubleClick
    var fourFingerMove: GestureAction = .scroll, thumbTwoTap: GestureAction = .secondaryClick
    // Optional so old saved bindings decode without discarding customized actions.
    var fourFingerTap:GestureAction?
    var fiveFingerTap:GestureAction?, fiveFingerMove:GestureAction?
    var fourCornersTap:GestureAction?
    var forceActions: [String: GestureAction]?
    var twoFingerPinch: GestureAction?
    var pinchActions: [String:GestureAction]?
    var spreadActions: [String:GestureAction]?
    var rotationActions:[String:GestureAction]?
    var shapeRepeats:[String:GestureShapeRepeat]?
    func shapeRepeat(_ trigger:GestureTrigger) -> GestureShapeRepeat { shapeRepeats?[trigger.rawValue] ?? GestureShapeRepeat() }
    mutating func setShapeRepeat(_ value:GestureShapeRepeat,for trigger:GestureTrigger) {
        guard trigger.isPinch || trigger.isRotation else { return }
        if shapeRepeats == nil { shapeRepeats = [:] }
        shapeRepeats?[trigger.rawValue] = GestureShapeRepeat(mode:value.mode,intervalMS:value.boundedIntervalMS)
    }
    subscript(trigger: GestureTrigger) -> GestureAction {
        get {
            if trigger.isRotation { return rotationActions?[trigger.rawValue] ?? .disabled }
            switch trigger {
            case .fourFingerTap:return fourFingerTap ?? .disabled
            case .fiveFingerTap:return fiveFingerTap ?? .disabled
            case .fiveFingerMove:return fiveFingerMove ?? .disabled
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
            case .fiveFingerTap:fiveFingerTap = newValue
            case .fiveFingerMove:fiveFingerMove = newValue
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
        return trigger.accepts(action) ? action : .disabled
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
    case up, down, left, right, upLeft, upRight, downLeft, downRight
    static let cardinals: [Self] = [.up,.down,.left,.right]
    static let diagonals: [Self] = [.upLeft,.upRight,.downLeft,.downRight]
    var isDiagonal: Bool { Self.diagonals.contains(self) }
    var id: String { rawValue }
    var title: String {
        switch self {
        case .upLeft:return "Up-left"; case .upRight:return "Up-right"
        case .downLeft:return "Down-left"; case .downRight:return "Down-right"
        default:return rawValue.capitalized
        }
    }
    var symbol: String {
        switch self {
        case .upLeft:return "arrow.up.left"; case .upRight:return "arrow.up.right"
        case .downLeft:return "arrow.down.left"; case .downRight:return "arrow.down.right"
        default:return "arrow." + rawValue
        }
    }
    var arrow: String {
        switch self {
        case .upLeft:return "↖"; case .upRight:return "↗"
        case .downLeft:return "↙"; case .downRight:return "↘"
        case .up:return "↑"; case .down:return "↓"; case .left:return "←"; case .right:return "→"
        }
    }
    /// Screen/app coordinates: positive Y is down.
    var unitVector: CGPoint {
        let diagonal = 1 / sqrt(2.0)
        switch self {
        case .up:return .init(x:0,y:-1); case .down:return .init(x:0,y:1)
        case .left:return .init(x:-1,y:0); case .right:return .init(x:1,y:0)
        case .upLeft:return .init(x:-diagonal,y:-diagonal); case .upRight:return .init(x:diagonal,y:-diagonal)
        case .downLeft:return .init(x:-diagonal,y:diagonal); case .downRight:return .init(x:diagonal,y:diagonal)
        }
    }
    static func diagonal(for delta: CGPoint) -> Self? {
        let x = Double(delta.x), y = Double(delta.y)
        guard x.isFinite, y.isFinite, abs(x) > 0, abs(y) > 0,
              min(abs(x),abs(y)) >= max(abs(x),abs(y)) * (sqrt(2.0)-1) else { return nil }
        return y < 0 ? (x < 0 ? .upLeft : .upRight) : (x < 0 ? .downLeft : .downRight)
    }
    func projection(_ delta: CGPoint) -> Double {
        Double(delta.x * unitVector.x + delta.y * unitVector.y)
    }
}

/// Per-input directional assignments; live recognition shares the same logic for two through five fingers.
enum GestureDirectionalRepeatBehavior: String, CaseIterable, Codable, Sendable {
    case timed, motion
    var title:String { self == .timed ? "Repeat every ms" : "Repeat with motion" }
}

struct GestureDirectionalAssignments: Equatable, Codable, Sendable {
    static let cardinalTriggers: [GestureTrigger] = [.twoFingerMove,.threeFingerMove,.fourFingerMove,.fiveFingerMove]
    static let triggers = cardinalTriggers + [.thumbTwoMove]
    static func directions(for trigger:GestureTrigger) -> [GestureMovementDirection] {
        trigger == .thumbTwoMove ? GestureMovementDirection.diagonals : GestureMovementDirection.cardinals
    }
    static let liveTriggers = triggers
    static let allowedActions: [GestureAction] = [.disabled,.primaryClick,.primaryDoubleClick,.secondaryClick] + GestureAction.oneShotActions + GestureAction.directionalScrollActions
    var mode: GestureMovementMode = .continuous
    var actions: [String:GestureAction] = [:]
    var repeatOverrides: [String:Bool]? // Decode compatibility with the original checkbox.
    var repeatIntervalsMS: [String:Double]?
    var repeatEnabledOverrides: [String:Bool]?
    var repeatBehaviors: [String:GestureDirectionalRepeatBehavior]?
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
    func repeatBehavior(_ direction:GestureMovementDirection) -> GestureDirectionalRepeatBehavior {
        repeatBehaviors?[direction.rawValue] ?? (action(direction).isDirectionalScroll ? .motion : .timed)
    }
    func repeatIntervalMS(_ direction:GestureMovementDirection) -> Double {
        guard repeatBehavior(direction) == .timed else { return 0 }
        if let enabled = repeatEnabledOverrides?[direction.rawValue] {
            return enabled ? configuredRepeatIntervalMS(direction) : 0
        }
        return savedRepeatIntervalMS(direction)
    }
    func repeats(_ direction:GestureMovementDirection) -> Bool {
        if repeatBehavior(direction) == .motion {
            // Legacy scroll assignments always followed motion, even with saved timer settings.
            if action(direction).isDirectionalScroll && repeatBehaviors?[direction.rawValue] == nil { return true }
            return repeatEnabledOverrides?[direction.rawValue] ?? (action(direction).isDirectionalScroll || savedRepeatIntervalMS(direction) > 0)
        }
        return repeatIntervalMS(direction) > 0
    }
    var hasAssignments:Bool { GestureMovementDirection.allCases.contains { action($0) != .disabled } }
    func action(_ direction:GestureMovementDirection) -> GestureAction {
        let value = actions[direction.rawValue] ?? .disabled
        return Self.allowedActions.acceptsGestureAction(value) ? value : .disabled
    }
}

enum GestureHoldTiming {
    static let defaultSeconds = 0.5
    static func milliseconds(_ seconds:Double) -> Int { Int((seconds*1000).rounded()) }
    static func validated(_ seconds:Double?) -> Double {
        guard let seconds, seconds.isFinite else { return defaultSeconds }
        return (min(5,max(0.1,seconds))*100).rounded()/100
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
    var holdThresholds: [String:Double]?
    func holdThreshold(count:Int) -> Double { GestureHoldTiming.validated(holdThresholds?[String(count)]) }
    mutating func setHoldThreshold(_ seconds:Double,count:Int) {
        guard holdAvailable(count:count) else { return }
        if holdThresholds == nil { holdThresholds = [:] }
        holdThresholds?[String(count)] = GestureHoldTiming.validated(seconds)
    }
    var liveHoldThresholds:[Int:Double] {
        Dictionary(uniqueKeysWithValues:(2...6).map { ($0,holdThreshold(count:$0)) })
    }
    static let holdAllowedActions = GestureDirectionalAssignments.allowedActions.filter { !GestureAction.directionalScrollActions.contains($0) }
    static func moveTrigger(count:Int) -> GestureTrigger? {
        switch count { case 2:return .twoFingerMove; case 3:return .threeFingerMove; case 4:return .fourFingerMove; case 5:return .fiveFingerMove; default:return nil }
    }
    static let thumbHoldKey = 6, cornersHoldKey = 7
    static func holdActions(for key:Int) -> [GestureAction] { key == cornersHoldKey ? TwoHandGestureSettings.allowedActions : holdAllowedActions }
    func holdAvailable(count:Int) -> Bool { (2...7).contains(count) }
    func holdAction(count:Int) -> GestureAction {
        guard holdAvailable(count:count) else { return .disabled }
        let action = holdActions?[String(count)] ?? (count == Self.cornersHoldKey ? .openConfig : .disabled)
        return Self.holdActions(for:count).acceptsGestureAction(action,held:true) ? action : .disabled
    }
    mutating func setHoldAction(_ action:GestureAction,count:Int) {
        guard holdAvailable(count:count), Self.holdActions(for:count).acceptsGestureAction(action,held:true) else { return }
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
        value.setHoldThreshold(holdThreshold(count:Self.cornersHoldKey),for:.fourCorners)
        return value
    }
    // Legacy enable-only clients use factory assignment when enabling a disabled input.
    subscript(trigger: GestureTrigger) -> Bool {
        get { bindings.action(for:trigger) != .disabled }
        set { bindings[trigger] = newValue ? (self[trigger] ? bindings[trigger] : (trigger.defaultAction == .disabled ? (trigger.allowedActions.contains(.primaryClick) ? .primaryClick : trigger.allowedActions.first(where:{$0 != .disabled}) ?? .disabled) : trigger.defaultAction)) : .disabled }
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
        var config = directionalMovement?[trigger.rawValue] ?? GestureDirectionalAssignments()
        if trigger == .thumbTwoMove { config.mode = .directional }
        let unsupported = trigger == .thumbTwoMove ? GestureMovementDirection.cardinals : GestureMovementDirection.diagonals
        for direction in unsupported where config.actions[direction.rawValue] != nil {
            config.actions[direction.rawValue] = nil
        }
        return config
    }
    mutating func editMovement(_ trigger:GestureTrigger,mode:GestureMovementMode,
                               direction:GestureMovementDirection? = nil,action:GestureAction? = nil) {
        guard GestureDirectionalAssignments.triggers.contains(trigger) else { return }
        var editor = movement(trigger)
        if let direction, let action {
            guard GestureDirectionalAssignments.directions(for:trigger).contains(direction), GestureDirectionalAssignments.allowedActions.acceptsGestureAction(action) else { return }
            editor.actions[direction.rawValue] = action
        }
        editor.mode = mode
        if directionalMovement == nil { directionalMovement = [:] }
        directionalMovement?[trigger.rawValue] = editor
    }
    mutating func preserveMissingRepeatBehaviors(from current:Self) {
        if let saved = current.bindings.shapeRepeats {
            bindings.shapeRepeats = saved.merging(bindings.shapeRepeats ?? [:]) { _,supplied in supplied }
        }
        for (trigger,saved) in current.directionalMovement ?? [:] {
            guard let behaviors = saved.repeatBehaviors, !behaviors.isEmpty else { continue }
            var imported = directionalMovement?[trigger] ?? GestureDirectionalAssignments()
            imported.repeatBehaviors = behaviors.merging(imported.repeatBehaviors ?? [:]) { _, supplied in supplied }
            if directionalMovement == nil { directionalMovement = [:] }
            directionalMovement?[trigger] = imported
        }
    }
    mutating func setDirectionalRepeatBehavior(_ behavior:GestureDirectionalRepeatBehavior,direction:GestureMovementDirection,for trigger:GestureTrigger) {
        guard GestureDirectionalAssignments.triggers.contains(trigger),
              GestureDirectionalAssignments.directions(for:trigger).contains(direction) else { return }
        setDirectionalRepeat(true,direction:direction,for:trigger)
        var editor = movement(trigger)
        if editor.repeatBehaviors == nil { editor.repeatBehaviors = [:] }
        editor.repeatBehaviors?[direction.rawValue] = behavior
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
            return config.mode == .directional && (trigger != .thumbTwoMove || config.hasAssignments) ? (trigger,config) : nil
        })
    }
    var outputSettings: Self {
        var result = self
        for trigger in GestureDirectionalAssignments.triggers where movement(trigger).mode == .directional && result.bindings[trigger] != .disabled {
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
    var stenoConnectionMode:StenoConnectionMode?
    var resolvedStenoConnectionMode:StenoConnectionMode { stenoConnectionMode ?? .defaultMode }
    var stenoHapticOnTouch:Bool?
    var stenoHapticOnRelease:Bool?
    var stenoForceThreshold:Double?
    var resolvedStenoForceThreshold:Double { StenoForceThreshold.validated(stenoForceThreshold ?? StenoForceThreshold.defaultValue) }
    var stenoPointerMode:StenoPointerMode?
    var resolvedStenoPointerMode:StenoPointerMode { .twoFinger }
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
        guard trigger.accepts(action) else { return false }
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
    func holdThreshold(count:Int,in scope:GestureHandScope) -> Double? {
        let a = left.holdThreshold(count:count), b = right.holdThreshold(count:count)
        return scope == .left ? a : scope == .right ? b : a == b ? a : nil
    }
    mutating func setHoldThreshold(_ seconds:Double,count:Int,in scope:GestureHandScope) {
        if scope != .right { left.setHoldThreshold(seconds,count:count) }
        if scope != .left { right.setHoldThreshold(seconds,count:count) }
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
    func shapeRepeat(_ trigger:GestureTrigger,in scope:GestureHandScope) -> GestureShapeRepeat? {
        let a = left.bindings.shapeRepeat(trigger), b = right.bindings.shapeRepeat(trigger)
        switch scope { case .left:return a; case .right:return b; case .both:return a == b ? a : nil }
    }
    mutating func setShapeRepeat(_ value:GestureShapeRepeat,for trigger:GestureTrigger,in scope:GestureHandScope) {
        if scope != .right { left.bindings.setShapeRepeat(value,for:trigger) }
        if scope != .left { right.bindings.setShapeRepeat(value,for:trigger) }
    }
    func directionalRepeatBehavior(_ direction:GestureMovementDirection,for trigger:GestureTrigger,in scope:GestureHandScope) -> GestureDirectionalRepeatBehavior? {
        let a = left.movement(trigger).repeatBehavior(direction), b = right.movement(trigger).repeatBehavior(direction)
        return scope == .left ? a : scope == .right ? b : a == b ? a : nil
    }
    mutating func setDirectionalRepeatBehavior(_ behavior:GestureDirectionalRepeatBehavior,direction:GestureMovementDirection,for trigger:GestureTrigger,in scope:GestureHandScope) {
        if scope != .right { left.setDirectionalRepeatBehavior(behavior,direction:direction,for:trigger) }
        if scope != .left { right.setDirectionalRepeatBehavior(behavior,direction:direction,for:trigger) }
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
    // Keep the existing fourCorners identity for saved Outer Corners settings.
    case fourCorners, innerCorners
    case topOuterCorners, topInnerCorners, bottomOuterCorners, bottomInnerCorners
    case threeFingers, fourFingers
    var id:String { rawValue }
    var title:String {
        switch self {
        case .fourCorners:return "Outer Corners"
        case .innerCorners:return "Inner Corners"
        case .topOuterCorners:return "↖ ↗ Corners"
        case .topInnerCorners:return "↗ ↖ Corners"
        case .bottomOuterCorners:return "↙ ↘ Corners"
        case .bottomInnerCorners:return "↘ ↙ Corners"
        case .threeFingers:return "3 fingers per hand"
        case .fourFingers:return "4 fingers per hand"
        }
    }
    var count:Int {
        switch self {
        case .fourCorners,.innerCorners:return 2
        case .topOuterCorners,.topInnerCorners,.bottomOuterCorners,.bottomInnerCorners:return 1
        case .threeFingers:return 3
        case .fourFingers:return 4
        }
    }
    var isCorner:Bool { self != .threeFingers && self != .fourFingers }
    var expandedCornerChord:Self? {
        switch self {
        case .topOuterCorners,.bottomOuterCorners:return .fourCorners
        case .topInnerCorners,.bottomInnerCorners:return .innerCorners
        default:return nil
        }
    }
    var phases:[TwoHandPhase] { isCorner ? [.hold] : TwoHandPhase.allCases }
    /// Bits match CornerGestureGeometry: bottom-left, top-left, bottom-right,
    /// top-right. Native Y increases toward the top of the pad.
    func cornerMask(leftHand:Bool) -> Int? {
        switch self {
        case .fourCorners:return leftHand ? 0b0011 : 0b1100
        case .innerCorners:return leftHand ? 0b1100 : 0b0011
        case .topOuterCorners:return leftHand ? 0b0010 : 0b1000
        case .topInnerCorners:return leftHand ? 0b1000 : 0b0010
        case .bottomOuterCorners:return leftHand ? 0b0001 : 0b0100
        case .bottomInnerCorners:return leftHand ? 0b0100 : 0b0001
        case .threeFingers,.fourFingers:return nil
        }
    }
    var placementDescription:String {
        switch self {
        case .fourCorners:return "Left pad: top-left + bottom-left. Right pad: top-right + bottom-right. Hold all four outside corners to open Config by default."
        case .innerCorners:return "Left pad: top-right + bottom-right. Right pad: top-left + bottom-left. Hold the four corners facing the gap between the pads."
        case .topOuterCorners:return "Hold one finger at the top-left of the left pad and one at the top-right of the right pad."
        case .topInnerCorners:return "Hold one finger at the top-right of the left pad and one at the top-left of the right pad."
        case .bottomOuterCorners:return "Hold one finger at the bottom-left of the left pad and one at the bottom-right of the right pad."
        case .bottomInnerCorners:return "Hold one finger at the bottom-right of the left pad and one at the bottom-left of the right pad."
        case .threeFingers,.fourFingers:return "Use \(count) fingers on each pad (\(count*2) total). Both hands form one gesture; this does not mirror independent assignments."
        }
    }
    static let recognitionOrder:[Self] = allCases
}
enum TwoHandPhase:String,CaseIterable,Codable,Identifiable,Sendable {
    case tap, hold, force
    var id:String { rawValue }
    var title:String { rawValue.capitalized }
}
struct TwoHandTrigger:Equatable,Sendable {
    var chord:TwoHandChord
    var phase:TwoHandPhase
    var key:String {
        switch (chord,phase) {
        case (.threeFingers,.force):return "threeFingers.force"
        case (.fourFingers,.force):return "fourFingers.force"
        case (_, .force):return "unsupported.force"
        case (.fourCorners,.tap):return "fourCorners.tap"
        case (.fourCorners,.hold):return "fourCorners.hold"
        case (.innerCorners,.tap):return "innerCorners.tap"
        case (.innerCorners,.hold):return "innerCorners.hold"
        case (.topOuterCorners,.tap):return "topOuterCorners.tap"
        case (.topOuterCorners,.hold):return "topOuterCorners.hold"
        case (.topInnerCorners,.tap):return "topInnerCorners.tap"
        case (.topInnerCorners,.hold):return "topInnerCorners.hold"
        case (.bottomOuterCorners,.tap):return "bottomOuterCorners.tap"
        case (.bottomOuterCorners,.hold):return "bottomOuterCorners.hold"
        case (.bottomInnerCorners,.tap):return "bottomInnerCorners.tap"
        case (.bottomInnerCorners,.hold):return "bottomInnerCorners.hold"
        case (.threeFingers,.tap):return "threeFingers.tap"
        case (.threeFingers,.hold):return "threeFingers.hold"
        case (.fourFingers,.tap):return "fourFingers.tap"
        case (.fourFingers,.hold):return "fourFingers.hold"
        }
    }
}
struct TwoHandGestureSettings:Equatable,Codable,Sendable {
    var assignments:[String:GestureAction] = [:]
    var holdThresholds:[String:Double]?
    func holdThreshold(for chord:TwoHandChord) -> Double { GestureHoldTiming.validated(holdThresholds?[chord.rawValue]) }
    mutating func setHoldThreshold(_ seconds:Double,for chord:TwoHandChord) {
        if holdThresholds == nil { holdThresholds = [:] }
        holdThresholds?[chord.rawValue] = GestureHoldTiming.validated(seconds)
    }
    static let allowedActions:[GestureAction] = [.disabled,.openConfig,.primaryClick,.primaryDoubleClick,.secondaryClick]+GestureAction.oneShotActions
    func action(_ trigger:TwoHandTrigger) -> GestureAction {
        guard !trigger.chord.isCorner || trigger.phase == .hold else { return .disabled }
        let value = assignments[trigger.key] ?? (trigger.chord == .fourCorners && trigger.phase == .hold ? .openConfig : .disabled)
        return Self.allowedActions.acceptsGestureAction(value,held:trigger.phase == .hold) ? value : .disabled
    }
    func enabled(_ chord:TwoHandChord) -> Bool {
        action(.init(chord:chord,phase:.tap)) != .disabled || action(.init(chord:chord,phase:.hold)) != .disabled
            || (!chord.isCorner && action(.init(chord:chord,phase:.force)) != .disabled)
    }
    mutating func setAction(_ action:GestureAction,for trigger:TwoHandTrigger) {
        guard trigger.chord.phases.contains(trigger.phase), Self.allowedActions.acceptsGestureAction(action,held:trigger.phase == .hold) else { return }
        assignments[trigger.key] = action
    }
}


extension TwoHandGestureSettings {
    var stenoConfigurationOnly:Self {
        var value = Self()
        value.holdThresholds = holdThresholds
        value.setAction(.openConfig,for:.init(chord:.fourCorners,phase:.hold))
        return value
    }
}


enum TwoHandGestureEligibility {
    static func enabled(pads:GestureSelectedPads,owned:Set<UInt64>,takeover:Bool,armed:Bool) -> Bool {
        guard takeover, armed, let left = pads.left, let right = pads.right, left != right else { return false }
        return owned.contains(left) && owned.contains(right)
    }
}


/// A shortcut has the same catalog identity as Keyboard; lifetime belongs to this assignment.
struct GestureShortcutAssignment:Equatable,Hashable,Codable,Sendable {
    let label:String
    var holdUntilRelease:Bool
    let action:KeyAction?
    private enum CodingKeys:String,CodingKey { case label, holdUntilRelease }
    init(label:String,holdUntilRelease:Bool = false) {
        self.label = label; self.holdUntilRelease = holdUntilRelease
        let resolved = KeyActionCatalog.action(for:label)
        self.action = resolved.flatMap { $0.kind == .key || $0.kind == .appLaunch || $0.kind == .textPaste ? $0 : nil }
    }
    init(from decoder:any Decoder) throws {
        let box = try decoder.container(keyedBy:CodingKeys.self)
        self.init(label:try box.decode(String.self,forKey:.label),
                  holdUntilRelease:try box.decodeIfPresent(Bool.self,forKey:.holdUntilRelease) ?? false)
    }
    func encode(to encoder:any Encoder) throws {
        var box = encoder.container(keyedBy:CodingKeys.self)
        try box.encode(label,forKey:.label); try box.encode(holdUntilRelease,forKey:.holdUntilRelease)
    }
}
extension Array where Element == GestureAction {
    func acceptsGestureAction(_ value:GestureAction,held:Bool = false) -> Bool {
        if let shortcut = value.shortcutAssignment {
            return shortcut.action != nil && (!shortcut.holdUntilRelease || held && shortcut.action?.kind == .key)
        }
        return contains(value)
    }
}
extension GestureTrigger {
    func accepts(_ value:GestureAction) -> Bool {
        (self == .fourCornersTap || self == .thumbTwoMove) ? value == .disabled : allowedActions.acceptsGestureAction(value)
    }
}


extension PerHandGestureSettings {
    /// Editor-only projection. Saved assignments and all 1–3 contact inputs stay intact.
    var layoutContactPreview:Self {
        var value = self
        for trigger in GestureTrigger.allCases {
            let highCount = trigger.forceCount.map { $0 >= 4 } == true
                || trigger.pinchCount.map { $0 >= 4 } == true
                || trigger.rotationCount.map { $0 >= 4 } == true
                || [.fourFingerMove,.fiveFingerMove,.fourFingerTap,.fiveFingerTap,.fourCornersTap].contains(trigger)
            if highCount {
                value.bindings[trigger] = .disabled
                value.directionalMovement?[trigger.rawValue] = nil
            }
        }
        for count in [4,5,Self.cornersHoldKey] { value.setHoldAction(.disabled,count:count) }
        return value
    }
}

extension TwoHandGestureSettings {
    var layoutContactPreview:Self {
        var value = self
        for phase in TwoHandPhase.allCases { value.setAction(.disabled,for:.init(chord:.fourFingers,phase:phase)) }
        return value
    }
}

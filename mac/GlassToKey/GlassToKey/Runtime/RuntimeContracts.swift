import Foundation
import CoreGraphics
import OpenMultitouchSupport
import OpenMultitouchSupportXCF

enum RuntimeIntentMode: String, Sendable {
    case idle
    case keyCandidate
    case typing
    case mouse
    case gesture
}

enum RuntimeDispatchEventKind: Sendable {
    case keyDown(code: CGKeyCode, flags: CGEventFlags)
    case keyUp(code: CGKeyCode, flags: CGEventFlags)
    case haptic(strength: Double, deviceID: String?)
}

struct RuntimeDispatchEvent: Sendable {
    var kind: RuntimeDispatchEventKind
    var timestamp: TimeInterval
}

struct RuntimeRawContact: Sendable {
    var id: Int32
    var posX: Float
    var posY: Float
    var pressure: Float
    var majorAxis: Float
    var minorAxis: Float
    var angle: Float
    var density: Float
    var state: OMSState
}

struct RuntimeRawFrame: Sendable {
    var sequence: UInt64
    var timestamp: TimeInterval
    var deviceNumericID: UInt64
    var deviceIndex: Int
    var contacts: [RuntimeRawContact]
    var rawTouches: [OMSRawTouch]
}

struct RuntimeDiagnosticsCounters: Sendable {
    var captureFrames: UInt64 = 0
    var dispatchQueueDepth: Int = 0
    var dispatchDrops: UInt64 = 0
}

struct RuntimeRenderSnapshot: Sendable {
    var leftTouches: [OMSTouchData] = []
    var rightTouches: [OMSTouchData] = []
    var hasTransitionState: Bool = false
    var highlightedColumn: Int?
    var highlightedKeyStorageID: String?
    var highlightedButtonID: UUID?
    var activeLayer: Int = 0
    var revision: UInt64 = 0
}

struct RuntimeTouchSnapshot: Sendable {
    var left: [OMSTouchData] = []
    var right: [OMSTouchData] = []
    var revision: UInt64 = 0
    var hasTransitionState: Bool = false
}

struct RuntimeStatusSnapshot: Sendable {
    var intentBySide: SidePair<RuntimeIntentMode> = SidePair(left: .idle, right: .idle)
    var contactCountBySide: SidePair<Int> = SidePair(left: 0, right: 0)
    var typingEnabled: Bool = true
    var keyboardModeEnabled: Bool = false
    var diagnostics: RuntimeDiagnosticsCounters = RuntimeDiagnosticsCounters()
}

extension RuntimeRawFrame {
    init(sequence: UInt64, frame: OMSRawTouchFrame) {
        self.sequence = sequence
        self.timestamp = frame.timestamp
        self.deviceNumericID = frame.deviceIDNumeric
        self.deviceIndex = frame.deviceIndex
        self.rawTouches = frame.touches
        self.contacts = frame.touches.compactMap { touch in
            guard let state = Self.mapState(touch.state) else { return nil }
            return RuntimeRawContact(
                id: touch.id,
                posX: touch.posX,
                posY: touch.posY,
                pressure: touch.pressure,
                majorAxis: touch.majorAxis,
                minorAxis: touch.minorAxis,
                angle: touch.angle,
                density: touch.density,
                state: state
            )
        }
    }

    private static func mapState(_ state: OpenMTState) -> OMSState? {
        switch state {
        case .notTouching:
            return .notTouching
        case .starting:
            return .starting
        case .hovering:
            return .hovering
        case .making:
            return .making
        case .touching:
            return .touching
        case .breaking:
            return .breaking
        case .lingering:
            return .lingering
        case .leaving:
            return .leaving
        @unknown default:
            return nil
        }
    }
}

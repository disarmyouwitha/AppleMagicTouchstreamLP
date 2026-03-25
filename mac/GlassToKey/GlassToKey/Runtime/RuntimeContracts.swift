import Foundation
import CoreGraphics

enum RuntimeCaptureDeliveryMode: String, Codable, Sendable {
    case captureOnly
    case liveAndCapture
}

struct RuntimeCaptureIngressSnapshot: Codable, Sendable {
    var deliveryMode: RuntimeCaptureDeliveryMode
    var liveQueueDepth: Int
    var liveDroppedFrames: UInt64
    var dispatchQueueDepth: Int
    var dispatchDropped: UInt64
}

enum RuntimeDispatchEventKind: Sendable {
    case keyStroke(code: CGKeyCode, flags: CGEventFlags, altAscii: UInt8)
    case key(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, altAscii: UInt8)
    case leftClick(clickCount: Int)
    case rightClick
    case middleClick
    case systemKey(String)
    case appLaunch(String)
    case haptic(strength: Double, deviceID: String?)
}

struct RuntimeDispatchEvent: Sendable {
    var kind: RuntimeDispatchEventKind
    var timestamp: TimeInterval
    var uptimeNanoseconds: UInt64
    var sourceSequence: UInt64?
}

enum RuntimeTouchDiagnosticPhase: String, Codable, Sendable {
    case none
    case pending
    case active
    case disqualified
    case released
}

enum RuntimeTouchDecisionOutcome: String, Codable, Sendable {
    case none
    case pending
    case dispatched
    case rejected
}

struct RuntimeTouchTargetSnapshot: Codable, Sendable {
    var label: String
    var side: String?
    var storageKey: String?
    var buttonID: String?
    var actionKind: String
    var holdForceThreshold: Int
    var isContinuousKey: Bool
}

struct RuntimeTouchDiagnostic: Codable, Sendable {
    var id: Int32
    var state: String
    var side: String?
    var x: Double
    var y: Double
    var pressure: Double
    var phase: RuntimeTouchDiagnosticPhase
    var decision: RuntimeTouchDecisionOutcome
    var reason: String?
    var target: RuntimeTouchTargetSnapshot?
    var armed: Bool
    var dwellMilliseconds: Int?
    var maxDistance: Double?
    var forceThresholdSatisfied: Bool
}

struct RuntimeFrameDiagnostic: Codable, Sendable {
    var sequence: UInt64
    var timestamp: TimeInterval
    var deviceIndex: Int
    var activeLayer: Int
    var leftIntent: String
    var rightIntent: String
    var ingress: RuntimeCaptureIngressSnapshot?
    var touches: [RuntimeTouchDiagnostic]
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

extension RuntimeRawFrame {
    init(sequence: UInt64, frame: OMSRawTouchFrame) {
        self.sequence = sequence
        self.timestamp = frame.timestamp
        self.deviceNumericID = frame.deviceIDNumeric
        self.deviceIndex = frame.deviceIndex
        self.rawTouches = Array(frame.touches)
        self.contacts = frame.touches.map { touch in
            return RuntimeRawContact(
                id: touch.id,
                posX: touch.posX,
                posY: touch.posY,
                pressure: touch.pressure,
                majorAxis: touch.majorAxis,
                minorAxis: touch.minorAxis,
                angle: touch.angle,
                density: touch.density,
                state: touch.state
            )
        }
    }
}

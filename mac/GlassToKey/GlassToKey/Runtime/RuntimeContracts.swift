import Foundation
import CoreGraphics
import OpenMultitouchSupport

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

enum RuntimeDispatchEventKind: Codable, Sendable {
    case keyStroke(code: CGKeyCode, flags: CGEventFlags, altAscii: UInt8)
    case key(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, altAscii: UInt8)
    case leftClick(clickCount: Int)
    case rightClick
    case middleClick
    case systemKey(String)
    case appLaunch(String)
    case haptic(strength: Double, deviceID: String?)
}

enum RuntimeDispatchEventStatus: String, Codable, Sendable {
    case accepted
    case posted
    case cancelled
}

struct RuntimeDispatchEvent: Codable, Sendable {
    var commandID: UInt64
    var kind: RuntimeDispatchEventKind
    var status: RuntimeDispatchEventStatus
    var timestamp: TimeInterval
    var uptimeNanoseconds: UInt64
    var sourceSequence: UInt64?
}

struct ProcessedDispatchEvent: Codable, Sendable {
    var event: RuntimeDispatchEvent
    var arrivalTicks: Int64
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

struct RuntimeRawContact: Codable, Sendable {
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

struct RuntimeRawFrame: Codable, Sendable {
    var sequence: UInt64
    var timestamp: TimeInterval
    var deviceNumericID: UInt64
    var deviceIndex: Int
    var contacts: [RuntimeRawContact]
    var rawTouches: [OMSRawTouch]
}

struct RuntimeRenderSnapshot: Codable, Sendable {
    var leftTouches: [OMSTouchData] = []
    var rightTouches: [OMSTouchData] = []
    var hasTransitionState: Bool = false
    var highlightedColumn: Int?
    var highlightedKeyStorageID: String?
    var highlightedButtonID: UUID?
    var activeLayer: Int = 0
    var revision: UInt64 = 0
}

struct RuntimeFrameProcessingResult: Sendable {
    var renderSnapshot: RuntimeRenderSnapshot?
    var processedFrameRecord: ProcessedFrameRecord?
}

struct RuntimeTouchSnapshot: Codable, Sendable {
    var left: [OMSTouchData] = []
    var right: [OMSTouchData] = []
    var revision: UInt64 = 0
    var hasTransitionState: Bool = false
}

struct ProcessedFrameRecord: Codable, Sendable {
    var frame: RuntimeRawFrame
    var arrivalTicks: Int64
    var ingress: RuntimeCaptureIngressSnapshot?
    var diagnostic: RuntimeFrameDiagnostic?
    var dispatchEvents: [ProcessedDispatchEvent] = []

    var sequence: UInt64 {
        frame.sequence
    }
}

extension RuntimeDispatchEventKind {
    private enum CodingKeys: String, CodingKey {
        case type
        case code
        case flagsRawValue
        case keyDown
        case altAscii
        case clickCount
        case label
        case strength
        case deviceID
    }

    private enum Kind: String, Codable {
        case keyStroke
        case key
        case leftClick
        case rightClick
        case middleClick
        case systemKey
        case appLaunch
        case haptic
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .keyStroke:
            self = .keyStroke(
                code: try container.decode(CGKeyCode.self, forKey: .code),
                flags: CGEventFlags(rawValue: try container.decode(UInt64.self, forKey: .flagsRawValue)),
                altAscii: try container.decode(UInt8.self, forKey: .altAscii)
            )
        case .key:
            self = .key(
                code: try container.decode(CGKeyCode.self, forKey: .code),
                flags: CGEventFlags(rawValue: try container.decode(UInt64.self, forKey: .flagsRawValue)),
                keyDown: try container.decode(Bool.self, forKey: .keyDown),
                altAscii: try container.decode(UInt8.self, forKey: .altAscii)
            )
        case .leftClick:
            self = .leftClick(clickCount: try container.decode(Int.self, forKey: .clickCount))
        case .rightClick:
            self = .rightClick
        case .middleClick:
            self = .middleClick
        case .systemKey:
            self = .systemKey(try container.decode(String.self, forKey: .label))
        case .appLaunch:
            self = .appLaunch(try container.decode(String.self, forKey: .label))
        case .haptic:
            self = .haptic(
                strength: try container.decode(Double.self, forKey: .strength),
                deviceID: try container.decodeIfPresent(String.self, forKey: .deviceID)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .keyStroke(code, flags, altAscii):
            try container.encode(Kind.keyStroke, forKey: .type)
            try container.encode(code, forKey: .code)
            try container.encode(flags.rawValue, forKey: .flagsRawValue)
            try container.encode(altAscii, forKey: .altAscii)
        case let .key(code, flags, keyDown, altAscii):
            try container.encode(Kind.key, forKey: .type)
            try container.encode(code, forKey: .code)
            try container.encode(flags.rawValue, forKey: .flagsRawValue)
            try container.encode(keyDown, forKey: .keyDown)
            try container.encode(altAscii, forKey: .altAscii)
        case let .leftClick(clickCount):
            try container.encode(Kind.leftClick, forKey: .type)
            try container.encode(clickCount, forKey: .clickCount)
        case .rightClick:
            try container.encode(Kind.rightClick, forKey: .type)
        case .middleClick:
            try container.encode(Kind.middleClick, forKey: .type)
        case let .systemKey(label):
            try container.encode(Kind.systemKey, forKey: .type)
            try container.encode(label, forKey: .label)
        case let .appLaunch(label):
            try container.encode(Kind.appLaunch, forKey: .type)
            try container.encode(label, forKey: .label)
        case let .haptic(strength, deviceID):
            try container.encode(Kind.haptic, forKey: .type)
            try container.encode(strength, forKey: .strength)
            try container.encodeIfPresent(deviceID, forKey: .deviceID)
        }
    }
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

/*
 OMSTouchData.swift

 Created by Takuto Nakamura on 2024/03/02.
*/

import Foundation
import OpenMultitouchSupportXCF

public struct OMSPosition: Codable, Sendable {
    public var x: Float
    public var y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
}

public struct OMSAxis: Codable, Sendable {
    public var major: Float
    public var minor: Float

    public init(major: Float, minor: Float) {
        self.major = major
        self.minor = minor
    }
}

public enum OMSState: String, Codable, Sendable {
    case notTouching
    case starting
    case hovering
    case making
    case touching
    case breaking
    case lingering
    case leaving

    init?(_ state: OpenMTState) {
        switch state {
        case .notTouching: self = .notTouching
        case .starting:    self = .starting
        case .hovering:    self = .hovering
        case .making:      self = .making
        case .touching:    self = .touching
        case .breaking:    self = .breaking
        case .lingering:   self = .lingering
        case .leaving:     self = .leaving
        @unknown default:  return nil
        }
    }
}

/// Raw device fields. Identity codes and absolute-coordinate units are unverified.
/// A missing telemetry object means the source did not record these fields.
/// Raw nine-byte contact record retained for future decoder corrections.
/// DriverKit velocity/absolute coordinates are derived, not Apple's processed values.
public struct OMSDriverKitTelemetry: Codable, Sendable, Equatable {
    public let contactBytes: [UInt8]
    public let velocityAvailable: Bool
    public init(contactBytes: [UInt8], velocityAvailable: Bool) {
        self.contactBytes = contactBytes; self.velocityAvailable = velocityAvailable
    }
}

public struct OMSTouchTelemetry: Codable, Sendable, Equatable {
    public let fingerID: Int32

    public var fingerName: String {
        switch fingerID {
        case 1: "Thumb"
        case 2: "Index"
        case 3: "Middle"
        case 4: "Ring"
        case 5: "Pinky"
        case 6: "Palm"
        default: "Unknown"
        }
    }
    public let handID: Int32
    public let velocityX: Float
    public let velocityY: Float
    public let absoluteX: Float
    public let absoluteY: Float
    public let absoluteVelocityX: Float
    public let absoluteVelocityY: Float
    public let sourceFrame: Int32
    public let sourceTimestamp: Double
    public let driverKit: OMSDriverKitTelemetry?

    public init(
        fingerID: Int32,
        handID: Int32,
        velocityX: Float,
        velocityY: Float,
        absoluteX: Float,
        absoluteY: Float,
        absoluteVelocityX: Float,
        absoluteVelocityY: Float,
        sourceFrame: Int32,
        sourceTimestamp: Double,
        driverKit: OMSDriverKitTelemetry? = nil
    ) {
        self.fingerID = fingerID
        self.handID = handID
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.absoluteX = absoluteX
        self.absoluteY = absoluteY
        self.absoluteVelocityX = absoluteVelocityX
        self.absoluteVelocityY = absoluteVelocityY
        self.sourceFrame = sourceFrame
        self.sourceTimestamp = sourceTimestamp
        self.driverKit = driverKit
    }
}

public struct OMSTouchData: Codable, CustomStringConvertible, Sendable {
    public var deviceID: String
    public var deviceIndex: Int
    public var id: Int32
    public var position: OMSPosition
    public var total: Float
    public var pressure: Float
    public var axis: OMSAxis
    public var angle: Float
    public var density: Float
    public var state: OMSState
    public var timestamp: TimeInterval
    public var telemetry: OMSTouchTelemetry?
    public var formattedTimestamp: String?

    public init(
        deviceID: String,
        deviceIndex: Int,
        id: Int32,
        position: OMSPosition,
        total: Float,
        pressure: Float,
        axis: OMSAxis,
        angle: Float,
        density: Float,
        state: OMSState,
        timestamp: TimeInterval,
        formattedTimestamp: String? = nil,
        telemetry: OMSTouchTelemetry? = nil
    ) {
        self.deviceID = deviceID
        self.deviceIndex = deviceIndex
        self.id = id
        self.position = position
        self.total = total
        self.pressure = pressure
        self.axis = axis
        self.angle = angle
        self.density = density
        self.state = state
        self.timestamp = timestamp
        self.formattedTimestamp = formattedTimestamp
        self.telemetry = telemetry
    }

    public var description: String {
        var text = "deviceID:\(deviceID), "
        text += "deviceIndex:\(deviceIndex), "
        text += String(format: "id:%2d, ", id)
        text += String(format: "pos:(%05.3f,%05.3f), ", position.x, position.y)
        text += String(format: "total:%05.3f, ", total)
        text += String(format: "pressure:%05.3f, ", pressure)
        text += String(format: "axis(%05.3f,%05.3f), ", axis.major, axis.minor)
        text += String(format: "angle:%05.3f, ", angle)
        text += String(format: "density:%05.3f, ", density)
        text += "\(state.rawValue)"
        if let formattedTimestamp {
            text += ", \(formattedTimestamp)"
        } else {
            text += String(format: ", %.6f", timestamp)
        }
        return text
    }
}

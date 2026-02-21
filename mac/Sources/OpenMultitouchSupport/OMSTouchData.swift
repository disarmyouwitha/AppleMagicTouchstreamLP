/*
 OMSTouchData.swift

 Created by Takuto Nakamura on 2024/03/02.
*/

import Foundation
import OpenMultitouchSupportXCF

public struct OMSPosition: Sendable {
    public var x: Float
    public var y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
}

public struct OMSAxis: Sendable {
    public var major: Float
    public var minor: Float

    public init(major: Float, minor: Float) {
        self.major = major
        self.minor = minor
    }
}

public enum OMSState: String, Sendable {
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

public struct OMSTouchData: CustomStringConvertible, Sendable {
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
        formattedTimestamp: String? = nil
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

/*
 OMSTouchData.swift

 Created by Takuto Nakamura on 2024/03/02.
*/

import Foundation
import OpenMultitouchSupportXCF

struct OMSPosition: Sendable {
    var x: Float
    var y: Float

    init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
}

struct OMSAxis: Sendable {
    var major: Float
    var minor: Float

    init(major: Float, minor: Float) {
        self.major = major
        self.minor = minor
    }
}

enum OMSState: String, Sendable {
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
        case .starting: self = .starting
        case .hovering: self = .hovering
        case .making: self = .making
        case .touching: self = .touching
        case .breaking: self = .breaking
        case .lingering: self = .lingering
        case .leaving: self = .leaving
        @unknown default: return nil
        }
    }
}

struct OMSTouchData: CustomStringConvertible, Sendable {
    var deviceID: String
    var deviceIndex: Int
    var id: Int32
    var position: OMSPosition
    var total: Float
    var pressure: Float
    var axis: OMSAxis
    var angle: Float
    var density: Float
    var state: OMSState
    var timestamp: TimeInterval
    var formattedTimestamp: String?

    init(
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

    var description: String {
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

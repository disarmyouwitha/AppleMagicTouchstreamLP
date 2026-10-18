import Foundation
import OpenMultitouchSupport

/// Live decoded input boundary. Applications can consume these frames without
/// enabling the playground's optional synthetic pointer/button interpretation.
struct TrackpadContactFrame: Sendable {
    let deviceID: UInt64
    let deviceIndex: Int
    let timestamp: Double
    let sourceTimestamp: Double
    let contacts: [OMSRawTouch]
    let buttons: UInt8
}

@MainActor
protocol TrackpadFrameOutput: AnyObject {
    var postedPointerEvents: UInt64 { get }
    func configure(devices: Set<UInt64>, pointerEnabled: Bool, clickEnabled: Bool) -> Bool
    func process(_ frame: TrackpadContactFrame)
    func reset(device: UInt64)
    func releaseButtons()
    func stop()
}


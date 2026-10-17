import Foundation

/// Compatibility boundary for capture/replay. GesturePad has no action output
/// implementation: no native events, app launches, dictation, or haptics.
final class PassiveOutputBoundary: @unchecked Sendable {
    struct Metrics: Sendable {
        var queueDepth: Int = 0
        var drops: UInt64 = 0
    }
    static let shared = PassiveOutputBoundary()
    init() {}
    init(recordingWith scheduler: any TouchEngineScheduler,
         sink: @escaping (RuntimeDispatchEvent) -> Void) {}
    func snapshotMetrics() -> Metrics { Metrics() }
    func clearQueue() {}
    func setRecordedEventHandler(_ handler: ((RuntimeDispatchEvent) -> Void)?) {}
}

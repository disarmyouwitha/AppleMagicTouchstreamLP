import Foundation

protocol EngineActorBoundary: Sendable {
    func ingest(_ frame: RuntimeRawFrame) async
    func renderSnapshot() async -> RuntimeRenderSnapshot
    func statusSnapshot() async -> RuntimeStatusSnapshot
}

actor EngineActorStub: EngineActorBoundary {
    private var latestRender = RuntimeRenderSnapshot()
    private var latestStatus = RuntimeStatusSnapshot()

    func ingest(_ frame: RuntimeRawFrame) async {
        let contactCount = frame.contacts.count
        latestRender.revision &+= 1

        if frame.deviceIndex == 0 {
            latestStatus.contactCountBySide.left = contactCount
        } else {
            latestStatus.contactCountBySide.right = contactCount
        }
        latestStatus.diagnostics.captureFrames &+= 1
    }

    func renderSnapshot() async -> RuntimeRenderSnapshot {
        latestRender
    }

    func statusSnapshot() async -> RuntimeStatusSnapshot {
        latestStatus
    }
}

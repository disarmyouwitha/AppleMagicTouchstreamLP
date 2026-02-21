import Foundation

protocol EngineActorBoundary: Sendable {
    func ingest(_ frame: RuntimeRawFrame) async
    func renderSnapshot() async -> RuntimeRenderSnapshot
    func statusSnapshot() async -> RuntimeStatusSnapshot
}

actor EngineActorPhase2: EngineActorBoundary {
    private var latestRender = RuntimeRenderSnapshot()
    private var latestStatus = RuntimeStatusSnapshot()

    func ingest(_ frame: RuntimeRawFrame) async {
        let contactCount = frame.contacts.count
        if frame.deviceIndex == 0 {
            latestStatus.contactCountBySide.left = contactCount
            latestStatus.intentBySide.left = Self.intent(for: contactCount)
        } else {
            latestStatus.contactCountBySide.right = contactCount
            latestStatus.intentBySide.right = Self.intent(for: contactCount)
        }
        latestStatus.diagnostics.captureFrames &+= 1
        latestRender.revision &+= 1
    }

    func renderSnapshot() async -> RuntimeRenderSnapshot {
        latestRender
    }

    func statusSnapshot() async -> RuntimeStatusSnapshot {
        latestStatus
    }

    private static func intent(for contactCount: Int) -> RuntimeIntentMode {
        switch contactCount {
        case ...0:
            return .idle
        case 1:
            return .keyCandidate
        default:
            return .typing
        }
    }
}

actor EngineActorStub: EngineActorBoundary {
    private let impl = EngineActorPhase2()

    func ingest(_ frame: RuntimeRawFrame) async {
        await impl.ingest(frame)
    }

    func renderSnapshot() async -> RuntimeRenderSnapshot {
        await impl.renderSnapshot()
    }

    func statusSnapshot() async -> RuntimeStatusSnapshot {
        await impl.statusSnapshot()
    }
}

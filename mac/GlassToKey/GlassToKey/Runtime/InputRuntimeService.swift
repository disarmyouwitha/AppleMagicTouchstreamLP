import Foundation
import OpenMultitouchSupport
import os

final class InputRuntimeService: @unchecked Sendable {
    struct Metrics: Sendable {
        var ingestedFrames: UInt64 = 0
        var emittedFrames: UInt64 = 0
        var releasedWithoutConsumers: UInt64 = 0
    }

    private struct ContinuationStore {
        var byID: [UUID: AsyncStream<RuntimeRawFrame>.Continuation] = [:]
        var list: [AsyncStream<RuntimeRawFrame>.Continuation] = []
    }

    private struct State {
        var task: Task<Void, Never>?
        var isRunning = false
        var sequence: UInt64 = 0
        var metrics = Metrics()
    }

    private let manager: OMSManager
    private let continuationLock = OSAllocatedUnfairLock<ContinuationStore>(
        uncheckedState: ContinuationStore()
    )
    private let stateLock = OSAllocatedUnfairLock<State>(uncheckedState: State())

    init(manager: OMSManager = .shared) {
        self.manager = manager
    }

    deinit {
        stop()
    }

    var rawFrameStream: AsyncStream<RuntimeRawFrame> {
        AsyncStream(bufferingPolicy: .bufferingNewest(2)) { continuation in
            let id = UUID()
            continuationLock.withLockUnchecked { store in
                store.byID[id] = continuation
                store.list = Array(store.byID.values)
            }
            continuation.onTermination = { [continuationLock] _ in
                continuationLock.withLockUnchecked { store in
                    store.byID.removeValue(forKey: id)
                    store.list = Array(store.byID.values)
                }
            }
        }
    }

    @discardableResult
    func start() -> Bool {
        let shouldStart = stateLock.withLockUnchecked { state in
            guard !state.isRunning else { return false }
            state.isRunning = true
            return true
        }
        guard shouldStart else { return false }

        guard manager.startListening() else {
            stateLock.withLockUnchecked { state in
                state.isRunning = false
            }
            return false
        }

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.ingestLoop()
        }
        stateLock.withLockUnchecked { state in
            state.task = task
        }
        return true
    }

    @discardableResult
    func stop() -> Bool {
        let wasRunning = stateLock.withLockUnchecked { state -> Bool in
            guard state.isRunning else { return false }
            state.isRunning = false
            state.task?.cancel()
            state.task = nil
            return true
        }
        guard wasRunning else { return false }
        _ = manager.stopListening()
        return true
    }

    func snapshotMetrics() -> Metrics {
        stateLock.withLockUnchecked { $0.metrics }
    }

    private func ingestLoop() async {
        for await frame in manager.rawTouchStream {
            if Task.isCancelled {
                frame.release()
                return
            }
            let sequence = stateLock.withLockUnchecked { state in
                state.sequence &+= 1
                state.metrics.ingestedFrames &+= 1
                return state.sequence
            }
            let runtimeFrame = RuntimeRawFrame(sequence: sequence, frame: frame)
            emit(runtimeFrame)
            frame.release()
        }
    }

    private func emit(_ frame: RuntimeRawFrame) {
        let continuations = continuationLock.withLockUnchecked { $0.list }
        if continuations.isEmpty {
            stateLock.withLockUnchecked { state in
                state.metrics.releasedWithoutConsumers &+= 1
            }
            return
        }

        for continuation in continuations {
            continuation.yield(frame)
        }
        stateLock.withLockUnchecked { state in
            state.metrics.emittedFrames &+= 1
        }
    }
}

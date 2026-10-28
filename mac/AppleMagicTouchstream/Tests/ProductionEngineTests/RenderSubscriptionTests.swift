import Foundation
import XCTest
@testable import GlassToKeyRuntime

final class RenderSubscriptionTests: XCTestCase, @unchecked Sendable {
    func testVisualizerCanSubscribeAgainAfterRepeatedDetach() async {
        let service = RuntimeRenderSnapshotService()
        for revision in UInt64(1)...3 {
            let updates = service.revisionUpdates
            let received = expectation(description:"Fresh visualizer receives revision \(revision)")
            let consumer = Task {
                for await value in updates where value == revision { received.fulfill() }
            }
            service.submit(RuntimeRenderSnapshot(revision:revision))
            await fulfillment(of:[received],timeout:1)
            consumer.cancel()
            await consumer.value
        }
    }

    func testCancelingOldVisualizerDoesNotStopNewVisualizer() async {
        let service = RuntimeRenderSnapshotService()
        let oldUpdates = service.revisionUpdates
        let newUpdates = service.revisionUpdates
        let oldReceived = expectation(description:"Old visualizer receives first frame")
        let newReceived = expectation(description:"New visualizer receives first frame")
        let newContinues = expectation(description:"New visualizer survives old cancellation")
        let oldConsumer = Task {
            for await value in oldUpdates where value == 1 { oldReceived.fulfill() }
        }
        let newConsumer = Task {
            for await value in newUpdates {
                if value == 1 { newReceived.fulfill() }
                if value == 2 { newContinues.fulfill() }
            }
        }
        defer { oldConsumer.cancel(); newConsumer.cancel() }
        service.submit(RuntimeRenderSnapshot(revision:1))
        await fulfillment(of:[oldReceived,newReceived],timeout:1)
        oldConsumer.cancel()
        await oldConsumer.value
        service.submit(RuntimeRenderSnapshot(revision:2))
        await fulfillment(of:[newContinues],timeout:1)
    }
}

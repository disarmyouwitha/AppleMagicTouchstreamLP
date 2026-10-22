import Foundation
import XCTest
@testable import GlassToKeyRuntime

@MainActor
private final class FakeNativeTakeover: NativeTakeoverBackend {
    var owned: Set<UInt64> = []
    var refuseStart = false
    var refuseRelease = false
    var starts: [[UInt64]] = []
    var endCount = 0
    var events: [String] = []
    func update(deviceIDs: [UInt64]) -> Bool {
        events.append("native-update")
        starts.append(deviceIDs)
        guard !refuseStart else { return false }
        owned = Set(deviceIDs)
        return true
    }
    func end() {
        events.append("native-end")
        endCount += 1
        if !refuseRelease { owned = [] }
    }
    var status: [String: Any] {
        ["active": !owned.isEmpty, "deviceIDs": owned.map { NSNumber(value: $0) },
         "message": owned.isEmpty ? "Off" : "Active"]
    }
}

@MainActor
final class NativeTrackpadTakeoverTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "AMT.TakeoverTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return defaults
    }

    func testDefaultOffAndSavedOptInRestoresWithoutOpeningHardwareInInit() async {
        let backend = FakeNativeTakeover(), storage = defaults()
        let control = NativeTrackpadTakeover(backend: backend, defaults: storage)
        XCTAssertFalse(control.enabled)
        await control.updateSelection(deviceIDs: [42, 7, 42])
        XCTAssertTrue(backend.starts.isEmpty)
        await control.setEnabled(true)
        XCTAssertEqual(backend.starts, [[7, 42]])
        let restored = NativeTrackpadTakeover(backend: FakeNativeTakeover(), defaults: storage)
        XCTAssertTrue(restored.enabled)
        XCTAssertFalse(restored.isActive)
        _ = await control.suspend("termination")
        XCTAssertTrue(storage.bool(forKey: NativeTrackpadTakeover.defaultsKey))
    }

    func testSelectionUpdatesWhileOwnedAndNoneReleasesWithoutOptingOut() async {
        let backend = FakeNativeTakeover()
        let control = NativeTrackpadTakeover(backend: backend, defaults: defaults())
        await control.updateSelection(deviceIDs: [7])
        await control.setEnabled(true)
        let changed = await control.updateSelection(deviceIDs: [99, 7, 99])
        XCTAssertTrue(changed)
        XCTAssertEqual(backend.starts, [[7], [7, 99]])
        let cleared = await control.updateSelection(deviceIDs: [])
        XCTAssertTrue(cleared)
        XCTAssertTrue(control.enabled)
        XCTAssertFalse(control.hasOwnership)
    }

    func testTransitionFlushesKeyboardCommitsSelectionThenResumes() async {
        let backend = FakeNativeTakeover()
        let control = NativeTrackpadTakeover(backend: backend, defaults: defaults())
        await control.updateSelection(deviceIDs: [7])
        await control.setEnabled(true)
        backend.events = []
        control.beforeRelease = {
            XCTAssertTrue(control.hasOwnership)
            backend.events.append("output-reset")
        }
        control.afterRelease = {
            XCTAssertTrue(control.hasOwnership)
            backend.events.append("output-resume")
        }
        control.onOwnershipChanged = { backend.events.append($0 ? "lock" : "unlock") }
        await control.updateSelection(deviceIDs: [8]) { backend.events.append("commit") }
        XCTAssertEqual(backend.events, ["lock", "output-reset", "native-update", "commit", "output-resume", "lock"])
        backend.events = []
        await control.release()
        XCTAssertEqual(backend.events, ["lock", "output-reset", "native-end", "output-resume", "unlock"])
        XCTAssertFalse(control.enabled)
        XCTAssertFalse(control.hasOwnership)
    }

    func testFailedSelectionDoesNotCommitOrDiscardOldOwnership() async {
        let backend = FakeNativeTakeover()
        let control = NativeTrackpadTakeover(backend: backend, defaults: defaults())
        await control.updateSelection(deviceIDs: [7])
        await control.setEnabled(true)
        backend.refuseStart = true
        var committed = false
        let success = await control.updateSelection(deviceIDs: [8]) { committed = true }
        XCTAssertFalse(success)
        XCTAssertFalse(committed)
        XCTAssertEqual(backend.owned, [7])
        backend.refuseStart = false
        await control.updateSelection(deviceIDs: [8]) { committed = true }
        XCTAssertTrue(committed)
        await control.release()
    }

    func testConcurrentReleaseWaitsForOneSharedCleanup() async {
        let backend = FakeNativeTakeover()
        let control = NativeTrackpadTakeover(backend: backend, defaults: defaults())
        await control.updateSelection(deviceIDs: [7])
        await control.setEnabled(true)
        control.beforeRelease = { await Task.yield() }
        async let first: Void = control.release()
        async let second: Void = control.release()
        _ = await (first, second)
        XCTAssertEqual(backend.endCount, 1)
        XCTAssertFalse(control.hasOwnership)
    }

    func testFailedReleaseRetainsOwnershipAndAllowsRetry() async {
        let backend = FakeNativeTakeover()
        let control = NativeTrackpadTakeover(backend: backend, defaults: defaults())
        await control.updateSelection(deviceIDs: [7])
        await control.setEnabled(true)
        backend.refuseRelease = true
        await control.release()
        XCTAssertTrue(control.isActive)
        XCTAssertFalse(control.enabled)
        XCTAssertFalse(control.isReleasing)
        backend.refuseRelease = false
        await control.release()
        XCTAssertFalse(control.hasOwnership)
        XCTAssertEqual(backend.endCount, 2)
    }

    func testCancelledQueuedSelectionCannotReacquireAfterEmergencyRelease() async {
        let backend = FakeNativeTakeover()
        let control = NativeTrackpadTakeover(backend: backend, defaults: defaults())
        await control.updateSelection(deviceIDs: [7])
        await control.setEnabled(true)
        var barrier: CheckedContinuation<Void, Never>?
        control.beforeRelease = {
            // Pause only the first transition; subsequent cleanup can complete.
            control.beforeRelease = nil
            await withCheckedContinuation { barrier = $0 }
        }
        let first = Task { await control.updateSelection(deviceIDs: [8]) }
        while barrier == nil { await Task.yield() }
        let queued = Task { await control.updateSelection(deviceIDs: [9]) }
        await Task.yield()
        queued.cancel()
        let release = Task { await control.release() }
        await Task.yield()
        barrier?.resume()
        _ = await first.value
        let queuedResult = await queued.value
        await release.value
        XCTAssertFalse(queuedResult)
        XCTAssertEqual(backend.starts, [[7], [8]])
        XCTAssertFalse(control.enabled)
        XCTAssertTrue(backend.owned.isEmpty)
    }

    func testNestedLifecycleSuspensionsKeepPreferenceAndRespectEmergencyRelease() async {
        let backend = FakeNativeTakeover(), storage = defaults()
        let control = NativeTrackpadTakeover(backend: backend, defaults: storage)
        await control.updateSelection(deviceIDs: [7])
        await control.setEnabled(true)
        _ = await control.suspend("sleep")
        _ = await control.suspend("replay")
        await control.updateSelection(deviceIDs: [8])
        await control.resume("sleep")
        XCTAssertFalse(control.isActive)
        await control.resume("replay")
        XCTAssertEqual(backend.owned, [8])
        _ = await control.suspend("sleep")
        await control.release()
        await control.resume("sleep")
        XCTAssertFalse(control.isActive)
        XCTAssertFalse(storage.bool(forKey: NativeTrackpadTakeover.defaultsKey))
    }

}

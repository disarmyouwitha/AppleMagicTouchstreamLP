import Foundation
import XCTest
@testable import GlassToKeyRuntime

@MainActor
private final class FakeNativeTakeover: NativeTakeoverBackend {
    var active = false
    var refuseStart = false
    var refuseRelease = false
    var starts: [[UInt64]] = []
    var endCount = 0
    var events: [String] = []
    func begin(deviceIDs: [UInt64]) -> Bool {
        starts.append(deviceIDs)
        active = !refuseStart && !deviceIDs.isEmpty
        return active
    }
    func end() {
        events.append("native-end")
        endCount += 1
        if !refuseRelease { active = false }
    }
    var status: [String: Any] { ["active": active, "message": active ? "Active" : "Off"] }
}

@MainActor
final class NativeTrackpadTakeoverTests: XCTestCase {
    func testExactSelectionsDeduplicateAndCannotRetakeWhileOwned() async {
        let backend = FakeNativeTakeover()
        let control = NativeTrackpadTakeover(backend: backend)
        control.start(deviceIDs: [42, 7, 42])
        XCTAssertEqual(backend.starts, [[7, 42]])
        XCTAssertTrue(control.hasOwnership)
        control.start(deviceIDs: [99])
        XCTAssertEqual(backend.starts.count, 1)
        await control.release()
    }

    func testReleaseFlushesKeyboardBeforeNativeEndAndResumesBeforeUnlock() async {
        let backend = FakeNativeTakeover()
        let control = NativeTrackpadTakeover(backend: backend)
        control.beforeRelease = {
            XCTAssertTrue(control.hasOwnership)
            backend.events.append("output-reset")
        }
        control.afterRelease = {
            XCTAssertTrue(control.hasOwnership) // Keep Refresh/selection locked during reset.
            backend.events.append("output-resume")
        }
        control.onOwnershipChanged = { owned in backend.events.append(owned ? "lock" : "unlock") }
        control.start(deviceIDs: [7])
        await control.release()
        XCTAssertEqual(backend.events, ["lock", "output-reset", "native-end", "output-resume", "unlock"])
        XCTAssertFalse(control.hasOwnership)
        await control.release()
        XCTAssertEqual(backend.endCount, 1)
    }

    func testConcurrentReleaseWaitsForOneSharedCleanup() async {
        let backend = FakeNativeTakeover()
        let control = NativeTrackpadTakeover(backend: backend)
        control.beforeRelease = { await Task.yield() }
        control.start(deviceIDs: [7])
        async let first: Void = control.release()
        async let second: Void = control.release()
        _ = await (first, second)
        XCTAssertEqual(backend.endCount, 1)
        XCTAssertFalse(control.hasOwnership)
    }

    func testFailedReleaseRetainsOwnershipAndAllowsRetry() async {
        let backend = FakeNativeTakeover()
        let control = NativeTrackpadTakeover(backend: backend)
        control.start(deviceIDs: [7])
        backend.refuseRelease = true
        await control.release()
        XCTAssertTrue(control.isActive)
        XCTAssertFalse(control.isReleasing)
        control.start(deviceIDs: [8])
        XCTAssertEqual(backend.starts.count, 1)
        backend.refuseRelease = false
        await control.release()
        XCTAssertFalse(control.hasOwnership)
        XCTAssertEqual(backend.endCount, 2)
    }

    func testRejectedStartDoesNotRetainOwnership() {
        let backend = FakeNativeTakeover()
        let control = NativeTrackpadTakeover(backend: backend)
        backend.refuseStart = true
        control.start(deviceIDs: [7])
        XCTAssertFalse(control.hasOwnership)
        XCTAssertEqual(control.status, "Off")
        XCTAssertEqual(backend.endCount, 0)
    }
}

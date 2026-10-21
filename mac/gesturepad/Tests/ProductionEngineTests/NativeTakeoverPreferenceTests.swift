import Foundation
import XCTest
@testable import GesturePadRuntime

@MainActor
final class NativeTakeoverPreferenceTests: XCTestCase {
    private final class Backend {
        var owned: Set<UInt64> = []
        var calls: [String] = []
        var failStart = false
        var failRelease = false
        func transition(_ ids: [UInt64]) -> Bool {
            calls.append("transition:\(ids)")
            if failStart || (failRelease && !owned.isSubset(of: Set(ids))) { return false }
            owned = Set(ids)
            return true
        }
        func stop() {
            calls.append("stop")
            if !failRelease { owned = [] }
        }
    }

    private func make(_ backend: Backend, defaults: UserDefaults) -> NativeTakeoverPreference {
        NativeTakeoverPreference(defaults: defaults, ownedIDs: { backend.owned },
            transition: { backend.transition($0) }, stop: { backend.stop() })
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "GesturePadTakeoverTests.\(UUID().uuidString)")!
    }

    func testDefaultOffAndOptInRestoresOnlyAfterSelectionIsReady() {
        let defaults = isolatedDefaults()
        let backend = Backend()
        let first = make(backend, defaults: defaults)
        first.updateSelection([7])
        XCTAssertFalse(first.enabled)
        XCTAssertTrue(backend.calls.isEmpty)
        first.setEnabled(true)
        XCTAssertEqual(backend.owned, [7])
        backend.stop() // process exit releases but does not erase preference
        backend.calls = []
        let next = make(backend, defaults: defaults)
        XCTAssertTrue(next.enabled)
        XCTAssertTrue(backend.calls.isEmpty)
        next.updateSelection([7])
        XCTAssertEqual(backend.calls, ["transition:[7]"])
    }

    func testSelectionSwitchReleasesOldSetAndDeduplicatesNewSet() {
        let backend = Backend()
        let preference = make(backend, defaults: isolatedDefaults())
        preference.updateSelection([1, 1])
        preference.setEnabled(true)
        preference.updateSelection([2, 3, 2])
        preference.updateSelection([3, 2])
        XCTAssertEqual(backend.calls, ["transition:[1]", "transition:[2, 3]"])
        preference.updateSelection([])
        XCTAssertTrue(backend.owned.isEmpty)
        XCTAssertTrue(preference.enabled)
    }

    func testRefreshReleasesBeforeDeviceMutationAndThenResumes() {
        let backend = Backend()
        let preference = make(backend, defaults: isolatedDefaults())
        preference.updateSelection([1])
        preference.setEnabled(true)
        XCTAssertTrue(preference.suspend("selection"))
        XCTAssertTrue(backend.owned.isEmpty) // native device list can now change
        preference.updateSelection([2])
        XCTAssertTrue(backend.owned.isEmpty)
        preference.resume("selection")
        XCTAssertEqual(backend.owned, [2])
    }

    func testSleepAndReplayOverlapUntilBothResume() {
        let backend = Backend()
        let preference = make(backend, defaults: isolatedDefaults())
        preference.updateSelection([1])
        preference.setEnabled(true)
        preference.suspend("sleep")
        preference.suspend("replay")
        preference.resume("sleep")
        XCTAssertTrue(backend.owned.isEmpty)
        preference.resume("replay")
        XCTAssertEqual(backend.owned, [1])
        XCTAssertTrue(preference.enabled)
    }

    func testEmergencyReleaseDuringSuspensionPersistsOffAndCannotRecapture() {
        let defaults = isolatedDefaults()
        let backend = Backend()
        let preference = make(backend, defaults: defaults)
        preference.updateSelection([1])
        preference.setEnabled(true)
        preference.suspend("sleep")
        preference.setEnabled(false)
        preference.resume("sleep")
        preference.updateSelection([2])
        XCTAssertTrue(backend.owned.isEmpty)
        XCTAssertFalse(make(backend, defaults: defaults).enabled)
    }

    func testFailedReleaseRetainsOwnershipAndPreventsNewStart() {
        let backend = Backend()
        let preference = make(backend, defaults: isolatedDefaults())
        preference.updateSelection([1])
        preference.setEnabled(true)
        backend.failRelease = true
        XCTAssertFalse(preference.updateSelection([2]))
        XCTAssertEqual(backend.owned, [1])
        XCTAssertTrue(preference.updateSelection([1]))
        backend.failRelease = false
        preference.setEnabled(false)
        XCTAssertTrue(backend.owned.isEmpty)
    }

    func testFailedStartDoesNotLoopAndExplicitRetryWorks() {
        let backend = Backend()
        let preference = make(backend, defaults: isolatedDefaults())
        backend.failStart = true
        preference.updateSelection([1])
        preference.setEnabled(true)
        preference.updateSelection([1])
        XCTAssertEqual(backend.calls, ["transition:[1]"])
        backend.failStart = false
        preference.setEnabled(true)
        XCTAssertEqual(backend.owned, [1])
    }
}

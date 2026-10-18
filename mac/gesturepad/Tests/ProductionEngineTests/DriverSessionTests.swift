import Foundation
import XCTest
@testable import GesturePadRuntime

final class DriverSessionTests: XCTestCase {
    func testRestartLeaseKeepsSessionDuringGapThenTransfersOnce() {
        let now = Date(timeIntervalSince1970: 100)
        let nonce = UUID().uuidString
        var lease = DriverOwnerLease(ownerPID: 10)
        XCTAssertTrue(lease.prepare(pid: 10, nonce: nonce, now: now))
        XCTAssertFalse(lease.shouldRelease(ownerAlive: false, now: now.addingTimeInterval(10)))
        XCTAssertTrue(lease.claim(pid: 11, nonce: nonce, now: now.addingTimeInterval(11)))
        XCTAssertEqual(lease.ownerPID, 11)
        XCTAssertFalse(lease.claim(pid: 12, nonce: nonce, now: now.addingTimeInterval(12)), "Transfer is single use")
        XCTAssertFalse(lease.shouldRelease(ownerAlive: true, now: now.addingTimeInterval(30)))
        XCTAssertTrue(lease.shouldRelease(ownerAlive: false, now: now.addingTimeInterval(30)), "New owner crash must release")
    }
    func testFailedRestartCannotLeavePadsCapturedForever() {
        let now = Date(timeIntervalSince1970: 100)
        var lease = DriverOwnerLease(ownerPID: 10)
        XCTAssertTrue(lease.prepare(pid: 10, nonce: UUID().uuidString, now: now))
        XCTAssertTrue(lease.shouldRelease(ownerAlive: false, now: now.addingTimeInterval(21)))
        XCTAssertFalse(lease.shouldRelease(ownerAlive: true, now: now.addingTimeInterval(21)), "Failed launch leaves living original owner in control")
    }
    func testWrongOwnerNonceExpiredOrCancelledClaimIsRejected() {
        let now = Date(timeIntervalSince1970: 100), nonce = UUID().uuidString
        var lease = DriverOwnerLease(ownerPID: 10)
        XCTAssertFalse(lease.prepare(pid: 11, nonce: nonce, now: now))
        XCTAssertTrue(lease.prepare(pid: 10, nonce: nonce, now: now))
        XCTAssertFalse(lease.claim(pid: 11, nonce: UUID().uuidString, now: now))
        XCTAssertFalse(lease.claim(pid: 10, nonce: nonce, now: now))
        XCTAssertFalse(lease.claim(pid: 11, nonce: nonce, now: now.addingTimeInterval(20)))
        lease.cancel(pid: 10, nonce: nonce)
        XCTAssertFalse(lease.claim(pid: 11, nonce: nonce, now: now))
        XCTAssertTrue(lease.shouldRelease(ownerAlive: false, now: now))
    }
    func testSnapshotRequiresExactSessionAndFreshTransferIncludingZeroPads() throws {
        let now = Date(), session = UUID().uuidString, nonce = UUID().uuidString
        let snapshot = DriverRestartSnapshot(session: session, nonce: nonce, helperPID: 10, ownerPID: 11,
            expiresAt: now.addingTimeInterval(10), devices: [], synthesize: false)
        let decoded = try JSONDecoder().decode(DriverRestartSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertTrue(decoded.isValid(session: session, nonce: nonce, now: now))
        XCTAssertFalse(decoded.isValid(session: session, nonce: UUID().uuidString, now: now))
        XCTAssertFalse(decoded.isValid(session: UUID().uuidString, nonce: nonce, now: now))
        XCTAssertFalse(decoded.isValid(session: session, nonce: nonce, now: now.addingTimeInterval(11)))
    }
    func testRestartRetainsUnselectedInventoryWhenNoRoutesSelected() throws {
        let pad = DriverSessionDevice(serial: "arbitrary-pad", transport: "Bluetooth", id: 42,
            index: 1, registryID: 99, name: "Magic Trackpad")
        let snapshot = DriverRestartSnapshot(session: UUID().uuidString, nonce: UUID().uuidString,
            helperPID: 10, ownerPID: 11, expiresAt: Date().addingTimeInterval(10),
            devices: [], synthesize: false, inventory: [pad])
        let decoded = try JSONDecoder().decode(DriverRestartSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertTrue(decoded.devices.isEmpty)
        XCTAssertEqual(decoded.inventory, [pad], "Unselected captured pad must remain selectable after Restart")
    }

}

import XCTest
@testable import GlassToKeyRuntime

final class HIDBlackholeIdentityTests: XCTestCase {
    private func device(id: UInt64 = 1, serial: String = "D0:C0:50:D5:69:55", location: Int = 1,
                        transport: String = "Bluetooth", page: Int = 1, usage: Int = 2,
                        product: String = "Magic Trackpad") -> HIDBlackholeIdentity {
        HIDBlackholeIdentity(registryID: id, product: product, vendor: 76, productID: 804,
            transport: transport, serial: serial, location: location, usagePage: page, usage: usage)
    }

    func testRelatedMouseAndVendorInterfacesGroupTogether() {
        let mouse = device()
        let vendor = device(id: 2, page: 0xff00, usage: 18, product: "Vendor Collection")
        XCTAssertEqual(mouse.groupID, vendor.groupID)
        XCTAssertTrue(mouse.isTrackpad)
        XCTAssertFalse(vendor.isTrackpad)
    }

    func testTwoIdenticalTrackpadsAreNotMerged() {
        XCTAssertNotEqual(device().groupID, device(id: 2, serial: "D0:C0:50:D4:75:6C").groupID)
    }

    func testIdentityNormalizesSerialFormattingAndKeepsTransportsSeparate() {
        XCTAssertEqual(device().groupID, device(serial: "d0-c0-50-d5-69-55", transport: "bluetooth").groupID)
        XCTAssertNotEqual(device().groupID, device(transport: "USB").groupID)
    }

    func testZeroSerialFallsBackToLocationAndUnknownDevicesStaySeparate() {
        XCTAssertEqual(device(id: 1, serial: "000000000000", location: 12).groupID,
                       device(id: 2, serial: "", location: 12).groupID)
        XCTAssertNotEqual(device(id: 1, serial: "", location: 0).groupID,
                          device(id: 2, serial: "", location: 0).groupID)
    }

    func testKeyboardCollectionIsExcludedFromSeizeEligibility() {
        XCTAssertTrue(device(page: 1, usage: 6).isKeyboard)
        XCTAssertFalse(device(page: 1, usage: 2).isKeyboard)
    }
}

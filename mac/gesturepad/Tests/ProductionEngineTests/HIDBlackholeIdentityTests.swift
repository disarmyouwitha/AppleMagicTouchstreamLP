import XCTest
@testable import GesturePadRuntime

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
    func testOMSServiceMapsThroughItsHIDAncestorToAllSiblingInterfaces() {
        let mouse = device(id: 10)
        let vendor = device(id: 11, page: 0xff00, usage: 18)
        let group = HIDBlackholeExperiment.Group(id: mouse.groupID, label: mouse.label, interfaces: [mouse, vendor])
        XCTAssertEqual(HIDBlackholeExperiment.matchingGroupID(registryPath: [30, 20, 10, 1], groups: [group]), group.id)
    }

    func testRegistryMappingDoesNotGuessWhenServiceIsMissing() {
        let trackpad = device(id: 10)
        let group = HIDBlackholeExperiment.Group(id: trackpad.groupID, label: trackpad.label, interfaces: [trackpad])
        XCTAssertNil(HIDBlackholeExperiment.matchingGroupID(registryPath: [100, 90, 80], groups: [group]))
        XCTAssertNil(HIDBlackholeExperiment.matchingGroupID(registryPath: [], groups: [group]))
    }

    func testRegistryMappingKeepsTwoSameModelTrackpadsSeparate() {
        let left = device(id: 10)
        let right = device(id: 40, serial: "D0:C0:50:D4:75:6C")
        let groups = [
            HIDBlackholeExperiment.Group(id: left.groupID, label: left.label, interfaces: [left]),
            HIDBlackholeExperiment.Group(id: right.groupID, label: right.label, interfaces: [right])
        ]
        XCTAssertEqual(HIDBlackholeExperiment.matchingGroupID(registryPath: [60, 50, 40], groups: groups), right.groupID)
        XCTAssertEqual(HIDBlackholeExperiment.matchingGroupID(registryPath: [30, 20, 10], groups: groups), left.groupID)
    }

    func testRegistryMappingRejectsAmbiguousGroups() {
        let trackpad = device(id: 10)
        let groups = [
            HIDBlackholeExperiment.Group(id: "one", label: "one", interfaces: [trackpad]),
            HIDBlackholeExperiment.Group(id: "two", label: "two", interfaces: [trackpad])
        ]
        XCTAssertNil(HIDBlackholeExperiment.matchingGroupID(registryPath: [30, 20, 10], groups: groups))
    }

    func testBothSelectedPadsAreLinkedAndDuplicateSelectionIsDeduplicated() {
        let left = device(id: 10)
        let right = device(id: 40, serial: "other-trackpad")
        let groups = [
            HIDBlackholeExperiment.Group(id: left.groupID, label: "left", interfaces: [left]),
            HIDBlackholeExperiment.Group(id: right.groupID, label: "right", interfaces: [right])
        ]
        XCTAssertEqual(HIDBlackholeExperiment.matchingGroupIDs(registryPaths: [[30, 10], [60, 40]], groups: groups), Set([left.groupID, right.groupID]))
        XCTAssertEqual(HIDBlackholeExperiment.matchingGroupIDs(registryPaths: [[30, 10], [30, 10]], groups: groups), Set([left.groupID]))
        XCTAssertNil(HIDBlackholeExperiment.matchingGroupIDs(registryPaths: [[30, 10], [999]], groups: groups))
        XCTAssertNil(HIDBlackholeExperiment.matchingGroupIDs(registryPaths: [], groups: groups))
    }

}

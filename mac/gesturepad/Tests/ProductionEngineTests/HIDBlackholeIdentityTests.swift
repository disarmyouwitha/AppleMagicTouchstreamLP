import OpenMultitouchSupport
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

final class TwoFingerPointerTests: XCTestCase {
    private func touch(_ id: Int32, _ x: Float, _ y: Float = 0.5, state: OMSState = .touching) -> OMSRawTouch {
        OMSRawTouch(id: id, posX: x, posY: y, total: 1, pressure: 0.1,
            majorAxis: 1, minorAxis: 1, angle: 0, density: 1, state: state)
    }
    func testTwoFingerTranslationAndVerticalDirection() {
        var tracker = TwoFingerPointerTracker()
        XCTAssertNil(tracker.process(device: 1, time: 1, contacts: [touch(1, 0.2), touch(2, 0.4)]))
        let delta = tracker.process(device: 1, time: 1.01,
            contacts: [touch(2, 0.41, 0.51), touch(1, 0.21, 0.51)])
        XCTAssertEqual(delta!.x, 9.6, accuracy: 0.001)
        XCTAssertEqual(delta!.y, -6.894, accuracy: 0.001)
    }
    func testSingleFingerExtraFingerAndReplacementResetBaseline() {
        var tracker = TwoFingerPointerTracker()
        XCTAssertNil(tracker.process(device: 1, time: 1, contacts: [touch(1, 0.2)]))
        XCTAssertNil(tracker.process(device: 1, time: 1.01, contacts: [touch(1, 0.21), touch(2, 0.4)]))
        XCTAssertNil(tracker.process(device: 1, time: 1.02, contacts: [touch(1, 0.22), touch(2, 0.4), touch(3, 0.6)]))
        XCTAssertNil(tracker.process(device: 1, time: 1.03, contacts: [touch(1, 0.23), touch(2, 0.4)]))
        XCTAssertNil(tracker.process(device: 1, time: 1.04, contacts: [touch(1, 0.24), touch(4, 0.4)]))
    }
    func testIndependentDevicesStaleFramesAndReleaseDoNotJump() {
        var tracker = TwoFingerPointerTracker()
        let pair = [touch(1, 0.2), touch(2, 0.4)]
        XCTAssertNil(tracker.process(device: 1, time: 1, contacts: pair))
        XCTAssertNil(tracker.process(device: 2, time: 1.01, contacts: pair))
        XCTAssertNil(tracker.process(device: 1, time: 2, contacts: pair))
        XCTAssertNil(tracker.process(device: 1, time: 2.01, contacts: [touch(1, 0.2, state: .breaking)]))
        XCTAssertNil(tracker.process(device: 1, time: 2.02, contacts: pair))
        tracker.reset()
        XCTAssertNil(tracker.process(device: 2, time: 2.03, contacts: pair))
    }
}

final class HIDRawReportBufferTests: XCTestCase {
    func testCopiesCallbackBytesAndPreservesMetadata() throws {
        var buffer = HIDRawReportBuffer(byteLimit: 8, reportLimit: 3)
        var payload: [UInt8] = [5, 10, 255]
        payload.withUnsafeBufferPointer {
            buffer.append(uptime: 12.5, reportID: 5, result: -1, pointer: $0.baseAddress!, length: $0.count)
        }
        payload[1] = 99
        let records = buffer.records()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].payload, Data([5, 10, 255]))
        XCTAssertEqual(records[0].uptime, 12.5)
        XCTAssertEqual(records[0].reportID, 5)
        XCTAssertEqual(records[0].result, -1)
        let encoded = try JSONEncoder().encode(records)
        let decoded = try JSONDecoder().decode([HIDRawReportBuffer.Record].self, from: encoded)
        XCTAssertEqual(decoded[0].payload, records[0].payload)
    }

    func testByteAndReportLimitsDropWholeReports() {
        var bytes = HIDRawReportBuffer(byteLimit: 3, reportLimit: 10)
        var reports = HIDRawReportBuffer(byteLimit: 20, reportLimit: 1)
        let payload: [UInt8] = [1, 2]
        payload.withUnsafeBufferPointer { source in
            for _ in 0..<3 {
                bytes.append(uptime: 0, reportID: 1, result: 0, pointer: source.baseAddress!, length: 2)
                reports.append(uptime: 0, reportID: 1, result: 0, pointer: source.baseAddress!, length: 2)
            }
        }
        XCTAssertEqual(bytes.records().count, 1)
        XCTAssertEqual(bytes.bytes.count, 2)
        XCTAssertEqual(bytes.dropped, 2)
        XCTAssertEqual(reports.records().count, 1)
        XCTAssertEqual(reports.dropped, 2)
    }
}

final class PointerIdentityStatsTests: XCTestCase {
    func testPhasesHaveExplicitBoundaries() {
        XCTAssertEqual(PointerIdentityStats.phase(elapsed: 0), "left-pad")
        XCTAssertEqual(PointerIdentityStats.phase(elapsed: 9.99), "left-pad")
        XCTAssertEqual(PointerIdentityStats.phase(elapsed: 10), "right-pad")
        XCTAssertEqual(PointerIdentityStats.phase(elapsed: 20), "mouse")
        XCTAssertEqual(PointerIdentityStats.phase(elapsed: 30), "mixed")
        XCTAssertEqual(PointerIdentityStats.phase(elapsed: 40), "complete")
    }

    func testSenderEvidenceStaysSeparateFromPhaseAndMissingEvents() throws {
        var stats = PointerIdentityStats()
        stats.record(phase: "left-pad", type: 5, hasHIDEvent: true, senderID: 11, dx: 2, dy: 3)
        stats.record(phase: "left-pad", type: 5, hasHIDEvent: true, senderID: 11, dx: -1, dy: 4)
        stats.record(phase: "right-pad", type: 5, hasHIDEvent: true, senderID: 11, dx: 0, dy: 0)
        stats.record(phase: "mouse", type: 5, hasHIDEvent: false, senderID: 0, dx: 0, dy: 0)
        stats.record(phase: "mixed", type: 5, hasHIDEvent: true, senderID: 0, dx: 0, dy: 0)
        XCTAssertEqual(stats.totalEvents, 5)
        XCTAssertEqual(stats.buckets.count, 4)
        XCTAssertEqual(stats.buckets[0].count, 2)
        XCTAssertEqual(stats.buckets[0].deltaX, 1)
        XCTAssertEqual(stats.buckets[0].deltaY, 7)
        XCTAssertEqual(stats.missingHIDEvents, 1)
        XCTAssertEqual(stats.zeroSenderEvents, 1)
        let copy = try JSONDecoder().decode(PointerIdentityStats.self, from: JSONEncoder().encode(stats))
        XCTAssertEqual(copy.totalEvents, 5)
        for id in 1...300 {
            stats.record(phase: "mixed", type: 5, hasHIDEvent: true, senderID: UInt64(id), dx: 0, dy: 0)
        }
        XCTAssertEqual(stats.buckets.count, 256)
        XCTAssertGreaterThan(stats.overflowEvents, 0)
    }
}

final class SelectedTrackpadEventPolicyTests: XCTestCase {
    func testOnlySelectedMovementAndScrollAreSuppressed() {
        let selected: Set<UInt64> = [4295108038, 4295137219]
        for sender in selected {
            XCTAssertTrue(SelectedTrackpadEventPolicy.suppress(type: 5, senderID: sender, selectedSenders: selected, tag: 0))
            XCTAssertTrue(SelectedTrackpadEventPolicy.suppress(type: 22, senderID: sender, selectedSenders: selected, tag: 0))
            for type: UInt32 in [1, 2, 3, 4, 6, 7, 25, 26, 27] {
                XCTAssertFalse(SelectedTrackpadEventPolicy.suppress(type: type, senderID: sender, selectedSenders: selected, tag: 0))
            }
        }
        for sender: UInt64 in [0, 4295095385] {
            for type: UInt32 in [5, 22] {
                XCTAssertFalse(SelectedTrackpadEventPolicy.suppress(type: type, senderID: sender, selectedSenders: selected, tag: 0))
            }
        }
        XCTAssertFalse(SelectedTrackpadEventPolicy.suppress(type: 5, senderID: 4295108038,
            selectedSenders: selected, tag: SelectedTrackpadEventPolicy.interpreterTag))
    }

    func testRoutingRequiresSelectedInterfaceAncestorNotSharedSystemParent() {
        let interfaces: Set<UInt64> = [4295108009, 4295137189]
        XCTAssertTrue(SelectedTrackpadEventPolicy.matches(ancestry: [4295108038, 4295108032, 4295108009, 1], selectedInterfaces: interfaces))
        XCTAssertTrue(SelectedTrackpadEventPolicy.matches(ancestry: [4295137219, 4295137215, 4295137189, 1], selectedInterfaces: interfaces))
        XCTAssertFalse(SelectedTrackpadEventPolicy.matches(ancestry: [4295095385, 4295095369, 1], selectedInterfaces: interfaces))
        XCTAssertFalse(SelectedTrackpadEventPolicy.matches(ancestry: [], selectedInterfaces: interfaces))
        XCTAssertFalse(SelectedTrackpadEventPolicy.matches(ancestry: [4295108038], selectedInterfaces: []))
    }
}

final class ThreeFingerDragStatusTests: XCTestCase {
    func testReadOnlyPreferenceParsingKeepsUnknownDistinctFromOff() {
        for value in ["true", "YES", " on ", "1"] {
            XCTAssertEqual(GesturePadThreeFingerDragStatus.parse(value), true)
        }
        for value in ["false", "NO", " off ", "0"] {
            XCTAssertEqual(GesturePadThreeFingerDragStatus.parse(value), false)
        }
        XCTAssertEqual(GesturePadThreeFingerDragStatus.parse(NSNumber(value: true)), true)
        XCTAssertEqual(GesturePadThreeFingerDragStatus.parse(NSNumber(value: false)), false)
        XCTAssertNil(GesturePadThreeFingerDragStatus.parse("unknown"))
    }
}

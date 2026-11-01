import CoreGraphics
import Foundation
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

final class TwoHandGestureTests:XCTestCase {
    private func contacts(_ count:Int,dx:Float = 0,idBase:Int32 = 1,pressure:Float = 40) -> [OMSRawTouch] {
        (0..<count).map { i in OMSRawTouch(id:idBase+Int32(i),posX:0.3+Float(i)*0.1+dx,posY:0.5,
            total:1,pressure:pressure,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching) }
    }
    private func corners(left:Bool,inner:Bool = false) -> [OMSRawTouch] {
        (0..<2).map { i in OMSRawTouch(id:Int32(i+1),posX:left != inner ? 0.08 : 0.92,posY:i == 0 ? 0.08 : 0.92,
            total:1,pressure:40,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching) }
    }
    private func chordContacts(_ chord:TwoHandChord,left:Bool) -> [OMSRawTouch] {
        switch chord {
        case .fourCorners:return corners(left:left)
        case .innerCorners:return corners(left:left,inner:true)
        case .threeFingers,.fourFingers:return contacts(chord.count)
        default:
            let inner = chord == .topInnerCorners || chord == .bottomInnerCorners
            let top = chord == .topInnerCorners || chord == .topOuterCorners
            return [OMSRawTouch(id:1,posX:left != inner ? 0.08 : 0.92,posY:top ? 0.92 : 0.08,
                total:1,pressure:40,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)]
        }
    }
    private func cornerSettings(_ chord:TwoHandChord) -> TwoHandGestureSettings {
        var value = TwoHandGestureSettings()
        for c in TwoHandChord.allCases { value.setAction(.disabled,for:.init(chord:c,phase:.hold)) }
        value.setAction(.missionControl,for:.init(chord:chord,phase:.hold))
        return value
    }
    private func settings(_ chord:TwoHandChord) -> TwoHandGestureSettings {
        var settings = TwoHandGestureSettings()
        settings.setAction(.primaryClick,for:.init(chord:chord,phase:.tap))
        settings.setAction(.missionControl,for:.init(chord:chord,phase:.hold))
        return settings
    }
    func testBothForceRequiresConcurrentPressureAndLatchesUntilBothAllUp() {
        for chord in [TwoHandChord.threeFingers,.fourFingers] {
            var engine = TwoHandGestureEngine(), settings = TwoHandGestureSettings()
            let force = TwoHandTrigger(chord:chord,phase:.force)
            settings.setAction(.secondaryClick,for:force)
            let low = contacts(chord.count), high = [contacts(chord.count,pressure:130)[0]]+Array(contacts(chord.count).dropFirst())
            XCTAssertFalse(engine.process(leftHand:true,now:1,contacts:low,settings:settings).reserved)
            XCTAssertFalse(engine.process(leftHand:false,now:1.01,contacts:low,settings:settings).reserved)
            XCTAssertFalse(engine.process(leftHand:true,now:1.02,contacts:high,settings:settings).reserved)
            let win = engine.process(leftHand:false,now:1.04,contacts:high,settings:settings)
            XCTAssertTrue(win.began); XCTAssertEqual(win.trigger,force)
            for i in 1...3 {
                let event = engine.process(leftHand:i % 2 == 0,now:1.04+Double(i)*0.01,
                    contacts:contacts(1,dx:0.1,idBase:70,pressure:40),settings:settings)
                XCTAssertTrue(event.reserved); XCTAssertNil(event.trigger)
            }
            XCTAssertNil(engine.advance(now:1.08,settings:settings))
            XCTAssertTrue(engine.process(leftHand:true,now:1.09,contacts:[],settings:settings).reserved)
            XCTAssertTrue(engine.process(leftHand:false,now:1.1,contacts:[],settings:settings).reserved)
            XCTAssertFalse(engine.ownsCycle)
            _ = engine.process(leftHand:true,now:1.2,contacts:high,settings:settings)
            XCTAssertEqual(engine.process(leftHand:false,now:1.21,contacts:high,settings:settings).trigger,force)
        }
    }
    func testBothForceRejectsLatePressureAndCanRearmPressureBeforeAcquisition() {
        var engine = TwoHandGestureEngine(), settings = TwoHandGestureSettings()
        let force = TwoHandTrigger(chord:.threeFingers,phase:.force)
        settings.setAction(.primaryClick,for:force)
        let low = contacts(3), high = contacts(3,pressure:130)
        _ = engine.process(leftHand:true,now:1,contacts:low,settings:settings)
        _ = engine.process(leftHand:false,now:1.01,contacts:low,settings:settings)
        _ = engine.process(leftHand:true,now:1.02,contacts:high,settings:settings)
        _ = engine.process(leftHand:false,now:1.1,contacts:low,settings:settings)
        _ = engine.process(leftHand:true,now:1.19,contacts:high,settings:settings)
        XCTAssertFalse(engine.process(leftHand:false,now:1.2,contacts:high,settings:settings).reserved)
        _ = engine.process(leftHand:true,now:1.21,contacts:low,settings:settings)
        _ = engine.process(leftHand:false,now:1.22,contacts:low,settings:settings)
        _ = engine.process(leftHand:true,now:1.23,contacts:high,settings:settings)
        XCTAssertEqual(engine.process(leftHand:false,now:1.24,contacts:high,settings:settings).trigger,force)
    }
    func testBothForceCannotReplaceFiredHoldAndConsumesPendingTap() {
        for holdFirst in [false,true] {
            var engine = TwoHandGestureEngine(), value = settings(.fourFingers)
            value.setAction(.secondaryClick,for:.init(chord:.fourFingers,phase:.force))
            value.setHoldThreshold(0.1,for:.fourFingers)
            let low = contacts(4), high = contacts(4,pressure:130)
            _ = engine.process(leftHand:true,now:1,contacts:low,settings:value)
            _ = engine.process(leftHand:false,now:1.01,contacts:low,settings:value)
            if holdFirst {
                XCTAssertEqual(engine.advance(now:1.12,settings:value)?.phase,.hold)
                XCTAssertNil(engine.process(leftHand:true,now:1.13,contacts:high,settings:value).trigger)
                XCTAssertNil(engine.process(leftHand:false,now:1.14,contacts:high,settings:value).trigger)
            } else {
                _ = engine.process(leftHand:true,now:1.04,contacts:high,settings:value)
                XCTAssertEqual(engine.process(leftHand:false,now:1.05,contacts:high,settings:value).trigger?.phase,.force)
                XCTAssertNil(engine.advance(now:1.12,settings:value))
            }
            _ = engine.process(leftHand:true,now:1.15,contacts:[],settings:value)
            XCTAssertNil(engine.process(leftHand:false,now:1.16,contacts:[],settings:value).trigger)
        }
    }
    func testBothForceNoneWrongCountStaleAndInvalidPressureNeverAcquire() {
        for enabled in [false,true] {
            for pressure in [Float(129),.nan,.infinity,-1] {
                var engine = TwoHandGestureEngine(), value = TwoHandGestureSettings()
                if enabled { value.setAction(.primaryClick,for:.init(chord:.threeFingers,phase:.force)) }
                _ = engine.process(leftHand:true,now:1,contacts:contacts(3,pressure:pressure),settings:value)
                XCTAssertFalse(engine.process(leftHand:false,now:1.01,contacts:contacts(3,pressure:130),settings:value).reserved)
            }
        }
        var engine = TwoHandGestureEngine(), value = TwoHandGestureSettings()
        value.setAction(.primaryClick,for:.init(chord:.threeFingers,phase:.force))
        _ = engine.process(leftHand:true,now:1,contacts:contacts(3,pressure:130),settings:value)
        XCTAssertFalse(engine.process(leftHand:false,now:1.01,contacts:contacts(4,pressure:130),settings:value).reserved)
        XCTAssertFalse(engine.process(leftHand:false,now:1.3,contacts:contacts(3,pressure:130),settings:value).reserved)
    }
    func testBothForceStaleOrInvalidPressureCannotReviveUntilLift() {
        for invalid in [false,true] {
            var engine = TwoHandGestureEngine(), value = TwoHandGestureSettings()
            let trigger = TwoHandTrigger(chord:.threeFingers,phase:.force)
            value.setAction(.primaryClick,for:trigger)
            _ = engine.process(leftHand:true,now:1,contacts:contacts(3,pressure:invalid ? .nan:40),settings:value)
            _ = engine.process(leftHand:false,now:1.01,contacts:contacts(3),settings:value)
            let now = invalid ? 1.02:1.3
            _ = engine.process(leftHand:true,now:now,contacts:contacts(3,pressure:130),settings:value)
            XCTAssertFalse(engine.process(leftHand:false,now:now+0.01,contacts:contacts(3,pressure:130),settings:value).reserved)
            _ = engine.process(leftHand:true,now:now+0.02,contacts:[],settings:value)
            _ = engine.process(leftHand:false,now:now+0.03,contacts:[],settings:value)
            _ = engine.process(leftHand:true,now:now+0.04,contacts:contacts(3,pressure:130),settings:value)
            XCTAssertEqual(engine.process(leftHand:false,now:now+0.05,contacts:contacts(3,pressure:130),settings:value).trigger,trigger)
        }
    }
    func testBothForceSettingsRoundTripAndStayDisabledInSteno() throws {
        var profile = AppKeymapProfile.defaultProfile(), value = HandGestureSettings()
        for chord in [TwoHandChord.threeFingers,.fourFingers] {
            let trigger = TwoHandTrigger(chord:chord,phase:.force)
            XCTAssertEqual(value.twoHand.action(trigger),.disabled)
            value.coordinated = value.twoHand
            var both = value.twoHand; both.setAction(.secondaryClick,for:trigger); value.coordinated = both
            XCTAssertEqual(value.twoHand.stenoConfigurationOnly.action(trigger),.disabled)
        }
        profile.handGestureSettings = value
        let data = try PortableKeymapInterop.exportBundle(from:profile)
        let imported = try PortableKeymapInterop.importProfile(from:data,currentProfile:.defaultProfile())
        XCTAssertEqual(imported.handGestureSettings,value)
        var both = value.twoHand
        both.setAction(.shortcut(.init(label:"Cmd+C",holdUntilRelease:true)),for:.init(chord:.threeFingers,phase:.force))
        XCTAssertEqual(both.action(.init(chord:.threeFingers,phase:.force)),.secondaryClick)
    }
    func testTapRequiresBothHandsAndRearmsAfterBothLift() {
        for chord in [TwoHandChord.threeFingers,.fourFingers] {
            var engine = TwoHandGestureEngine()
            let settings = settings(chord), c = contacts(chord.count)
            XCTAssertFalse(engine.process(leftHand:true,now:1,contacts:c,settings:settings).reserved)
            XCTAssertFalse(engine.ownsCycle)
            XCTAssertTrue(engine.process(leftHand:false,now:1.03,contacts:c,settings:settings).began)
            XCTAssertTrue(engine.ownsCycle)
            XCTAssertNil(engine.process(leftHand:true,now:1.08,contacts:contacts(0),settings:settings).trigger)
            let ended = engine.process(leftHand:false,now:1.11,contacts:contacts(0),settings:settings)
            XCTAssertTrue(ended.reserved)
            XCTAssertEqual(ended.trigger,.init(chord:chord,phase:.tap))
            XCTAssertFalse(engine.ownsCycle)
            XCTAssertFalse(engine.process(leftHand:true,now:1.12,contacts:contacts(0),settings:settings).reserved)
            XCTAssertFalse(engine.process(leftHand:false,now:1.13,contacts:contacts(0),settings:settings).reserved)
        }
    }
    func testFreshFramesCannotLetOrdinaryBothAcquireASecondHandLate() {
        for chord in [TwoHandChord.threeFingers,.fourFingers] {
            for firstLeft in [true,false] {
                for delay in [1.01,1.5,3.0] {
                    var engine = TwoHandGestureEngine()
                    let settings = settings(chord), c = contacts(chord.count)
                    XCTAssertFalse(engine.process(leftHand:firstLeft,now:1,contacts:c,settings:settings).reserved)
                    for frame in 1...Int(delay*100) {
                        XCTAssertFalse(engine.process(leftHand:firstLeft,now:1+Double(frame)*0.01,contacts:c,settings:settings).reserved)
                    }
                    let second = engine.process(leftHand:!firstLeft,now:1+delay+0.001,contacts:c,settings:settings)
                    XCTAssertFalse(second.reserved,"Late second hand must keep its independent gesture")
                    XCTAssertFalse(engine.ownsCycle)
                    XCTAssertNil(engine.advance(now:1+delay+0.01,settings:settings))
                }
            }
        }
    }

    func testEveryBothChordSharesTheOneSecondInitialLandingWindow() {
        for chord in TwoHandChord.allCases {
            for firstLeft in [true,false] {
                for delay in [0.5,0.999,1.001,3.0] {
                    var engine = TwoHandGestureEngine()
                    let settings = chord.isCorner ? cornerSettings(chord) : settings(chord)
                    let first = chordContacts(chord,left:firstLeft), second = chordContacts(chord,left:!firstLeft)
                    _ = engine.process(leftHand:firstLeft,now:1,contacts:first,settings:settings)
                    for frame in 1...Int(delay*100) {
                        _ = engine.process(leftHand:firstLeft,now:1+Double(frame)*0.01,contacts:first,settings:settings)
                    }
                    let decision = engine.process(leftHand:!firstLeft,now:1+delay,contacts:second,settings:settings)
                    XCTAssertEqual(decision.began,delay <= 1,"\(chord) at \(delay) seconds")
                    XCTAssertEqual(decision.reserved,delay <= 1)
                }
            }
        }
    }

    func testHoldFiresOnceAndConsumesTapUntilAllUp() {
        for chord in [TwoHandChord.threeFingers,.fourFingers] {
            var engine = TwoHandGestureEngine()
            let settings = settings(chord), c = contacts(chord.count)
            _ = engine.process(leftHand:true,now:1,contacts:c,settings:settings)
            _ = engine.process(leftHand:false,now:1.01,contacts:c,settings:settings)
            var outputs:[TwoHandTrigger] = []
            for i in 1...10 {
                let now = 1.01+Double(i)*0.1
                if let t = engine.process(leftHand:true,now:now,contacts:c,settings:settings).trigger { outputs.append(t) }
                if let t = engine.process(leftHand:false,now:now+0.001,contacts:c,settings:settings).trigger { outputs.append(t) }
                if let t = engine.advance(now:now+0.002,settings:settings) { outputs.append(t) }
            }
            XCTAssertEqual(outputs,[.init(chord:chord,phase:.hold)])
            XCTAssertNil(engine.process(leftHand:true,now:2.03,contacts:contacts(0),settings:settings).trigger)
            XCTAssertNil(engine.process(leftHand:false,now:2.04,contacts:contacts(0),settings:settings).trigger)
            XCTAssertFalse(engine.ownsCycle)
        }
    }
    func testOuterCornersDefaultToConfigAndAllowStaggeredLanding() {
        var engine = TwoHandGestureEngine()
        let settings = TwoHandGestureSettings()
        XCTAssertEqual(settings.action(.init(chord:.fourCorners,phase:.tap)),.disabled)
        XCTAssertEqual(settings.action(.init(chord:.fourCorners,phase:.hold)),.openConfig)
        _ = engine.process(leftHand:true,now:1,contacts:corners(left:true),settings:settings)
        _ = engine.process(leftHand:true,now:1.4,contacts:corners(left:true),settings:settings)
        XCTAssertTrue(engine.process(leftHand:false,now:1.41,contacts:corners(left:false),settings:settings).began)
        var outputs:[TwoHandTrigger] = []
        for i in 1...11 {
            let now = 1.41+Double(i)*0.1
            if let t = engine.process(leftHand:true,now:now,contacts:corners(left:true),settings:settings).trigger { outputs.append(t) }
            if let t = engine.process(leftHand:false,now:now+0.001,contacts:corners(left:false),settings:settings).trigger { outputs.append(t) }
        }
        XCTAssertEqual(outputs,[.init(chord:.fourCorners,phase:.hold)])
    }
    func testUnassignedInnerCornersWrongCountsAndAsynchronousChordsCannotMatch() {
        for kind in 0..<4 {
            var engine = TwoHandGestureEngine()
            let settings = kind == 0 ? TwoHandGestureSettings() : settings(.threeFingers)
            _ = engine.process(leftHand:true,now:1,contacts:kind == 0 ? corners(left:true,inner:true) : contacts(3),settings:settings)
            let result = engine.process(leftHand:false,now:kind == 2 ? 1.4 : 1.01,
                contacts:kind == 0 ? corners(left:false,inner:true) : contacts(kind == 1 ? 4 : kind == 3 ? 0 : 3),settings:settings)
            XCTAssertNil(result.trigger); XCTAssertFalse(engine.ownsCycle)
        }
    }
    func testMotionOrIdentityReplacementCancelsButKeepsAllUpLatch() {
        for replacement in [false,true] {
            var engine = TwoHandGestureEngine()
            let settings = settings(.threeFingers)
            _ = engine.process(leftHand:true,now:1,contacts:contacts(3),settings:settings)
            _ = engine.process(leftHand:false,now:1.01,contacts:contacts(3),settings:settings)
            let update = engine.process(leftHand:true,now:1.02,
                contacts:contacts(3,dx:replacement ? 0 : 0.03,idBase:replacement ? 10 : 1),settings:settings)
            XCTAssertTrue(update.reserved); XCTAssertFalse(update.began)
            XCTAssertNil(engine.advance(now:1.6,settings:settings))
            XCTAssertNil(engine.process(leftHand:true,now:1.61,contacts:contacts(0),settings:settings).trigger)
            XCTAssertNil(engine.process(leftHand:false,now:1.62,contacts:contacts(0),settings:settings).trigger)
            XCTAssertFalse(engine.ownsCycle)
        }
    }
    func testAddedAndLiftedFingersNeverTransferTheOwnedCycle() {
        var engine = TwoHandGestureEngine()
        let settings = settings(.threeFingers)
        _ = engine.process(leftHand:true,now:1,contacts:contacts(3),settings:settings)
        _ = engine.process(leftHand:false,now:1.01,contacts:contacts(3),settings:settings)
        for (time,count,left) in [(1.02,4,true),(1.03,1,false),(1.04,0,true)] {
            let decision = engine.process(leftHand:left,now:time,contacts:contacts(count),settings:settings)
            XCTAssertTrue(decision.reserved); XCTAssertNil(decision.trigger); XCTAssertFalse(decision.began)
        }
        XCTAssertTrue(engine.ownsCycle)
        XCTAssertNil(engine.process(leftHand:false,now:1.05,contacts:contacts(0),settings:settings).trigger)
        XCTAssertFalse(engine.ownsCycle)
    }
    func testFreshnessIsPerHandAndTimerCannotFireAfterLossOfInput() {
        var engine = TwoHandGestureEngine()
        let settings = settings(.threeFingers)
        _ = engine.process(leftHand:true,now:1,contacts:contacts(3),settings:settings)
        _ = engine.process(leftHand:false,now:1.01,contacts:contacts(3),settings:settings)
        XCTAssertNil(engine.advance(now:1.3,settings:settings))
        for i in 1...10 {
            XCTAssertNil(engine.process(leftHand:true,now:1.3+Double(i)*0.05,contacts:contacts(3),settings:settings).trigger)
            XCTAssertNil(engine.process(leftHand:false,now:1.301+Double(i)*0.05,contacts:contacts(3),settings:settings).trigger)
        }
        XCTAssertNil(engine.process(leftHand:true,now:1.9,contacts:contacts(0),settings:settings).trigger)
        XCTAssertNil(engine.process(leftHand:false,now:1.91,contacts:contacts(0),settings:settings).trigger)
    }
    func testDisabledChordsDoNotDelayExistingSingleHandGestures() {
        var engine = TwoHandGestureEngine()
        for count in [1,2,3,4,5] {
            XCTAssertFalse(engine.process(leftHand:true,now:Double(count),contacts:contacts(count),settings:.init()).reserved)
        }
        let enabled = settings(.threeFingers)
        engine.reset()
        XCTAssertFalse(engine.process(leftHand:true,now:10,contacts:contacts(3),settings:enabled).reserved)
        XCTAssertFalse(engine.process(leftHand:true,now:10.16,contacts:contacts(3),settings:enabled).reserved)
    }
    func testKeyboardPriorityAndResetDiscardPendingAndOwnedSessions() {
        var engine = TwoHandGestureEngine()
        let settings = settings(.threeFingers)
        _ = engine.process(leftHand:true,now:1,contacts:contacts(3),settings:settings)
        _ = engine.process(leftHand:false,now:1.01,contacts:contacts(3),settings:settings)
        XCTAssertFalse(engine.process(leftHand:true,now:1.02,contacts:contacts(3),settings:settings,blocked:true).reserved)
        XCTAssertFalse(engine.ownsCycle)
        XCTAssertNil(engine.advance(now:2,settings:settings))
        _ = engine.process(leftHand:true,now:3,contacts:contacts(3),settings:settings)
        engine.reset()
        XCTAssertFalse(engine.ownsCycle)
        XCTAssertFalse(engine.process(leftHand:false,now:3.01,contacts:contacts(0),settings:settings).reserved)
    }
    func testLongReleaseSkewRejoinAndDuplicateIDsCannotTap() {
        for kind in 0..<3 {
            var engine = TwoHandGestureEngine()
            let settings = settings(.threeFingers)
            _ = engine.process(leftHand:true,now:1,contacts:contacts(3),settings:settings)
            _ = engine.process(leftHand:false,now:1.01,contacts:contacts(3),settings:settings)
            _ = engine.process(leftHand:true,now:1.05,contacts:contacts(0),settings:settings)
            if kind == 1 {
                _ = engine.process(leftHand:true,now:1.06,contacts:contacts(3),settings:settings)
                _ = engine.process(leftHand:true,now:1.07,contacts:contacts(0),settings:settings)
            }
            if kind == 2 {
                _ = engine.process(leftHand:false,now:1.06,contacts:[contacts(1)[0],contacts(1)[0]],settings:settings)
            }
            XCTAssertNil(engine.process(leftHand:false,now:kind == 0 ? 1.3 : 1.1,contacts:contacts(0),settings:settings).trigger)
        }
    }
    func testOnlyAcquisitionResetsBothPadsAndFinalReleaseConsumesItsOwnFrame() {
        var engine = TwoHandGestureEngine()
        let settings = settings(.threeFingers)
        let first = engine.process(leftHand:true,now:1,contacts:contacts(3),settings:settings)
        XCTAssertFalse(first.reserved); XCTAssertFalse(first.began)
        XCTAssertTrue(engine.process(leftHand:false,now:1.01,contacts:contacts(3),settings:settings).began)
        for i in 1...3 {
            let decision = engine.process(leftHand:true,now:1.01+Double(i)*0.01,contacts:contacts(3),settings:settings)
            XCTAssertTrue(decision.reserved); XCTAssertFalse(decision.began)
        }
        XCTAssertFalse(engine.process(leftHand:true,now:1.06,contacts:contacts(0),settings:settings).began)
        let ended = engine.process(leftHand:false,now:1.07,contacts:contacts(0),settings:settings)
        XCTAssertTrue(ended.reserved); XCTAssertFalse(ended.began)
        // No second-hand frame can re-block the already released first hand.
        XCTAssertFalse(engine.ownsCycle)
        XCTAssertFalse(engine.process(leftHand:true,now:1.08,contacts:contacts(0),settings:settings).reserved)
    }
    func testUnjoinedSingleHandTapStillCompletesDuringTheJoinWindow() {
        var shared = TwoHandGestureEngine(), local = TrackpadGestureRouter(), tap = ThreeFingerTapRecognizer()
        let settings = settings(.threeFingers)
        var clicks = 0
        for (host,native,count) in [(1.0,9000.0,3),(1.04,9000.04,3),(1.08,9000.08,0)] {
            let c = contacts(count)
            let decision = shared.process(leftHand:true,now:host,contacts:c,settings:settings)
            XCTAssertFalse(decision.reserved)
            let update = local.recognize(device:1,time:native,contacts:c,enabled:{$0 == .threeFingerMove})
            if tap.recognize(device:1,time:native,contacts:c,gestureActive:update.millimetres != nil,
                ordinaryEnabled:true,thumbEnabled:false) == .threeFingerTap { clicks += 1 }
        }
        XCTAssertEqual(clicks,1)
        XCTAssertFalse(shared.ownsCycle)
    }
    func testGlobalLocalOwnerReadoutPersistsUntilAllUp() {
        var router = TrackpadGestureRouter()
        _ = router.recognize(device:1,time:1,contacts:contacts(3),enabled:{$0 == .threeFingerMove})
        _ = router.recognize(device:1,time:1.01,contacts:contacts(3,dx:0.01),enabled:{$0 == .threeFingerMove})
        XCTAssertEqual(router.owner(device:1),.threeFingerMove)
        _ = router.recognize(device:1,time:1.02,contacts:contacts(1,dx:0.01),enabled:{$0 == .threeFingerMove})
        XCTAssertEqual(router.owner(device:1),.threeFingerMove)
        _ = router.recognize(device:1,time:1.03,contacts:contacts(0),enabled:{$0 == .threeFingerMove})
        XCTAssertNil(router.owner(device:1))
    }
    func testStaggeredHandsMayTapOrHoldFromTheTimeTheSecondHandJoins() {
        for keepHolding in [false,true] {
            var engine = TwoHandGestureEngine()
            let settings = settings(.threeFingers)
            _ = engine.process(leftHand:true,now:1,contacts:contacts(3),settings:settings)
            _ = engine.process(leftHand:true,now:1.3,contacts:contacts(3),settings:settings)
            XCTAssertTrue(engine.process(leftHand:false,now:1.31,contacts:contacts(3),settings:settings).began)
            if keepHolding {
                var outputs:[TwoHandTrigger] = []
                for i in 1...6 {
                    let now = 1.31+Double(i)*0.1
                    if let t = engine.process(leftHand:true,now:now,contacts:contacts(3),settings:settings).trigger { outputs.append(t) }
                    if let t = engine.process(leftHand:false,now:now+0.001,contacts:contacts(3),settings:settings).trigger { outputs.append(t) }
                }
                XCTAssertEqual(outputs,[.init(chord:.threeFingers,phase:.hold)])
            } else {
                XCTAssertNil(engine.process(leftHand:true,now:1.4,contacts:contacts(0),settings:settings).trigger)
                XCTAssertEqual(engine.process(leftHand:false,now:1.41,contacts:contacts(0),settings:settings).trigger,.init(chord:.threeFingers,phase:.tap))
            }
        }
    }
    func testTimelySingleHandDragHandsOffWithOneBalancedRelease() throws {
        for count in [3,4] {
            let chord:TwoHandChord = count == 3 ? .threeFingers : .fourFingers
            let settings = settings(chord)
            var both = TwoHandGestureEngine(), local = TrackpadGestureRouter(), drag = PrimaryDragOutput()
            let first = contacts(count)
            XCTAssertFalse(both.process(leftHand:true,now:1,contacts:first,settings:settings).reserved)
            _ = local.recognize(device:1,time:1,contacts:first,enabled:{$0 == .threeFingerMove || $0 == .fourFingerMove})
            let moving = contacts(count,dx:0.01)
            XCTAssertFalse(both.process(leftHand:true,now:1.01,contacts:moving,settings:settings).reserved)
            let owner = local.recognize(device:1,time:1.01,contacts:moving,enabled:{$0 == .threeFingerMove || $0 == .fourFingerMove})
            XCTAssertEqual(owner.phase,.began) // 10 ms, no 150 ms join delay.
            if count == 3 { XCTAssertNotNil(drag.begin(device:1,location:.zero,flags:[])) }
            // A quick second landing still hands off and rebases within the shared one-second window.
            _ = both.process(leftHand:true,now:1.9,contacts:moving,settings:settings)
            let acquired = both.process(leftHand:false,now:1.91,contacts:contacts(count),settings:settings)
            XCTAssertTrue(acquired.began); XCTAssertTrue(acquired.reserved)
            if count == 3 {
                XCTAssertEqual(try XCTUnwrap(drag.end(device:1)).type,.leftMouseUp)
                XCTAssertNil(drag.end(device:1))
            }
            local.reset(device:1)
            XCTAssertNil(local.owner(device:1)); XCTAssertNil(drag.owner)
            XCTAssertNil(both.process(leftHand:true,now:1.98,contacts:contacts(0),settings:settings).trigger)
            XCTAssertEqual(both.process(leftHand:false,now:1.99,contacts:contacts(0),settings:settings).trigger,.init(chord:chord,phase:.tap))
        }
    }
    func testEligibilityRequiresTwoDistinctSelectedOwnedArmedPads() {
        XCTAssertTrue(TwoHandGestureEligibility.enabled(pads:.init(left:1,right:2),owned:[1,2],takeover:true,armed:true))
        for pads in [GestureSelectedPads(left:1,right:1),.init(left:1,right:nil),.init(left:nil,right:2),.init(left:1,right:3)] {
            XCTAssertFalse(TwoHandGestureEligibility.enabled(pads:pads,owned:[1,2],takeover:true,armed:true))
        }
        XCTAssertFalse(TwoHandGestureEligibility.enabled(pads:.init(left:1,right:2),owned:[1,2],takeover:false,armed:true))
        XCTAssertFalse(TwoHandGestureEligibility.enabled(pads:.init(left:1,right:2),owned:[1,2],takeover:true,armed:false))
    }
    func testMirrorEditDoesNotChangeCoordinatedBindingsAndKeymapRoundTrips() throws {
        var settings = HandGestureSettings()
        var both = settings.twoHand
        both.setAction(.missionControl,for:.init(chord:.threeFingers,phase:.hold))
        both.setAction(.secondaryClick,for:.init(chord:.fourFingers,phase:.tap))
        both.setAction(.pointer,for:.init(chord:.threeFingers,phase:.tap)) // unsupported continuous output rejected
        settings.coordinated = both
        settings.setAction(.disabled,for:.threeFingerTap,in:.both)
        XCTAssertEqual(settings.twoHand,both)
        XCTAssertEqual(both.action(.init(chord:.threeFingers,phase:.tap)),.disabled)
        var profile = AppKeymapProfile.defaultProfile(); profile.handGestureSettings = settings
        XCTAssertEqual(try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile()).handGestureSettings,settings)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(settings)) as? [String:Any])
        legacy.removeValue(forKey:"coordinated")
        XCTAssertEqual(try JSONDecoder().decode(HandGestureSettings.self,from:JSONSerialization.data(withJSONObject:legacy)).twoHand,.init())
    }
}


extension TwoHandGestureTests {
    func testCornerFamiliesDefaultToHoldOnlyAndPreserveOuterSavedIdentity() throws {
        let defaults = TwoHandGestureSettings()
        XCTAssertEqual(TwoHandChord.fourCorners.title,"Outer Corners")
        XCTAssertEqual(GesturePane.fourCorners.title,"Outer Corners")
        XCTAssertEqual(TwoHandTrigger(chord:.fourCorners,phase:.hold).key,"fourCorners.hold")
        for chord in TwoHandChord.allCases where chord.isCorner {
            XCTAssertEqual(chord.phases,[.hold])
            XCTAssertEqual(defaults.action(.init(chord:chord,phase:.hold)),chord == .fourCorners ? .openConfig : .disabled)
            XCTAssertEqual(defaults.holdThreshold(for:chord),0.5)
            var value = defaults
            value.setAction(.primaryClick,for:.init(chord:chord,phase:.tap))
            XCTAssertEqual(value.action(.init(chord:chord,phase:.tap)),.disabled)
        }
        let old = Data(#"{"assignments":{"fourCorners.hold":"showDesktop"},"holdThresholds":{"fourCorners":0.8}}"#.utf8)
        let decoded = try JSONDecoder().decode(TwoHandGestureSettings.self,from:old)
        XCTAssertEqual(decoded.action(.init(chord:.fourCorners,phase:.hold)),.showDesktop)
        XCTAssertEqual(decoded.holdThreshold(for:.fourCorners),0.8)
        XCTAssertFalse(decoded.enabled(.innerCorners))
    }
    func testEveryCornerFamilyRecognizesOnlyItsMirroredPositionsAndCleansUp() {
        for chord in TwoHandChord.allCases where chord.isCorner {
            let settings = cornerSettings(chord)
            for candidate in TwoHandChord.allCases where candidate.isCorner {
                var engine = TwoHandGestureEngine()
                let left = chordContacts(candidate,left:true), right = chordContacts(candidate,left:false)
                XCTAssertFalse(engine.process(leftHand:true,now:1,contacts:left,settings:settings).reserved)
                let acquired = engine.process(leftHand:false,now:1.01,contacts:right,settings:settings)
                XCTAssertEqual(acquired.began,candidate == chord,"\(chord) versus \(candidate)")
                if candidate != chord { continue }
                var fired:[TwoHandTrigger] = []
                for i in 1...7 {
                    let time = 1.01+Double(i)*0.1
                    if let t = engine.process(leftHand:true,now:time,contacts:left,settings:settings).trigger { fired.append(t) }
                    if let t = engine.process(leftHand:false,now:time+0.001,contacts:right,settings:settings).trigger { fired.append(t) }
                }
                XCTAssertEqual(fired,[.init(chord:chord,phase:.hold)])
                XCTAssertTrue(engine.maintainsHeldOutput)
                _ = engine.process(leftHand:true,now:1.8,contacts:contacts(0),settings:settings)
                XCTAssertTrue(engine.ownsCycle)
                _ = engine.process(leftHand:false,now:1.81,contacts:contacts(0),settings:settings)
                XCTAssertFalse(engine.ownsCycle); XCTAssertFalse(engine.maintainsHeldOutput)
            }
        }
    }
    func testCornerPairMayGrowBeforeActivationButNeverReplacesFiredOutput() {
        for pair in [TwoHandChord.topOuterCorners,.bottomOuterCorners,.topInnerCorners,.bottomInnerCorners] {
            let full = pair.expandedCornerChord!
            for activateFirst in [false,true] {
                var settings = cornerSettings(pair), engine = TwoHandGestureEngine()
                settings.setAction(.showDesktop,for:.init(chord:full,phase:.hold))
                settings.setHoldThreshold(0.1,for:pair); settings.setHoldThreshold(0.1,for:full)
                let left = chordContacts(pair,left:true), right = chordContacts(pair,left:false)
                // Keep the original pair's IDs when the complementary corners join.
                func expanded(_ initial:[OMSRawTouch],left:Bool) -> [OMSRawTouch] {
                    let other = chordContacts(full,left:left).first { $0.posY != initial[0].posY }!
                    return initial + [OMSRawTouch(id:2,posX:other.posX,posY:other.posY,total:1,pressure:40,
                        majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)]
                }
                let fullLeft = expanded(left,left:true), fullRight = expanded(right,left:false)
                _ = engine.process(leftHand:true,now:1,contacts:left,settings:settings)
                XCTAssertTrue(engine.process(leftHand:false,now:1,contacts:right,settings:settings).began)
                if activateFirst { XCTAssertEqual(engine.advance(now:1.101,settings:settings),.init(chord:pair,phase:.hold)) }
                let t = activateFirst ? 1.12 : 1.02
                XCTAssertNil(engine.process(leftHand:true,now:t,contacts:fullLeft,settings:settings).trigger)
                XCTAssertNil(engine.advance(now:t+0.11,settings:settings)) // incomplete expansion cannot fire pair
                _ = engine.process(leftHand:false,now:t+0.12,contacts:fullRight,settings:settings)
                var fired:[TwoHandTrigger] = []
                for i in 1...3 {
                    let time = t+0.12+Double(i)*0.05
                    if let result = engine.process(leftHand:true,now:time,contacts:fullLeft,settings:settings).trigger { fired.append(result) }
                    if let result = engine.process(leftHand:false,now:time+0.001,contacts:fullRight,settings:settings).trigger { fired.append(result) }
                }
                XCTAssertEqual(fired,activateFirst ? [] : [.init(chord:full,phase:.hold)])
            }
        }
    }
    func testCornerHoldFamiliesCancelInvalidStaleExtraOrLiftedInputUntilAllUp() {
        for chord in TwoHandChord.allCases where chord.isCorner {
            for failure in 0...5 {
                let settings = cornerSettings(chord)
                let left = chordContacts(chord,left:true), right = chordContacts(chord,left:false)
                var engine = TwoHandGestureEngine()
                _ = engine.process(leftHand:true,now:1,contacts:left,settings:settings)
                _ = engine.process(leftHand:false,now:1.01,contacts:right,settings:settings)
                var bad = left
                let first = left[0]
                switch failure {
                case 0:bad = []
                case 1:bad.append(contacts(1,idBase:9)[0])
                case 2:bad[0] = OMSRawTouch(id:9,posX:first.posX,posY:first.posY,total:1,pressure:40,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
                case 3:bad[0] = OMSRawTouch(id:first.id,posX:first.posX+0.03,posY:first.posY,total:1,pressure:40,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
                case 4:bad[0] = OMSRawTouch(id:first.id,posX:.nan,posY:first.posY,total:1,pressure:40,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
                default:XCTAssertNil(engine.advance(now:1.25,settings:settings))
                }
                let attempted = failure == 5 ? 1.3 : 1.1
                XCTAssertNil(engine.process(leftHand:true,now:attempted,contacts:bad,settings:settings).trigger)
                for i in 1...7 {
                    let time = attempted+Double(i)*0.1
                    XCTAssertNil(engine.process(leftHand:true,now:time,contacts:left,settings:settings).trigger)
                    XCTAssertNil(engine.process(leftHand:false,now:time+0.001,contacts:right,settings:settings).trigger)
                }
                XCTAssertFalse(engine.maintainsHeldOutput)
                _ = engine.process(leftHand:true,now:attempted+0.8,contacts:contacts(0),settings:settings)
                _ = engine.process(leftHand:false,now:attempted+0.81,contacts:contacts(0),settings:settings)
                XCTAssertFalse(engine.ownsCycle)
            }
        }
    }
    func testAbandonedCornerExpansionCannotReviveTheOriginalPairHold() {
        var settings = cornerSettings(.topInnerCorners), engine = TwoHandGestureEngine()
        settings.setAction(.showDesktop,for:.init(chord:.innerCorners,phase:.hold))
        let left = chordContacts(.topInnerCorners,left:true), right = chordContacts(.topInnerCorners,left:false)
        _ = engine.process(leftHand:true,now:1,contacts:left,settings:settings)
        _ = engine.process(leftHand:false,now:1.01,contacts:right,settings:settings)
        let extra = OMSRawTouch(id:2,posX:0.92,posY:0.08,total:1,pressure:40,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        _ = engine.process(leftHand:true,now:1.02,contacts:left+[extra],settings:settings)
        _ = engine.process(leftHand:true,now:1.03,contacts:left,settings:settings)
        for i in 1...8 {
            let time = 1.03+Double(i)*0.1
            XCTAssertNil(engine.process(leftHand:true,now:time,contacts:left,settings:settings).trigger)
            XCTAssertNil(engine.process(leftHand:false,now:time+0.001,contacts:right,settings:settings).trigger)
        }
        XCTAssertFalse(engine.maintainsHeldOutput)
    }
    func testNewCornerAssignmentsAndThresholdsRoundTripWithHeldNamedShortcuts() throws {
        var settings = HandGestureSettings(), both = settings.twoHand
        var shortcut = KeyActionCatalog.action(for:"Shift")!; shortcut.customName = "Corner Shift"
        let action = GestureAction.shortcut(.init(label:shortcut.storageLabel,holdUntilRelease:true))
        for (i,chord) in TwoHandChord.allCases.enumerated() where chord.isCorner {
            both.setAction(action,for:.init(chord:chord,phase:.hold))
            both.setHoldThreshold(0.2+Double(i)*0.1,for:chord)
        }
        settings.coordinated = both
        var profile = AppKeymapProfile.defaultProfile(); profile.handGestureSettings = settings
        let imported = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
        XCTAssertEqual(imported.handGestureSettings,settings)
    }
    func testEachCoordinatedChordUsesItsConfiguredHoldThreshold() {
        for chord in TwoHandChord.allCases {
            for duration in [0.25,0.8] {
                var settings = settings(chord), engine = TwoHandGestureEngine()
                settings.setHoldThreshold(duration,for:chord)
                let left = chordContacts(chord,left:true)
                let right = chordContacts(chord,left:false)
                _ = engine.process(leftHand:true,now:0,contacts:left,settings:settings)
                XCTAssertTrue(engine.process(leftHand:false,now:0,contacts:right,settings:settings).began)
                for i in 1..<Int(duration*100) {
                    let time = Double(i)/100
                    XCTAssertNil(engine.process(leftHand:true,now:time,contacts:left,settings:settings).trigger)
                    XCTAssertNil(engine.process(leftHand:false,now:time,contacts:right,settings:settings).trigger)
                }
                XCTAssertEqual(engine.advance(now:duration+0.001,settings:settings),.init(chord:chord,phase:.hold))
                XCTAssertNil(engine.advance(now:duration+0.01,settings:settings))
            }
        }
    }
}

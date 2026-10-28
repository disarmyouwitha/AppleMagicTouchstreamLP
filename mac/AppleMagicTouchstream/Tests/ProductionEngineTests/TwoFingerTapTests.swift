import CoreGraphics
import Carbon
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

final class TwoFingerTapTests: XCTestCase {
    private func touch(_ id: Int32, _ x: Float = 0.3) -> OMSRawTouch {
        OMSRawTouch(id:id,posX:x,posY:0.5,total:1,pressure:100,majorAxis:5,minorAxis:3,
            angle:0,density:1,state:.touching)
    }
    private var pair: [OMSRawTouch] { [touch(1),touch(2,0.6)] }
    private var empty: [OMSRawTouch] { [] }
    func testEmojiRestoresModifiersBeforeFollowingTapClick() throws {
        for before:CGEventFlags in [[],.maskShift,.maskCommand,[.maskControl,.maskAlternate]] {
            let stroke = try XCTUnwrap(KeyboardStrokeOutput.events(code:CGKeyCode(kVK_Function),
                flags:[],restoringFlags:before))
            XCTAssertEqual(stroke.down.type,.keyDown)
            XCTAssertEqual(stroke.up.type,.keyUp)
            XCTAssertEqual(stroke.down.getIntegerValueField(.keyboardEventKeycode),Int64(kVK_Space))
            XCTAssertEqual(stroke.up.getIntegerValueField(.keyboardEventKeycode),Int64(kVK_Space))
            XCTAssertEqual(stroke.down.flags,[.maskCommand,.maskControl])
            XCTAssertEqual(stroke.up.flags,before)
            var clicks = PrimaryTapClickOutput()
            let click = try XCTUnwrap(clicks.events(location:.init(x:100,y:100),time:1,
                doubleClickInterval:0.5,flags:stroke.up.flags))
            XCTAssertEqual(click.down.flags,before)
            XCTAssertEqual(click.up.flags,before)
        }
    }
    func testCommandSRestoresModifiersBeforeFollowingTapClick() throws {
        // The user capture has one Cmd+S keyStroke followed by accepted taps.
        // Test the production event factory without posting to macOS.
        for before:CGEventFlags in [[],.maskShift,.maskCommand,[.maskControl,.maskAlternate]] {
            let stroke = try XCTUnwrap(KeyboardStrokeOutput.events(code:1,
                flags:before.union(.maskCommand),restoringFlags:before))
            XCTAssertEqual(stroke.down.type,.keyDown)
            XCTAssertEqual(stroke.up.type,.keyUp)
            XCTAssertEqual(stroke.down.getIntegerValueField(.keyboardEventKeycode),1)
            XCTAssertEqual(stroke.up.getIntegerValueField(.keyboardEventKeycode),1)
            XCTAssertTrue(stroke.down.flags.contains(.maskCommand))
            XCTAssertEqual(stroke.up.flags,before)
            var clicks = PrimaryTapClickOutput()
            let click = try XCTUnwrap(clicks.events(location:.init(x:100,y:100),time:1,
                doubleClickInterval:0.5,flags:stroke.up.flags))
            XCTAssertEqual(click.down.flags,before)
            XCTAssertEqual(click.up.flags,before)
        }
    }

    func testTwoFingerTapClicksOnlyOnceOnAllUpWithEitherFingerLiftingFirst() {
        for survivor: Int32 in [1,2] {
            var tap = TwoFingerTapRecognizer()
            XCTAssertFalse(tap.process(device:1,time:1,contacts:[touch(1)]))
            XCTAssertFalse(tap.process(device:1,time:1.03,contacts:pair))
            let remaining = survivor == 1 ? touch(1) : touch(2,0.6)
            XCTAssertFalse(tap.process(device:1,time:1.08,contacts:[remaining]))
            XCTAssertTrue(tap.process(device:1,time:1.1,contacts:empty))
            XCTAssertFalse(tap.process(device:1,time:1.11,contacts:empty))
        }
    }
    func testSingleFingerHoldLatePairExtraFingerAndMovementDoNotClick() {
        for kind in 0..<5 {
            var tap = TwoFingerTapRecognizer()
            _ = tap.process(device:1,time:1,contacts:kind == 0 || kind == 2 ? [touch(1)] : pair)
            switch kind {
            case 0: break
            case 1:
                _ = tap.process(device:1,time:1.1,contacts:pair)
                _ = tap.process(device:1,time:1.2,contacts:pair)
                _ = tap.process(device:1,time:1.3,contacts:pair)
                _ = tap.process(device:1,time:1.4,contacts:pair)
                _ = tap.process(device:1,time:1.5,contacts:pair)
                _ = tap.process(device:1,time:1.6,contacts:pair)
            case 2: _ = tap.process(device:1,time:1.1,contacts:pair)
            case 3: _ = tap.process(device:1,time:1.03,contacts:pair+[touch(3,0.8)])
            default:
                // Opposing motion has no centroid travel, but is not a tap.
                _ = tap.process(device:1,time:1.03,contacts:[touch(1,0.28),touch(2,0.62)])
            }
            XCTAssertFalse(tap.process(device:1,time:kind == 1 ? 1.61 : 1.12,contacts:empty),"kind=\(kind)")
        }
    }
    func testHalfSecondTapWindowIncludingReleaseBoundary() {
        for (release,accepted) in [(1.49,true),(1.5,true),(1.501,false)] {
            var tap = TwoFingerTapRecognizer()
            _ = tap.process(device:1,time:1,contacts:pair)
            for frame in [1.1,1.2,1.3,1.4] {
                XCTAssertFalse(tap.process(device:1,time:frame,contacts:pair))
            }
            XCTAssertEqual(tap.process(device:1,time:release,contacts:empty),accepted)
        }
    }

    func testLongStaggeredReleaseRejoinAndIdentityReplacementRejectTap() {
        for kind in 0..<3 {
            var tap = TwoFingerTapRecognizer()
            _ = tap.process(device:1,time:1,contacts:pair)
            _ = tap.process(device:1,time:1.04,contacts:[touch(1)])
            if kind == 1 { _ = tap.process(device:1,time:1.06,contacts:pair) }
            if kind == 2 { _ = tap.process(device:1,time:1.06,contacts:[touch(9)]) }
            XCTAssertFalse(tap.process(device:1,time:kind == 0 ? 1.14 : 1.08,contacts:empty))
        }
    }
    func testMovementRecognitionCancelsTapAndCannotClickWhenMousingEnds() {
        var tap = TwoFingerTapRecognizer()
        var router = TrackpadGestureRouter()
        for (time,contacts) in [(1.0,pair),(1.02,[touch(1,0.303),touch(2,0.603)]),(1.06,empty)] {
            let motion = router.process(device:1,time:time,contacts:contacts,mouse:true,scroll:true)
            XCTAssertFalse(tap.process(device:1,time:time,contacts:contacts,gestureActive:motion != nil))
        }
    }
    func testSmallLandingDriftStaysTapButClearMovementClaimsMouse() {
        for (offset,expectedClick) in [(Float(0.0015),true),(Float(0.003),false)] {
            var tap = TwoFingerTapRecognizer()
            var router = TrackpadGestureRouter()
            for (time,contacts) in [(1.0,pair),(1.04,[touch(1,0.3+offset),touch(2,0.6+offset)])] {
                let motion = router.process(device:1,time:time,contacts:contacts,mouse:true,scroll:true)
                XCTAssertFalse(tap.process(device:1,time:time,contacts:contacts,gestureActive:motion != nil))
            }
            let motion = router.process(device:1,time:1.08,contacts:empty,mouse:true,scroll:true)
            XCTAssertEqual(tap.process(device:1,time:1.08,contacts:empty,gestureActive:motion != nil),expectedClick)
        }
    }

    func testStaleInvalidDuplicateAndUnorderedFramesCannotClick() {
        for kind in 0..<4 {
            var tap = TwoFingerTapRecognizer()
            _ = tap.process(device:1,time:1,contacts:pair)
            switch kind {
            case 0: _ = tap.process(device:1,time:1.2,contacts:pair)
            case 1: _ = tap.process(device:1,time:1.02,contacts:[touch(1,.nan),touch(2)])
            case 2: _ = tap.process(device:1,time:1.02,contacts:[touch(1),touch(1)])
            default: _ = tap.process(device:1,time:1,contacts:pair)
            }
            XCTAssertFalse(tap.process(device:1,time:1.22,contacts:empty))
        }
    }
    func testCancellationBlocksUntilAllUpButIdleWatchdogDoesNotEatNextTap() {
        var tap = TwoFingerTapRecognizer()
        tap.invalidate(device:1) // no pending tap; inactive status watchdog
        _ = tap.process(device:1,time:1,contacts:pair)
        XCTAssertTrue(tap.process(device:1,time:1.06,contacts:empty))
        _ = tap.process(device:1,time:2,contacts:pair)
        tap.reset() // feature/selection/lifecycle cancellation
        _ = tap.process(device:1,time:2.03,contacts:pair)
        XCTAssertFalse(tap.process(device:1,time:2.06,contacts:empty))
        tap.cancel(device:1) // physical button or touch braking momentum
        _ = tap.process(device:1,time:3,contacts:pair)
        XCTAssertFalse(tap.process(device:1,time:3.06,contacts:empty))
        _ = tap.process(device:1,time:4,contacts:pair)
        XCTAssertTrue(tap.process(device:1,time:4.06,contacts:empty))
    }
    func testPadsAreIndependentAndShortBounceDoesNotClick() {
        var tap = TwoFingerTapRecognizer()
        _ = tap.process(device:1,time:1,contacts:pair)
        _ = tap.process(device:2,time:1.01,contacts:[touch(1)])
        XCTAssertFalse(tap.process(device:2,time:1.06,contacts:empty))
        XCTAssertTrue(tap.process(device:1,time:1.07,contacts:empty))
        _ = tap.process(device:1,time:2,contacts:pair)
        XCTAssertFalse(tap.process(device:1,time:2.005,contacts:empty))
    }
    func testClickEdgesLocationFlagsTagAndDoubleClickCountWithoutPosting() throws {
        var output = PrimaryTapClickOutput()
        let point = CGPoint(x:120,y:230)
        let first = try XCTUnwrap(output.events(location:point,time:1,doubleClickInterval:0.5,flags:.maskShift))
        XCTAssertEqual(first.down.type,.leftMouseDown); XCTAssertEqual(first.up.type,.leftMouseUp)
        XCTAssertEqual(first.down.location,point); XCTAssertEqual(first.up.location,point)
        XCTAssertEqual(first.down.flags,.maskShift); XCTAssertEqual(first.up.flags,.maskShift)
        XCTAssertEqual(first.down.getIntegerValueField(.mouseEventButtonNumber),0)
        XCTAssertEqual(first.up.getIntegerValueField(.mouseEventButtonNumber),0)
        XCTAssertEqual(first.down.getIntegerValueField(.eventSourceUserData),SelectedTrackpadEventPolicy.interpreterTag)
        XCTAssertEqual(first.up.getDoubleValueField(.mouseEventPressure),0)
        XCTAssertEqual(first.down.getIntegerValueField(.mouseEventClickState),1)
        let second = try XCTUnwrap(output.events(location:point,time:1.2,doubleClickInterval:0.5,flags:.maskShift))
        XCTAssertEqual(second.down.getIntegerValueField(.mouseEventClickState),2)
        XCTAssertEqual(second.up.getIntegerValueField(.mouseEventClickState),2)
        XCTAssertEqual(output.events(location:point,time:1.3,doubleClickInterval:0.5)?.down.getIntegerValueField(.mouseEventClickState),1)
        XCTAssertEqual(output.events(location:CGPoint(x:200,y:300),time:1.4,doubleClickInterval:0.5)?.down.getIntegerValueField(.mouseEventClickState),1)
        output.reset()
        XCTAssertEqual(output.events(location:point,time:1.5,doubleClickInterval:0.5)?.down.getIntegerValueField(.mouseEventClickState),1)
    }
}

@MainActor
final class OneFingerForceClickTests: XCTestCase {
    private func touch(_ pressure: Float, id: Int32 = 1) -> OMSRawTouch {
        OMSRawTouch(id:id,posX:0.5,posY:0.5,total:1,pressure:pressure,
            majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
    }
    func testThresholdClicksOnceUntilAllUpAndPadsAreIndependent() {
        var recognizer = ForceClickRecognizer()
        XCTAssertFalse(recognizer.process(device:1,time:1,contacts:[touch(129)]))
        XCTAssertTrue(recognizer.process(device:1,time:1.01,contacts:[touch(130)]))
        XCTAssertFalse(recognizer.process(device:1,time:1.02,contacts:[touch(180)]))
        XCTAssertFalse(recognizer.process(device:1,time:1.03,contacts:[touch(50)]))
        XCTAssertFalse(recognizer.process(device:1,time:1.04,contacts:[touch(130)]))
        XCTAssertTrue(recognizer.process(device:2,time:1.04,contacts:[touch(130)]))
        XCTAssertFalse(recognizer.process(device:1,time:1.05,contacts:[OMSRawTouch]()))
        XCTAssertTrue(recognizer.process(device:1,time:1.06,contacts:[touch(130)]))
    }
    func testMultiFingerSurvivorsReplacementStaleAndInvalidFramesCannotClick() {
        for mode in 0..<5 {
            var recognizer = ForceClickRecognizer()
            XCTAssertFalse(recognizer.process(device:1,time:1,contacts:[touch(20)]))
            switch mode {
            case 0: XCTAssertFalse(recognizer.process(device:1,time:1.01,contacts:[touch(20),touch(20,id:2)]))
            case 1: XCTAssertFalse(recognizer.process(device:1,time:1.01,contacts:[touch(20,id:2)]))
            case 2: XCTAssertFalse(recognizer.process(device:1,time:0.99,contacts:[touch(130)]))
            case 3: XCTAssertFalse(recognizer.process(device:1,time:1.3,contacts:[touch(130)]))
            default: XCTAssertFalse(recognizer.process(device:1,time:1.01,contacts:[touch(.nan)]))
            }
            XCTAssertFalse(recognizer.process(device:1,time:1.31,contacts:[touch(130)]))
            XCTAssertFalse(recognizer.process(device:1,time:1.32,contacts:[OMSRawTouch]()))
            XCTAssertTrue(recognizer.process(device:1,time:1.33,contacts:[touch(130)]))
            recognizer.reset()
            XCTAssertFalse(recognizer.process(device:1,time:1.34,contacts:[touch(130)]))
        }
    }
    func testPressureClaimsKeyboardThroughReleaseWithoutReservingOrdinaryTyping() {
        var arbitration = GestureKeyboardArbitration()
        XCTAssertFalse(arbitration.process(device:1,activeCount:1) { _ in false })
        XCTAssertTrue(arbitration.process(device:1,activeCount:1,forceClick:true) { _ in false })
        XCTAssertFalse(arbitration.process(device:2,activeCount:1) { _ in false })
        XCTAssertTrue(arbitration.process(device:1,activeCount:1) { _ in false })
        XCTAssertTrue(arbitration.process(device:1,activeCount:0) { _ in false })
        XCTAssertFalse(arbitration.process(device:1,activeCount:1) { _ in false })
    }
}

private extension ForceClickRecognizer {
    mutating func process<C: Collection>(device:UInt64,time:Double,contacts:C) -> Bool where C.Element == OMSRawTouch {
        recognize(device:device,time:time,contacts:contacts,enabled:{$0 == .oneFingerForce}) != nil
    }
}

@MainActor
final class ConfigurableForceClickTests: XCTestCase {
    private func contacts(_ count:Int, pressure:Float = 20) -> [OMSRawTouch] {
        (0..<count).map { id in
            OMSRawTouch(id:Int32(id+1),posX:0.2+Float(id)*0.1,posY:0.5,total:1,pressure:pressure,
                majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        }
    }
    func testEveryCountDispatchesItsAssignedTapActionAndCannotRepeatOrBecomeATap() throws {
        for count in 1...5 {
            for action in [GestureAction.primaryClick,.primaryDoubleClick,.secondaryClick] {
                var recognizer = ForceClickRecognizer(), settings = HandGestureSettings(), clicks = PrimaryTapClickOutput()
                let trigger = try XCTUnwrap(GestureTrigger.force(count:count))
                settings.setAction(action,for:trigger,in:.left)
                let bindings = settings.left.bindings
                XCTAssertNil(recognizer.recognize(device:1,time:1,contacts:contacts(count),enabled:{bindings.action(for:$0) != .disabled}))
                let recognized = try XCTUnwrap(recognizer.recognize(device:1,time:1.01,contacts:contacts(count,pressure:130),enabled:{bindings.action(for:$0) != .disabled}))
                XCTAssertEqual(recognized,trigger)
                let events = try XCTUnwrap(GestureTapActionOutput.events(action:bindings.action(for:recognized),location:CGPoint(x:100,y:100),time:1.01,doubleClickInterval:0.5,clicks:&clicks))
                XCTAssertEqual(events.map(\.type),action == .secondaryClick ? [.rightMouseDown,.rightMouseUp] : action == .primaryDoubleClick ? [.leftMouseDown,.leftMouseUp,.leftMouseDown,.leftMouseUp] : [.leftMouseDown,.leftMouseUp])
                XCTAssertNil(recognizer.recognize(device:1,time:1.02,contacts:contacts(1,pressure:180),enabled:{_ in true}))
                XCTAssertTrue(recognizer.claimed(device:1))
                XCTAssertNil(recognizer.recognize(device:1,time:1.03,contacts:[OMSRawTouch](),enabled:{_ in true}))
                XCTAssertFalse(recognizer.claimed(device:1))
                XCTAssertEqual(recognizer.recognize(device:1,time:1.04,contacts:contacts(count,pressure:130),enabled:{_ in true}),trigger)
            }
        }
    }
    func testAddingBeforePressIsAllowedButLiftingDuplicateIDsAndSixFingersBlock() {
        var recognizer = ForceClickRecognizer()
        XCTAssertNil(recognizer.recognize(device:1,time:1,contacts:contacts(1),enabled:{_ in true}))
        XCTAssertNil(recognizer.recognize(device:1,time:1.01,contacts:contacts(3),enabled:{_ in true}))
        XCTAssertEqual(recognizer.recognize(device:1,time:1.02,contacts:contacts(3,pressure:130),enabled:{_ in true}),.threeFingerForce)
        for malformed in [contacts(3),contacts(6),[contacts(1)[0],contacts(1)[0]]] {
            var invalid = ForceClickRecognizer()
            XCTAssertNil(invalid.recognize(device:1,time:1,contacts:malformed,enabled:{_ in true}))
            XCTAssertNil(invalid.recognize(device:1,time:1.01,contacts:contacts(2,pressure:130),enabled:{_ in true}))
        }
    }
    func testDisabledCountCannotTriggerFeedbackOrBorrowAnotherHandsForceAction() throws {
        for count in 1...5 {
            var settings = HandGestureSettings()
            let trigger = try XCTUnwrap(GestureTrigger.force(count: count))
            settings.setAction(.disabled, for: trigger, in: .left)
            settings.setAction(.primaryClick, for: trigger, in: .right)
            var recognizer = ForceClickRecognizer()
            // Feedback is emitted only from a returned force trigger in live output.
            for step in 0..<5 {
                XCTAssertNil(recognizer.recognize(device: 1, time: 1 + Double(step) * 0.01,
                    contacts: contacts(count, pressure: 180),
                    enabled: { settings.left.bindings.action(for: $0) != .disabled }))
                XCTAssertFalse(recognizer.claimed(device: 1))
            }
            XCTAssertEqual(recognizer.recognize(device: 2, time: 1,
                contacts: contacts(count, pressure: 180),
                enabled: { settings.right.bindings.action(for: $0) != .disabled }), trigger)
        }
    }

    func testDisabledForceDoesNotClaimAndOneHighContactIsEnoughWithoutSummingPressure() {
        var recognizer = ForceClickRecognizer()
        XCTAssertNil(recognizer.recognize(device:1,time:1,contacts:contacts(5,pressure:130),enabled:{_ in false}))
        XCTAssertFalse(recognizer.claimed(device:1))
        var next = ForceClickRecognizer()
        XCTAssertNil(next.recognize(device:1,time:1,contacts:contacts(5,pressure:30),enabled:{_ in true}))
        var press = contacts(5)
        press[4] = OMSRawTouch(id:5,posX:0.6,posY:0.5,total:5,pressure:130,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        XCTAssertEqual(next.recognize(device:1,time:1.01,contacts:press,enabled:{_ in true}),.fiveFingerForce)
    }
}

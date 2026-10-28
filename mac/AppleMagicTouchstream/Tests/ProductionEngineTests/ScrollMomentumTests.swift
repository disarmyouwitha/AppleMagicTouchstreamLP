import AppKit
import CoreGraphics
import XCTest
import OpenMultitouchSupport
@testable import GlassToKeyRuntime

final class ScrollMomentumTests: XCTestCase {
    private func flick(_ point: CGPoint = CGPoint(x:0,y:10)) -> ScrollMomentum {
        var momentum = ScrollMomentum()
        momentum.observe(points:.zero,contactTime:0.99)
        for i in 0..<8 { momentum.observe(points:point,contactTime:1+Double(i)*0.01) }
        return momentum
    }
    private func contact(_ id:Int32 = 1,state:OMSState = .touching) -> OMSRawTouch {
        OMSRawTouch(id:id,posX:0.3+Float(id)*0.1,posY:0.5,total:1,pressure:40,
            majorAxis:5,minorAxis:3,angle:0,density:1,state:state)
    }

    func testEitherPadBrakesEveryReleasedCoastWithOneBalancedEnd() throws {
        for source:UInt64 in [1,2] {
            var momentum:[UInt64:ScrollMomentum] = [1:flick(),2:flick()]
            var outputs:[UInt64:PreciseScrollOutput] = [1:.init(),2:.init()]
            for owner:UInt64 in [1,2] {
                _ = outputs[owner]?.event(points:.init(x:0,y:1))
                XCTAssertTrue(momentum[owner]!.start(contactTime:1.071,hostTime:10))
                _ = outputs[owner]?.finish(cancelled:false,preserveForMomentum:true)
                _ = outputs[owner]?.event(points:.init(x:0,y:1),momentum:true)
            }
            var ended:[CGEvent] = []
            XCTAssertTrue(ScrollMomentumInterruption.process(device:source,contacts:[contact()],selected:[1,2],
                momentum:&momentum,outputs:&outputs,endMomentum:{ended.append($0)}))
            XCTAssertEqual(ended.count,2)
            for event in ended { XCTAssertEqual(try XCTUnwrap(NSEvent(cgEvent:event)).momentumPhase,.ended) }
            for owner:UInt64 in [1,2] {
                XCTAssertFalse(momentum[owner]!.isCoasting)
                XCTAssertNil(momentum[owner]?.advance(hostTime:10.01))
                XCTAssertFalse(outputs[owner]!.momentumActive)
            }
            XCTAssertFalse(ScrollMomentumInterruption.process(device:source,contacts:[contact()],selected:[1,2],
                momentum:&momentum,outputs:&outputs,endMomentum:{_ in XCTFail("Duplicate end")}))
        }
    }

    func testTerminalHoverAndUnselectedFramesDoNotBrakeOrCancelPhysicalScroll() throws {
        var momentum:[UInt64:ScrollMomentum] = [1:flick(),2:.init()]
        XCTAssertTrue(momentum[1]!.start(contactTime:1.071,hostTime:10))
        var outputs:[UInt64:PreciseScrollOutput] = [1:.init(),2:.init()]
        _ = outputs[1]?.event(points:.init(x:0,y:1),momentum:true)
        _ = outputs[2]?.event(points:.init(x:0,y:1)) // Still under fingers, not a coast.
        for (source,touches) in [(UInt64(2),[OMSRawTouch]()),(2,[contact(state:.breaking)]),
                                  (2,[contact(state:.hovering)]),(99,[contact()])] {
            XCTAssertFalse(ScrollMomentumInterruption.process(device:source,contacts:touches,selected:[1,2],
                momentum:&momentum,outputs:&outputs,endMomentum:{_ in XCTFail("Not an eligible contact")}))
            XCTAssertTrue(momentum[1]!.isCoasting)
        }
        var ends = 0
        XCTAssertFalse(ScrollMomentumInterruption.process(device:2,contacts:[contact()],selected:[1,2],
            momentum:&momentum,outputs:&outputs,endMomentum:{_ in ends += 1}))
        XCTAssertEqual(ends,1)
        XCTAssertFalse(momentum[1]!.isCoasting)
        XCTAssertTrue(outputs[2]!.active)
        XCTAssertNotNil(outputs[2]?.event(points:.init(x:0,y:1)))
    }

    func testOtherPadKeepsTapEligibilityAndCoastCanBeCancelledBeforeItsFirstTick() throws {
        for source:UInt64 in [1,2] {
            var momentum:[UInt64:ScrollMomentum] = [1:flick()]
            var outputs:[UInt64:PreciseScrollOutput] = [1:.init()]
            XCTAssertTrue(momentum[1]!.start(contactTime:1.071,hostTime:10))
            _ = outputs[1]?.event(points:.init(x:0,y:1))
            _ = outputs[1]?.finish(cancelled:false,preserveForMomentum:true)
            let consumed = ScrollMomentumInterruption.process(device:source,contacts:[contact()],selected:[1,2],
                momentum:&momentum,outputs:&outputs,endMomentum:{_ in XCTFail("No momentum begin was emitted")} )
            XCTAssertEqual(consumed,source == 1)
            XCTAssertNil(momentum[1]?.advance(hostTime:10.01))
            var tap = TwoFingerTapRecognizer()
            let pair = [contact(),contact(2)]
            _ = tap.process(device:source,time:1,contacts:pair,gestureActive:consumed)
            _ = tap.process(device:source,time:1.04,contacts:pair,gestureActive:consumed)
            XCTAssertEqual(tap.process(device:source,time:1.06,contacts:[OMSRawTouch](),gestureActive:consumed),source == 2)
        }
    }

    func testCapturedOtherHandContactStopsMomentumBeforePointerMovement() throws {
        struct Fixture:Decodable {
            struct Sample:Decodable { let frame:RuntimeRawFrame; let arrivalTicks:Int64 }
            let frames:[Sample]
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource:"cross-pad-momentum",withExtension:"json",subdirectory:"Fixtures"))
        let fixture = try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:url))
        let right:UInt64 = 288230377507875157, left:UInt64 = 288230377507812716
        let axis = try ApplePointerAccelerationProfile(resolution:400,acceleration:0,
            curves:[ApplePointerCurve(index:0,linear:1,parabolic:1)])
        var referenceMoves:[CGPoint] = []
        for crossPad in [false,true] {
            var router = TrackpadGestureRouter(), scroll = FourFingerScrollEngine(profile:.init(horizontal:axis,vertical:axis,natural:true))
            var momentum:[UInt64:ScrollMomentum] = [right:.init()]
            var outputs:[UInt64:PreciseScrollOutput] = [right:.init()]
            var overlap = 0, coasts = 0, ends:[UInt64] = [], moves:[CGPoint] = []
            var tick = Double(fixture.frames[0].arrivalTicks)/1e9
            for sample in fixture.frames {
                let f = sample.frame, now = Double(sample.arrivalTicks)/1e9
                while tick+1/120 < now {
                    tick += 1/120
                    if let step = momentum[right]?.advance(hostTime:tick) {
                        _ = outputs[right]?.event(points:step.points,momentum:true)
                        if step.finished { _ = outputs[right]?.finishMomentum() }
                    }
                }
                _ = ScrollMomentumInterruption.process(device:f.deviceNumericID,contacts:f.rawTouches,
                    selected:crossPad ? [left,right] : [f.deviceNumericID],momentum:&momentum,outputs:&outputs,
                    endMomentum:{_ in ends.append(f.sequence)})
                if f.deviceNumericID == left && f.rawTouches.contains(where:{$0.state == .making || $0.state == .touching}) && momentum[right]!.isCoasting { overlap += 1 }
                let update = router.recognize(device:f.deviceNumericID,time:f.timestamp,contacts:f.rawTouches,
                    enabled:{$0 == .twoFingerMove || $0 == .fourFingerMove})
                if update.gesture == .fourFingerMove {
                    if update.phase == .ended {
                        let coast = momentum[right]!.start(contactTime:f.timestamp,hostTime:now)
                        if coast { coasts += 1; tick = now }
                        _ = outputs[right]?.finish(cancelled:false,preserveForMomentum:coast)
                        scroll.reset()
                    } else if let delta = update.millimetres,
                              let points = scroll.process(time:f.timestamp,millimetres:delta,sensitivity:1) {
                        _ = outputs[right]?.event(points:points)
                        momentum[right]?.observe(points:points,contactTime:f.timestamp)
                    }
                } else if update.gesture == .twoFingerMove, f.deviceNumericID == left, let delta = update.millimetres { moves.append(delta) }
            }
            XCTAssertEqual(coasts,2)
            XCTAssertFalse(moves.isEmpty)
            if crossPad {
                XCTAssertEqual(overlap,0)
                XCTAssertEqual(ends,[13523,13623]) // First left contacts, before pointer recognition.
                XCTAssertEqual(moves,referenceMoves) // No reset or altered mouse acquisition/deltas.
                XCTAssertFalse(momentum[right]!.isCoasting)
            } else {
                XCTAssertGreaterThan(overlap,0) // Reproduces the previous same-pad-only policy.
                referenceMoves = moves
            }
        }
    }
    func testFlickCoastsDecaysAndTerminatesWithoutReversing() throws {
        var momentum = flick(CGPoint(x:3,y:-10))
        XCTAssertTrue(momentum.start(contactTime:1.071,hostTime:10))
        var previous = Double.infinity, total = CGPoint.zero
        for i in 1...400 {
            guard let step = momentum.advance(hostTime:10+Double(i)/120) else { break }
            XCTAssertGreaterThanOrEqual(step.points.x,0)
            XCTAssertLessThanOrEqual(step.points.y,0)
            let length = hypot(step.points.x,step.points.y)
            XCTAssertLessThanOrEqual(length,previous+1e-9)
            previous = length
            total.x += step.points.x; total.y += step.points.y
        }
        XCTAssertFalse(momentum.isCoasting)
        XCTAssertGreaterThan(abs(total.y),250)
        XCTAssertLessThan(abs(total.y),350)
        XCTAssertNil(momentum.advance(hostTime:14))
    }
    func testCoastIntegralDoesNotDependOnTickFrequency() throws {
        func integrate(_ hz: Double) throws -> Double {
            var momentum = flick()
            XCTAssertTrue(momentum.start(contactTime:1.071,hostTime:10))
            var total = 0.0
            for i in 1...Int(hz*0.5) {
                total += try XCTUnwrap(momentum.advance(hostTime:10+Double(i)/hz)).points.y
            }
            return total
        }
        XCTAssertEqual(try integrate(60),try integrate(120),accuracy:1e-8)
    }
    func testSlowMovementPausedLiftAndOldLiftDoNotCoast() {
        var slow = flick(CGPoint(x:0,y:0.1))
        XCTAssertFalse(slow.start(contactTime:1.071,hostTime:10))
        var old = flick()
        XCTAssertFalse(old.start(contactTime:1.2,hostTime:10))
        var paused = flick()
        for i in 0..<10 { paused.observe(points:.zero,contactTime:1.08+Double(i)*0.01) }
        XCTAssertFalse(paused.start(contactTime:1.171,hostTime:10))
    }
    func testReversalTracksNewDirectionAndCancellationDiscardsVelocity() throws {
        var momentum = flick()
        momentum.observe(points:.zero,contactTime:1.08)
        momentum.observe(points:CGPoint(x:0,y:-10),contactTime:1.09)
        XCTAssertTrue(momentum.start(contactTime:1.091,hostTime:10))
        XCTAssertLessThan(try XCTUnwrap(momentum.advance(hostTime:10.01)).points.y,0)
        momentum.cancel() // new touch, disable, ownership/lifecycle reset
        XCTAssertFalse(momentum.isCoasting)
        XCTAssertNil(momentum.advance(hostTime:10.02))
        XCTAssertFalse(momentum.start(contactTime:1.092,hostTime:11))
    }
    func testStalledOrInvalidTimerEndsWithoutCatchUpJump() throws {
        for next in [10.2,Double.nan,9.9,10] {
            var momentum = flick()
            XCTAssertTrue(momentum.start(contactTime:1.071,hostTime:10))
            let end = try XCTUnwrap(momentum.advance(hostTime:next))
            XCTAssertTrue(end.finished)
            XCTAssertEqual(end.points,.zero)
            XCTAssertFalse(momentum.isCoasting)
        }
    }
    func testPadsHaveIndependentCoastsAndMaximumVelocityIsBounded() throws {
        var left = flick(CGPoint(x:100,y:100)), right = flick(CGPoint(x:0,y:-5))
        XCTAssertTrue(left.start(contactTime:1.071,hostTime:10))
        XCTAssertTrue(right.start(contactTime:1.071,hostTime:10))
        let fast = try XCTUnwrap(left.advance(hostTime:10+1/120))
        XCTAssertLessThan(hypot(fast.points.x,fast.points.y),51)
        left.cancel()
        XCTAssertNotNil(right.advance(hostTime:10.01))
        XCTAssertTrue(right.isCoasting)
    }
    func testPhysicalEndMomentumPhasesAndInterruptionWithoutPosting() throws {
        var output = PreciseScrollOutput()
        let physical = try XCTUnwrap(output.event(points:CGPoint(x:0,y:0.25)))
        XCTAssertEqual(try XCTUnwrap(NSEvent(cgEvent:physical)).phase,.began)
        let location = physical.location
        XCTAssertEqual(output.finish(cancelled:false,preserveForMomentum:true)?.getIntegerValueField(.scrollWheelEventScrollPhase),4)
        let begin = try XCTUnwrap(output.event(points:CGPoint(x:0,y:0.25),momentum:true))
        let cocoa = try XCTUnwrap(NSEvent(cgEvent:begin))
        XCTAssertEqual(cocoa.phase,[])
        XCTAssertEqual(cocoa.momentumPhase,.began)
        XCTAssertEqual(begin.location,location)
        XCTAssertTrue(cocoa.hasPreciseScrollingDeltas)
        let change = try XCTUnwrap(output.event(points:CGPoint(x:0,y:0.5),momentum:true))
        XCTAssertEqual(try XCTUnwrap(NSEvent(cgEvent:change)).momentumPhase,.changed)
        // The quarter-pixel physical remainder survives into momentum: 0.25+0.25+0.5 = 1.
        XCTAssertEqual(change.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),1)
        XCTAssertNil(output.event(points:CGPoint(x:0,y:1))) // physical must end momentum first
        let end = try XCTUnwrap(output.finishMomentum())
        XCTAssertEqual(end.getIntegerValueField(.scrollWheelEventMomentumPhase),3)
        XCTAssertEqual(try XCTUnwrap(NSEvent(cgEvent:end)).momentumPhase,.ended)
        XCTAssertNil(output.finishMomentum())
        XCTAssertFalse(output.momentumActive)
        XCTAssertEqual(output.event(points:CGPoint(x:0,y:-1))?.getIntegerValueField(.scrollWheelEventScrollPhase),1)
    }
}

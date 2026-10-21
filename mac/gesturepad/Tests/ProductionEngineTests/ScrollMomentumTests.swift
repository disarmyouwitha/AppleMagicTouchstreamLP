import AppKit
import CoreGraphics
import XCTest
@testable import GesturePadRuntime

final class ScrollMomentumTests: XCTestCase {
    private func flick(_ point: CGPoint = CGPoint(x:0,y:10)) -> ScrollMomentum {
        var momentum = ScrollMomentum()
        momentum.observe(points:.zero,contactTime:0.99)
        for i in 0..<8 { momentum.observe(points:point,contactTime:1+Double(i)*0.01) }
        return momentum
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

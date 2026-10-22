import CoreGraphics
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

final class GestureSessionEngineTests: XCTestCase {
    // Deliberately unrelated to mouse/scroll: adding an owner needs no engine branch.
    private enum Gesture: Hashable, Sendable { case pan, rotate, scrub }
    private func touches(_ count: Int, _ offset: Float = 0, idBase: Int32 = 0) -> [OMSRawTouch] {
        (0..<count).map { i in
            OMSRawTouch(id:idBase+Int32(i+1),posX:0.1+Float(i)*0.1+offset,posY:0.5,
                total:1,pressure:100,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        }
    }
    private func engine() -> GestureSessionEngine<Gesture> {
        GestureSessionEngine(rules:[
            GestureActivationRule(gesture:.pan,activationCount:2,minimumMovementMM:0.35),
            GestureActivationRule(gesture:.rotate,activationCount:3,minimumMovementMM:0.2),
            GestureActivationRule(gesture:.scrub,activationCount:4,minimumMovementMM:0.2)
        ])
    }
    func testArbitraryGestureOwnsAllPositiveCountsUntilSingleCompletion() {
        var engine = engine()
        XCTAssertEqual(engine.process(device:1,time:1,touches:touches(3),enabled:{ _ in true }).phase,.pending)
        let began = engine.process(device:1,time:1.01,touches:touches(3,0.003),enabled:{ _ in true })
        XCTAssertEqual(began.phase,.began); XCTAssertEqual(began.gesture,.rotate)
        for (i,count) in [4,1,2,3].enumerated() {
            let changed = engine.process(device:1,time:1.02+Double(i)*0.01,
                touches:touches(count,0.004+Float(i)*0.001),enabled:{ _ in true })
            XCTAssertEqual(changed.phase,.changed); XCTAssertEqual(changed.gesture,.rotate)
        }
        let ended = engine.process(device:1,time:1.07,touches:touches(0),enabled:{ _ in true })
        XCTAssertEqual(ended.phase,.ended); XCTAssertEqual(ended.gesture,.rotate)
        XCTAssertNil(ended.millimetres); XCTAssertNil(ended.cancellation)
        XCTAssertEqual(engine.process(device:1,time:1.08,touches:touches(0),enabled:{ _ in true }).phase,.pending)
    }
    func testRulePriorityAndDisabledCandidateDoNotOverrideOwner() {
        var engine = GestureSessionEngine<Gesture>(rules:[
            GestureActivationRule(gesture:.rotate,activationCount:2,minimumMovementMM:0.2),
            GestureActivationRule(gesture:.pan,activationCount:2,minimumMovementMM:0.2)
        ])
        _ = engine.process(device:1,time:1,touches:touches(2),enabled:{ _ in true })
        XCTAssertEqual(engine.process(device:1,time:1.01,touches:touches(2,0.003),enabled:{ _ in true }).gesture,.rotate)
        engine.reset()
        _ = engine.process(device:1,time:2,touches:touches(2),enabled:{ $0 != .rotate })
        XCTAssertEqual(engine.process(device:1,time:2.01,touches:touches(2,0.003),enabled:{ $0 != .rotate }).gesture,.pan)
        XCTAssertEqual(engine.process(device:1,time:2.02,touches:touches(2,0.004),enabled:{ _ in true }).gesture,.pan)
    }
    func testIndependentPadsAndExplicitCancellation() {
        var engine = engine()
        _ = engine.process(device:1,time:1,touches:touches(2),enabled:{ _ in true })
        _ = engine.process(device:2,time:1,touches:touches(4),enabled:{ _ in true })
        XCTAssertEqual(engine.process(device:1,time:1.01,touches:touches(2,0.003),enabled:{ _ in true }).gesture,.pan)
        XCTAssertEqual(engine.process(device:2,time:1.01,touches:touches(4,0.003),enabled:{ _ in true }).gesture,.scrub)
        let cancel = engine.cancel(device:1)
        XCTAssertEqual(cancel.phase,.cancelled); XCTAssertEqual(cancel.gesture,.pan)
        XCTAssertEqual(cancel.cancellation,.explicitReset)
        XCTAssertEqual(engine.process(device:2,time:1.02,touches:touches(1,0.004),enabled:{ _ in true }).gesture,.scrub)
        XCTAssertNil(engine.process(device:1,time:1.02,touches:touches(1,0.004),enabled:{ _ in true }).gesture)
    }
    func testContinuationPolicyAndFeatureDisableHaveExplicitCancellation() {
        var engine = GestureSessionEngine<Gesture>(rules:[
            GestureActivationRule(gesture:.rotate,activationCount:3,minimumMovementMM:0.2,continuation:.contactCount(2...4))
        ])
        _ = engine.process(device:1,time:1,touches:touches(3),enabled:{ _ in true })
        _ = engine.process(device:1,time:1.01,touches:touches(3,0.003),enabled:{ _ in true })
        let rejected = engine.process(device:1,time:1.02,touches:touches(1,0.004),enabled:{ _ in true })
        XCTAssertEqual(rejected.phase,.cancelled); XCTAssertEqual(rejected.cancellation,.continuationRejected)
        engine.reset()
        _ = engine.process(device:1,time:2,touches:touches(3),enabled:{ _ in true })
        _ = engine.process(device:1,time:2.01,touches:touches(3,0.003),enabled:{ _ in true })
        let disabled = engine.process(device:1,time:2.02,touches:touches(3,0.004),enabled:{ _ in false })
        XCTAssertEqual(disabled.phase,.cancelled); XCTAssertEqual(disabled.cancellation,.disabled)
    }
    func testDiscontinuitiesCancelAndAreNotNormalCompletion() {
        for kind in 0..<4 {
            var engine = engine()
            _ = engine.process(device:1,time:1,touches:touches(2),enabled:{ _ in true })
            _ = engine.process(device:1,time:1.01,touches:touches(2,0.003),enabled:{ _ in true })
            let result: GestureSessionUpdate<Gesture>
            switch kind {
            case 0: result = engine.process(device:1,time:2,touches:touches(0),enabled:{ _ in true })
            case 1: result = engine.process(device:1,time:1.01,touches:touches(2),enabled:{ _ in true })
            case 2: result = engine.process(device:1,time:1.02,touches:touches(2,idBase:10),enabled:{ _ in true })
            default: result = engine.process(device:1,time:1.02,touches:touches(2,.nan),enabled:{ _ in true })
            }
            XCTAssertEqual(result.phase,.cancelled); XCTAssertEqual(result.gesture,.pan)
            XCTAssertEqual(result.cancellation,.contactDiscontinuity)
        }
    }
    func testRecognizerSpecificActivationFilterIsSeparateFromContinuation() {
        var engine = engine()
        _ = engine.process(device:1,time:1,touches:touches(3),enabled:{ _ in true })
        let pending = engine.process(device:1,time:1.01,touches:touches(3,0.003),
            enabled:{ _ in true },activationFilter:{ _,context in
                XCTAssertEqual(context.activeCount,3)
                XCTAssertGreaterThan(context.pendingMovementMM.x,0.2)
                return false
            })
        XCTAssertEqual(pending.phase,.pending)
        XCTAssertEqual(engine.process(device:1,time:1.02,touches:touches(3,0.004),
            enabled:{ _ in true },activationFilter:{ _,_ in true }).phase,.began)
        // Activation no longer gates a recognized gesture's continuation.
        XCTAssertEqual(engine.process(device:1,time:1.03,touches:touches(1,0.005),
            enabled:{ _ in true },activationFilter:{ _,_ in false }).phase,.changed)
    }

    func testLandingMembershipChangeCannotCreateMotionOrCountBasedHandoff() throws {
        var engine = engine()
        _ = engine.process(device:1,time:1,touches:touches(2),enabled:{ _ in true })
        _ = engine.process(device:1,time:1.01,touches:touches(2,0.003),enabled:{ _ in true })
        let joined = engine.process(device:1,time:1.02,touches:touches(4,0.004),enabled:{ _ in true })
        XCTAssertEqual(joined.gesture,.pan); XCTAssertEqual(joined.phase,.changed)
        XCTAssertEqual(try XCTUnwrap(joined.millimetres).x,0.16,accuracy:0.0001)
    }
}

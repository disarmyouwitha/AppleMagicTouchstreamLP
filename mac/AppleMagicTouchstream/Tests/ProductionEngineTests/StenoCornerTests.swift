import Foundation
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

final class StenoCornerTests:XCTestCase {
    private func touch(_ id:Int32,_ x:Float,_ y:Float) -> OMSRawTouch {
        .init(id:id,posX:x,posY:y,total:1,pressure:40,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
    }
    func testStenoCornerPolicyKeepsOnlyOpenConfigAndPreservesSavedHoldThreshold() {
        var saved = TwoHandGestureSettings()
        saved.setAction(.showDesktop,for:.init(chord:.fourCorners,phase:.hold))
        saved.setAction(.secondaryClick,for:.init(chord:.innerCorners,phase:.hold))
        saved.setHoldThreshold(0.7,for:.fourCorners)
        let config = saved.stenoConfigurationOnly
        XCTAssertEqual(saved.action(.init(chord:.fourCorners,phase:.hold)),.showDesktop)
        XCTAssertEqual(config.action(.init(chord:.fourCorners,phase:.hold)),.openConfig)
        XCTAssertEqual(config.holdThreshold(for:.fourCorners),0.7)
        XCTAssertEqual(config.action(.init(chord:.fourCorners,phase:.tap)),.disabled)
        for chord in TwoHandChord.allCases where chord != .fourCorners { XCTAssertFalse(config.enabled(chord)) }
    }
    func testPerPadAndBothOuterCornersUseSharedHoldOwnerOnceAndConsumeAllUp() {
        let config = TwoHandGestureSettings().stenoConfigurationOnly
        let four = [touch(1,0.08,0.08),touch(2,0.08,0.92),touch(3,0.92,0.08),touch(4,0.92,0.92)]
        var single = SinglePadCornersEngine(), singleOutputs:[TwoHandTrigger] = []
        for i in 0...9 {
            let result = single.process(now:1+Double(i)*0.1,contacts:four,settings:config)
            XCTAssertTrue(result.reserved)
            if let trigger = result.trigger { singleOutputs.append(trigger) }
        }
        XCTAssertEqual(singleOutputs,[.init(chord:.fourCorners,phase:.hold)])
        XCTAssertTrue(single.process(now:1.95,contacts:[OMSRawTouch](),settings:config).reserved)
        XCTAssertFalse(single.ownsCycle)
        var both = TwoHandGestureEngine(), bothOutputs:[TwoHandTrigger] = []
        let left = Array(four.prefix(2)), right = Array(four.suffix(2))
        for i in 0...9 {
            let time = 2+Double(i)*0.1
            if let trigger = both.process(leftHand:true,now:time,contacts:left,settings:config).trigger { bothOutputs.append(trigger) }
            if let trigger = both.process(leftHand:false,now:time+0.001,contacts:right,settings:config).trigger { bothOutputs.append(trigger) }
        }
        XCTAssertEqual(bothOutputs,[.init(chord:.fourCorners,phase:.hold)])
        XCTAssertNil(both.process(leftHand:true,now:2.95,contacts:[OMSRawTouch](),settings:config).trigger)
        XCTAssertNil(both.process(leftHand:false,now:2.96,contacts:[OMSRawTouch](),settings:config).trigger)
        XCTAssertFalse(both.ownsCycle)
    }
}

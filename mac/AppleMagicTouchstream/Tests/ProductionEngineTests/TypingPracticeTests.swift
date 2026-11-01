import AppKit
import SwiftUI
import XCTest
@testable import GlassToKeyRuntime

final class TypingPracticeTests:XCTestCase {
    private struct Seeded:RandomNumberGenerator {
        var state:UInt64 = 17
        mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
    }
    func testGeneratedRoundsRespectPoolLengthAndAvoidRepeatedNeighbors() {
        for mode in TypingPracticeSession.Mode.allCases {
            var random = Seeded()
            let prompt = TypingPracticeSession.prompt(mode:mode,count:25,custom:"cat dog sun",using:&random)
            let words = prompt.split(separator:" ").map(String.init)
            XCTAssertEqual(words.count,25)
            XCTAssertTrue(zip(words,words.dropFirst()).allSatisfy {$0 != $1})
            let pool = mode == .custom ? ["cat","dog","sun"]:mode == .steno ? TypingPracticeSession.stenoWords:TypingPracticeSession.commonWords
            XCTAssertTrue(words.allSatisfy {pool.contains($0)})
        }
        var random = Seeded()
        XCTAssertEqual(TypingPracticeSession.prompt(mode:.custom,count:10,custom:" \n",using:&random),"")
        XCTAssertEqual(TypingPracticeSession.prompt(mode:.custom,count:10,custom:"one",using:&random).split(separator:" ").count,10)
    }
    func testClockStartsOnFirstInputAndFreezesAtCompletion() {
        let start = Date(timeIntervalSince1970:100)
        var session = TypingPracticeSession(prompt:"hello world")
        session.update("",at:start)
        XCTAssertNil(session.startedAt); XCTAssertEqual(session.elapsed(at:start),0)
        session.update("hello",at:start)
        XCTAssertEqual(session.startedAt,start)
        XCTAssertEqual(session.wpm(at:start.addingTimeInterval(60)),1,accuracy:0.001)
        session.update("hello world",at:start.addingTimeInterval(60))
        XCTAssertTrue(session.isComplete); XCTAssertEqual(session.progress,1)
        XCTAssertEqual(session.accuracy,100)
        XCTAssertEqual(session.wpm(at:start.addingTimeInterval(120)),2.2,accuracy:0.001)
        session.update("changed",at:start.addingTimeInterval(130))
        XCTAssertEqual(session.input,"hello world")
    }
    func testBackspacesAndPloverReplacementRecomputeCurrentAccuracy() {
        var session = TypingPracticeSession(prompt:"cat cats",ignoresCase:true)
        let now = Date(timeIntervalSince1970:100)
        session.update("Car",at:now)
        XCTAssertEqual(session.correctCharacters,2)
        XCTAssertEqual(session.accuracy,200.0/3,accuracy:0.001)
        session.update("Ca",at:now.addingTimeInterval(1))
        XCTAssertEqual(session.accuracy,100)
        session.update(" Cat  Cats ",at:now.addingTimeInterval(2))
        XCTAssertTrue(session.isComplete); XCTAssertEqual(session.progress,1)
        XCTAssertEqual(session.comparisonInput,"cat cats")
    }
    func testExactCaseInWordsModeAndBoundedCustomInput() {
        var session = TypingPracticeSession(prompt:"cat")
        session.update("CAT",at:.now)
        XCTAssertFalse(session.isComplete); XCTAssertEqual(session.accuracy,0)
        session.update(String(repeating:"a",count:7000),at:.now)
        XCTAssertEqual(session.input.count,6000)
        XCTAssertEqual(TypingPracticeSession.words(from:String(repeating:"word ",count:1000)).count,500)
    }
}

@MainActor final class TypingPracticeViewTests:XCTestCase {
    func testPracticeAndFreeTypeRenderWithoutOutputOrMutatingFreeText() throws {
        for (practice,mode) in [(false,TypingPracticeSession.Mode.words),(true,.words),(true,.steno),(true,.custom)] {
            var freeText = "keep my free text"
            let view = TypingPracticePanel(freeText:Binding(get:{freeText},set:{freeText = $0}),initialPractice:practice,initialMode:mode)
                .padding(16).frame(width:864).background(Color.white).environment(\.colorScheme,.light)
            let host = NSHostingView(rootView:view)
            host.frame = CGRect(x:0,y:0,width:864,height:500)
            let window = NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
            window.contentView = host
            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            RunLoop.current.run(until:Date().addingTimeInterval(0.05))
            XCTAssertFalse(window.isVisible)
            XCTAssertEqual(freeText,"keep my free text")
            if let directory = ProcessInfo.processInfo.environment["AMT_PRACTICE_PREVIEW_DIR"] {
                let url = URL(fileURLWithPath:directory,isDirectory:true)
                try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
                host.cacheDisplay(in:host.bounds,to:bitmap)
                try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:url.appendingPathComponent("practice-\(practice)-\(mode.rawValue).png"))
            }
            window.contentView = nil
        }
    }
}

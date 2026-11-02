import XCTest
@testable import GlassToKeyRuntime

final class JavelinTests:XCTestCase {
    private func mask(_ keys:StenoKey...) -> UInt64 { keys.reduce(0) { $0|$1.bit } }
    func testAliasesAndNumbers() {
        XCTAssertEqual(JavelinTranslator.stroke(mask(.s1)),2)
        XCTAssertEqual(JavelinTranslator.stroke(mask(.s2)),2)
        XCTAssertEqual(JavelinTranslator.stroke(mask(.star1,.star2,.star3,.star4)),1<<10)
        XCTAssertEqual(JavelinTranslator.stroke(mask(.n1,.nc)),1)
        XCTAssertEqual(JavelinTranslator.stroke(mask(.fn,.power,.res1,.res2)),0)
        XCTAssertEqual(JavelinTranslator.stroke(mask(.tl,.kl,.a,.tr)),(1<<2)|(1<<3)|(1<<8)|(1<<19))
    }
    func testNativeMultiStrokeFormattingUndoAndReset() {
        let translator = JavelinTranslator(dictionaries:[["KAT":"cat","-S":"{^s}","KAT/-S":"cats","TP":"{.}","H-L":"hello"]])
        XCTAssertEqual(translator.translate(mask(.kl,.a,.tr)),.init(backspaces:0,text:"cat"))
        XCTAssertEqual(translator.translate(mask(.sr)),.init(backspaces:0,text:"s"))
        XCTAssertEqual(translator.translate(mask(.star1)),.init(backspaces:1,text:""))
        XCTAssertEqual(translator.translate(mask(.tl,.pl)),.init(backspaces:0,text:"."))
        XCTAssertEqual(translator.translate(mask(.hl,.lr)),.init(backspaces:0,text:" Hello"))
        translator.reset()
        XCTAssertEqual(translator.translate(mask(.star1)),.init(backspaces:0,text:""))
        XCTAssertEqual(translator.translate(mask(.kl,.a,.tr)),.init(backspaces:0,text:"cat"))
    }
    func testDictionaryPriorityAndUnsupportedPlugins() {
        let translator = JavelinTranslator(dictionaries:[["KAT":"kitten","H-L":"{#super(a)}","TP":"{PLOVER:TOGGLE}","TK":"=repeat_last_translation"],["KAT":"cat"]])
        XCTAssertEqual(translator.unsupportedCount,3)
        XCTAssertEqual(translator.translate(mask(.kl,.a,.tr)).text,"kitten")
        XCTAssertTrue(JavelinTranslator.supported("{:}"))
        XCTAssertFalse(JavelinTranslator.supported("{:console}"))
        XCTAssertFalse(JavelinTranslator.supported("{MODE:CAPS}"))
        translator.reset()
        XCTAssertEqual(translator.translate(mask(.hl,.lr)),.init(backspaces:0,text:""))
    }
    func testLongerOutlineReplacesPreviousWordAndUndoRestoresIt() {
        let translator = JavelinTranslator(dictionaries:[["KAT":"cat","-S":"{^s}","KAT/-S":"felines"]])
        XCTAssertEqual(translator.translate(mask(.kl,.a,.tr)).text,"cat")
        XCTAssertEqual(translator.translate(mask(.sr)),.init(backspaces:3,text:"felines"))
        XCTAssertEqual(translator.translate(mask(.star1)),.init(backspaces:7,text:"cat"))
    }
    func testIndependentInstancesAndEnglishAffixRules() {
        let first = JavelinTranslator(dictionaries:[["KAT":"city","-S":"{^s}"]])
        let second = JavelinTranslator(dictionaries:[["KAT":"cat","-S":"{^s}"]])
        XCTAssertEqual(first.translate(mask(.kl,.a,.tr)).text,"city")
        XCTAssertEqual(second.translate(mask(.kl,.a,.tr)).text,"cat")
        XCTAssertEqual(first.translate(mask(.sr)),.init(backspaces:1,text:"ies"))
        XCTAssertEqual(second.translate(mask(.sr)),.init(backspaces:0,text:"s"))
    }
    func testConnectionModeRoundTrip() throws {
        for mode in StenoConnectionMode.allCases {
            XCTAssertEqual(try JSONDecoder().decode(StenoConnectionMode.self,from:JSONEncoder().encode(mode)),mode)
        }
        XCTAssertEqual(StenoConnectionMode(rawValue:"plugin"),.plugin)
        XCTAssertEqual(StenoConnectionMode(rawValue:"serial"),.serial)
    }
    func testBundledLapwingWithoutPloverOrNativeOutput() throws {
        let translator = try JavelinTranslator.bundled()
        XCTAssertGreaterThan(translator.entryCount,140_000)
        XCTAssertEqual(translator.translate(mask(.kl,.a,.tr)).text,"cat")
        XCTAssertEqual(translator.translate(mask(.sr)).text,"s")
        XCTAssertEqual(translator.translate(mask(.star1)).backspaces,1)
    }
}

import Foundation
import XCTest
import os
@testable import GlassToKeyRuntime

final class StenoStrokeRecordingTests:XCTestCase {
    func testCanonicalRawChordsAndMultiStrokeLimit() throws {
        var outline = StenoRecordedOutline()
        let cat = StenoKey.kl.bit|StenoKey.a.bit|StenoKey.tr.bit
        XCTAssertTrue(outline.append(cat)); XCTAssertTrue(outline.append(StenoKey.sr.bit))
        XCTAssertEqual(outline.text,"KAT/-S")
        XCTAssertEqual(StenoRecordedOutline.format(StenoKey.s1.bit|StenoKey.s2.bit),"S")
        XCTAssertEqual(StenoRecordedOutline.format(StenoKey.star1.bit|StenoKey.star4.bit),"*")
        XCTAssertEqual(StenoRecordedOutline.format(StenoKey.n1.bit|StenoKey.s2.bit),"#S")
        XCTAssertNil(StenoRecordedOutline.format(StenoKey.res1.bit))
        XCTAssertNil(StenoRecordedOutline.format(UInt64.max))
        for _ in 2..<31 { XCTAssertTrue(outline.append(cat)) }
        XCTAssertFalse(outline.append(cat)); XCTAssertEqual(outline.strokes.count,31)
        XCTAssertEqual(try StenoDictionaryDocument.canonicalOutline(outline.text),outline.text)
    }
    func testStoppedOrReplacedRecordingCannotReceiveQueuedChords() {
        let recorder = StenoStrokeRecorder(), id = UUID(), next = UUID()
        let events = OSAllocatedUnfairLock(initialState:[StenoStrokeRecorder.Event]())
        recorder.begin(id:id) { event in events.withLock { $0.append(event) } }
        XCTAssertEqual(recorder.routingID,id)
        XCTAssertTrue(recorder.consume(StenoKey.kl.bit,id:id))
        recorder.cancel(id:id)
        XCTAssertNil(recorder.routingID)
        XCTAssertFalse(recorder.consume(StenoKey.a.bit,id:id))
        recorder.begin(id:next) { event in events.withLock { $0.append(event) } }
        recorder.cancel(id:id) // A stale window cannot stop the replacement lease.
        XCTAssertEqual(recorder.id,next)
        XCTAssertFalse(recorder.consume(StenoKey.a.bit,id:id))
        XCTAssertTrue(recorder.consume(StenoKey.tr.bit,id:next))
        recorder.reset()
        XCTAssertEqual(events.withLock { $0 },[.stroke(StenoKey.kl.bit),.ended,.stroke(StenoKey.tr.bit),.ended])
    }
    func testRecordingBoundariesWaitForAllUpAndSuppressHeldChordAfterStop() throws {
        let recorder = StenoStrokeRecorder(), id = UUID()
        recorder.observeContacts(active:true) // A chord was already down before Record.
        recorder.begin(id:id) { event in if case .stroke = event { XCTFail("A crossing-boundary chord must not be recorded") } }
        let beforeStart = try XCTUnwrap(recorder.routingID)
        XCTAssertNotEqual(beforeStart,id)
        XCTAssertFalse(recorder.consume(StenoKey.a.bit,id:beforeStart))
        recorder.observeContacts(active:false)
        XCTAssertEqual(recorder.routingID,id)
        recorder.observeContacts(active:true)
        recorder.cancel(id:id) // Stop while another chord remains down.
        let afterStop = try XCTUnwrap(recorder.routingID)
        XCTAssertNotEqual(afterStop,id)
        XCTAssertFalse(recorder.consume(StenoKey.a.bit,id:afterStop))
        recorder.observeContacts(active:false)
        XCTAssertNil(recorder.routingID)
        recorder.observeContacts(active:true) // Fresh typing is no longer intercepted.
        XCTAssertNil(recorder.routingID)
        recorder.reset()
    }
    func testReplayNeverArmsOrMutatesLiveStrokeRecording() {
        let recorder = StenoStrokeRecorder.shared, id = UUID()
        recorder.begin(id:id) { _ in }
        defer { recorder.reset() }
        let events = OSAllocatedUnfairLock(initialState:[RuntimeDispatchEvent]())
        let service = DispatchService(recordingWith:ReplayTouchEngineScheduler(startTime:1)) { event in events.withLock { $0.append(event) } }
        service.configureStenoMode(true,connectionMode:.javelin)
        XCTAssertFalse(service.beginStenoStrokeRecording(id:UUID()) { _ in XCTFail("Replay capture") })
        service.updateStenoRecordingContacts(active:true)
        service.postStenoStroke(StenoKey.a.bit)
        service.clearQueue()
        XCTAssertEqual(recorder.id,id)
        XCTAssertEqual(events.withLock { $0.count },1)
    }
}

import CoreGraphics
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

final class ThreeFingerDragTests: XCTestCase {
    func testMouseOutputTraceKeepsLatestEdgesInOrderWithoutChangingPriorSnapshot() {
        var trace = GestureMouseOutputTrace()
        for index in 0..<40 {
            trace.observe(type:index.isMultiple(of:2) ? .leftMouseDown : .leftMouseUp,
                sourceID:17,timestamp:UInt64(index),tagged:true)
        }
        let captured = trace.snapshot()
        XCTAssertEqual(captured.map(\.timestamp),Array(8..<40).map(UInt64.init))
        trace.observe(type:.rightMouseUp,sourceID:1,timestamp:40,tagged:false)
        XCTAssertEqual(captured.last?.timestamp,39)
        XCTAssertEqual(trace.snapshot().map(\.timestamp),Array(9...40).map(UInt64.init))
        XCTAssertEqual(trace.snapshot().last?.sourceID,1)
        XCTAssertEqual(trace.snapshot().last?.tagged,false)
    }

    func testCaptureButtonDiagnosticRoundTripsAndOldRecordsRemainReadable() throws {
        let evidence = RuntimeGestureOutputDiagnostic(dragOwner:nil,dragOwnerCount:0,dragSourceID:17,
            combinedButtons:1,hidButtons:0,dragSourceButtons:0,otherGestureSourceButtons:1,
            observerHealthy:true,observedMouseEdges:[
                RuntimeGestureMouseEdge(type:CGEventType.leftMouseUp.rawValue,sourceID:17,timestamp:123,tagged:true)])
        let record = ProcessedFrameRecord(frame:RuntimeRawFrame(sequence:1,timestamp:1,deviceNumericID:42,
            deviceIndex:0,contacts:[],rawTouches:[]),arrivalTicks:0,ingress:nil,diagnostic:nil,
            gestureOutput:evidence)
        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(ProcessedFrameRecord.self,from:data).gestureOutput,evidence)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        legacy.removeValue(forKey:"gestureOutput")
        let oldData = try JSONSerialization.data(withJSONObject:legacy)
        XCTAssertNil(try JSONDecoder().decode(ProcessedFrameRecord.self,from:oldData).gestureOutput)
    }

    func testClickModifierEvidenceRoundTripsAndMissingLegacyFlagsStayUnknown() throws {
        let old = Data(#"{"type":1,"sourceID":0,"timestamp":123,"tagged":true}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(RuntimeGestureMouseEdge.self,from:old).flagsRawValue)
        var trace = GestureMouseOutputTrace()
        let flags = CGEventFlags([.maskAlternate,.maskCommand]).rawValue
        trace.observe(type:.leftMouseDown,sourceID:0,timestamp:124,tagged:true,flagsRawValue:flags)
        let edge = try XCTUnwrap(trace.snapshot().first)
        XCTAssertEqual(edge.flagsRawValue,flags)
        let evidence = RuntimeGestureOutputDiagnostic(dragOwner:nil,dragOwnerCount:0,dragSourceID:17,
            combinedButtons:0,hidButtons:0,dragSourceButtons:0,otherGestureSourceButtons:0,
            observerHealthy:true,observedMouseEdges:[edge],combinedFlagsRawValue:flags,hidFlagsRawValue:0,
            ownedKeyboardFlagsRawValue:0,hidModifierKeys:0)
        let restored = try JSONDecoder().decode(RuntimeGestureOutputDiagnostic.self,from:JSONEncoder().encode(evidence))
        XCTAssertEqual(restored,evidence)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(evidence)) as? [String:Any])
        for key in ["combinedFlagsRawValue","hidFlagsRawValue","ownedKeyboardFlagsRawValue","hidModifierKeys"] { legacy.removeValue(forKey:key) }
        let decoded = try JSONDecoder().decode(RuntimeGestureOutputDiagnostic.self,from:JSONSerialization.data(withJSONObject:legacy))
        XCTAssertNil(decoded.combinedFlagsRawValue)
        XCTAssertNil(decoded.hidFlagsRawValue)
        XCTAssertNil(decoded.ownedKeyboardFlagsRawValue)
        XCTAssertNil(decoded.hidModifierKeys)
    }

    func testModifierHistoryRedactsOrdinaryKeysAndRetainsBorrowAndRestoreEdges() throws {
        var trace = ModifierDiagnosticRing()
        func entry(_ flags:CGEventFlags,code:CGKeyCode = 9,origin:RuntimeModifierTraceEntry.Origin = .submitted,type:CGEventType = .keyDown) -> RuntimeModifierTraceEntry {
            .init(origin:origin,timestamp:100,type:type.rawValue,modifierKeyCode:code,
                flagsRawValue:flags.rawValue,sourcePID:123,sourceID:0,tagged:false)
        }
        trace.record(entry([]))
        XCTAssertTrue(try XCTUnwrap(trace.snapshot(since:nil)).entries.isEmpty)
        trace.record(entry(.maskCommand))
        trace.record(entry([],type:.keyUp))
        let borrowed = try XCTUnwrap(trace.snapshot(since:nil))
        XCTAssertEqual(borrowed.entries.count,2)
        XCTAssertEqual(borrowed.entries.map(\.flagsRawValue),[CGEventFlags.maskCommand.rawValue,0])
        XCTAssertTrue(borrowed.entries.allSatisfy { $0.modifierKeyCode == nil })
        XCTAssertNil(trace.snapshot(since:borrowed.throughSequence))
        trace.record(entry([],code:55,origin:.observed,type:.flagsChanged))
        let delta = try XCTUnwrap(trace.snapshot(since:borrowed.throughSequence))
        XCTAssertEqual(delta.entries.count,1)
        XCTAssertEqual(delta.entries[0].modifierKeyCode,55)
        XCTAssertEqual(delta.entries[0].origin,.observed)
        XCTAssertEqual(delta.entries[0].sourcePID,123)
        XCTAssertEqual(borrowed.entries.count,2,"Prior capture snapshots are immutable")
        XCTAssertFalse(DragButtonInterference.interrupts(type:.flagsChanged,tag:0))
    }
    func testModifierHistoryIsBoundedAndReportsOverrunWithoutRepeatingFrames() throws {
        var trace = ModifierDiagnosticRing()
        for time in 1...300 {
            trace.record(.init(origin:.observed,timestamp:UInt64(time),type:CGEventType.flagsChanged.rawValue,
                modifierKeyCode:55,flagsRawValue:time.isMultiple(of:2) ? 0:CGEventFlags.maskCommand.rawValue,
                sourcePID:0,sourceID:0,tagged:false))
        }
        let first = try XCTUnwrap(trace.snapshot(since:nil))
        XCTAssertEqual(first.entries.count,256)
        XCTAssertEqual(first.entries.first?.sequence,45)
        XCTAssertEqual(first.entries.last?.sequence,300)
        XCTAssertEqual(first.droppedEntries,44)
        XCTAssertNil(trace.snapshot(since:first.throughSequence))
        let delta = try XCTUnwrap(trace.snapshot(since:298))
        XCTAssertEqual(delta.entries.map(\.sequence),[299,300])
        XCTAssertEqual(delta.droppedEntries,0)
        XCTAssertEqual(try XCTUnwrap(trace.snapshot(since:nil)),first,"New captures include the retained prehistory again")
        let diagnostic = RuntimeGestureOutputDiagnostic(dragOwner:nil,dragOwnerCount:0,dragSourceID:nil,
            combinedButtons:0,hidButtons:0,dragSourceButtons:0,otherGestureSourceButtons:0,
            observerHealthy:true,observedMouseEdges:[],modifierHistory:first)
        let data = try JSONEncoder().encode(diagnostic)
        XCTAssertEqual(try JSONDecoder().decode(RuntimeGestureOutputDiagnostic.self,from:data),diagnostic)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        legacy.removeValue(forKey:"modifierHistory")
        XCTAssertNil(try JSONDecoder().decode(RuntimeGestureOutputDiagnostic.self,from:JSONSerialization.data(withJSONObject:legacy)).modifierHistory)
    }

    func testSecondaryAndMiddleDragsReserveMatchingUpAndShareOnlySameButton() throws {
        for (button,downType,dragType,upType) in [(CGMouseButton.right,CGEventType.rightMouseDown,CGEventType.rightMouseDragged,CGEventType.rightMouseUp),(.center,.otherMouseDown,.otherMouseDragged,.otherMouseUp)] {
            var drag = PrimaryDragOutput()
            let down = try XCTUnwrap(drag.begin(device:1,location:.init(x:10,y:20),flags:.maskCommand,button:button))
            XCTAssertEqual(down.type,downType)
            XCTAssertEqual(down.getIntegerValueField(.mouseEventButtonNumber),Int64(button.rawValue))
            XCTAssertFalse(drag.join(device:2,button:.left))
            XCTAssertNil(drag.begin(device:2,location:.zero,flags:[],button:.left))
            XCTAssertEqual(drag.owner,1)
            XCTAssertTrue(drag.join(device:2,button:button))
            let moved = try XCTUnwrap(drag.movePointer(location:.init(x:15,y:25),delta:.init(x:5,y:5),flags:[]))
            XCTAssertEqual(moved.type,dragType)
            XCTAssertEqual(moved.getIntegerValueField(.mouseEventButtonNumber),Int64(button.rawValue))
            XCTAssertNil(drag.end(device:1))
            XCTAssertEqual(drag.owner,2)
            let up = try XCTUnwrap(drag.end(device:2))
            XCTAssertEqual(up.type,upType)
            XCTAssertEqual(up.location,.init(x:15,y:25))
            XCTAssertEqual(up.flags,[])
            XCTAssertNil(drag.end())
            XCTAssertTrue(drag.owners.isEmpty)
            // Lifecycle cancellation releases the matching button through the same path.
            _ = drag.begin(device:1,location:.zero,flags:[],button:button)
            XCTAssertEqual(drag.end()?.type,upType)
        }
    }
    func testMiddleClickAndNewActionCatalogRoundTrip() throws {
        var clicks = PrimaryTapClickOutput()
        let events = try XCTUnwrap(GestureTapActionOutput.events(action:.middleClick,location:.init(x:5,y:10),time:1,doubleClickInterval:0.5,flags:.maskShift,clicks:&clicks))
        XCTAssertEqual(events.map(\.type),[.otherMouseDown,.otherMouseUp])
        XCTAssertTrue(events.allSatisfy { $0.getIntegerValueField(.mouseEventButtonNumber) == 2 && $0.flags == .maskShift })
        var settings = HandGestureSettings()
        settings.setAction(.middleClick,for:.twoFingerTap,in:.left)
        settings.setAction(.secondaryDrag,for:.threeFingerMove,in:.left)
        settings.setAction(.middleDrag,for:.threeFingerMove,in:.right)
        settings.setAction(.capsWord,for:.fourFingerTap,in:.left)
        var profile = AppKeymapProfile.defaultProfile()
        profile.handGestureSettings = settings
        let action = try XCTUnwrap(KeyActionCatalog.action(for:"Caps Word"))
        XCTAssertEqual(action.kind,.capsWord)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(profile)) as? [String:Any])
        object["keyMappingsByLayout"] = ["6x3":["0":["left:0:0":["primary":["label":"Caps Word","keyCode":0,"flags":0,"kind":"capsWord"],"holdForceThreshold":0]]]]
        profile = try JSONDecoder().decode(AppKeymapProfile.self,from:JSONSerialization.data(withJSONObject:object))
        let decoded = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
        XCTAssertEqual(decoded.handGestureSettings,settings)
        XCTAssertEqual(decoded.keyMappingsByLayout?["6x3"]?[0]?["left:0:0"]?.primary,action)
        for action in [GestureAction.secondaryDrag,.middleDrag] {
            XCTAssertTrue(action.requiresPointerProfile)
            XCTAssertTrue(GestureTrigger.threeFingerMove.allowedActions.contains(action))
            XCTAssertFalse(GestureTrigger.twoFingerTap.allowedActions.contains(action))
        }
        XCTAssertTrue(GestureTrigger.twoFingerTap.allowedActions.contains(.middleClick))
    }

    private func touches(_ count: Int = 3, dx: Float = 0, triangular: Bool = false, thumb: Bool = false) -> [OMSRawTouch] {
        (0..<count).map { index in
            let telemetry: OMSTouchTelemetry? = thumb ? OMSTouchTelemetry(
                fingerID:index == 0 ? 1 : Int32(index+2),handID:1,velocityX:0,velocityY:0,
                absoluteX:0,absoluteY:0,absoluteVelocityX:0,absoluteVelocityY:0,sourceFrame:1,sourceTimestamp:1) : nil
            return OMSRawTouch(id:Int32(index+1),posX:0.3+Float(index)*0.11+dx,
                posY:triangular && index == 1 ? 0.8 : 0.5,total:1,pressure:100,
                majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching,telemetry:telemetry)
        }
    }
    func testCloseAlignedChordRejectsThumbTriangleAndSpread() {
        XCTAssertTrue(ThreeFingerDragChord.accepts(touches()))
        XCTAssertFalse(ThreeFingerDragChord.accepts(touches(thumb:true)))
        XCTAssertFalse(ThreeFingerDragChord.accepts(touches(triangular:true)))
        XCTAssertFalse(ThreeFingerDragChord.accepts(touches(2)))
        let spread = touches().enumerated().map { index,t in
            OMSRawTouch(id:t.id,posX:Float(index)*0.4,posY:t.posY,total:1,pressure:100,
                majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        }
        XCTAssertFalse(ThreeFingerDragChord.accepts(spread))
        // Geometry does not assume the user's hand is perfectly horizontal.
        let rotated = touches().map { t in
            OMSRawTouch(id:t.id,posX:0.5,posY:0.2+(t.posX-0.3)*160/114.9,total:1,
                pressure:100,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        }
        XCTAssertTrue(ThreeFingerDragChord.accepts(rotated))
    }
    private func archedRow(_ count:Int = 3, depthMM:Float = 11, dx:Float = 0) -> [OMSRawTouch] {
        (0..<count).map { index -> OMSRawTouch in
            let x:Float = 0.3 + Float(index)*(22.0/160.0) + dx
            let y:Float = 0.5 + (index == 1 ? depthMM/114.9 : 0)
            return OMSRawTouch(id:Int32(index+1),posX:x,posY:y,total:1,pressure:40,
                majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        }
    }
    func testNaturalArchedRowsActivateWithoutWaitingForFingersToStraighten() {
        for depth:Float in [9,11,13] {
            XCTAssertTrue(ThreeFingerRowChord.accepts(archedRow(depthMM:depth)))
            var router = TrackpadGestureRouter()
            _ = router.update(device:1,time:1,contacts:archedRow(depthMM:depth),mouse:true,scroll:true,drag:true)
            let activation = router.update(device:1,time:1.01,contacts:archedRow(depthMM:depth,dx:0.003),mouse:true,scroll:true,drag:true)
            XCTAssertEqual(activation.gesture,.threeFingerMove)
            XCTAssertEqual(activation.phase,.began)
        }
        XCTAssertFalse(ThreeFingerRowChord.accepts(archedRow(depthMM:18)))
    }
    func testStaggeredLandingStartsDragOnThirdFingerThenKeepsItsLatch() {
        var router = TrackpadGestureRouter()
        XCTAssertNil(router.update(device:1,time:1,contacts:archedRow(1),mouse:true,scroll:true,drag:true).gesture)
        XCTAssertNil(router.update(device:1,time:1.02,contacts:archedRow(2,dx:0.001),mouse:true,scroll:true,drag:true).gesture)
        let begin = router.update(device:1,time:1.04,contacts:archedRow(dx:0.004),mouse:true,scroll:true,drag:true)
        XCTAssertEqual(begin.gesture,.threeFingerMove); XCTAssertEqual(begin.phase,.began)
        for (time,count) in [(1.06,2),(1.08,1)] {
            let held = router.update(device:1,time:time,contacts:archedRow(count,dx:0.005),mouse:true,scroll:true,drag:true)
            XCTAssertEqual(held.gesture,.threeFingerMove); XCTAssertEqual(held.phase,.changed)
        }
        XCTAssertEqual(router.update(device:1,time:1.1,contacts:[],mouse:true,scroll:true,drag:true).phase,.ended)
    }
    private func approachingFourth(_ state:OMSState = .hovering) -> OMSRawTouch {
        OMSRawTouch(id:4,posX:0.75,posY:0.5,total:1,pressure:4,majorAxis:5,minorAxis:3,angle:0,density:1,state:state)
    }
    func testFourthPrecontactDefersOnlyPendingDragAndExpiresAfterLandingWindow() {
        for phase in [OMSState.starting,.hovering] {
            var router = TrackpadGestureRouter()
            _ = router.update(device:1,time:1,contacts:archedRow()+[approachingFourth(phase)],mouse:true,scroll:true,drag:true)
            let pending = router.update(device:1,time:1.01,contacts:archedRow(dx:0.003)+[approachingFourth(phase)],mouse:true,scroll:true,drag:true)
            XCTAssertNil(pending.gesture)
            // A sustained hover is not a touching fourth finger and cannot block
            // genuine three-finger movement beyond the bounded landing interval.
            let began = router.update(device:1,time:1.081,contacts:archedRow(dx:0.004)+[approachingFourth(phase)],mouse:true,scroll:true,drag:true)
            XCTAssertEqual(began.gesture,.threeFingerMove); XCTAssertEqual(began.phase,.began)
            let continued = router.update(device:1,time:1.09,contacts:archedRow(4,dx:0.005),mouse:true,scroll:true,drag:true)
            XCTAssertEqual(continued.gesture,.threeFingerMove); XCTAssertEqual(continued.phase,.changed)
        }
    }
    func testFourthPrecontactDoesNotDelayUnassignedScrollOrOtherPad() {
        var router = TrackpadGestureRouter()
        let contacts = archedRow()+[approachingFourth()]
        _ = router.update(device:1,time:1,contacts:contacts,mouse:true,scroll:false,drag:true)
        let moved = archedRow(dx:0.003)+[approachingFourth()]
        XCTAssertEqual(router.update(device:1,time:1.01,contacts:moved,mouse:true,scroll:false,drag:true).gesture,.threeFingerMove)
        router.reset()
        _ = router.update(device:1,time:2,contacts:contacts,mouse:true,scroll:true,drag:true)
        _ = router.update(device:2,time:2,contacts:archedRow(),mouse:true,scroll:true,drag:true)
        XCTAssertNil(router.update(device:1,time:2.01,contacts:moved,mouse:true,scroll:true,drag:true).gesture)
        XCTAssertEqual(router.update(device:2,time:2.01,contacts:archedRow(dx:0.003),mouse:true,scroll:true,drag:true).gesture,.threeFingerMove)
        // If the extra pre-contact disappears, no timer has to elapse.
        XCTAssertEqual(router.update(device:1,time:2.02,contacts:archedRow(dx:0.004),mouse:true,scroll:true,drag:true).gesture,.threeFingerMove)
    }

    func testDragClaimsMovementAndLatchesAcrossCountsThenEnds() {
        var router = TrackpadGestureRouter()
        XCTAssertNil(router.process(device:1,time:1,contacts:touches(),mouse:true,scroll:true,drag:true))
        let begin = router.update(device:1,time:1.02,contacts:touches(dx:0.003),mouse:true,scroll:true,drag:true)
        XCTAssertEqual(begin.gesture,.drag); XCTAssertEqual(begin.phase,.began)
        for (time,count) in [(1.04,1),(1.06,4),(1.08,2)] {
            let step = router.update(device:1,time:time,contacts:touches(count,dx:Float(time-1)*0.1),mouse:true,scroll:true,drag:true)
            XCTAssertEqual(step.gesture,.drag); XCTAssertEqual(step.phase,.changed)
        }
        let end = router.update(device:1,time:1.1,contacts:touches(0),mouse:true,scroll:true,drag:true)
        XCTAssertEqual(end.gesture,.drag); XCTAssertEqual(end.phase,.ended)
    }
    func testRejectedChordsNeverDragAndExistingMouseNeverSwitches() {
        for (triangle,thumb) in [(true,false),(false,true)] {
            var router = TrackpadGestureRouter()
            for (time,dx) in [(1.0,Float(0)),(1.02,Float(0.004))] {
                XCTAssertNil(router.process(device:1,time:time,contacts:touches(dx:dx,triangular:triangle,thumb:thumb),mouse:true,scroll:true,drag:true))
            }
        }
        var router = TrackpadGestureRouter()
        _ = router.process(device:1,time:1,contacts:touches(2),mouse:true,scroll:true,drag:true)
        XCTAssertEqual(router.process(device:1,time:1.02,contacts:touches(2,dx:0.004),mouse:true,scroll:true,drag:true)?.gesture,.mouse)
        XCTAssertEqual(router.process(device:1,time:1.04,contacts:touches(dx:0.005),mouse:true,scroll:true,drag:true)?.gesture,.mouse)
    }
    func testStationaryTapDoubleClicksButDragNeverClicksOnLift() {
        for moving in [false,true] {
            var router = TrackpadGestureRouter(), taps = TwoFingerTapRecognizer(requiredCount:3)
            var clicks = 0
            for (time,contacts) in [(1.0,touches()),(1.04,touches(dx:moving ? 0.003 : 0)),(1.08,touches(0))] {
                let motion = router.process(device:1,time:time,contacts:contacts,mouse:true,scroll:true,drag:true)
                if taps.process(device:1,time:time,contacts:contacts,gestureActive:motion != nil) { clicks += 1 }
            }
            XCTAssertEqual(clicks,moving ? 0 : 1)
        }
    }
    func testDiscontinuityAndDisablingReportCancellation() {
        for disabled in [false,true] {
            var router = TrackpadGestureRouter()
            _ = router.update(device:1,time:1,contacts:touches(),mouse:true,scroll:true,drag:true)
            _ = router.update(device:1,time:1.02,contacts:touches(dx:0.004),mouse:true,scroll:true,drag:true)
            let cancelled = router.update(device:1,time:disabled ? 1.04 : 1.3,contacts:touches(dx:0.005),mouse:true,scroll:true,drag:!disabled)
            XCTAssertEqual(cancelled.phase,.cancelled); XCTAssertEqual(cancelled.gesture,.drag)
        }
    }
    func testOutputHasOneOwnerBalancedEdgesLatestLocationAndIdempotentCleanup() throws {
        var drag = PrimaryDragOutput()
        let down = try XCTUnwrap(drag.begin(device:1,location:CGPoint(x:10,y:20),flags:.maskShift))
        XCTAssertEqual(down.type,.leftMouseDown)
        XCTAssertNil(drag.begin(device:2,location:.zero,flags:[]))
        XCTAssertNil(drag.end(device:2)); XCTAssertEqual(drag.owner,1)
        let move = try XCTUnwrap(drag.move(device:1,location:CGPoint(x:30,y:40),delta:CGPoint(x:20,y:20),flags:.maskCommand))
        XCTAssertEqual(move.type,.leftMouseDragged)
        XCTAssertEqual(move.getDoubleValueField(.mouseEventDeltaX),20)
        XCTAssertNil(drag.move(device:1,location:CGPoint(x:Double.nan,y:0),delta:.zero,flags:[]))
        XCTAssertEqual(drag.owner,1) // failed allocation/input still leaves reserved cleanup available
        let up = try XCTUnwrap(drag.end())
        XCTAssertEqual(up.type,.leftMouseUp); XCTAssertEqual(up.location,move.location)
        XCTAssertEqual(up.flags,.maskCommand)
        for event in [down,move,up] {
            XCTAssertEqual(event.getIntegerValueField(.mouseEventClickState),1)
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData),SelectedTrackpadEventPolicy.interpreterTag)
        }
        XCTAssertEqual(up.getDoubleValueField(.mouseEventPressure),0)
        XCTAssertNil(drag.owner); XCTAssertNil(drag.end()); XCTAssertNil(drag.move(device:1,location:.zero,delta:.zero,flags:[]))
        XCTAssertNil(drag.begin(device:1,location:CGPoint(x:Double.nan,y:0),flags:[]))
        XCTAssertNotNil(drag.begin(device:2,location:.zero,flags:[]))
        XCTAssertEqual(drag.end(device:2,location:CGPoint(x:9,y:8))?.location,CGPoint(x:9,y:8))
    }
    func testPrivateDragSourceOutlivesReturnedReleaseAndNextDrag() throws {
        for globalRelease in [false,true] {
            var drag = PrimaryDragOutput()
            let down = try XCTUnwrap(drag.begin(device:1,location:.zero,flags:[]))
            weak var source = drag.eventSource
            let sourceID = down.getIntegerValueField(.eventSourceStateID)
            XCTAssertNotNil(source)
            XCTAssertTrue(drag.join(device:2))
            let up:CGEvent
            if globalRelease {
                up = try XCTUnwrap(drag.end())
            } else {
                XCTAssertNil(drag.end(device:1))
                XCTAssertNotNil(source)
                up = try XCTUnwrap(drag.end(device:2))
            }
            XCTAssertEqual(up.type,.leftMouseUp)
            XCTAssertEqual(up.getIntegerValueField(.eventSourceStateID),sourceID)
            XCTAssertNil(drag.owner); XCTAssertNil(drag.eventSource)
            withExtendedLifetime(drag) {
                // Event metadata alone is insufficient: CGEvent does not retain this object.
                XCTAssertNotNil(source,"The reserved mouse-up still needs its live source after end() returns")
            }
            let nextDown = try XCTUnwrap(drag.begin(device:3,location:.zero,flags:[]))
            XCTAssertEqual(nextDown.getIntegerValueField(.eventSourceStateID),sourceID)
            XCTAssertNotNil(source,"A new drag must not destroy the source of a queued old release")
            XCTAssertNotNil(drag.end())
        }
    }

    func testHeldSyntheticButtonDoesNotReleaseOrRestartAcrossManyFrames() throws {
        var router = TrackpadGestureRouter(), drag = PrimaryDragOutput()
        var downCount = 0, dragCount = 0, upCount = 0
        for index in 0..<60 {
            let time = 1+Double(index)*0.01
            let contacts = index == 59 ? touches(0) : touches(index > 30 ? 1 : 3,dx:Float(index)*0.0005)
            // Models the global button table reporting our own down on every frame.
            XCTAssertFalse(DragButtonInterference.suppress(polledButtonsDown:drag.owner != nil,ownsPrimary:drag.owner != nil))
            let update = router.update(device:1,time:time,contacts:contacts,mouse:true,scroll:true,drag:true)
            if update.phase == .began, update.gesture == .drag {
                XCTAssertNotNil(drag.begin(device:1,location:CGPoint(x:100,y:100),flags:[])); downCount += 1
            }
            if update.phase == .ended || update.phase == .cancelled {
                if drag.end(device:1) != nil { upCount += 1 }
            } else if let mm = update.millimetres, update.gesture == .drag {
                let previous = try XCTUnwrap(drag.location)
                let next = CGPoint(x:previous.x+mm.x*6,y:previous.y+mm.y*6)
                XCTAssertNotNil(drag.move(device:1,location:next,delta:CGPoint(x:mm.x*6,y:mm.y*6),flags:[]))
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(drag.location).x,previous.x)
                dragCount += 1
            }
        }
        XCTAssertEqual(downCount,1); XCTAssertEqual(upCount,1); XCTAssertGreaterThan(dragCount,45)
        XCTAssertNil(drag.owner)
        XCTAssertTrue(DragButtonInterference.suppress(polledButtonsDown:true,ownsPrimary:false))
    }
    func testObserverIgnoresOurEdgesAndInterruptsOutsideButtonPresses() {
        for type in [CGEventType.leftMouseDown,.rightMouseDown,.otherMouseDown] {
            XCTAssertFalse(DragButtonInterference.interrupts(type:type,tag:SelectedTrackpadEventPolicy.interpreterTag))
            XCTAssertTrue(DragButtonInterference.interrupts(type:type,tag:0))
        }
        XCTAssertFalse(DragButtonInterference.interrupts(type:.leftMouseDragged,tag:0))
        XCTAssertFalse(DragButtonInterference.interrupts(type:.leftMouseUp,tag:0))
    }
    func testDragAndMouseUseIdenticalAccelerationForEquivalentMovement() throws {
        let profile = try ApplePointerAccelerationProfile(resolution:400,fixedMultiplier:48545/65536,
            acceleration:3,curves:[ApplePointerCurve(index:3,linear:1,parabolic:123208/65536,
                cubic:23593/65536,tangentLinear:7,tangentRoot:12)])
        var mouseRouter = TrackpadGestureRouter(), dragRouter = TrackpadGestureRouter()
        var mouse = TwoFingerPointerMotionEngine(), drag = TwoFingerPointerMotionEngine()
        mouse.configure(response:.apple,sensitivity:1,profiles:[1:profile])
        drag.configure(response:.apple,sensitivity:1,profiles:[1:profile])
        var compared = 0
        for index in 0..<80 {
            let time = 1+Double(index)*0.01, dx = Float(index)*0.0005
            let mouseMotion = mouseRouter.process(device:1,time:time,contacts:touches(2,dx:dx),mouse:true,scroll:true,drag:true)
            let dragMotion = dragRouter.process(device:1,time:time,contacts:touches(3,dx:dx),mouse:true,scroll:true,drag:true)
            XCTAssertEqual(mouseMotion == nil,dragMotion == nil)
            if let mouseMotion, let dragMotion {
                XCTAssertEqual(mouseMotion.gesture,.mouse); XCTAssertEqual(dragMotion.gesture,.drag)
                let a = try XCTUnwrap(mouse.processMotion(device:1,time:time,millimetres:mouseMotion.millimetres))
                let b = try XCTUnwrap(drag.processMotion(device:1,time:time,millimetres:dragMotion.millimetres))
                XCTAssertEqual(a.x,b.x,accuracy:0.005); XCTAssertEqual(a.y,b.y,accuracy:0.005)
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared,70)
    }

}

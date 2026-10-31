import AppKit
import Carbon
import Darwin
import OpenMultitouchSupport
import SwiftUI
import XCTest
@testable import GlassToKeyRuntime

final class GeminiPRTests:XCTestCase {
    func testCanonicalPloverWireVectorsAndEveryKeyBit() throws {
        let vectors:[(StenoKey,[UInt8])] = [
            (.fn,[0xC0,0,0,0,0,0]),(.n1,[0xA0,0,0,0,0,0]),(.n6,[0x81,0,0,0,0,0]),
            (.s1,[0x80,0x40,0,0,0,0]),(.s2,[0x80,0x20,0,0,0,0]),(.tl,[0x80,0x10,0,0,0,0]),
            (.a,[0x80,0,0x20,0,0,0]),(.o,[0x80,0,0x10,0,0,0]),
            (.star1,[0x80,0,8,0,0,0]),(.star2,[0x80,0,4,0,0,0]),
            (.star3,[0x80,0,0,0x20,0,0]),(.star4,[0x80,0,0,0x10,0,0]),
            (.e,[0x80,0,0,8,0,0]),(.u,[0x80,0,0,4,0,0]),(.fr,[0x80,0,0,2,0,0]),
            (.pr,[0x80,0,0,0,0x40,0]),(.nc,[0x80,0,0,0,0,2]),(.zr,[0x80,0,0,0,0,1])]
        for (key,expected) in vectors { XCTAssertEqual(GeminiPRPacket.bytes(for:key.bit),expected,key.label) }
        XCTAssertEqual(GeminiPRPacket.bytes(for:GeminiPRPacket.keyMask),[255,127,127,127,127,127])
        XCTAssertEqual(StenoKey.allCases.count,42)
        for key in StenoKey.allCases {
            let packet = GeminiPRPacket.bytes(for:key.bit)
            var decoded:UInt64 = 0
            for byte in 0..<6 {
                for bit in 0..<7 where packet[byte] & (UInt8(1) << (6-bit)) != 0 { decoded |= UInt64(1) << (byte*7+bit) }
            }
            XCTAssertEqual(decoded,key.bit)
            XCTAssertEqual(packet[0]&0x80,0x80)
            XCTAssertTrue(packet.dropFirst().allSatisfy { $0&0x80 == 0 })
        }
    }

    func testIsolatedPTYDeliversRawPacketsDropsWithoutReaderAndCleansUp() throws {
        let port = GeminiPRPort() // Private test PTY; never connects to Plover or native input.
        XCTAssertNil(port.snapshot.path)
        port.start(); defer { port.stop() }
        let path = try XCTUnwrap(port.snapshot.path)
        XCTAssertFalse(port.snapshot.connected)
        XCTAssertFalse(port.send(StenoKey.s1.bit))
        let fd = Darwin.open(path,O_RDWR|O_NOCTTY|O_NONBLOCK)
        XCTAssertGreaterThanOrEqual(fd,0)
        guard fd >= 0 else { return }
        var readerOpen = true; defer { if readerOpen { Darwin.close(fd) } }
        // Serial clients (including Plover/pyserial) configure raw mode after open.
        // Darwin restores terminal defaults when the last slave closes.
        func configureReader(_ descriptor:Int32) {
            var settings = termios()
            XCTAssertEqual(tcgetattr(descriptor,&settings),0)
            cfmakeraw(&settings)
            XCTAssertEqual(tcsetattr(descriptor,TCSANOW,&settings),0)
        }
        configureReader(fd)
        XCTAssertTrue(port.snapshot.connected)
        let mask = StenoKey.kl.bit|StenoKey.pl.bit|StenoKey.hl.bit // Includes a raw CR byte, not a line.
        XCTAssertTrue(port.send(mask))
        var bytes = [UInt8](repeating:0,count:6)
        let count = bytes.withUnsafeMutableBytes { Darwin.read(fd,$0.baseAddress,6) }
        XCTAssertEqual(count,6)
        XCTAssertEqual(bytes,GeminiPRPacket.bytes(for:mask))
        Darwin.close(fd); readerOpen = false
        XCTAssertFalse(port.send(StenoKey.zr.bit))
        let next = Darwin.open(path,O_RDWR|O_NOCTTY|O_NONBLOCK)
        XCTAssertGreaterThanOrEqual(next,0)
        guard next >= 0 else { return }
        defer { Darwin.close(next) }
        configureReader(next)
        XCTAssertEqual(bytes.withUnsafeMutableBytes { Darwin.read(next,$0.baseAddress,6) },-1) // No stale stroke backlog.
        XCTAssertTrue(port.send(StenoKey.a.bit|StenoKey.e.bit))
        XCTAssertEqual(bytes.withUnsafeMutableBytes { Darwin.read(next,$0.baseAddress,6) },6)
        XCTAssertEqual(bytes,GeminiPRPacket.bytes(for:StenoKey.a.bit|StenoKey.e.bit))
        port.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath:path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:URL(fileURLWithPath:path).deletingLastPathComponent().path))
    }
}

final class StenoChordTests:XCTestCase {
    private let size = CGSize(width:160,height:115)
    private func touch(_ x:Float = 0.2,_ state:OMSState = .touching,id:Int32 = 1) -> OMSRawTouch {
        .init(id:id,posX:x,posY:0.7,total:1,pressure:100,majorAxis:5,minorAxis:3,angle:0,density:1,state:state)
    }
    private var regions:[StenoRegion] { [
        .init(key:.s1,geometry:.init(normalizedRect:.init(x:0.1,y:0.2,width:0.2,height:0.2),size:size)),
        .init(key:.tl,geometry:.init(normalizedRect:.init(x:0.4,y:0.2,width:0.2,height:0.2),size:size))] }
    func testBothPadsAndRollingKeysEmitOnceAfterLastRelease() {
        var chord = StenoChordEngine()
        XCTAssertNil(chord.process(device:0,time:1,touches:[touch()],regions:regions,size:size))
        XCTAssertNil(chord.process(device:1,time:100,touches:[touch(0.5)],regions:regions,size:size))
        XCTAssertNil(chord.process(device:0,time:1.1,touches:[touch(0.5,id:2)],regions:regions,size:size))
        XCTAssertNil(chord.process(device:0,time:1.15,touches:[],regions:regions,size:size))
        XCTAssertEqual(chord.process(device:1,time:100.1,touches:[],regions:regions,size:size),StenoKey.s1.bit|StenoKey.tl.bit)
        XCTAssertEqual(chord.completedKeys[0],StenoKey.s1.bit|StenoKey.tl.bit)
        XCTAssertEqual(chord.completedKeys[1],StenoKey.tl.bit)
        XCTAssertNil(chord.process(device:1,time:100.2,touches:[],regions:regions,size:size))
        XCTAssertEqual(chord.completedKeys,SIMD2<UInt64>(repeating:0))
    }
    func testCancellationInvalidOverflowStaleAndDisconnectNeverEmitPartialStroke() {
        for reason in ["reset","overflow","invalid","stale","disconnect"] {
            var chord = StenoChordEngine()
            _ = chord.process(device:0,time:1,touches:[touch()],regions:regions,size:size)
            switch reason {
            case "reset": chord.cancel()
            case "overflow": XCTAssertNil(chord.process(device:0,time:1.05,touches:(0..<17).map { touch(id:Int32($0)) },regions:regions,size:size))
            case "invalid": XCTAssertNil(chord.process(device:0,time:1.05,touches:[touch(.nan)],regions:regions,size:size))
            case "stale": XCTAssertNil(chord.process(device:0,time:2,touches:[touch()],regions:regions,size:size))
            default: chord.removeDevice(0)
            }
            XCTAssertNil(chord.process(device:0,time:2.1,touches:[],regions:regions,size:size),reason)
            XCTAssertNil(chord.process(device:0,time:2.2,touches:[touch(0.5)],regions:regions,size:size),reason)
            XCTAssertEqual(chord.process(device:0,time:2.3,touches:[],regions:regions,size:size),StenoKey.tl.bit,reason)
        }
    }
}

final class StenoMouseTests:XCTestCase {
    private let size = CGSize(width:160,height:115)
    private var regions:[StenoRegion] { [.init(key:.s1,geometry:.init(normalizedRect:.init(x:0,y:0,width:1,height:1),size:size))] }
    private func touch(_ x:Float = 0.2,id:Int32 = 1,pressure:Float = 50) -> OMSRawTouch {
        .init(id:id,posX:x,posY:0.5,total:1,pressure:pressure,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
    }
    @discardableResult private func frame(_ engine:inout StenoChordEngine,_ time:Double,_ touches:[OMSRawTouch],pad:Int = 0) -> UInt64? {
        engine.process(device:pad,time:time,touches:touches,regions:regions,size:size)
    }
    func testLightOneFingerMovementStaysStenoAndTwoFingerMouseDoesNotType() {
        var engine = StenoChordEngine(); engine.pointerMode = .twoFinger
        frame(&engine,1,[touch()]); frame(&engine,1.02,[touch(0.23)])
        XCTAssertNil(engine.pointerUpdate)
        XCTAssertEqual(frame(&engine,1.04,[]),StenoKey.s1.bit)
        frame(&engine,1.06,[touch(),touch(0.4,id:2)])
        frame(&engine,1.08,[touch(0.23),touch(0.43,id:2)])
        XCTAssertNotNil(engine.pointerUpdate?.millimetres)
        XCTAssertNil(frame(&engine,1.1,[]))
        XCTAssertEqual(engine.completedKeys,SIMD2<UInt64>(repeating:0))
    }
    func testOneFingerForceHoldsDragThroughMotionPressureDropAndCountChanges() {
        var engine = StenoChordEngine(); engine.pointerMode = .twoFinger
        frame(&engine,1,[touch(pressure:140)])
        XCTAssertTrue(engine.pointerUpdate?.dragBegan == true)
        XCTAssertTrue(engine.pointerUpdate?.dragging == true)
        XCTAssertNil(engine.pointerUpdate?.click)
        frame(&engine,1.02,[touch(0.22)]) // Lower pressure keeps the button held.
        XCTAssertTrue(engine.pointerUpdate?.dragging == true)
        XCTAssertFalse(engine.pointerUpdate?.dragBegan == true)
        XCTAssertNotNil(engine.pointerUpdate?.millimetres)
        frame(&engine,1.04,[touch(0.23),touch(0.43,id:2)])
        XCTAssertTrue(engine.pointerUpdate?.dragging == true)
        frame(&engine,1.06,[touch(0.24)])
        XCTAssertTrue(engine.pointerUpdate?.dragging == true)
        XCTAssertNil(frame(&engine,1.08,[]))
        XCTAssertTrue(engine.pointerUpdate?.reset == true)
        XCTAssertFalse(engine.pointerUpdate?.dragging == true)
        frame(&engine,1.1,[touch()]); XCTAssertEqual(frame(&engine,1.12,[]),StenoKey.s1.bit)
    }
    func testOneFingerForceTapProducesDragDownAndReleaseWithoutStroke() {
        var engine = StenoChordEngine(); engine.pointerMode = .twoFinger
        frame(&engine,1,[touch(pressure:140)])
        XCTAssertTrue(engine.pointerUpdate?.dragBegan == true)
        XCTAssertNil(frame(&engine,1.02,[]))
        XCTAssertTrue(engine.pointerUpdate?.reset == true)
        XCTAssertFalse(engine.pointerUpdate?.dragging == true)
    }
    func testTwoFingerPrimaryAndThreeFingerSecondaryForceRemainOneShot() {
        for count in [2,3] {
            var engine = StenoChordEngine(); engine.pointerMode = .twoFinger
            let fingers = (0..<count).map { touch(0.2+Float($0)*0.2,id:Int32($0+1),pressure:140) }
            frame(&engine,1,fingers)
            XCTAssertEqual(engine.pointerUpdate?.click,count == 2 ? .primary:.secondary)
            XCTAssertFalse(engine.pointerUpdate?.dragBegan == true)
            frame(&engine,1.02,fingers); XCTAssertNil(engine.pointerUpdate?.click)
            XCTAssertNil(frame(&engine,1.04,[]))
        }
    }
    func testOtherPadMouseAndDragCanShareCursorAndDisconnectKeepsOtherOwner() {
        var engine = StenoChordEngine(); engine.pointerMode = .twoFinger
        frame(&engine,1,[touch(pressure:140)])
        frame(&engine,1.01,[touch(),touch(0.4,id:2)],pad:1)
        frame(&engine,1.02,[touch(0.23),touch(0.43,id:2)],pad:1)
        XCTAssertNotNil(engine.pointerUpdate?.millimetres)
        XCTAssertFalse(engine.pointerUpdate?.dragging == true) // Other pad only moves the shared cursor.
        frame(&engine,1.03,[],pad:1)
        frame(&engine,1.04,[touch(pressure:140)],pad:1)
        XCTAssertTrue(engine.pointerUpdate?.dragBegan == true)
        engine.removeDevice(1)
        frame(&engine,1.06,[touch(0.24)])
        XCTAssertTrue(engine.pointerUpdate?.dragging == true)
        XCTAssertNotNil(engine.pointerUpdate?.millimetres)
        XCTAssertNil(frame(&engine,1.08,[]))
        XCTAssertTrue(engine.pointerUpdate?.reset == true)
    }
    func testBothHandsKeepPendingStenoPriorityAndLargerCountsCannotRolloverToMouse() {
        var engine = StenoChordEngine(); engine.pointerMode = .twoFinger
        frame(&engine,1,[touch()]); frame(&engine,1.01,[touch()],pad:1)
        frame(&engine,1.02,[touch(pressure:140)])
        XCTAssertNil(engine.pointerUpdate)
        frame(&engine,1.04,[]); XCTAssertEqual(frame(&engine,1.05,[],pad:1),StenoKey.s1.bit)
        frame(&engine,1.1,[touch(),touch(0.4,id:2),touch(0.6,id:3)])
        frame(&engine,1.12,[touch(),touch(0.4,id:2)])
        frame(&engine,1.14,[touch(0.23),touch(0.43,id:2,pressure:140)])
        XCTAssertNil(engine.pointerUpdate)
        XCTAssertEqual(frame(&engine,1.16,[]),StenoKey.s1.bit)
    }
    func testResetInvalidStaleAndDisconnectCancelDragWithoutStroke() {
        for reason in ["reset","invalid","stale","disconnect"] {
            var engine = StenoChordEngine(); engine.pointerMode = .twoFinger
            frame(&engine,1,[touch(pressure:140)])
            switch reason {
            case "reset": engine.cancel()
            case "invalid": frame(&engine,1.02,[touch(.nan)])
            case "stale": frame(&engine,2,[touch()])
            default: engine.removeDevice(0)
            }
            XCTAssertTrue(engine.pointerUpdate?.reset == true,reason)
            XCTAssertFalse(engine.pointerUpdate?.dragging == true,reason)
            XCTAssertNil(frame(&engine,2.1,[]),reason)
            frame(&engine,2.12,[touch()]); XCTAssertEqual(frame(&engine,2.14,[]),StenoKey.s1.bit,reason)
        }
    }
    func testInvalidPadCancelsOnlyItsDragAndOtherPadContinues() {
        var engine = StenoChordEngine(); engine.pointerMode = .twoFinger
        frame(&engine,1,[touch(pressure:140)])
        frame(&engine,1.01,[touch(pressure:140)],pad:1)
        frame(&engine,1.02,[touch(.nan)])
        XCTAssertTrue(engine.pointerUpdate?.reset == true)
        frame(&engine,1.03,[touch(0.22)],pad:1)
        XCTAssertTrue(engine.pointerUpdate?.dragging == true)
        XCTAssertNotNil(engine.pointerUpdate?.millimetres)
        frame(&engine,1.04,[touch(0.23,pressure:140)])
        XCTAssertFalse(engine.pointerUpdate?.dragBegan == true)
        frame(&engine,1.05,[])
        frame(&engine,1.06,[touch(0.23)],pad:1)
        XCTAssertTrue(engine.pointerUpdate?.dragging == true)
        XCTAssertNil(frame(&engine,1.08,[],pad:1))
    }
    func testDragActivationExcludesAllPreForceTravel() {
        var engine = StenoChordEngine(); engine.pointerMode = .twoFinger
        frame(&engine,1,[touch()]); frame(&engine,1.02,[touch(0.3)])
        frame(&engine,1.04,[touch(0.32,pressure:140)])
        XCTAssertTrue(engine.pointerUpdate?.dragBegan == true)
        XCTAssertNil(engine.pointerUpdate?.millimetres)
        frame(&engine,1.06,[touch(0.33)])
        XCTAssertEqual(engine.pointerUpdate?.millimetres?.x ?? -1,1.6,accuracy:0.001)
    }
    func testConfiguredThresholdAppliesToDragAndBothClicks() {
        for count in 1...3 {
            var engine = StenoChordEngine(); engine.pointerMode = .twoFinger; engine.forceThreshold = 220
            func fingers(_ pressure:Float) -> [OMSRawTouch] { (0..<count).map { touch(0.2+Float($0)*0.2,id:Int32($0+1),pressure:pressure) } }
            frame(&engine,1,fingers(219))
            XCTAssertNil(engine.pointerUpdate)
            frame(&engine,1.02,fingers(220))
            if count == 1 { XCTAssertTrue(engine.pointerUpdate?.dragBegan == true) }
            else { XCTAssertEqual(engine.pointerUpdate?.click,count == 2 ? .primary:.secondary) }
            XCTAssertNil(frame(&engine,1.04,[]))
        }
        var engine = StenoChordEngine(); engine.pointerMode = .twoFinger; engine.forceThreshold = 80
        frame(&engine,1,[touch(pressure:80)])
        XCTAssertTrue(engine.pointerUpdate?.dragBegan == true)
    }
    func testThresholdRoundTripValidationAndMissingImportPreservesCurrentValue() throws {
        XCTAssertEqual(StenoForceThreshold.validated(.nan),130)
        XCTAssertEqual(StenoForceThreshold.validated(-20),1)
        XCTAssertEqual(StenoForceThreshold.validated(900),500)
        var current = AppKeymapProfile.defaultProfile()
        var settings = HandGestureSettings(); settings.stenoForceThreshold = 230
        current.handGestureSettings = settings
        let restored = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:current),currentProfile:.defaultProfile())
        XCTAssertEqual(restored.handGestureSettings?.resolvedStenoForceThreshold,230)
        var old = AppKeymapProfile.defaultProfile(); old.handGestureSettings = HandGestureSettings()
        let merged = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:old),currentProfile:current)
        XCTAssertEqual(merged.handGestureSettings?.resolvedStenoForceThreshold,230)
        XCTAssertEqual(HandGestureSettings().resolvedStenoForceThreshold,130)
    }
    func testHapticEdgesAndWholeStrokeReleaseExcludeHeldRepeatsAndPointerCancellation() {
        var engine = StenoChordEngine(); engine.pointerMode = .twoFinger
        frame(&engine,1,[touch()]); XCTAssertEqual(engine.hapticTouchPads,0)
        frame(&engine,1.02,[touch()]); XCTAssertEqual(engine.hapticTouchPads,0)
        frame(&engine,1.09,[touch()]); XCTAssertEqual(engine.hapticTouchPads,1)
        frame(&engine,1.1,[touch()],pad:1); XCTAssertEqual(engine.hapticTouchPads,0)
        frame(&engine,1.19,[touch()],pad:1); XCTAssertEqual(engine.hapticTouchPads,2)
        frame(&engine,1.2,[]); XCTAssertEqual(engine.hapticReleasePads,0)
        XCTAssertEqual(frame(&engine,1.21,[],pad:1),StenoKey.s1.bit)
        XCTAssertEqual(engine.hapticReleasePads,3)
        frame(&engine,1.3,[touch()]); XCTAssertEqual(engine.hapticTouchPads,0)
        let revision = engine.hapticCancellationRevision
        frame(&engine,1.32,[touch(pressure:140)])
        XCTAssertTrue(engine.pointerUpdate?.dragBegan == true)
        XCTAssertGreaterThan(engine.hapticCancellationRevision,revision)
        XCTAssertEqual(engine.hapticTouchPads,0)
        frame(&engine,1.34,[]); XCTAssertEqual(engine.hapticReleasePads,0)
        frame(&engine,1.36,[touch()]); engine.cancel()
        frame(&engine,1.38,[]); XCTAssertEqual(engine.hapticReleasePads,0)
    }
    func testMovementDropsPendingTouchAndReleaseFeedbackButQuickTapStillHasFeedback() {
        var engine = StenoChordEngine(); engine.pointerMode = .twoFinger
        frame(&engine,1,[touch(),touch(0.4,id:2)])
        XCTAssertEqual(engine.hapticTouchPads,0)
        let revision = engine.hapticCancellationRevision
        frame(&engine,1.02,[touch(0.23),touch(0.43,id:2)])
        XCTAssertNotNil(engine.pointerUpdate?.millimetres)
        XCTAssertGreaterThan(engine.hapticCancellationRevision,revision)
        frame(&engine,1.1,[touch(0.24),touch(0.44,id:2)])
        XCTAssertEqual(engine.hapticTouchPads,0)
        XCTAssertNil(frame(&engine,1.12,[])); XCTAssertEqual(engine.hapticReleasePads,0)
        frame(&engine,1.2,[touch()])
        XCTAssertEqual(frame(&engine,1.24,[]),StenoKey.s1.bit)
        XCTAssertEqual(engine.hapticTouchPads,1); XCTAssertEqual(engine.hapticReleasePads,1)
    }
    func testForceDragUsesSharedBalancedLedgerUntilLastPadOwnerLifts() throws {
        var engine = StenoChordEngine(); engine.pointerMode = .twoFinger
        var output = PrimaryDragOutput()
        frame(&engine,1,[touch(pressure:140)])
        XCTAssertTrue(engine.pointerUpdate?.dragBegan == true)
        XCTAssertEqual(try XCTUnwrap(output.begin(device:42,location:.zero,flags:[])).type,.leftMouseDown)
        frame(&engine,1.01,[touch(pressure:140)],pad:1)
        XCTAssertTrue(engine.pointerUpdate?.dragBegan == true); XCTAssertTrue(output.join(device:43))
        frame(&engine,1.03,[]); XCTAssertTrue(engine.pointerUpdate?.reset == true)
        XCTAssertNil(output.end(device:42)); XCTAssertEqual(output.owner,43)
        frame(&engine,1.04,[touch(0.22)],pad:1)
        XCTAssertTrue(engine.pointerUpdate?.dragging == true)
        XCTAssertEqual(try XCTUnwrap(output.movePointer(location:.init(x:20,y:5),delta:.init(x:20,y:5),flags:[])).type,.leftMouseDragged)
        frame(&engine,1.06,[],pad:1); XCTAssertTrue(engine.pointerUpdate?.reset == true)
        let up = try XCTUnwrap(output.end(device:43))
        XCTAssertEqual(up.type,.leftMouseUp); XCTAssertEqual(up.location,CGPoint(x:20,y:5)); XCTAssertTrue(output.owners.isEmpty)
        // Events were constructed only, never posted.
    }
    func testNewStenoOptionsRoundTripAndMissingImportPreservesCurrentValues() throws {
        var settings = HandGestureSettings(); settings.stenoConnectionMode = .plugin
        settings.stenoHapticOnTouch = true; settings.stenoHapticOnRelease = true
        var profile = AppKeymapProfile.defaultProfile(); profile.handGestureSettings = settings
        let restored = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
        XCTAssertEqual(restored.handGestureSettings?.resolvedStenoConnectionMode,.plugin)
        XCTAssertEqual(restored.handGestureSettings?.stenoHapticOnTouch,true)
        XCTAssertEqual(restored.handGestureSettings?.stenoHapticOnRelease,true)
        var old = AppKeymapProfile.defaultProfile(); old.handGestureSettings = HandGestureSettings()
        let merged = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:old),currentProfile:profile)
        XCTAssertEqual(merged.handGestureSettings?.resolvedStenoConnectionMode,.plugin)
        XCTAssertEqual(merged.handGestureSettings?.stenoHapticOnTouch,true)
        XCTAssertEqual(merged.handGestureSettings?.stenoHapticOnRelease,true)
    }
    func testLegacyModeSettingsAlwaysResolveToFixedTwoFingerBehavior() throws {
        for mode in StenoPointerMode.allCases {
            var settings = HandGestureSettings(); settings.stenoPointerMode = mode
            var profile = AppKeymapProfile.defaultProfile(); profile.handGestureSettings = settings
            let restored = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
            XCTAssertEqual(restored.handGestureSettings?.resolvedStenoPointerMode,.twoFinger)
        }
        XCTAssertEqual(HandGestureSettings().resolvedStenoPointerMode,.twoFinger)
        XCTAssertEqual(TrackpadLayoutPreset.stenoVoyager.displayName,"STENO 6x3")
    }

}

@MainActor final class StenoLayoutTests:XCTestCase {
    private func session(_ preset:TrackpadLayoutPreset = .steno,left:Int = 4,right:Int = 7,pointerMode:StenoPointerMode = .disabled,forceThreshold:Double = 130,connectionMode:StenoConnectionMode = .serial,hapticTouch:Bool = false,hapticRelease:Bool = false) -> ProductionReplaySession {
        let run = ProductionReplaySession(startTime:1)
        let size = CGSize(width:432,height:310.23)
        run.engine.updateLayouts(leftLayout:StenoLayoutDefinition.layout(preset:preset,side:.left,size:size,pointerMode:pointerMode,forceThreshold:forceThreshold,connectionMode:connectionMode,hapticTouch:hapticTouch,hapticRelease:hapticRelease),
            rightLayout:StenoLayoutDefinition.layout(preset:preset,side:.right,size:size,pointerMode:pointerMode,forceThreshold:forceThreshold,connectionMode:connectionMode,hapticTouch:hapticTouch,hapticRelease:hapticRelease),leftLabels:preset.leftLabels,rightLabels:preset.rightLabels,
            trackpadSize:size,trackpadWidthMm:160)
        run.engine.updateActiveDevices(leftIndex:left,rightIndex:right,leftDeviceID:"42",rightDeviceID:"43")
        run.engine.setListening(true)
        return run
    }
    private func contact(_ key:StenoKey,preset:TrackpadLayoutPreset,side:TrackpadSide,id:Int32 = 1) -> OMSRawTouch {
        let labels = side == .left ? preset.leftLabels:preset.rightLabels
        let layout = StenoLayoutDefinition.layout(preset:preset,side:side,size:.init(width:432,height:310.23))
        for row in labels.indices { for col in labels[row].indices where labels[row][col] == key.label {
            let rect = layout.normalizedKeyRects[row][col]
            return .init(id:id,posX:Float(rect.centerX),posY:Float(1-rect.centerY),total:1,pressure:100,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        } }
        fatalError("Missing steno key")
    }
    private func frame(_ run:ProductionReplaySession,_ time:Double,_ index:Int,_ touches:[OMSRawTouch]) {
        run.ingest(.init(sequence:UInt64(time*10000),timestamp:time,deviceNumericID:index == 4 ? 42:43,deviceIndex:index,contacts:[],rawTouches:touches))
    }
    private func packets(_ run:ProductionReplaySession) -> [String] {
        run.output.events.compactMap { if case let .systemKey(label) = $0.kind, label.hasPrefix("GeminiPR:") { return label }; return nil }
    }
    func testBothPresetsKeepVoyagerKeysAndAsteriskGeometryDistinct() throws {
        for preset in [TrackpadLayoutPreset.steno,.stenoVoyager] {
            XCTAssertTrue(TrackpadLayoutPreset.selectableCases.contains(preset))
            XCTAssertEqual(TrackpadLayoutPreset.resolveByName(preset.rawValue),preset)
            for side in [TrackpadSide.left,.right] {
                let layout = StenoLayoutDefinition.layout(preset:preset,side:side,size:.init(width:432,height:310.23))
                let labels = side == .left ? preset.leftLabels:preset.rightLabels
                XCTAssertTrue(layout.isSteno); XCTAssertFalse(layout.allowHoldBindings)
                XCTAssertEqual(layout.normalizedKeyRects.map(\.count),labels.map(\.count))
                for key in layout.normalizedKeyRects.flatMap({$0}) {
                    XCTAssertGreaterThanOrEqual(key.x,0); XCTAssertLessThanOrEqual(key.x+key.width,1)
                    XCTAssertGreaterThanOrEqual(key.y,0); XCTAssertLessThanOrEqual(key.y+key.height,1)
                }
            }
        }
        XCTAssertNotEqual(TrackpadLayoutPreset.steno.leftLabels,TrackpadLayoutPreset.stenoVoyager.leftLabels)
        XCTAssertEqual(TrackpadLayoutPreset.stenoVoyager.leftLabels[0], [StenoKey.n5,.n4,.n3,.n2,.n1,.nc].map(\.label))
        XCTAssertTrue(TrackpadLayoutPreset.steno.leftLabels[3].contains(StenoKey.a.label))
        XCTAssertTrue(TrackpadLayoutPreset.steno.rightLabels[3].contains(StenoKey.u.label))
    }
    func testProductionEngineRoutesArbitraryNativeIndicesAndAllUpToOnePacket() {
        for preset in [TrackpadLayoutPreset.steno,.stenoVoyager] {
            let run = session(preset)
            frame(run,1,4,[contact(.tl,preset:preset,side:.left)])
            frame(run,1.05,7,[contact(.fr,preset:preset,side:.right)])
            frame(run,1.1,4,[])
            XCTAssertTrue(packets(run).isEmpty)
            frame(run,1.15,7,[])
            XCTAssertEqual(packets(run),[GeminiPRPacket.recordingLabel(for:StenoKey.tl.bit|StenoKey.fr.bit)])
            run.finish(at:2)
            XCTAssertTrue(run.output.events.allSatisfy { if case .systemKey = $0.kind { return true }; return false })
            XCTAssertNil(GeminiPRPort.shared.snapshot.path) // Replay never opened the live endpoint.
        }
    }
    func testSingleFingertipCanChordAdjacentUpperAndLowerRowKeys() {
        let run = session()
        var point = contact(.tl,preset:.steno,side:.left)
        // T-/K- seam between upper/lower rectangles; the 1.5 mm edge region hits both.
        point = .init(id:point.id,posX:point.posX,posY:Float(1-0.42),total:1,pressure:100,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        frame(run,1,4,[point]); frame(run,1.1,4,[])
        XCTAssertEqual(packets(run),[GeminiPRPacket.recordingLabel(for:StenoKey.tl.bit|StenoKey.kl.bit)])
    }
    func testSwitchingLayoutsWithHeldContactsCancelsAndCannotTypeTheirOldPositions() {
        let run = session()
        let held = contact(.tl,preset:.steno,side:.left)
        frame(run,1,4,[held])
        let size = CGSize(width:432,height:310.23)
        let normal = ContentViewModel.Layout(normalizedKeyRects:[[.init(x:0,y:0,width:1,height:1)]],trackpadSize:size)
        run.engine.updateLayouts(leftLayout:normal,rightLayout:normal,leftLabels:[["A"]],rightLabels:[["A"]],trackpadSize:size,trackpadWidthMm:160)
        frame(run,1.05,4,[held]); frame(run,1.1,4,[])
        XCTAssertTrue(run.output.events.isEmpty)
        frame(run,1.2,4,[held]); frame(run,1.25,4,[])
        XCTAssertTrue(run.output.events.contains { if case .keyStroke = $0.kind { return true }; return false })
        XCTAssertTrue(packets(run).isEmpty)
    }
    func testLayoutRenderingPreview() throws {
        guard let folder = ProcessInfo.processInfo.environment["STENO_PREVIEW_DIR"] else { return }
        for preset in [TrackpadLayoutPreset.steno,.stenoVoyager] {
            let size = CGSize(width:432,height:310)
            var snapshot = TrackpadSurfaceSnapshot.empty
            snapshot.trackpadSize = size; snapshot.spacing = 16; snapshot.showDetailed = true
            snapshot.leftLayout = StenoLayoutDefinition.layout(preset:preset,side:.left,size:size)
            snapshot.rightLayout = StenoLayoutDefinition.layout(preset:preset,side:.right,size:size)
            snapshot.leftLabels = preset.leftLabels.map { $0.map { TrackpadSurfaceLabel(primary:KeyActionCatalog.action(for:$0)?.displayText ?? $0) } }
            snapshot.rightLabels = preset.rightLabels.map { $0.map { TrackpadSurfaceLabel(primary:KeyActionCatalog.action(for:$0)?.displayText ?? $0) } }
            let view = TrackpadSurfaceView(frame:.init(x:0,y:0,width:880,height:310))
            view.snapshot = snapshot
            let image = NSImage(size:view.bounds.size)
            image.lockFocusFlipped(true)
            NSColor.windowBackgroundColor.setFill(); view.bounds.fill(); view.draw(view.bounds)
            image.unlockFocus()
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(image.tiffRepresentation)))
            try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:folder+"/"+preset.rawValue+".png"))
        }
    }
    func testProductionMouseReplayRecordsIntentionWithoutSerialOrNativeOutput() {
        for mode in [StenoPointerMode.twoFinger] {
            let run = session(pointerMode:mode)
            var first = contact(.tl,preset:.steno,side:.left)
            let other = contact(.pl,preset:.steno,side:.left,id:2)
            let before = mode == .twoFinger ? [first,other]:[first]
            frame(run,1,4,before)
            func moved(_ touch:OMSRawTouch) -> OMSRawTouch {
                .init(id:touch.id,posX:touch.posX+0.025,posY:touch.posY,total:1,pressure:50,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
            }
            frame(run,1.02,4,before.map(moved)); frame(run,1.04,4,[])
            XCTAssertTrue(packets(run).isEmpty)
            XCTAssertTrue(run.output.acceptedBindings.isEmpty)
            XCTAssertTrue(run.output.events.contains { if case let .systemKey(label) = $0.kind { return label.hasPrefix("StenoMouse:42:move") }; return false })
            XCTAssertTrue(run.output.events.allSatisfy { if case .systemKey = $0.kind { return true }; return false })
            XCTAssertNil(GeminiPRPort.shared.snapshot.path)
            // A fresh stationary press after pointer all-up still writes a chord.
            first = contact(.tl,preset:.steno,side:.left)
            frame(run,1.06,4,[first]); frame(run,1.08,4,[])
            XCTAssertEqual(packets(run),[GeminiPRPacket.recordingLabel(for:StenoKey.tl.bit)])
            XCTAssertEqual(run.output.acceptedBindings.map(\.label),[StenoKey.tl.legend])
            XCTAssertEqual(run.output.acceptedBindings.map(\.side),[.left])
        }
    }
    func testProductionForceClickReplayRecordsPrimaryAndSecondaryWithoutNativeOutput() {
        for mode in [StenoPointerMode.twoFinger] {
            for count in [mode.count,3] {
                let run = session(pointerMode:mode)
                let keys:[StenoKey] = [.tl,.pl,.hl]
                let fingers = (0..<count).map { index -> OMSRawTouch in
                    let point = contact(keys[index],preset:.steno,side:.left,id:Int32(index+1))
                    return .init(id:point.id,posX:point.posX,posY:point.posY,total:1,pressure:140,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
                }
                frame(run,1,4,fingers); frame(run,1.02,4,fingers); frame(run,1.04,4,[])
                let expected = count == 3 ? "StenoMouse:42:rightClick":"StenoMouse:42:click"
                XCTAssertEqual(run.output.events.filter { if case let .systemKey(label) = $0.kind { return label == expected }; return false }.count,1)
                XCTAssertTrue(packets(run).isEmpty)
                XCTAssertTrue(run.output.events.allSatisfy { if case .systemKey = $0.kind { return true }; return false })
                XCTAssertNil(GeminiPRPort.shared.snapshot.path)
            }
        }
    }
    func testReconfiguringStenoWithHeldContactsCancelsPartialStroke() {
        let run = session(pointerMode:.twoFinger)
        let point = contact(.tl,preset:.steno,side:.left)
        frame(run,1,4,[point])
        let size = CGSize(width:432,height:310.23)
        run.engine.updateLayouts(leftLayout:StenoLayoutDefinition.layout(preset:.steno,side:.left,size:size,pointerMode:.twoFinger),
            rightLayout:StenoLayoutDefinition.layout(preset:.steno,side:.right,size:size,pointerMode:.twoFinger),
            leftLabels:TrackpadLayoutPreset.steno.leftLabels,rightLabels:TrackpadLayoutPreset.steno.rightLabels,trackpadSize:size,trackpadWidthMm:160)
        frame(run,1.02,4,[point]); frame(run,1.04,4,[])
        XCTAssertTrue(run.output.events.isEmpty)
        frame(run,1.06,4,[point]); frame(run,1.08,4,[])
        XCTAssertEqual(packets(run),[GeminiPRPacket.recordingLabel(for:StenoKey.tl.bit)])
    }
    func testProductionDragReplayRecordsBeginReleaseAndLifecycleCleanupOnly() {
        for reason in ["lift","reset","mapping","custom","disconnect","layout"] {
            let run = session(pointerMode:.twoFinger)
            let point = contact(.tl,preset:.steno,side:.left)
            let held = OMSRawTouch(id:point.id,posX:point.posX,posY:point.posY,total:1,pressure:140,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
            frame(run,1,4,[held]); frame(run,1.02,4,[held])
            switch reason {
            case "reset": run.engine.resetState()
            case "mapping": run.engine.updateKeyMappings([:])
            case "custom": run.engine.updateCustomButtons([])
            case "disconnect": run.engine.updateActiveDevices(leftIndex:nil,rightIndex:7,leftDeviceID:nil,rightDeviceID:"43")
            case "layout":
                let size = CGSize(width:432,height:310.23)
                let normal = ContentViewModel.Layout(normalizedKeyRects:[[.init(x:0,y:0,width:1,height:1)]],trackpadSize:size)
                run.engine.updateLayouts(leftLayout:normal,rightLayout:normal,leftLabels:[["A"]],rightLabels:[["A"]],trackpadSize:size,trackpadWidthMm:160)
            default: frame(run,1.04,4,[])
            }
            let intentions = run.output.events.compactMap { if case let .systemKey(label) = $0.kind { return label }; return nil }
            XCTAssertEqual(intentions.filter { $0 == "StenoMouse:42:dragBegin" }.count,1,reason)
            XCTAssertTrue(intentions.contains("StenoMouse:42:reset"),reason)
            XCTAssertTrue(packets(run).isEmpty,reason)
            XCTAssertNil(GeminiPRPort.shared.snapshot.path)
        }
    }
    func testThresholdChangeReleasesDragAndCannotReactivateHeldContacts() {
        let run = session(pointerMode:.twoFinger)
        let point = contact(.tl,preset:.steno,side:.left)
        let held = OMSRawTouch(id:point.id,posX:point.posX,posY:point.posY,total:1,pressure:140,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        frame(run,1,4,[held])
        let size = CGSize(width:432,height:310.23)
        run.engine.updateLayouts(leftLayout:StenoLayoutDefinition.layout(preset:.steno,side:.left,size:size,pointerMode:.twoFinger,forceThreshold:90),
            rightLayout:StenoLayoutDefinition.layout(preset:.steno,side:.right,size:size,pointerMode:.twoFinger,forceThreshold:90),
            leftLabels:TrackpadLayoutPreset.steno.leftLabels,rightLabels:TrackpadLayoutPreset.steno.rightLabels,trackpadSize:size,trackpadWidthMm:160)
        frame(run,1.02,4,[held]); frame(run,1.04,4,[])
        var intentions = run.output.events.compactMap { if case let .systemKey(label) = $0.kind { return label }; return nil }
        XCTAssertEqual(intentions.filter { $0 == "StenoMouse:42:dragBegin" }.count,1)
        XCTAssertTrue(intentions.contains("StenoMouse:42:reset"))
        frame(run,1.06,4,[held]); frame(run,1.08,4,[])
        intentions = run.output.events.compactMap { if case let .systemKey(label) = $0.kind { return label }; return nil }
        XCTAssertEqual(intentions.filter { $0 == "StenoMouse:42:dragBegin" }.count,2)
        XCTAssertTrue(packets(run).isEmpty)
    }
    func testStenoHapticCheckboxesAreIndependentAndReplayNeverOpensEitherTransport() {
        for touch in [false,true] { for release in [false,true] {
            let run = session(pointerMode:.twoFinger,connectionMode:.plugin,hapticTouch:touch,hapticRelease:release)
            run.engine.updateHapticStrength(0.25)
            XCTAssertTrue(run.output.events.isEmpty)
            let point = contact(.tl,preset:.steno,side:.left)
            frame(run,1,4,[point]); frame(run,1.02,4,[point]); frame(run,1.1,4,[point]); frame(run,1.15,4,[])
            let pulses = run.output.events.filter { if case .haptic = $0.kind { return true }; return false }
            XCTAssertEqual(pulses.count,(touch ? 1:0)+(release ? 1:0))
            XCTAssertNil(GeminiPRPort.shared.snapshot.path); XCTAssertEqual(PloverConnection.shared.snapshot.port,0)
        } }
        let run = session(pointerMode:.twoFinger,hapticTouch:true,hapticRelease:true)
        // Strength zero suppresses feedback even when both boxes are checked.
        let point = contact(.tl,preset:.steno,side:.left)
        frame(run,1,4,[point]); frame(run,1.05,4,[])
        XCTAssertFalse(run.output.events.contains { if case .haptic = $0.kind { return true }; return false })
    }
    func testStenoPluginPanelPreview() throws {
        guard let path = ProcessInfo.processInfo.environment["STENO_PLUGIN_PREVIEW_PATH"] else { return }
        let view = NSHostingView(rootView:StenoConnectionPanel(forceThreshold:.constant(130),connectionMode:.constant(.plugin),hapticTouch:.constant(true),hapticRelease:.constant(true)).padding(12).frame(width:360).background(Color(nsColor:.windowBackgroundColor)))
        view.frame = .init(origin:.zero,size:view.fittingSize); view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds))
        view.cacheDisplay(in:view.bounds,to:bitmap)
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:path))
    }
    func testPluginIsDefaultAndSerialChoiceRemainsExplicit() {
        XCTAssertEqual(HandGestureSettings().resolvedStenoConnectionMode,.plugin)
        var settings = HandGestureSettings(); settings.stenoConnectionMode = .serial
        XCTAssertEqual(settings.resolvedStenoConnectionMode,.serial)
        XCTAssertEqual(StenoLayoutDefinition.layout(preset:.steno,side:.left,size:.init(width:432,height:310)).stenoConnectionMode,.plugin)
    }
    func testMousePanelPreview() throws {
        guard let path = ProcessInfo.processInfo.environment["STENO_MOUSE_PREVIEW_PATH"] else { return }
        let view = NSHostingView(rootView:StenoConnectionPanel(forceThreshold:.constant(130)).padding(12).frame(width:360).background(Color(nsColor:.windowBackgroundColor)))
        view.frame = .init(origin:.zero,size:view.fittingSize)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds))
        view.cacheDisplay(in:view.bounds,to:bitmap)
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:path))
    }
    func testStenoKeysSettingsAndWireKeycodesRoundTrip() throws {
        for key in StenoKey.allCases {
            XCTAssertEqual(KeyActionCatalog.action(for:key.label),key.action)
            XCTAssertEqual(try JSONDecoder().decode(KeyAction.self,from:JSONEncoder().encode(key.action)),key.action)
        }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(AppKeymapProfile.defaultProfile())) as? [String:Any])
        object["layoutPreset"] = "STENO Voyager"
        object["keyMappingsByLayout"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(["STENO Voyager":[0:["left:1:1":KeyMapping(primary:StenoKey.s1.action,hold:nil)]]]))
        let profile = try JSONDecoder().decode(AppKeymapProfile.self,from:JSONSerialization.data(withJSONObject:object))
        let restored = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
        XCTAssertEqual(restored.layoutPreset,"STENO Voyager")
        XCTAssertEqual(restored.keyMappingsByLayout?["STENO Voyager"]?[0]?["left:1:1"]?.primary,StenoKey.s1.action)
    }
}

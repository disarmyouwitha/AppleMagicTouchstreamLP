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
        XCTAssertNil(chord.process(device:1,time:100.2,touches:[],regions:regions,size:size))
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

@MainActor final class StenoLayoutTests:XCTestCase {
    private func session(_ preset:TrackpadLayoutPreset = .steno,left:Int = 4,right:Int = 7) -> ProductionReplaySession {
        let run = ProductionReplaySession(startTime:1)
        let size = CGSize(width:432,height:310.23)
        run.engine.updateLayouts(leftLayout:StenoLayoutDefinition.layout(preset:preset,side:.left,size:size),
            rightLayout:StenoLayoutDefinition.layout(preset:preset,side:.right,size:size),leftLabels:preset.leftLabels,rightLabels:preset.rightLabels,
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

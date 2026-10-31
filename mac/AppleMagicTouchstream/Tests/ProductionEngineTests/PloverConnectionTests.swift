import AppKit
import Darwin
import Foundation
import XCTest
@testable import GlassToKeyRuntime

@MainActor final class PloverConnectionTests:XCTestCase {
    private func wait(_ condition:()->Bool,seconds:Double = 4) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while !condition(), Date() < end { Thread.sleep(forTimeInterval:0.01) }
        return condition()
    }
    private func client(_ port:UInt16) throws -> Int32 {
        let fd = socket(AF_INET,SOCK_STREAM,0)
        guard fd >= 0 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno)) }
        var timeout = timeval(tv_sec:2,tv_usec:0), one:Int32 = 1
        setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&one,socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr:INADDR_LOOPBACK.bigEndian)
        let result = withUnsafePointer(to:&address) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard result == 0 else { Darwin.close(fd); throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno)) }
        return fd
    }
    private func write(_ fd:Int32,_ bytes:[UInt8]) { XCTAssertEqual(bytes.withUnsafeBytes { Darwin.send(fd,$0.baseAddress,bytes.count,0) },bytes.count) }
    private func read(_ fd:Int32,_ length:Int) -> [UInt8] {
        var result:[UInt8] = []
        while result.count < length {
            let remaining = length-result.count
            var bytes = [UInt8](repeating:0,count:remaining)
            let n = bytes.withUnsafeMutableBytes { recv(fd,$0.baseAddress,remaining,0) }
            if n <= 0 { break }; result.append(contentsOf:bytes.prefix(n))
        }
        return result
    }
    func testPrivateLoopbackHandshakeBinaryPacketsInvalidClientAndPortConflict() throws {
        let server = PloverConnection(port:0)
        XCTAssertEqual(server.snapshot.port,0)
        server.start(); defer { server.stop() }
        let port = server.snapshot.port
        XCTAssertNotEqual(port,0)
        XCTAssertFalse(server.send(StenoKey.s1.bit)) // No backlog for a future Plover.
        let conflict = PloverConnection(port:port); conflict.start(); defer { conflict.stop() }
        XCTAssertNotNil(conflict.snapshot.error)
        let bad = try client(port); write(bad,Array("BAD\n".utf8))
        XCTAssertTrue(read(bad,1).isEmpty); Darwin.close(bad)
        let fd = try client(port); defer { Darwin.close(fd) }
        write(fd,Array("AMT-GEM".utf8)); Thread.sleep(forTimeInterval:0.05)
        XCTAssertFalse(server.snapshot.connected)
        write(fd,Array("INIPR/1\n".utf8))
        XCTAssertEqual(read(fd,6),Array("READY\n".utf8))
        XCTAssertTrue(wait { server.snapshot.connected })
        let mask = StenoKey.kl.bit|StenoKey.pl.bit|StenoKey.hl.bit
        XCTAssertTrue(server.send(mask))
        XCTAssertEqual(read(fd,6),GeminiPRPacket.bytes(for:mask)) // Raw CR, not text/lines.
        server.flush(); XCTAssertFalse(server.snapshot.connected)
        XCTAssertFalse(server.send(StenoKey.zr.bit))
        server.stop(); XCTAssertEqual(server.snapshot.port,0)
    }
    func testUnavailableListenerAutomaticallyRecoversAndRetryPreservesHealthyConnection() throws {
        let first = PloverConnection(port:0); first.start()
        let port = first.snapshot.port
        let recovering = PloverConnection(port:port); recovering.start()
        defer { first.stop(); recovering.stop() }
        XCTAssertNotNil(recovering.snapshot.error)
        first.stop()
        XCTAssertTrue(wait { recovering.snapshot.port == port && recovering.snapshot.error == nil })
        let fd = try client(port); defer { Darwin.close(fd) }
        write(fd,Array("AMT-GEMINIPR/1\n".utf8)); XCTAssertEqual(read(fd,6),Array("READY\n".utf8))
        XCTAssertTrue(wait { recovering.snapshot.connected })
        recovering.retry(); XCTAssertTrue(recovering.snapshot.connected)
        XCTAssertTrue(recovering.send(StenoKey.s1.bit)); XCTAssertEqual(read(fd,6),GeminiPRPacket.bytes(for:StenoKey.s1.bit))
        recovering.stop(); recovering.retry()
        XCTAssertEqual(recovering.snapshot.port,0) // UI/timer retries cannot resurrect a stopped transport.
    }
    private func python() throws -> URL {
        guard let path = PloverPluginInstaller.python(in:URL(fileURLWithPath:"/Applications/Plover.app")) else {
            throw XCTSkip("Plover is not installed; bundled-runtime integration is optional.")
        }
        return path
    }
    func testRealPloverMachineReceivesExactStrokesAndReconnectsWithoutNativeOutput() throws {
        let python = try python(), wheel = try XCTUnwrap(PloverPluginInstaller.wheelURL)
        let server = PloverConnection(port:0); server.start(); defer { server.stop() }
        let process = Process(), pipe = Pipe()
        process.executableURL = python
        process.arguments = ["-B","-c",#"""
        import sys, time, json
        sys.path.insert(0, sys.argv[1])
        import plover_applemagictouchstream.machine as plugin
        plugin.PORT = int(sys.argv[2])
        machine = plugin.AppleMagicTouchstream({})
        strokes = []
        def receive(keys):
            strokes.append(keys)
            print(json.dumps(sorted(keys)), flush=True)
        machine.add_stroke_callback(receive)
        machine.start_capture()
        try:
            until = time.monotonic() + 8
            while len(strokes) < 3 and time.monotonic() < until:
                time.sleep(.01)
            assert len(strokes) == 3, strokes
        finally:
            machine.stop_capture()
        """#,wheel.path,String(server.snapshot.port)]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run(); defer { if process.isRunning { process.terminate() } }
        XCTAssertTrue(wait { server.snapshot.connected })
        XCTAssertTrue(server.send(StenoKey.kl.bit|StenoKey.pl.bit|StenoKey.hl.bit))
        let first = pipe.fileHandleForReading.availableData
        XCTAssertEqual(Set(try JSONDecoder().decode([String].self,from:first)),Set(["K-","P-","H-"]))
        server.flush()
        XCTAssertTrue(wait { server.snapshot.connected })
        XCTAssertTrue(server.send(StenoKey.tl.bit|StenoKey.fr.bit)); XCTAssertTrue(server.send(StenoKey.zr.bit))
        let rest = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus,0)
        let lines = String(decoding:rest,as:UTF8.self).split(separator:"\n")
        XCTAssertEqual(lines.count,2)
        if lines.count == 2 {
            XCTAssertEqual(Set(try JSONDecoder().decode([String].self,from:Data(lines[0].utf8))),Set(["T-","-F"]))
            XCTAssertEqual(try JSONDecoder().decode([String].self,from:Data(lines[1].utf8)),["-Z"])
        }
        XCTAssertNil(GeminiPRPort.shared.snapshot.path)
        XCTAssertEqual(PloverConnection.shared.snapshot.port,0)
    }
    func testInstallerLoadsBundledWheelIntoIsolatedRealPloverProfile() throws {
        let python = try python(), wheel = try XCTUnwrap(PloverPluginInstaller.wheelURL)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("amt-plover-test-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        XCTAssertEqual(PloverPluginInstaller.probe(python:python,wheel:wheel,configurationDirectory:folder).state,"missing")
        let process = Process(), pipe = Pipe()
        process.executableURL = python
        let script = "import sys\nimport plover.oslayer.config as config\nconfig.CONFIG_DIR = sys.argv[2]\n"+PloverPluginInstaller.installScript
        process.arguments = ["-B","-c",script,wheel.path,folder.path]
        process.standardOutput = pipe; process.standardError = pipe
        try process.run(); let log = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus,0,String(decoding:log,as:UTF8.self))
        let check = Process(), output = Pipe()
        check.executableURL = python
        check.arguments = ["-B","-c","from importlib.metadata import distribution; d=distribution('plover-applemagictouchstream'); e=next(e for e in d.entry_points if e.group=='plover.machine'); c=e.load(); assert c.KEYMAP_MACHINE_TYPE=='Gemini PR'; print(d.locate_file(''))"]
        var env = ProcessInfo.processInfo.environment; env["PYTHONUSERBASE"] = folder.appendingPathComponent("plugins/mac").path
        check.environment = env; check.standardOutput = output; check.standardError = output
        try check.run(); let result = output.fileHandleForReading.readDataToEndOfFile(); check.waitUntilExit()
        XCTAssertEqual(check.terminationStatus,0,String(decoding:result,as:UTF8.self))
        XCTAssertTrue(String(decoding:result,as:UTF8.self).contains(folder.path))
        let installed = PloverPluginInstaller.probe(python:python,wheel:wheel,configurationDirectory:folder)
        XCTAssertEqual(installed.state,"current"); XCTAssertEqual(installed.version,"0.1.0")
        let root = String(decoding:result,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
        let machine = URL(fileURLWithPath:root).appendingPathComponent("plover_applemagictouchstream/machine.py")
        var bytes = try Data(contentsOf:machine); bytes.append(Data("\n# stale installed source\n".utf8)); try bytes.write(to:machine)
        XCTAssertEqual(PloverPluginInstaller.probe(python:python,wheel:wheel,configurationDirectory:folder).state,"outdated")
    }
}

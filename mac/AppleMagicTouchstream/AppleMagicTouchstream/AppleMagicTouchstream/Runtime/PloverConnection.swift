import AppKit
import Darwin
import Foundation
import os
import UniformTypeIdentifiers

// Same handshake and packet framing as the bundled Windows/Linux Plover plugin.
final class PloverConnection:@unchecked Sendable {
    static let shared = PloverConnection()
    struct Snapshot:Sendable { var port:UInt16; var connected:Bool; var sent:UInt64; var dropped:UInt64; var error:String? }
    private struct State {
        var listener:Int32 = -1, client:Int32 = -1
        var port:UInt16 = 0
        var enabled = false
        var nextRetry:UInt64 = 0
        var ready = false
        var hello:[UInt8] = []
        var accepted:UInt64 = 0, sent:UInt64 = 0, dropped:UInt64 = 0
        var error:String?
        var timer:(any DispatchSourceTimer)?
    }
    private let state = OSAllocatedUnfairLock(initialState:State())
    private let queue = DispatchQueue(label:"ink.ranna.applemagictouchstream.plover",qos:.userInteractive)
    private let requestedPort:UInt16
    init(port:UInt16 = 31572) { requestedPort = port }
    var snapshot:Snapshot { state.withLock { .init(port:$0.port,connected:$0.ready,sent:$0.sent,dropped:$0.dropped,error:$0.error) } }
    func start() { start(onlyIfEnabled:false) }
    private func start(onlyIfEnabled:Bool) {
        state.withLock { value in
            if onlyIfEnabled && !value.enabled { return }
            value.enabled = true
            if value.timer == nil {
                let timer = DispatchSource.makeTimerSource(queue:queue)
                timer.schedule(deadline:.now(),repeating:.milliseconds(25),leeway:.milliseconds(2))
                timer.setEventHandler { [weak self] in self?.tick() }
                value.timer = timer; timer.resume()
            }
            guard value.listener < 0 else { return }
            value.nextRetry = DispatchTime.now().uptimeNanoseconds+1_000_000_000
            let fd = socket(AF_INET,SOCK_STREAM,0)
            guard fd >= 0 else { value.error = "Could not create Plover connection."; return }
            // Permit immediate rebinding after our previous accepted TCP session.
            // SO_REUSEPORT stays off: another live listener must remain exclusive.
            var reuse:Int32 = 1
            _ = setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&reuse,socklen_t(MemoryLayout<Int32>.size))
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
            address.sin_port = requestedPort.bigEndian; address.sin_addr = in_addr(s_addr:INADDR_LOOPBACK.bigEndian)
            let bound = withUnsafePointer(to:&address) { pointer in pointer.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size)) } }
            guard bound == 0, listen(fd,1) == 0, fcntl(fd,F_SETFL,O_NONBLOCK) == 0, fcntl(fd,F_SETFD,FD_CLOEXEC) == 0 else {
                Darwin.close(fd); value.error = "Plover connection unavailable (port \(requestedPort) may already be in use)."; return
            }
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to:&address) { pointer in pointer.withMemoryRebound(to:sockaddr.self,capacity:1) { getsockname(fd,$0,&length) } }
            value.listener = fd; value.port = UInt16(bigEndian:address.sin_port); value.error = nil

        }
    }
    /// Retry only an unavailable listener; never interrupt a healthy client.
    func retry() {
        start(onlyIfEnabled:true)
    }
    private func tick() {
        let needsRetry = state.withLock { $0.enabled && $0.listener < 0 && DispatchTime.now().uptimeNanoseconds >= $0.nextRetry }
        if needsRetry { retry() }
        state.withLock { value in
            guard value.listener >= 0 else { return }
            if value.client < 0 {
                let fd = accept(value.listener,nil,nil)
                guard fd >= 0 else { return }
                guard fcntl(fd,F_SETFL,O_NONBLOCK) == 0, fcntl(fd,F_SETFD,FD_CLOEXEC) == 0 else { Darwin.close(fd); return }
                var one:Int32 = 1, bufferSize:Int32 = 1024
                _ = setsockopt(fd,SOL_SOCKET,SO_SNDBUF,&bufferSize,socklen_t(MemoryLayout<Int32>.size))
                _ = setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&one,socklen_t(MemoryLayout<Int32>.size))
                _ = setsockopt(fd,IPPROTO_TCP,TCP_NODELAY,&one,socklen_t(MemoryLayout<Int32>.size))
                value.client = fd; value.accepted = DispatchTime.now().uptimeNanoseconds
            }
            var bytes = [UInt8](repeating:0,count:64)
            let count = bytes.withUnsafeMutableBytes { recv(value.client,$0.baseAddress,64,0) }
            if count == 0 { Self.closeClient(&value); return }
            if count < 0 {
                if errno != EAGAIN && errno != EWOULDBLOCK { Self.closeClient(&value) }
                else if !value.ready, DispatchTime.now().uptimeNanoseconds-value.accepted > 3_000_000_000 { Self.closeClient(&value) }
                return
            }
            guard !value.ready else { Self.closeClient(&value); return } // Protocol is one-way after HELLO.
            value.hello.append(contentsOf:bytes.prefix(count))
            let expected = Array("AMT-GEMINIPR/1\n".utf8)
            guard value.hello.count <= expected.count, expected.starts(with:value.hello) else { Self.closeClient(&value); return }
            if value.hello.count == expected.count {
                let ready = Array("READY\n".utf8)
                let written = ready.withUnsafeBytes { Darwin.send(value.client,$0.baseAddress,ready.count,0) }
                guard written == ready.count else { Self.closeClient(&value); return }
                value.ready = true; value.error = nil; value.hello.removeAll(keepingCapacity:true)
            }
        }
    }
    @discardableResult func send(_ mask:UInt64) -> Bool {
        guard mask != 0, mask & ~GeminiPRPacket.keyMask == 0 else { return false }
        let bytes = GeminiPRPacket.bytes(for:mask)
        return state.withLock { value in
            guard value.ready else { value.dropped &+= 1; return false }
            let count = bytes.withUnsafeBytes { Darwin.send(value.client,$0.baseAddress,bytes.count,0) }
            if count == bytes.count { value.sent &+= 1; return true }
            value.dropped &+= 1
            // Disconnect even on a full buffer: never splice a future stroke onto
            // a partial packet or carry stale output into a reconnect.
            Self.closeClient(&value); return false
        }
    }
    func flush() { state.withLock { Self.closeClient(&$0) } }
    func stop() {
        state.withLock { value in
            value.enabled = false; value.nextRetry = 0
            value.timer?.cancel(); value.timer = nil; Self.closeClient(&value)
            if value.listener >= 0 { Darwin.close(value.listener); value.listener = -1 }
            value.port = 0; value.error = nil
        }
    }
    private static func closeClient(_ value:inout State) {
        if value.client >= 0 { shutdown(value.client,SHUT_RDWR); Darwin.close(value.client); value.client = -1 }
        value.ready = false; value.hello.removeAll(keepingCapacity:true)
    }
    deinit { stop() }
}

enum StenoConnectionMode:String,CaseIterable,Codable,Sendable,Identifiable {
    case javelin, javelinPlover, plugin, serial
    static let defaultMode:Self = .javelin
    var isBuiltIn:Bool { self == .javelin || self == .javelinPlover }
    var dictionaryProfile:JavelinDictionaryProfile { self == .javelinPlover ? .plover:.lapwing }
    var id:String { rawValue }
    var title:String { switch self { case .javelinPlover: "Built-in Javelin (Plover)"; case .plugin: "Plover Plugin"; case .serial: "Gemini PR Serial"; case .javelin: "Built-in Javelin (Lapwing)" } }
}

enum StenoOutputConnection {
    static func configure(enabled:Bool,mode:StenoConnectionMode) {
        if !enabled || mode != .plugin { PloverConnection.shared.stop() }
        if !enabled || mode != .serial { GeminiPRPort.shared.stop() }
        if !enabled || !mode.isBuiltIn { JavelinBackend.shared.stop() }
        guard enabled else { return }
        switch mode {
        case .plugin: PloverConnection.shared.start()
        case .serial: GeminiPRPort.shared.start()
        case .javelin, .javelinPlover: JavelinBackend.shared.start(profile:mode.dictionaryProfile)
        }
    }
    static func flush() { GeminiPRPort.shared.flush(); PloverConnection.shared.flush(); JavelinBackend.shared.reset() }
    static func stop() { GeminiPRPort.shared.stop(); PloverConnection.shared.stop(); JavelinBackend.shared.stop() }
    static func send(_ mask:UInt64,mode:StenoConnectionMode) {
        switch mode {
        case .plugin: _ = PloverConnection.shared.send(mask)
        case .serial: _ = GeminiPRPort.shared.send(mask)
        case .javelin, .javelinPlover: break // Host edits use DispatchService's focus/generation-gated path.
        }
    }
}

/// Installs only on the explicit button press. No application launch or changes
/// to Plover's machine/output preferences. Uses its own Python and offline wheel.
@MainActor final class PloverPluginInstaller:ObservableObject {
    @Published private(set) var installing = false
    @Published private(set) var message:String?
    @Published private(set) var checking = false
    @Published private(set) var installation:InstallationStatus?
    var isInstalled:Bool { installation?.state == "current" }
    private var chosenPlover:URL?
    struct InstallationStatus:Decodable,Sendable {
        var state:String
        var version:String?
        var detail:String?
    }
    static var wheelURL:URL? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        let name = "plover_applemagictouchstream-0.1.0-py3-none-any"
        return bundle.url(forResource:name,withExtension:"whl") ?? bundle.url(forResource:name,withExtension:"whl",subdirectory:"Resources")
    }
    nonisolated static let installScript = """
    import os, sys
    from plover.oslayer.config import CONFIG_DIR, PLUGINS_PLATFORM
    os.environ['PYTHONUSERBASE'] = os.path.join(CONFIG_DIR, 'plugins', PLUGINS_PLATFORM)
    from plover.plugins_manager.__main__ import main
    main(['install', '--no-index', '--no-deps', '--disable-pip-version-check', '--upgrade', '--force-reinstall', sys.argv[1]])
    """
    nonisolated static let probeScript = #"""
    import os, sys, subprocess, json, signal
    signal.alarm(20)
    from plover.oslayer.config import CONFIG_DIR, PLUGINS_PLATFORM
    env = dict(os.environ, PYTHONUSERBASE=os.path.join(CONFIG_DIR, 'plugins', PLUGINS_PLATFORM))
    code = r'''import sys, json, zipfile
    from importlib.metadata import distribution, PackageNotFoundError
    try:
        d = distribution('plover-applemagictouchstream')
        e = next(e for e in d.entry_points if e.group == 'plover.machine' and e.name == 'AppleMagicTouchstream')
        valid = e.value == 'plover_applemagictouchstream.machine:AppleMagicTouchstream'
        with zipfile.ZipFile(sys.argv[1]) as wheel:
            for name in ('machine.py', '__init__.py'):
                path = 'plover_applemagictouchstream/' + name
                valid = valid and d.locate_file(path).read_bytes() == wheel.read(path)
        if valid:
            valid = e.load().KEYMAP_MACHINE_TYPE == 'Gemini PR'
        print(json.dumps({'state':'current' if valid else 'outdated', 'version':d.version}))
    except PackageNotFoundError:
        print(json.dumps({'state':'missing'}))
    except Exception as error:
        print(json.dumps({'state':'outdated', 'detail':str(error)}))
    '''
    try:
        result = subprocess.run([sys.executable, '-B', '-c', code, sys.argv[1]], env=env, capture_output=True, text=True, timeout=12)
        if result.returncode == 0:
            sys.stdout.write(result.stdout)
        else:
            print(json.dumps({'state':'unavailable', 'detail':result.stderr[-1000:]}))
    except Exception as error:
        print(json.dumps({'state':'unavailable', 'detail':str(error)}))
    """#
    nonisolated static func probe(python:URL,wheel:URL,configurationDirectory:URL? = nil) -> InstallationStatus {
        let process = Process(), pipe = Pipe()
        var script = probeScript, arguments:[String] = [wheel.path]
        if let configurationDirectory {
            script = "import sys\nimport plover.oslayer.config as config\nconfig.CONFIG_DIR = sys.argv[2]\n"+script
            arguments.append(configurationDirectory.path)
        }
        process.executableURL = python; process.arguments = ["-B","-c",script]+arguments
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
        do {
            try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            return try JSONDecoder().decode(InstallationStatus.self,from:data)
        } catch { return .init(state:"unavailable",detail:error.localizedDescription) }
    }
    private func availablePlover() -> URL? {
        let candidates = [chosenPlover,URL(fileURLWithPath:"/Applications/Plover.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Plover.app"),
            NSWorkspace.shared.urlForApplication(withBundleIdentifier:"org.openstenoproject.plover")].compactMap { $0 }
        return candidates.first { Self.python(in:$0) != nil }
    }
    func refreshInstallation() {
        guard !checking, !installing else { return }
        guard let app = availablePlover(), let python = Self.python(in:app), let wheel = Self.wheelURL else {
            installation = .init(state:"unavailable"); return
        }
        checking = true
        Task {
            installation = await Task.detached(priority:.utility) { Self.probe(python:python,wheel:wheel) }.value
            checking = false
        }
    }
    static func python(in app:URL) -> URL? {
        let versions = app.appendingPathComponent("Contents/Frameworks/Python.framework/Versions")
        let roots = [versions.appendingPathComponent("Current")] + ((try? FileManager.default.contentsOfDirectory(at:versions,includingPropertiesForKeys:nil)) ?? [])
        for root in roots {
            let bin = root.appendingPathComponent("bin")
            for path in [bin.appendingPathComponent("python3")] + ((try? FileManager.default.contentsOfDirectory(at:bin,includingPropertiesForKeys:nil)) ?? []).filter({$0.lastPathComponent.hasPrefix("python3.") && !$0.lastPathComponent.contains("-")}) {
                if FileManager.default.isExecutableFile(atPath:path.path) { return path }
            }
        }
        return nil
    }
    func install() {
        guard !installing else { return }
        var app = availablePlover()
        if app == nil {
            let panel = NSOpenPanel(); panel.title = "Choose Plover.app"; panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowedContentTypes = [.application]
            guard panel.runModal() == .OK else { return }; app = panel.url
        }
        guard let app, let python = Self.python(in:app), let wheel = Self.wheelURL else { message = "Plover's Python or the bundled plugin is missing."; return }
        chosenPlover = app
        installing = true; message = "Installing…"
        Task {
            let result = await Task.detached(priority:.userInitiated) {
                let process = Process(), pipe = Pipe()
                process.executableURL = python; process.arguments = ["-B","-c",Self.installScript,wheel.path]
                process.standardOutput = pipe; process.standardError = pipe; process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                    let output = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                    return process.terminationStatus == 0 ? "Installed. Restart Plover and select AppleMagicTouchstream under Configure → Machine.":"Install failed: "+String(decoding:output.suffix(2000),as:UTF8.self)
                } catch { return "Install failed: "+error.localizedDescription }
            }.value
            message = result; installing = false
            refreshInstallation()
        }
    }
}

import Foundation
import ReaderCore
import Testing

/// A running SiliconReader driven over its control socket.
///
/// Each session gets its own socket and (unless shared on purpose) its own
/// throwaway library, so tests never see each other's or the user's state.
final class AppSession {
    enum SessionError: Error, CustomStringConvertible {
        case appNotBuilt(String)
        case didNotStart(String)
        case protocolError(String)
        case commandFailed(String)

        var description: String {
            switch self {
            case .appNotBuilt(let m), .didNotStart(let m), .protocolError(let m), .commandFailed(let m): m
            }
        }
    }

    let library: URL
    private let process = Process()
    private let socketPath: String
    private var fd: Int32 = -1

    /// The app bundle from SILICON_READER_APP (set by `make e2e`).
    static func executable() throws -> URL {
        guard let app = ProcessInfo.processInfo.environment["SILICON_READER_APP"] else {
            throw SessionError.appNotBuilt("SILICON_READER_APP is not set; run the e2e tests with `make e2e`")
        }
        let binary = URL(fileURLWithPath: app).appendingPathComponent("Contents/MacOS/SiliconReader")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw SessionError.appNotBuilt("no app at \(binary.path); run `make app` first")
        }
        return binary
    }

    /// Launches the app on `documents`. `persist` turns on per-file state and
    /// session saving (off by default in control runs).
    init(documents: [URL] = [], library: URL? = nil, persist: Bool = false, extraArguments: [String] = []) throws {
        self.library = library ?? Self.temporaryDirectory().appendingPathComponent("library.json")
        // sun_path is limited to 104 bytes, so keep the socket path short.
        socketPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("sr-\(UUID().uuidString.prefix(8)).sock")

        process.executableURL = try Self.executable()
        process.arguments =
            ["-control", socketPath, "-library", self.library.path]
            + (persist ? ["-persist", "YES"] : []) + extraArguments + documents.map(\.path)
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        try connect(within: 15)
    }

    deinit {
        if fd >= 0 { close(fd) }
        if process.isRunning { process.terminate() }
        unlink(socketPath)
    }

    static func temporaryDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sr-e2e-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Commands

    @discardableResult
    func send(_ request: ControlRequest) throws -> ControlResponse {
        var line = try JSONEncoder().encode(request)
        line.append(UInt8(ascii: "\n"))
        try line.withUnsafeBytes { raw in
            guard write(fd, raw.baseAddress, raw.count) == raw.count else {
                throw SessionError.protocolError("write failed: \(errno)")
            }
        }
        let response = try JSONDecoder().decode(ControlResponse.self, from: readLine())
        guard response.ok else { throw SessionError.commandFailed(response.error ?? "\(request.cmd) failed") }
        return response
    }

    func state() throws -> ControlState {
        guard let state = try send(ControlRequest(.state)).state else { throw SessionError.protocolError("no state") }
        return state
    }

    /// Presses a key and returns the state afterwards; fails if nothing handled it.
    @discardableResult
    func press(_ chars: String, _ modifiers: String..., sourceLocation: SourceLocation = #_sourceLocation) throws
        -> ControlState
    {
        let response = try send(ControlRequest(.key, chars: chars, modifiers: modifiers))
        #expect(response.handled == true, "key \(modifiers) \(chars) was not handled", sourceLocation: sourceLocation)
        return try waitUntilSettled()
    }

    @discardableResult
    func waitUntilSettled(timeout: Double = 10) throws -> ControlState {
        guard let state = try send(ControlRequest(.wait, timeout: timeout)).state else {
            throw SessionError.protocolError("no state")
        }
        return state
    }

    /// Polls state until `condition` holds (for changes driven from outside, e.g. a file edit).
    func waitFor(within seconds: Double = 5, _ condition: (ControlState) -> Bool) throws -> ControlState {
        let deadline = Date().addingTimeInterval(seconds)
        var current = try state()
        while !condition(current) && Date() < deadline {
            usleep(50_000)
            current = try state()
        }
        return current
    }

    /// Asks the app to quit and waits for it to exit (saving state if persisting).
    func quit() throws {
        _ = try? send(ControlRequest(.quit))
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning {
            process.terminate()
            throw SessionError.commandFailed("app did not quit within 10 s")
        }
    }

    // MARK: - Socket

    private func connect(within seconds: Double) throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            guard process.isRunning else {
                throw SessionError.didNotStart("app exited with status \(process.terminationStatus)")
            }
            if let socket = try? Self.open(socketPath) {
                fd = socket
                return
            }
            usleep(50_000)
        }
        throw SessionError.didNotStart("control socket did not appear within \(Int(seconds)) s")
    }

    private static func open(_ path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            let bytes = Array(path.utf8)
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Foundation.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            throw SessionError.didNotStart("connect: \(errno)")
        }
        // Never hang a test run on a stuck app.
        var timeout = timeval(tv_sec: 20, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }

    private var pending = Data()

    private func readLine() throws -> Data {
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            if let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = pending[pending.startIndex..<newline]
                pending.removeSubrange(pending.startIndex...newline)
                return Data(line)
            }
            let count = read(fd, &chunk, chunk.count)
            guard count > 0 else { throw SessionError.protocolError("connection closed or timed out") }
            pending.append(contentsOf: chunk[0..<count])
        }
    }
}

/// Test documents in the repository.
enum Documents {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let fixtures = root.appendingPathComponent("Tests/ReaderCoreTests/Fixtures")
    /// 39 pages, outline, text layer.
    static let spec = fixtures.appendingPathComponent("djvu2spec.djvu")
    /// 2 pages; the next file after djvu2spec in the fixtures folder.
    static let lizard = fixtures.appendingPathComponent("lizard2002.djvu")
    /// 60-page PDF from the MuPDF submodule (`make deps`).
    static let pdf = root.appendingPathComponent("Vendor/mupdf/thirdparty/lcms2/doc/LittleCMS2.19 tutorial.pdf")
}

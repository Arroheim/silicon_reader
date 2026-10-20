import Foundation
import ReaderCore

/// Unix-socket server for the debug control channel (`-control <path>`).
///
/// Each connection is served on its own thread: it reads JSON lines, hands
/// each request to `handler` (which runs on the main actor) and writes the
/// JSON response line back. Only meant for tests on the local machine; the
/// socket is created with owner-only permissions.
final class ControlServer: @unchecked Sendable {
    // @unchecked: `listener` is set once in start() before threads exist.
    private let path: String
    private let handler: @Sendable (ControlRequest) async -> ControlResponse
    private var listener: Int32 = -1

    init(path: String, handler: @escaping @Sendable (ControlRequest) async -> ControlResponse) {
        self.path = path
        self.handler = handler
    }

    enum ServerError: Error {
        case pathTooLong
        case socket(String)
    }

    func start() throws {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.socket("socket: \(errno)") }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw ServerError.pathTooLong
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 4) == 0 else {
            close(fd)
            throw ServerError.socket("bind/listen: \(errno)")
        }
        chmod(path, 0o600)
        listener = fd
        Thread.detachNewThread { [self] in acceptLoop() }
    }

    private func acceptLoop() {
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            Thread.detachNewThread { [self] in serve(client) }
        }
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(client, &chunk, chunk.count)
            guard count > 0 else { return }
            buffer.append(contentsOf: chunk[0..<count])
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                guard write(response(for: Data(line)), to: client) else { return }
            }
        }
    }

    private func response(for line: Data) -> Data {
        let response: ControlResponse
        if let request = try? JSONDecoder().decode(ControlRequest.self, from: line) {
            response = runBlocking(request)
        } else {
            response = .failure("cannot decode request: \(String(decoding: line, as: UTF8.self))")
        }
        var data = (try? JSONEncoder().encode(response)) ?? Data("{\"ok\":false}".utf8)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// Waits on this connection's thread for the main-actor handler.
    private func runBlocking(_ request: ControlRequest) -> ControlResponse {
        final class Box: @unchecked Sendable { var value: ControlResponse? }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        let handler = handler
        Task {
            box.value = await handler(request)
            done.signal()
        }
        done.wait()
        return box.value ?? .failure("no response")
    }

    private func write(_ data: Data, to client: Int32) -> Bool {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Foundation.write(client, raw.baseAddress! + offset, raw.count - offset)
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
    }
}

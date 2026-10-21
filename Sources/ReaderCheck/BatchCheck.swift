import Foundation
import ReaderCore

/// Runs `FileCheck` over a folder, one child process per file so a crash or
/// hang in an engine is recorded instead of ending the run.
final class BatchCheck: @unchecked Sendable {
    // @unchecked: `results` and `done` are only touched under `lock`.
    struct Options {
        var folder: URL
        var jobs: Int
        var timeout: TimeInterval
        var report: URL
        var allPages: Bool
    }

    private let options: Options
    private let executable: URL
    private let lock = NSLock()
    private var results: [FileCheckResult] = []
    private var done = 0

    /// Runs children from a private copy of `executable`: a rebuild during a
    /// long run replaces the original and every later file failed to start.
    init(options: Options, executable: URL) {
        self.options = options
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("reader-check-\(getpid())")
        try? FileManager.default.removeItem(at: copy)
        self.executable = (try? FileManager.default.copyItem(at: executable, to: copy)) != nil ? copy : executable
    }

    deinit {
        if executable.lastPathComponent.hasPrefix("reader-check-") {
            try? FileManager.default.removeItem(at: executable)
        }
    }

    func run() -> Int32 {
        let files = Self.documents(in: options.folder)
        guard !files.isEmpty else {
            FileHandle.standardError.write(Data("no PDF or DjVu files in \(options.folder.path)\n".utf8))
            return 1
        }
        print("Checking \(files.count) documents with \(options.jobs) jobs, \(Int(options.timeout)) s timeout…")
        let started = Date()

        // A semaphore-bounded pool of threads, each waiting on one child process.
        let slots = DispatchSemaphore(value: options.jobs)
        let group = DispatchGroup()
        for file in files {
            slots.wait()
            group.enter()
            Thread.detachNewThread { [self] in
                let result = check(file)
                record(result, of: files.count)
                slots.signal()
                group.leave()
            }
        }
        group.wait()

        let sorted = lock.withLock { results.sorted { $0.path < $1.path } }
        writeReport(sorted)
        printSummary(sorted, elapsed: Date().timeIntervalSince(started))
        return sorted.contains { [.failed, .crashed, .timeout].contains($0.status) } ? 1 : 0
    }

    static func documents(in folder: URL) -> [URL] {
        guard
            let walker = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        else { return [] }
        return walker.compactMap { $0 as? URL }
            .filter { FolderNavigation.supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.path < $1.path }
    }

    /// Runs the child, enforcing the timeout; decodes its JSON line.
    private func check(_ file: URL) -> FileCheckResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--file", file.path] + (options.allPages ? ["--all-pages"] : [])
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return FileCheckResult(path: file.path, status: .failed, error: "cannot start checker: \(error)")
        }
        // Read before waiting so a large output can't fill the pipe and block the child.
        let data = output.fileHandleForReading.readDataToEndOfFileOrTimeout(options.timeout, exited: exited)
        if exited.wait(timeout: .now() + options.timeout) == .timedOut {
            process.terminate()
            return FileCheckResult(
                path: file.path, status: .timeout, error: "no result after \(Int(options.timeout)) s")
        }
        if process.terminationReason == .uncaughtSignal {
            return FileCheckResult(
                path: file.path, status: .crashed, error: "checker died with signal \(process.terminationStatus)")
        }
        guard let line = data.split(separator: UInt8(ascii: "\n")).last,
            let result = try? JSONDecoder().decode(FileCheckResult.self, from: Data(line))
        else {
            let error = "unreadable checker output (exit \(process.terminationStatus))"
            return FileCheckResult(path: file.path, status: .failed, error: error)
        }
        return result
    }

    private func record(_ result: FileCheckResult, of total: Int) {
        let count = lock.withLock {
            results.append(result)
            done += 1
            return done
        }
        let mark =
            switch result.status {
            case .ok: "✓"
            case .warning: "!"
            case .password: "🔒"
            default: "✗"
            }
        let name = URL(fileURLWithPath: result.path).lastPathComponent
        let detail = result.error ?? result.warnings.first ?? "\(result.pages) pages, \(Int(result.totalMs)) ms"
        print("[\(count)/\(total)] \(mark) \(name) — \(detail)")
    }

    private func writeReport(_ results: [FileCheckResult]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = results.compactMap { try? encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) }
        try? FileManager.default.createDirectory(
            at: options.report.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (lines.joined(separator: "\n") + "\n").write(to: options.report, atomically: true, encoding: .utf8)
    }

    private func printSummary(_ results: [FileCheckResult], elapsed: TimeInterval) {
        let byStatus = Dictionary(grouping: results, by: \.status)
        print("\n── Summary " + String(repeating: "─", count: 50))
        for status in [FileCheckResult.Status.ok, .warning, .password, .failed, .crashed, .timeout] {
            let label = status.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)
            print("  \(label) \(byStatus[status]?.count ?? 0)")
        }
        let opened = results.filter { $0.status == .ok || $0.status == .warning }
        if !opened.isEmpty {
            let totalPages = opened.reduce(0) { $0 + $1.pages }
            let noText = opened.filter { $0.textChars == 0 }.count
            let slowest = opened.sorted { $0.totalMs > $1.totalMs }.prefix(5)
            let hungriest = opened.max { $0.maxRSSMB < $1.maxRSSMB }
            print("  pages    \(totalPages) in opened documents; \(noText) without a text layer on sampled pages")
            print("  slowest:")
            for result in slowest {
                let name = URL(fileURLWithPath: result.path).lastPathComponent
                print(String(format: "    %6.0f ms  %@", result.totalMs, name))
            }
            if let hungriest {
                let name = URL(fileURLWithPath: hungriest.path).lastPathComponent
                print(String(format: "  peak memory %.0f MB: %@", hungriest.maxRSSMB, name))
            }
        }
        for result in results where ![.ok, .password].contains(result.status) {
            let reason = result.error ?? result.warnings.joined(separator: "; ")
            print("  \(result.status.rawValue): \(URL(fileURLWithPath: result.path).lastPathComponent) — \(reason)")
        }
        print(String(format: "  time     %.0f s; report: %@", elapsed, options.report.path))
    }
}

extension FileHandle {
    /// Reads until EOF, giving up when the child is past its deadline (it is then killed).
    fileprivate func readDataToEndOfFileOrTimeout(_ timeout: TimeInterval, exited: DispatchSemaphore) -> Data {
        final class Box: @unchecked Sendable { var data = Data() }
        let box = Box()
        let finished = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            box.data = self.readDataToEndOfFile()
            finished.signal()
        }
        _ = finished.wait(timeout: .now() + timeout)
        return box.data
    }
}

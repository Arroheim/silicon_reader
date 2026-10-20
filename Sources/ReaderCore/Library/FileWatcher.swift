import Foundation

/// Calls back when a file changes on disk (SumatraPDF's ReloadModifiedDocuments).
///
/// Editors and LaTeX tools often save by writing a new file and renaming it
/// over the old one, which leaves a descriptor on the deleted original. On
/// delete/rename the watcher waits for the path to reappear and re-attaches.
/// Bursts of events are coalesced into one callback after `debounce`.
public final class FileWatcher: @unchecked Sendable {
    // @unchecked: all mutable state is confined to `queue`.
    private let url: URL
    private let debounce: DispatchTimeInterval
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var stopped = false

    public init(
        url: URL, debounce: DispatchTimeInterval = .milliseconds(300), queue: DispatchQueue = .main,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.url = url
        self.debounce = debounce
        self.queue = queue
        self.onChange = onChange
        queue.async { self.attach(retries: 0) }
    }

    deinit {
        source?.cancel()
    }

    public func stop() {
        queue.async {
            self.stopped = true
            self.pending?.cancel()
            self.source?.cancel()
            self.source = nil
        }
    }

    /// Opens the file and listens; retries for up to ~2 s while it is missing.
    private func attach(retries: Int) {
        guard !stopped else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            if retries < 20 {
                queue.asyncAfter(deadline: .now() + .milliseconds(100)) { self.attach(retries: retries + 1) }
            }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .attrib], queue: queue)
        source.setEventHandler { [weak self] in self?.handle(source.data) }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
    }

    private func handle(_ events: DispatchSource.FileSystemEvent) {
        if !events.isDisjoint(with: [.delete, .rename]) {
            source?.cancel()
            source = nil
            attach(retries: 0)
        }
        schedule()
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !stopped else { return }
            onChange()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}

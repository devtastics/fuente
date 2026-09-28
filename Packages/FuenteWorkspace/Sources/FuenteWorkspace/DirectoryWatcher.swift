import CoreServices
import Foundation

/// Watches a folder tree with FSEvents and reports the folders whose contents changed, coalesced and on the
/// main actor. Changes inside `.git` internals are ignored; the working tree is not.
@MainActor
public final class DirectoryWatcher {
    public let rootURL: URL

    /// Called with the distinct folders that changed (the parent folder of each changed file).
    public var onChange: (([URL]) -> Void)?

    nonisolated(unsafe) private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.devtastics.fuente.fsevents")

    /// FSEvents reports real paths (`/private/var/...`); we map them back onto the root as the app knows it.
    private let resolvedRootPath: String

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
        resolvedRootPath = self.rootURL.resolvingSymlinksInPath().path
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    public func start(latency: TimeInterval = 0.25) {
        guard stream == nil else { return }
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            nil, directoryWatcherCallback, &context,
            [rootURL.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Runs on the FSEvents queue: reduces raw paths to their folders and hops to the main actor.
    nonisolated fileprivate func handle(paths: [String], flags: [FSEventStreamEventFlags]) {
        var folders: [URL] = []
        var seen: Set<String> = []
        for (rawPath, flag) in zip(paths, flags) {
            if rawPath.contains("/.git/") || rawPath.hasSuffix("/.git") { continue }
            let isDirectory = flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0
            let path = rawPath.hasPrefix(resolvedRootPath) ? rootURL.path + rawPath.dropFirst(resolvedRootPath.count) : rawPath
            let url = URL(fileURLWithPath: path).standardizedFileURL
            // A folder that itself appeared or vanished is a change in its parent; a folder whose
            // contents changed is reported on the folder. Report the parent in both cases: it covers both.
            let rootPath = rootURL.path
            func isInsideRoot(_ candidate: URL) -> Bool { candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") }
            let parent = url.deletingLastPathComponent()
            if isInsideRoot(parent), seen.insert(parent.path).inserted { folders.append(parent) }
            if isDirectory, isInsideRoot(url), seen.insert(url.path).inserted { folders.append(url) }
        }
        guard !folders.isEmpty else { return }
        Task { @MainActor [weak self] in self?.onChange?(folders) }
    }
}

private let directoryWatcherCallback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
    guard let info else { return }
    let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
    let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
    let flags = Array(UnsafeBufferPointer(start: eventFlags, count: count))
    watcher.handle(paths: paths, flags: flags)
}

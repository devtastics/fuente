import Foundation

/// A file or folder in the project tree. Folders load their children on first access.
@MainActor
public final class FileNode: Identifiable {
    public let url: URL
    public let isDirectory: Bool
    public weak var parent: FileNode?

    nonisolated public var id: URL { url }
    public var name: String { url.lastPathComponent }

    private var loadedChildren: [FileNode]?

    public init(url: URL, isDirectory: Bool, parent: FileNode? = nil) {
        self.url = url.standardizedFileURL
        self.isDirectory = isDirectory
        self.parent = parent
    }

    /// Children sorted folders first, then by name as the Finder does. Hidden files are skipped.
    public var children: [FileNode] {
        if let loadedChildren { return loadedChildren }
        let loaded = isDirectory ? FileNode.scan(url, parent: self) : []
        loadedChildren = loaded
        return loaded
    }

    /// Forgets the cached listing so the next access re-reads the disk.
    public func reload() {
        loadedChildren = nil
    }

    /// Re-reads the folder and merges: nodes for entries that still exist are kept (so an outline view keeps
    /// their expansion and selection), new entries get new nodes, vanished ones go. Returns whether anything changed.
    @discardableResult
    public func refresh() -> Bool {
        guard isDirectory, let current = loadedChildren else { return false }
        let fresh = FileNode.scan(url, parent: self)
        var existing: [URL: FileNode] = [:]
        for child in current { existing[child.url] = child }
        let merged = fresh.map { node -> FileNode in
            if let kept = existing[node.url], kept.isDirectory == node.isDirectory { return kept }
            return node
        }
        let changed = merged.map(\.url) != current.map(\.url)
        loadedChildren = merged
        return changed
    }

    /// The node for a URL inside this subtree, loading folders along the way. `nil` if outside or missing.
    public func node(for target: URL) -> FileNode? {
        let target = target.standardizedFileURL
        if target.path == url.path { return self }
        guard isDirectory, target.path.hasPrefix(url.path + "/") else { return nil }
        for child in children {
            if let found = child.node(for: target) { return found }
        }
        return nil
    }

    private static func scan(_ url: URL, parent: FileNode) -> [FileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return []
        }
        return entries
            .map { entry in
                let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return FileNode(url: entry, isDirectory: isDirectory, parent: parent)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}

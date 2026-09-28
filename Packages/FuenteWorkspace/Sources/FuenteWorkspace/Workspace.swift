import Foundation

/// A project: a root folder, its file tree and the documents open in it.
@MainActor
public final class Workspace {
    public let rootURL: URL
    public let root: FileNode
    public private(set) var documents: [Document] = []
    public private(set) var activeDocument: Document?

    public var name: String { rootURL.lastPathComponent }

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
        self.root = FileNode(url: rootURL, isDirectory: true)
    }

    public func contains(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(rootURL.path + "/")
    }

    public func document(for url: URL) -> Document? {
        let url = url.standardizedFileURL
        return documents.first { $0.url == url }
    }

    /// Opens a file, or activates it if already open. Fails if the file cannot be read.
    @discardableResult
    public func open(_ url: URL) throws -> Document {
        if let existing = document(for: url) {
            activeDocument = existing
            return existing
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw DocumentError.unreadable(url)
        }
        let created = Document(url: url)
        documents.append(created)
        activeDocument = created
        return created
    }

    public func activate(_ document: Document) {
        guard documents.contains(where: { $0 === document }) else { return }
        activeDocument = document
    }

    /// Closes a document. The neighbor becomes active when the closed one was.
    public func close(_ document: Document) {
        guard let index = documents.firstIndex(where: { $0 === document }) else { return }
        documents.remove(at: index)
        if activeDocument === document {
            activeDocument = documents.isEmpty ? nil : documents[min(index, documents.count - 1)]
        }
    }

    public var hasUnsavedChanges: Bool { documents.contains { $0.isDirty } }

    // MARK: - State

    /// Path relative to the root, or `nil` for URLs outside the project.
    public func relativePath(for url: URL) -> String? {
        let path = url.standardizedFileURL.path
        let root = rootURL.path + "/"
        guard path.hasPrefix(root) else { return nil }
        return String(path.dropFirst(root.count))
    }

    public func url(forRelativePath path: String) -> URL {
        rootURL.appendingPathComponent(path)
    }

    /// The state to persist: open documents with a location, the active one, and the given folders.
    public func state(expandedFolders: [URL]) -> WorkspaceState {
        WorkspaceState(
            openFiles: documents.compactMap { $0.url.flatMap(relativePath) },
            activeFile: activeDocument?.url.flatMap(relativePath),
            expandedFolders: expandedFolders.compactMap(relativePath)
        )
    }

    /// Reopens the files of a saved state that still exist. Returns the folders to expand.
    @discardableResult
    public func restore(_ state: WorkspaceState) -> [URL] {
        for path in state.openFiles {
            let url = url(forRelativePath: path)
            _ = try? open(url)
        }
        if let active = state.activeFile.map(url(forRelativePath:)), let document = document(for: active) {
            activate(document)
        }
        return state.expandedFolders.map(url(forRelativePath:))
    }

    // MARK: - File operations

    /// Creates an empty file in `folder` with a name that does not collide, refreshes the folder, returns the URL.
    @discardableResult
    public func createFile(in folder: URL, named name: String = "untitled.txt") throws -> URL {
        let url = Workspace.availableURL(in: folder, named: name)
        guard FileManager.default.createFile(atPath: url.path, contents: Data()) else { throw WorkspaceError.cannotCreate(url) }
        refreshFolder(folder)
        return url
    }

    @discardableResult
    public func createFolder(in folder: URL, named name: String = "untitled folder") throws -> URL {
        let url = Workspace.availableURL(in: folder, named: name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        refreshFolder(folder)
        return url
    }

    /// Renames within the same folder. Open documents under the old URL follow it.
    @discardableResult
    public func rename(_ url: URL, to name: String) throws -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("/") else { throw WorkspaceError.invalidName(name) }
        let destination = url.deletingLastPathComponent().appendingPathComponent(trimmed).standardizedFileURL
        guard destination.path != url.standardizedFileURL.path else { return url }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw WorkspaceError.alreadyExists(destination) }
        try FileManager.default.moveItem(at: url, to: destination)
        retargetDocuments(from: url, to: destination)
        refreshFolder(url.deletingLastPathComponent())
        return destination
    }

    /// Moves to the Trash and closes any document that lived inside.
    public func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        let prefix = url.standardizedFileURL.path
        for document in documents where document.url.map({ $0.path == prefix || $0.path.hasPrefix(prefix + "/") }) == true {
            close(document)
        }
        refreshFolder(url.deletingLastPathComponent())
    }

    private func retargetDocuments(from old: URL, to new: URL) {
        let oldPath = old.standardizedFileURL.path
        for document in documents {
            guard let path = document.url?.path else { continue }
            if path == oldPath {
                document.moved(to: new)
            } else if path.hasPrefix(oldPath + "/") {
                document.moved(to: new.appendingPathComponent(String(path.dropFirst(oldPath.count + 1))))
            }
        }
    }

    private func refreshFolder(_ folder: URL) {
        if let node = root.node(for: folder), node.isDirectory {
            _ = node.children          // make sure it is loaded, so the new entry shows up
            node.refresh()
            onFoldersChanged?([node])
        }
    }

    /// `name`, or `name 2`, `name 3`... when taken. The extension stays at the end.
    static func availableURL(in folder: URL, named name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var attempt = 1
        while true {
            let candidate = attempt == 1 ? name : (ext.isEmpty ? "\(base) \(attempt)" : "\(base) \(attempt).\(ext)")
            let url = folder.appendingPathComponent(candidate)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            attempt += 1
        }
    }

    // MARK: - Watching the disk

    private var watcher: DirectoryWatcher?

    /// Folders whose listing changed, already refreshed. The navigator reloads these items.
    public var onFoldersChanged: (([FileNode]) -> Void)?

    /// Open documents whose file changed outside the editor.
    public var onDocumentsChangedOnDisk: (([Document]) -> Void)?

    /// Starts following the folder on disk. Safe to call more than once.
    public func startWatching() {
        guard watcher == nil else { return }
        let watcher = DirectoryWatcher(rootURL: rootURL)
        watcher.onChange = { [weak self] folders in self?.handleChanges(in: folders) }
        watcher.start()
        self.watcher = watcher
    }

    public func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    /// Refreshes the loaded nodes for `folders` and reports documents that changed on disk.
    public func handleChanges(in folders: [URL]) {
        var refreshed: [FileNode] = []
        for folder in folders {
            if let node = root.node(for: folder), node.refresh() {
                refreshed.append(node)
            }
        }
        if !refreshed.isEmpty { onFoldersChanged?(refreshed) }

        // Compare paths: directory URLs differ in trailing slashes depending on how they were built.
        let folderPaths = Set(folders.map(\.path))
        let changedDocuments = documents.filter { document in
            guard let url = document.url else { return false }
            return folderPaths.contains(url.deletingLastPathComponent().path) && document.hasChangedOnDisk
        }
        if !changedDocuments.isEmpty { onDocumentsChangedOnDisk?(changedDocuments) }
    }
}

public enum WorkspaceError: Error, Equatable {
    case cannotCreate(URL)
    case invalidName(String)
    case alreadyExists(URL)
}

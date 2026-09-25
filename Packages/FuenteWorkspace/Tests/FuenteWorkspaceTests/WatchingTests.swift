import Foundation
import Testing
@testable import FuenteWorkspace

@MainActor
private func makeFolder() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("fuente-watch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
    try "a".write(to: root.appendingPathComponent("src/a.php"), atomically: true, encoding: .utf8)
    try "b".write(to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
    return root
}

@Suite @MainActor struct FileNodeRefreshTests {
    @Test func refreshKeepsSurvivingNodesAndReportsChanges() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let node = FileNode(url: root, isDirectory: true)
        let src = node.children[0]
        #expect(!node.refresh())                       // nothing changed yet

        try "c".write(to: root.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: root.appendingPathComponent("b.txt"))
        #expect(node.refresh())
        #expect(node.children.map(\.name) == ["src", "c.txt"])
        #expect(node.children[0] === src)              // same object: expansion survives
        #expect(src.children.map(\.name) == ["a.php"]) // untouched subtree still loaded
    }

    @Test func unloadedFoldersAreNotScanned() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let node = FileNode(url: root, isDirectory: true)
        #expect(!node.refresh())                       // never listed: nothing to refresh
    }
}

@Suite @MainActor struct DocumentDiskTests {
    @Test func noticesAndReloadsOutsideChanges() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("b.txt")
        let document = Document(url: url)
        #expect(!document.hasChangedOnDisk)

        try "changed".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        #expect(document.hasChangedOnDisk)
        document.markDirty()
        #expect(try document.reloadFromDisk() == "changed")
        #expect(!document.isDirty && !document.hasChangedOnDisk)
    }
}

@Suite @MainActor struct WorkspaceWatchingTests {
    @Test func handleChangesRefreshesFoldersAndFlagsDocuments() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(rootURL: root)
        _ = workspace.root.children                    // load the root listing
        let document = try workspace.open(root.appendingPathComponent("b.txt"))

        var refreshed: [FileNode] = []
        var flagged: [Document] = []
        workspace.onFoldersChanged = { refreshed = $0 }
        workspace.onDocumentsChangedOnDisk = { flagged = $0 }

        try "new".write(to: root.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        try "changed".write(to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: root.appendingPathComponent("b.txt").path)
        workspace.handleChanges(in: [root])
        #expect(refreshed.map(\.url.path) == [root.path])
        #expect(workspace.root.children.map(\.name) == ["src", "b.txt", "new.txt"])
        #expect(flagged.map(\.id) == [document.id])
    }

    @Test func fsEventsDeliverFolderChanges() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let watcher = DirectoryWatcher(rootURL: root)
        var received: [URL] = []
        let delivered = Task { @MainActor in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                watcher.onChange = { folders in
                    received = folders
                    watcher.onChange = nil
                    continuation.resume()
                }
            }
        }
        watcher.start(latency: 0.1)
        try await Task.sleep(for: .milliseconds(200))
        try "x".write(to: root.appendingPathComponent("src/x.php"), atomically: true, encoding: .utf8)

        let ok = await withTaskGroup(of: Bool.self) { group -> Bool in
            group.addTask { (try? await Task.sleep(for: .seconds(5))) == nil ? false : false }
            group.addTask { await delivered.value; return true }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        watcher.stop()
        #expect(ok, "FSEvents did not deliver within 5 s")
        #expect(received.map(\.path).contains(root.appendingPathComponent("src").standardizedFileURL.path))
    }
}

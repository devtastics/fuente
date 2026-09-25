import Foundation
import Testing
@testable import FuenteWorkspace

@Suite @MainActor struct WorkspaceStateTests {
    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fuente-state-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src/Util"), withIntermediateDirectories: true)
        try "a".write(to: root.appendingPathComponent("src/a.php"), atomically: true, encoding: .utf8)
        try "b".write(to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        return root
    }

    @Test func storeRoundTripsAndKeysByRoot() throws {
        let root = try makeProject()
        let storeDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("fuente-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: storeDirectory) }
        let store = WorkspaceStateStore(directory: storeDirectory)
        #expect(store.load(for: root) == nil)

        let state = WorkspaceState(openFiles: ["src/a.php", "b.txt"], activeFile: "b.txt", expandedFolders: ["src", "src/Util"])
        try store.save(state, for: root)
        #expect(store.load(for: root) == state)
        #expect(store.fileURL(for: root) != store.fileURL(for: root.appendingPathComponent("src")))
        #expect(store.fileURL(for: root).lastPathComponent.hasSuffix(".json"))
    }

    @Test func workspaceProducesAndRestoresState() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(rootURL: root)
        try workspace.open(root.appendingPathComponent("src/a.php"))
        try workspace.open(root.appendingPathComponent("b.txt"))
        workspace.activate(workspace.documents[0])
        let state = workspace.state(expandedFolders: [root.appendingPathComponent("src"), FileManager.default.temporaryDirectory])
        #expect(state == WorkspaceState(openFiles: ["src/a.php", "b.txt"], activeFile: "src/a.php", expandedFolders: ["src"]))

        let restored = Workspace(rootURL: root)
        let missing = WorkspaceState(openFiles: ["src/a.php", "gone.txt", "b.txt"], activeFile: "b.txt", expandedFolders: ["src/Util"])
        let folders = restored.restore(missing)
        #expect(restored.documents.map(\.name) == ["a.php", "b.txt"])
        #expect(restored.activeDocument?.name == "b.txt")
        #expect(folders.map(\.lastPathComponent) == ["Util"])
    }
}

import Foundation
import Testing
@testable import FuenteWorkspace

@Suite @MainActor struct FileOperationsTests {
    private func makeProject() throws -> (URL, Workspace) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fuente-ops-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "a".write(to: root.appendingPathComponent("src/a.php"), atomically: true, encoding: .utf8)
        let workspace = Workspace(rootURL: root)
        _ = workspace.root.children
        _ = workspace.root.children[0].children
        return (root, workspace)
    }

    @Test func createsFilesAndFoldersWithUniqueNames() throws {
        let (root, workspace) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        var refreshed: [FileNode] = []
        workspace.onFoldersChanged = { refreshed += $0 }
        let first = try workspace.createFile(in: root.appendingPathComponent("src"))
        let second = try workspace.createFile(in: root.appendingPathComponent("src"))
        let folder = try workspace.createFolder(in: root)
        #expect(first.lastPathComponent == "untitled.txt")
        #expect(second.lastPathComponent == "untitled 2.txt")
        #expect(folder.lastPathComponent == "untitled folder")
        #expect(workspace.root.children[0].children.map(\.name) == ["a.php", "untitled 2.txt", "untitled.txt"])
        #expect(refreshed.count == 3)
    }

    @Test func renameFollowsOpenDocumentsAndRejectsBadNames() throws {
        let (root, workspace) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = try workspace.open(root.appendingPathComponent("src/a.php"))
        let renamed = try workspace.rename(root.appendingPathComponent("src/a.php"), to: "b.php")
        #expect(renamed.lastPathComponent == "b.php")
        #expect(document.url == renamed.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: renamed.path))

        // Renaming the folder retargets documents inside it.
        let movedFolder = try workspace.rename(root.appendingPathComponent("src"), to: "lib")
        #expect(document.url?.path == movedFolder.appendingPathComponent("b.php").path)

        #expect(throws: WorkspaceError.invalidName("x/y")) { try workspace.rename(movedFolder, to: "x/y") }
        try "".write(to: root.appendingPathComponent("taken.txt"), atomically: true, encoding: .utf8)
        #expect(throws: WorkspaceError.self) { try workspace.rename(movedFolder, to: "taken.txt") }
    }

    @Test func trashClosesDocumentsInside() throws {
        let (root, workspace) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try workspace.open(root.appendingPathComponent("src/a.php"))
        try workspace.trash(root.appendingPathComponent("src"))
        #expect(workspace.documents.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("src").path))
        #expect(workspace.root.children.isEmpty)
    }
}
